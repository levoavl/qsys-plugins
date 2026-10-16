-- (c) levo AVL | Elias Jenny - MIT License
--
-- Sound2Beat beat engine. Pure Lua 5.3, no Q-SYS APIs, so it can be tested offline.
-- All functions take the time `t` in seconds from a monotonic clock.
--
-- Signal path:
--   level (dB, low band)  ->  onset detection  ->  tempo histogram  ->  beat clock (PLL)
--
-- Onset detection works in the dB domain: the onset strength is how far the level
-- rose above its minimum of the last ~120 ms. Working in dB makes it independent of
-- the overall volume (no gain tracking needed). The threshold adapts to the running
-- mean and spread of the strength, with a floor set by the sensitivity.
--
-- Tempo: every onset votes for the intervals to its last few predecessors, folded
-- into the BPM range by octaves, into a decaying histogram. The peak is the tempo,
-- the share of all votes near the peak is the confidence.
--
-- Beat clock: free-running oscillator. Onsets close to a predicted beat pull its phase;
-- a linear regression over the last on-beat onsets refines the period far below the
-- meter update resolution. The beat keeps going through breakdowns, and single missed
-- or extra kicks barely move it.

BeatEngine = {}
BeatEngine.__index = BeatEngine

local BIN = 0.5             -- histogram resolution in BPM
local SPREAD = 2            -- minimum vote spread in bins (gaussian sigma)
local HIST_TAU = 6          -- histogram decay time constant (s)
local MIN_WINDOW = 0.12     -- window for the level minimum (s)
local STAT_TAU = 2.0        -- time constant of the strength statistics (s)
local GATE_DB = -60         -- below this the input counts as silence
local MAX_IOI = 2.5         -- intervals longer than this are ignored (s)
local LOCK_TIMEOUT = 2.0    -- no onset for this long -> free running (s)
local TAP_RESET = 2.0       -- tap gap that starts a new tap sequence (s)
local TAP_HOLD = 4.0        -- detection does not correct the clock this long after a tap (s)
local PHASE_GAIN = 0.15     -- phase correction per on-beat onset
local FIT_MIN = 8           -- on-beat onsets needed before the regression sets the tempo
local FIT_MAX = 32          -- on-beat onsets kept for the regression
local FIT_AGE = 16          -- ... and not older than this (s)
local PERIOD_SPAN = 0.04    -- PLL period may deviate this much from the histogram tempo
local OFFBEAT_DB = 1.5      -- offbeat onsets this much louder (on average) -> the clock is on the offbeat
local JUMP_BPM = 4          -- histogram tempo this far off -> tempo change
local JUMP_CONFIRM = 6      -- ... confirmed by this many onsets in a row
-- Weight of the interval to the k-th previous onset. Only k = 1 and 2: further back,
-- missed kicks make the interval an odd number of beats (3, 5), which folds to a wrong
-- tempo (3/2, 5/4) and can win the histogram when meter updates are coarse.
local IOI_WEIGHTS = { 1.0, 0.5 }

local function clamp(x, a, b) if x < a then return a elseif x > b then return b else return x end end
local function lerp(a, b, f) return a + (b - a) * f end

function BeatEngine.New(cfg)
  local self = setmetatable({}, BeatEngine)
  self:Configure(cfg or {})
  self:Reset()
  return self
end

-- cfg: bpmMin, bpmMax, sensitivity (0..1), minConfidence (0..1)
function BeatEngine:Configure(cfg)
  local lo = clamp(tonumber(cfg.bpmMin) or 80, 30, 300)
  local hi = clamp(tonumber(cfg.bpmMax) or 160, 30, 300)
  if hi < lo * 2 then hi = lo * 2 end   -- folding by octaves needs at least one octave
  local changed = (lo ~= self.bpmMin or hi ~= self.bpmMax)
  self.bpmMin, self.bpmMax = lo, hi
  self.sensitivity = clamp(tonumber(cfg.sensitivity) or 0.5, 0, 1)
  self.minConfidence = clamp(tonumber(cfg.minConfidence) or 0.35, 0, 1)
  if changed and self.hist then self:ClearTempo() end
end

