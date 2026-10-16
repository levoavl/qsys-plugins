-- (c) levo AVL | Elias Jenny - MIT License
--
-- grandMA2 web remote: parsing of "playbacks" responses and derivation of the
-- executor state (Off / Fading In / On / Fading Out). Pure Lua, no Q-SYS APIs,
-- so it can be unit tested outside the Core.
--
-- Field meanings were taken from logs of grandMA2 onPC 3.9.60.91:
--   iExec        0-based executor index (exec 101 = 100)
--   combinedItems executor width
--   isRun        1 while the executor runs, including a running fade-out
--   tt.t         executor / sequence label
--   oI.t         sequence pool number ("" = empty executor)
--   cues.items[] cue text ("    1 Szene 1") and pgs.v = fade progress 0..1
--   executorBlocks[k]  fader executors: button1..3 {t = label}, fader {v, tt = function}
--   bottomButtons.items[1]  button executors: n.t = function ("Toggle", "Go"), fader.v = master

MA2State = {}

local function Trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
MA2State.Trim = Trim

local function Field(t, ...)
  for _, k in ipairs({ ... }) do
    if type(t) ~= "table" then return nil end
    t = t[k]
  end
  return t
end

local function Num(v)
  return type(v) == "number" and v or nil
end

-- Returns a list of entries, one per executor (combined executors yield one
-- entry per covered executor number):
--   { page, exec (1-based, as shown in MA), empty, name, cue, running,
--     progress (0..1 or nil), func, level (0..1 or nil), labels = {b1, b2, b3} }
function MA2State.ParsePlaybacks(data)
  local out = {}
  if type(data) ~= "table" or data.responseType ~= "playbacks" then return out end
  local page = Num(data.iPage) or 1
  for _, group in ipairs(data.itemGroups or {}) do
    for _, row in ipairs(group.items or {}) do
      for _, item in ipairs(row) do
        local base = Num(item.iExec)
        if base then
          local width = math.max(1, Num(item.combinedItems) or 1)
          local name = Trim(Field(item, "tt", "t"))
          local pool = Trim(Field(item, "oI", "t"))
          local running = (Num(item.isRun) or 0) ~= 0

          -- current cue: the one with a progress value, otherwise the first one
          local cueText, progress = "", nil
          local cues = Field(item, "cues", "items")
          if type(cues) == "table" then
            for i, cue in ipairs(cues) do
              local v = Num(Field(cue, "pgs", "v"))
              if i == 1 then cueText = Trim(cue.t) end
              if v then cueText, progress = Trim(cue.t), v; break end
            end
          end

          local bottom = Field(item, "bottomButtons", "items", 1)
          for k = 1, width do
            local block = Field(item, "executorBlocks", k)
            local e = {
              page = page,
              exec = base + k,
              empty = (pool == "" and name == ""),
              name = name,
              cue = cueText,
              running = running,
              progress = progress,
              labels = {},
            }
            if type(block) == "table" then
              e.func = Trim(Field(block, "fader", "tt"))
              e.level = Num(Field(block, "fader", "v"))
              for b = 1, 3 do
                local t = Trim(Field(block, "button" .. b, "t"))
                e.labels[b] = (t == "Empty") and "" or t
              end
            elseif type(bottom) == "table" then
              e.func = Trim(Field(bottom, "n", "t"))
              e.level = Num(Field(bottom, "fader", "v"))
            end
            e.func = e.func or ""
            if e.empty then e.func, e.labels = "", { "", "", "" } end
            out[#out + 1] = e
          end
        end
      end
    end
  end
  return out
end

MA2State.States = { Empty = "Empty", Off = "Off", FadingIn = "Fading In", On = "On", FadingOut = "Fading Out", Offline = "Offline" }
local S = MA2State.States

local EPS = 0.002

-- Tracker keeps the previous sample per executor to tell fade-in from fade-out
-- and holds optimistic states after a user action until the console agrees.
function MA2State.NewTracker()
  local tracker = { last = {}, optimistic = {} }

  -- `key` identifies the executor ("page.exec"), `now` is a time in seconds.
  -- Returns { state, active, fading, progress (0..1) }
  function tracker:Update(key, e, now)
    local prev = self.last[key]
    local st
    if e.empty then
      st = S.Empty
    elseif not e.running then
      st = S.Off
    elseif e.progress == nil then
      st = S.On
    else
      local p = e.progress
      if prev and prev.progress and prev.cue == e.cue and prev.running then
        if p < prev.progress - EPS then
          st = S.FadingOut
        elseif p > prev.progress + EPS then
          st = S.FadingIn
        elseif p >= 1 - EPS then
          st = S.On
        else
          -- progress not moving (slow or paused fade): keep the direction
          st = (prev.state == S.FadingOut or prev.state == S.FadingIn) and prev.state or S.On
        end
      elseif prev and prev.running and prev.cue ~= e.cue then
        st = (p >= 1 - EPS) and S.On or S.FadingIn  -- next cue started
      else
        st = (p >= 1 - EPS) and S.On or S.FadingIn  -- first sample
      end
    end
    self.last[key] = { progress = e.progress, cue = e.cue, running = e.running, state = st }

    local active = (st == S.On or st == S.FadingIn)
    local result = {
      state = st,
      active = active,
      fading = (st == S.FadingIn or st == S.FadingOut),
      progress = (st == S.FadingIn or st == S.FadingOut) and (e.progress or 0) or (active and 1 or 0),
    }

    local opt = self.optimistic[key]
    if opt then
      if now >= opt.untilTime or opt.active == active then
        self.optimistic[key] = nil  -- console agrees or hold time is over
      else
        result.state = opt.state
        result.active = opt.active
        result.fading = (opt.state == S.FadingIn or opt.state == S.FadingOut)
      end
    end
    return result
  end

  -- Assume the result of a user action until the console confirms it.
  function tracker:SetOptimistic(key, active, now, hold)
    self.optimistic[key] = {
      active = active,
      state = active and S.FadingIn or S.FadingOut,
      untilTime = now + (hold or 1.5),
    }
  end

  function tracker:Reset()
    self.last, self.optimistic = {}, {}
  end

  return tracker
end

-- Which state a button press probably leads to, from the MA button function.
-- Returns true (on), false (off) or nil (unknown / momentary, no assumption).
function MA2State.PredictPress(func, currentlyActive)
  local f = Trim(func):lower()
  if f == "off" then return false end
  if f == "on" or f == "go" or f == "go+" then return true end
  if f == "toggle" then return not currentlyActive end
  return nil
end

-- Group executor numbers into poll requests. `slots` is a list of {page, exec}
-- (1-based, as in MA). Returns a list of requests
--   { page, itemsType (2 fader / 3 button), startIndex (0-based), itemsCount }
-- The web remote answers in blocks of 5 executors.
function MA2State.BuildPollPlan(slots, maxSpan)
  maxSpan = maxSpan or 50
  local byGroup = {}
  for _, s in ipairs(slots) do
    local page, exec = math.floor(s.page or 0), math.floor(s.exec or 0)
    if page >= 1 and exec >= 1 then
      local itemsType = (exec > 100) and 3 or 2
      local gk = page * 10 + itemsType
      byGroup[gk] = byGroup[gk] or { page = page, itemsType = itemsType, idx = {} }
      byGroup[gk].idx[exec - 1] = true
    end
  end
  local keys = {}
  for gk in pairs(byGroup) do keys[#keys + 1] = gk end
  table.sort(keys)

  local plan = {}
  for _, gk in ipairs(keys) do
    local g = byGroup[gk]
    local list = {}
    for i in pairs(g.idx) do list[#list + 1] = i end
    table.sort(list)
    local lo, hi
    local function flush()
      if not lo then return end
      local start = (lo // 5) * 5
      local count = ((hi - start) // 5 + 1) * 5
      plan[#plan + 1] = { page = g.page, itemsType = g.itemsType, startIndex = start, itemsCount = count }
    end
    for _, i in ipairs(list) do
      if lo and (i - hi <= 10) and (i - ((lo // 5) * 5) < maxSpan) then
        hi = i
      else
        flush()
        lo, hi = i, i
      end
    end
    flush()
  end
  return plan
end