function BeatEngine:Reset()
  self.levels = {}          -- { t, db } of the last MIN_WINDOW
  self.strength = 0
  self.statMean, self.statVar = 1, 1
  self.armed = true
  self.lastOnset = -100
  self.onsets = {}          -- recent onset times
  self.onsetCount = 0
  self.onsetDb, self.onsetOpenUntil = -100, nil
  self.threshold = 0
  self.lastLevelT = nil
  self.lastDb, self.lastChangeT = nil, nil
  self.updateInterval = 0.02  -- measured interval between level changes (s)
  self:ClearTempo()
  -- clock
  self.period = nil         -- detected beat period (s), before scale
  self.nextBeat = nil
  self.beatNo = 0           -- absolute number of `nextBeat`
  self.fit = {}             -- onsets { n = beat number, t, on, db } for the regression
  self.gridHits = {}        -- did the last onsets fit the clock grid?
  self.bar = 0
  self.scale = 1
  self.hold = false
  self.auto = true
  self.taps = {}
  self.tapUntil = -100
  self.resyncPending = false
  self.everLocked = false
  self.silentSince = nil
end

function BeatEngine:ClearTempo()
  local n = math.floor((self.bpmMax - self.bpmMin) / BIN + 0.5) + 1
  self.hist, self.histN = {}, n
  for i = 1, n do self.hist[i] = 0 end
  self.histT = nil
  self.histBpm, self.confidence, self.histMass = nil, 0, 0
  self.jumpCount = 0
  self.refined = false      -- tempo refined by the regression (not only the histogram)
end

---------------------------------------------------------------------------
-- Histogram
---------------------------------------------------------------------------
function BeatEngine:Decay(t)
  if self.histT then
    local f = math.exp(-(t - self.histT) / HIST_TAU)
    if f < 0.9999 then
      for i = 1, self.histN do self.hist[i] = self.hist[i] * f end
    end
  end
  self.histT = t
end

function BeatEngine:Fold(bpm)
  if bpm <= 0 then return nil end
  while bpm < self.bpmMin do bpm = bpm * 2 end
  while bpm > self.bpmMax do bpm = bpm / 2 end
  if bpm < self.bpmMin then return nil end
  return bpm
end

-- One tempo vote. `sigma` is the uncertainty of the vote in BPM; precise votes are
-- narrow and high, imprecise ones wide and flat (same total weight).
function BeatEngine:Vote(bpm, weight, sigma)
  local raw = bpm
  bpm = self:Fold(bpm)
  if not bpm then return end
  sigma = (sigma or 0) * bpm / raw                     -- folding scales the uncertainty too
  local sb = math.max(SPREAD, sigma / BIN)             -- sigma in bins
  local pos = (bpm - self.bpmMin) / BIN + 1
  local c = math.floor(pos + 0.5)
  local w = clamp(weight * SPREAD / sb, 0, weight)     -- keep the area constant
  local reach = math.ceil(2.5 * sb)
  for i = c - reach, c + reach do
    if i >= 1 and i <= self.histN then
      local d = (i - pos) / sb
      self.hist[i] = self.hist[i] + w * math.exp(-0.5 * d * d)
    end
  end
end

-- Peak, confidence and the strongest other candidates
function BeatEngine:Analyse()
  local h, n = self.hist, self.histN
  local best, bi, total = 0, nil, 0
  for i = 1, n do
    total = total + h[i]
    if h[i] > best then best, bi = h[i], i end
  end
  self.histMass = total
  if not bi or total <= 0 then
    self.histBpm, self.confidence = nil, 0
    return
  end
  -- weighted centre around the peak for sub-bin precision
  local sw, sx, near = 0, 0, 0
  for i = math.max(1, bi - 2), math.min(n, bi + 2) do
    sw = sw + h[i]; sx = sx + h[i] * i
  end
  -- the peak is as wide as a single vote: measure its share over that width
  local peakBpm = self.bpmMin + (bi - 1) * BIN
  local dt = math.max(0.01, self.updateInterval * 0.6)
  local sigma2 = peakBpm * dt / (2 * 60 / peakBpm) / BIN      -- two-beat interval, in bins
  local win = math.ceil(math.max(2 * SPREAD, 2 * sigma2))
  for i = math.max(1, bi - win), math.min(n, bi + win) do near = near + h[i] end
  self.histBpm = self.bpmMin + (sx / sw - 1) * BIN
  -- the peak's share of all votes; a clean 4/4 track reaches ~0.5..0.8
  self.confidence = clamp(near / total * 1.4, 0, 1)
  -- a few votes are not enough, whatever the share
  self.confidence = self.confidence * clamp(total / 8, 0, 1)
end

-- Up to `count` histogram peaks as { bpm, share }
function BeatEngine:Candidates(count)
  local h, n, out = self.hist, self.histN, {}
  local total = self.histMass > 0 and self.histMass or 1
  for i = 2, n - 1 do
    if h[i] > 0.01 and h[i] >= h[i - 1] and h[i] > h[i + 1] then
      out[#out + 1] = { bpm = self.bpmMin + (i - 1) * BIN, share = h[i] / total }
    end
  end
  table.sort(out, function(a, b) return a.share > b.share end)
  while #out > (count or 3) do table.remove(out) end
  return out
end

---------------------------------------------------------------------------
-- Onset detection
---------------------------------------------------------------------------
-- Feed the current level (dB). Returns true when an onset was detected.
function BeatEngine:Feed(t, db)
  db = tonumber(db) or -100
  local lv = self.levels
  lv[#lv + 1] = { t, db }
  while #lv > 1 and lv[1][1] < t - MIN_WINDOW do table.remove(lv, 1) end
  local minDb = db
  for i = 1, #lv do if lv[i][2] < minDb then minDb = lv[i][2] end end
  local s = db - minDb
  self.strength = s

  -- strength statistics (exponential, time based so the tick rate does not matter)
  local dt = self.lastLevelT and clamp(t - self.lastLevelT, 0, 0.5) or 0
  self.lastLevelT = t
  if db ~= self.lastDb then
    if self.lastChangeT then
      local iv = clamp(t - self.lastChangeT, 0.005, 0.2)
      self.updateInterval = self.updateInterval + 0.05 * (iv - self.updateInterval)
    end
    self.lastDb, self.lastChangeT = db, t
  end
  local a = 1 - math.exp(-dt / STAT_TAU)
  -- statistics of the background only: onsets are capped at the threshold, otherwise
  -- the kicks themselves would raise the threshold above the kicks
  local floor = lerp(10, 3, self.sensitivity)
  local x = math.min(s, 2 * floor)
  local diff = x - self.statMean
  self.statMean = self.statMean + a * diff
  self.statVar = (1 - a) * (self.statVar + a * diff * diff)

  -- threshold: adaptive, with a floor given by the sensitivity
  local k = lerp(3.0, 1.0, self.sensitivity)
  local thr = math.max(floor, self.statMean + k * math.sqrt(self.statVar))
  self.threshold = thr

  if db < GATE_DB then
    self.silentSince = self.silentSince or t
  else
    self.silentSince = nil
  end

  if self.onsetOpenUntil and t <= self.onsetOpenUntil and db > self.onsetDb then
    self.onsetDb = db
    local last = self.fit[#self.fit]
    if last and last.t == self.lastOnset then last.db = db end
  end
  if s < thr * 0.5 then self.armed = true end
  local refractory = 0.6 * 60 / self.bpmMax
  if self.armed and s >= thr and db >= GATE_DB and (t - self.lastOnset) >= refractory then
    self.armed = false
    -- loudest level of this onset (the meter may still rise in the next updates)
    self.onsetDb = db
    self.onsetOpenUntil = t + 0.06
    self:OnOnset(t)
    return true
  end
  return false
end

function BeatEngine:OnOnset(t)
  self.lastOnset = t
  self.onsetCount = self.onsetCount + 1
  if self.hold then return end

  -- tempo votes
  self:Decay(t)
  local on = self.onsets
  for k = 1, #IOI_WEIGHTS do
    local prev = on[#on - k + 1]
    if not prev then break end
    local d = t - prev
    if d > MAX_IOI then break end
    if IOI_WEIGHTS[k] > 0 then
      -- timing of each onset is uncertain by about one meter update
      local dt = math.max(0.01, self.updateInterval * 0.6)
      self:Vote(60 / d, IOI_WEIGHTS[k], 60 / d * dt / d)
    end
  end
  on[#on + 1] = t
  while #on > 8 do table.remove(on, 1) end
  self:Analyse()
  self:FollowTempo(t)

  -- phase
  if self.resyncPending then
    self.resyncPending = false
    if self.period then
      self.nextBeat = t
      self.bar = 0
      self.fit = {}
    end
    return
  end
  if self.auto and t >= self.tapUntil then self:CorrectPhase(t) end
end

-- Take over the histogram tempo into the clock
function BeatEngine:FollowTempo(t)
  if not self.auto or t < self.tapUntil then return end
  local bpm = self.histBpm
  if not bpm or self.confidence < self.minConfidence * 0.7 then return end
  if not self.period then
    self.period = 60 / bpm
    self.nextBeat = t + self.period
    self.bar = 0
    self.fit = {}
    return
  end
  local cur = 60 / self.period
  local fitting = 0
  for _, h in ipairs(self.gridHits) do if h then fitting = fitting + 1 end end
  local stillFits = #self.gridHits >= 6 and fitting / #self.gridHits >= 0.6
  if math.abs(bpm - cur) > JUMP_BPM and self.confidence >= self.minConfidence and not stillFits then
    self.jumpCount = self.jumpCount + 1
    if self.jumpCount >= JUMP_CONFIRM then
      self.period = 60 / bpm
      self.jumpCount = 0
      self.fit, self.gridHits = {}, {}
      self.refined = false
    end
  else
    self.jumpCount = 0
    -- keep the PLL period inside a narrow band around the histogram tempo
    local p0 = 60 / bpm
    self.period = clamp(self.period, p0 * (1 - PERIOD_SPAN), p0 * (1 + PERIOD_SPAN))
  end
end

function BeatEngine:ClockPeriod()
  return self.period and self.period / self.scale or nil
end

function BeatEngine:CorrectPhase(t)
  local P = self:ClockPeriod()
  if not P or not self.nextBeat then return end
  -- Onsets are placed on a half-beat grid: with a folded tempo (e.g. 174 BPM shown
  -- as 87) or offbeat bass, onsets land between the beats - still exact timing.
  -- The beat number is counted from the previous onset, not read off the clock, so a
  -- clock that is still slightly off cannot shift the numbering.
  local half = P / 2
  local fit = self.fit
  local last = fit[#fit]
  local n
  if last and t - last.t < 4 then
    local x = (t - last.t) / half
    local h = math.floor(x + 0.5)
    if h < 1 or math.abs(x - h) > 0.35 then return end   -- off the grid (syncopation)
    n = last.n + h / 2
  else
    -- `nextBeat` may already lie in the past by less than one tick
    local k2 = math.floor((t - self.nextBeat) / half + 0.5)
    n = self.beatNo + k2 / 2
  end
  local onBeat = (n % 1 == 0)
  -- does the onset still fit the running clock? (guards against false tempo jumps)
  local eh = (t - self.nextBeat) / half
  eh = eh - math.floor(eh + 0.5)
  local hits = self.gridHits
  hits[#hits + 1] = math.abs(eh) < 0.3
  while #hits > 8 do table.remove(hits, 1) end
  -- only on-beat onsets pull the phase, otherwise the clock could slide onto the offbeat
  if onBeat then
    local e = t - (self.nextBeat + (n - self.beatNo) * P)
    if math.abs(e) < 0.25 * P then self.nextBeat = self.nextBeat + PHASE_GAIN * e end
  end

  -- Tempo by linear regression over the recent onsets: t = a + b * n. Single onsets
  -- are only as exact as the meter update rate; the fit over many beats averages that out.
  fit[#fit + 1] = { n = n, t = t, on = onBeat, db = self.onsetDb }
  while #fit > FIT_MAX or (#fit > 0 and fit[1].t < t - FIT_AGE) do table.remove(fit, 1) end
  if #fit < FIT_MIN then return end
  -- The clock sits on the offbeat when nearly all onsets fall between the beats, or
  -- when the onsets between the beats are clearly louder (kick vs. offbeat bass).
  local nOn, nOff, dbOn, dbOff = 0, 0, 0, 0
  for _, p in ipairs(fit) do
    if p.on then nOn = nOn + 1; dbOn = dbOn + p.db else nOff = nOff + 1; dbOff = dbOff + p.db end
  end
  local louderOff = nOn >= 6 and nOff >= 6 and (dbOff / nOff) > (dbOn / nOn) + OFFBEAT_DB
  if (nOff / #fit > 0.75 or louderOff) and t >= (self.noFlipUntil or 0) then
    -- renumber instead of starting over: the timing data stays valid
    self.nextBeat = self.nextBeat + half
    for _, p in ipairs(fit) do p.n = p.n - 0.5; p.on = not p.on end
    return
  end
  local sn, st, snn, snt = 0, 0, 0, 0
  for _, p in ipairs(fit) do sn = sn + p.n; st = st + p.t end
  local mn, mt = sn / #fit, st / #fit
  for _, p in ipairs(fit) do
    local dn = p.n - mn
    snn = snn + dn * dn; snt = snt + dn * (p.t - mt)
  end
  if snn <= 0 then return end
  local b = snt / snn                  -- clock period
  local period = b * self.scale        -- detected (unscaled) period
  if self.histBpm then
    local p0 = 60 / self.histBpm
    if period < p0 * (1 - PERIOD_SPAN) or period > p0 * (1 + PERIOD_SPAN) then return end
  end
  self.period = period
  self.refined = true
  -- move the phase towards the fitted grid as well
  local fitted = mt + (self.beatNo - mn) * b
  self.nextBeat = self.nextBeat + 0.3 * (fitted - self.nextBeat)
end

---------------------------------------------------------------------------
-- Clock: call every tick. Returns list of beat events { bar = 1..4 }.
---------------------------------------------------------------------------
function BeatEngine:Update(t, lead)
  local events = {}
  local P = self:ClockPeriod()
  if not P or not self.nextBeat then return events end
  lead = lead or 0
  -- catch up after a long pause without firing a burst of beats
  if t + lead - self.nextBeat > 4 * P then
    local skip = math.floor((t + lead - self.nextBeat) / P)
    self.nextBeat = self.nextBeat + skip * P
    self.beatNo = self.beatNo + skip
    self.bar = (self.bar + skip) % 4
  end
  while t + lead >= self.nextBeat do
    self.bar = self.bar % 4 + 1
    events[#events + 1] = { bar = self.bar, time = self.nextBeat }
    self.nextBeat = self.nextBeat + P
    self.beatNo = self.beatNo + 1
  end
  return events
end

---------------------------------------------------------------------------
-- User functions
---------------------------------------------------------------------------
function BeatEngine:Tap(t)
  local taps = self.taps
  if #taps > 0 and t - taps[#taps] > TAP_RESET then self.taps = {}; taps = self.taps end
  taps[#taps + 1] = t
  while #taps > 7 do table.remove(taps, 1) end
  if #taps < 2 then return end
  local iv = {}
  for i = 2, #taps do iv[#iv + 1] = taps[i] - taps[i - 1] end
  table.sort(iv)
  local p = iv[(#iv + 1) // 2]
  if #iv % 2 == 0 then p = (iv[#iv // 2] + iv[#iv // 2 + 1]) / 2 end
  self.period = p * self.scale     -- tapped tempo is what the user hears / wants
  self.nextBeat = t + p
  self.fit = {}
  -- the first tap of a sequence is the downbeat
  self.bar = (#taps - 1) % 4
  self.tapUntil = t + TAP_HOLD
  if self.auto then
    -- hint for the detection: strengthens the tapped octave
    self:Decay(t)
    self:Vote(60 / self.period, 3)
    self:Analyse()
  end
end

-- Next onset (or now, without signal) becomes beat 1
function BeatEngine:Resync(t)
  if not self.period then return end
  self.fit = {}
  if self.silentSince or (t - self.lastOnset) > LOCK_TIMEOUT then
    self.nextBeat = t
    self.bar = 0
  else
    self.resyncPending = true
  end
end

-- Move the beat by half a beat (clock sits on the offbeat)
function BeatEngine:ShiftHalf()
  local P = self:ClockPeriod()
  if not P or not self.nextBeat then return end
  self.nextBeat = self.nextBeat + P / 2
  for _, p in ipairs(self.fit) do p.n = p.n - 0.5; p.on = not p.on end
  self.noFlipUntil = (self.lastLevelT or 0) + 30   -- the user decided: no automatic flip back
end

function BeatEngine:SetScale(f)
  self.scale = clamp(f, 0.25, 4)
  self.fit = {}
end

function BeatEngine:SetHold(b) self.hold = b and true or false end
function BeatEngine:SetAuto(b) self.auto = b and true or false end

---------------------------------------------------------------------------
-- Readout
---------------------------------------------------------------------------
function BeatEngine:Bpm()
  local P = self:ClockPeriod()
  return P and 60 / P or nil
end

-- Tempo good enough to send to a console: refined by the regression, tapped or manual
function BeatEngine:IsPrecise(t)
  if not self:IsLocked(t) then return false end
  return self.refined or t < self.tapUntil or not self.auto
end

function BeatEngine:IsLocked(t)
  if self.hold or not self.period then return false end
  if t < self.tapUntil then return true end
  if not self.auto then return true end
  return self.confidence >= self.minConfidence and (t - self.lastOnset) <= LOCK_TIMEOUT
end

-- "No Signal" | "Searching" | "Locked" | "Free Running" | "Hold" | "Tap" | "Manual"
function BeatEngine:State(t)
  if self.hold then return "Hold" end
  if t < self.tapUntil then return "Tap" end
  if not self.auto then return self.period and "Manual" or "No Tempo" end
  if self:IsLocked(t) then self.everLocked = true; return "Locked" end
  if self.period and self.everLocked then return "Free Running" end
  if self.silentSince and t - self.silentSince > 2 then return "No Signal" end
  return "Searching"
end
