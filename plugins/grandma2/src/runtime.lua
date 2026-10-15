-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime code: only runs on the Core or in Emulation mode.

local json = require("rapidjson")

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0
local Counts = SlotCounts(Properties)
local PollInterval = math.max(0.1, (tonumber(Properties["Poll Interval (ms)"].Value) or 250) / 1000)

local TICK = 0.05             -- main timer resolution (s)
local RX_TIMEOUT = 3          -- no response for this long while logged in -> reconnect
local CONNECT_TIMEOUT = 6     -- TCP + handshake + login must finish within this time
local KEEPALIVE = 10          -- session keepalive interval
local FADER_HOLD = 0.6        -- ignore fader feedback this long after a user move
local FRAMES_PER_TICK = 6     -- send rate limit
local BACKOFF = { 1, 2, 4, 8, 15, 30 }

local Now = 0                 -- monotonic time in seconds, advanced by the main timer

local function Log(level, msg)
  if level <= DebugLevel then print(("[grandMA2] %s"):format(msg)) end
end

---------------------------------------------------------------------------
-- Control helpers (only write when the value changes)
---------------------------------------------------------------------------
local function SetString(name, s)
  local c = Controls[name]
  s = s or ""
  if c and c.String ~= s then c.String = s end
end

local function SetBool(name, b)
  local c = Controls[name]
  if c and c.Boolean ~= b then c.Boolean = b end
end

local function SetPosition(name, p)
  local c = Controls[name]
  if not c then return end
  p = math.max(0, math.min(1, p or 0))
  if math.abs(c.Position - p) > 0.0005 then c.Position = p end
end

local function SetLegend(name, text)
  local c = Controls[name]
  if c then pcall(function() if c.Legend ~= text then c.Legend = text end end) end
end

local STATUS = { OK = 0, Compromised = 1, Fault = 2, NotPresent = 3, Missing = 4, Initializing = 5 }
local function SetStatus(value, text)
  local c = Controls.Status
  if c.Value ~= value then c.Value = value end
  SetString("Status", text)
end

local function SetError(text)
  SetString("Last Error", text)
  if text ~= "" then Log(1, "Error: " .. text) end
end

---------------------------------------------------------------------------
-- Defaults for slot assignments (0 = not set)
---------------------------------------------------------------------------
local function DefaultInt(name, value)
  local c = Controls[name]
  if c and (c.Value or 0) < 1 then c.Value = value end
end

DefaultInt("Port", 80)
for i = 1, Counts.Faders do
  DefaultInt("Fader " .. i .. " Page", 1)
  DefaultInt("Fader " .. i .. " Exec", i)
end
for i = 1, Counts.Buttons do
  DefaultInt("Button " .. i .. " Page", 1)
  DefaultInt("Button " .. i .. " Exec", 100 + i)
end
for i = 1, Counts.Macros do
  DefaultInt("Macro " .. i .. " Number", i)
end
if Controls.Username.String == "" then Controls.Username.String = "administrator" end

---------------------------------------------------------------------------
-- Slots: what is assigned where
---------------------------------------------------------------------------
-- slot = { kind = "Fader"|"Button", index, prefix, page, exec, key, touchedAt }
local Slots = {}
local SlotsByKey = {}   -- "page.exec" -> { slot, ... }
local PollPlan = {}

local function KeyOf(page, exec) return ("%d.%d"):format(page, exec) end

local function RebuildSlots()
  Slots, SlotsByKey = {}, {}
  local list = {}
  local function add(kind, i)
    local prefix = kind .. " " .. i .. " "
    local page = math.floor(Controls[prefix .. "Page"].Value)
    local exec = math.floor(Controls[prefix .. "Exec"].Value)
    local slot = { kind = kind, index = i, prefix = prefix, page = page, exec = exec, key = KeyOf(page, exec), touchedAt = -100 }
    Slots[#Slots + 1] = slot
    if page >= 1 and exec >= 1 then
      SlotsByKey[slot.key] = SlotsByKey[slot.key] or {}
      table.insert(SlotsByKey[slot.key], slot)
      list[#list + 1] = { page = page, exec = exec }
    end
  end
  for i = 1, Counts.Faders do add("Fader", i) end
  for i = 1, Counts.Buttons do add("Button", i) end
  PollPlan = MA2State.BuildPollPlan(list)
  Log(2, ("Poll plan: %d request(s) for %d slot(s)"):format(#PollPlan, #list))
end

local function FaderSlot(i) return Slots[i] end
local function ButtonSlot(i) return Slots[Counts.Faders + i] end

---------------------------------------------------------------------------
-- Slot output
---------------------------------------------------------------------------
local Tracker = MA2State.NewTracker()
local LastEntry = {}   -- key -> last parsed entry (for predictions)
local LastResult = {}  -- key -> last derived result

local function ShowSlot(slot, e, r)
  local p = slot.prefix
  SetString(p .. "Name", e and e.name or "")
  SetString(p .. "Cue", e and e.cue or "")
  SetString(p .. "Function", e and e.func or "")
  SetString(p .. "State", r.state)
  SetBool(p .. "Active", r.active)
  SetBool(p .. "Fading", r.fading)
  SetPosition(p .. "Progress", r.progress)
  if slot.kind == "Fader" then
    for b = 1, 3 do
      local label = e and e.labels[b] or ""
      SetString(p .. "Button " .. b .. " Label", label)
      SetLegend(p .. "Button " .. b, label)
    end
    if e and e.level and (Now - slot.touchedAt) > FADER_HOLD then
      SetPosition(p .. "Level", e.level)
    end
  else
    SetLegend(p .. "Press", e and e.name or "")
  end
end

local OFFLINE = { state = MA2State.States.Offline, active = false, fading = false, progress = 0 }

local function ShowAllOffline()
  Tracker:Reset()
  LastEntry, LastResult = {}, {}
  for _, slot in ipairs(Slots) do
    SetString(slot.prefix .. "State", OFFLINE.state)
    SetBool(slot.prefix .. "Active", false)
    SetBool(slot.prefix .. "Fading", false)
    SetPosition(slot.prefix .. "Progress", 0)
  end
end

local function ApplyEntry(e)
  local key = KeyOf(e.page, e.exec)
  local slots = SlotsByKey[key]
  if not slots then return end
  local r = Tracker:Update(key, e, Now)
  local prev = LastResult[key]
  if DebugLevel >= 2 and (not prev or prev.state ~= r.state) then
    Log(2, ("Exec %s '%s': %s -> %s%s"):format(key, e.name, prev and prev.state or "-", r.state,
      r.fading and (" (%d%%)"):format(math.floor(r.progress * 100 + 0.5)) or ""))
  end
  LastEntry[key], LastResult[key] = e, r
  for _, slot in ipairs(slots) do ShowSlot(slot, e, r) end
end

-- After an optimistic update, show it right away instead of waiting for a poll
local function RefreshKey(key)
  local e = LastEntry[key]
  if e then ApplyEntry(e) end
end

---------------------------------------------------------------------------
-- Connection
---------------------------------------------------------------------------
local Conn = {
  ws = nil,
  phase = "idle",       -- idle | connecting | login | ready | waiting (backoff)
  session = 0,
  phaseSince = 0,
  lastRx = 0,
  lastKeepalive = 0,
  retryAt = nil,
  attempt = 0,
  reconnects = 0,
  pollQueue = {},
  pollWaiting = false,
  pollSentAt = 0,
  nextCycle = 0,
}

-- Outgoing queue: list of keys + payload map, so repeated fader moves coalesce
local TxOrder, TxPayload = {}, {}
local TxSeq = 0

local function Enqueue(msg, coalesceKey)
  if not coalesceKey then
    TxSeq = TxSeq + 1
    coalesceKey = "#" .. TxSeq
  end
  if TxPayload[coalesceKey] == nil then TxOrder[#TxOrder + 1] = coalesceKey end
  TxPayload[coalesceKey] = msg
end

local function ClearQueue()
  TxOrder, TxPayload = {}, {}
end

local function SendNow(msg, quiet)
  if not (Conn.ws and Conn.ws:IsOpen()) then return false end
  local text = type(msg) == "table" and json.encode(msg) or msg
  if not quiet then Log(2, "> " .. text) end
  return Conn.ws:Send(text)
end

local function DrainQueue()
  if Conn.phase ~= "ready" then return end
  local n = 0
  while n < FRAMES_PER_TICK and #TxOrder > 0 do
    local key = table.remove(TxOrder, 1)
    local msg = TxPayload[key]
    TxPayload[key] = nil
    SendNow(msg)
    n = n + 1
  end
end

local function SetPhase(phase)
  Conn.phase, Conn.phaseSince = phase, Now
  SetBool("Connected", phase == "login" or phase == "ready")
  SetBool("Logged In", phase == "ready")
end

local OnMessage  -- forward declaration

local function ScheduleRetry(reason)
  Conn.attempt = Conn.attempt + 1
  local delay = BACKOFF[math.min(Conn.attempt, #BACKOFF)]
  Conn.retryAt = Now + delay
  SetPhase("waiting")
  ShowAllOffline()
  SetStatus(STATUS.Missing, ("%s - retry in %ds"):format(reason or "Not connected", delay))
  Log(1, ("%s, retry in %ds"):format(reason or "Disconnected", delay))
end

local function Disconnect()
  if Conn.ws then Conn.ws:Close() end
  Conn.ws = nil
  ClearQueue()
  Conn.pollQueue, Conn.pollWaiting = {}, false
end

local function Connect()
  Disconnect()
  Conn.retryAt = nil
  local ip = Controls["IP Address"].String:gsub("^%s+", ""):gsub("%s+$", "")
  if ip == "" then
    SetPhase("idle")
    ShowAllOffline()
    SetStatus(STATUS.Missing, "No IP address set")
    return
  end
  local port = math.floor(Controls.Port.Value)
  if port < 1 then port = 80 end
  Conn.session = 0
  SetString("Session", "")
  SetPhase("connecting")
  SetStatus(STATUS.Initializing, "Connecting to " .. ip)
  Log(1, ("Connecting to %s:%d"):format(ip, port))
  Conn.ws = LevoWebSocket.New({
    Log = Log,
    OnOpen = function()
      SetPhase("login")
      SetStatus(STATUS.Initializing, "Connected, logging in")
      Conn.lastRx = Now
    end,
    OnMessage = function(text) OnMessage(text) end,
    OnClose = function(reason)
      Conn.ws = nil
      SetError(reason or "connection closed")
      ScheduleRetry("Connection lost")
    end,
  })
  Conn.ws:Connect(ip, port, "/?ma=1")
end

local function Reconnect(manual)
  if manual then
    Conn.attempt = 0
    Conn.reconnects = Conn.reconnects + 1
    SetString("Reconnects", tostring(Conn.reconnects))
  end
  Connect()
end

local function SendLogin()
  local user = Controls.Username.String
  local pass = Controls.Password.String
  Log(1, "Logging in as '" .. user .. "'")
  SendNow({
    requestType = "login",
    username = user,
    password = Crypto.MD5Compute(pass),
    session = Conn.session,
    maxRequests = 10,
  }, true)
end

local function SendPoll(req)
  local isButton = req.itemsType == 3
  SendNow({
    requestType = "playbacks",
    startIndex = { req.startIndex },
    itemsCount = { req.itemsCount },
    pageIndex = req.page - 1,
    itemsType = { req.itemsType },
    view = req.itemsType,
    execButtonViewMode = isButton and 2 or 1,
    buttonsViewMode = 0,
    session = Conn.session,
    maxRequests = 10,
  }, true)
  Conn.pollWaiting, Conn.pollSentAt = true, Now
end

local function NextPoll()
  if Conn.phase ~= "ready" or Conn.pollWaiting then return end
  local req = table.remove(Conn.pollQueue, 1)
  if req then SendPoll(req) end
end

OnMessage = function(text)
  Conn.lastRx = Now
  local ok, data = pcall(json.decode, text)
  if not ok or type(data) ~= "table" then
    Log(2, "< (invalid JSON) " .. text:sub(1, 200))
    return
  end

  if data.responseType == "playbacks" then
    Conn.pollWaiting = false
    for _, e in ipairs(MA2State.ParsePlaybacks(data)) do ApplyEntry(e) end
    if Conn.phase == "ready" then
      SetStatus(STATUS.OK, "OK")
    end
    NextPoll()
    return
  end

  Log(2, "< " .. text:sub(1, 400))

  if data.status == "server ready" then
    Conn.session = 0
    SendNow({ session = 0 })
    return
  end

  if data.session ~= nil then
    local s = tonumber(data.session) or 0
    if s ~= Conn.session then
      Conn.session = s
      SetString("Session", tostring(s))
      Log(1, "Session " .. s)
    end
    if s < 0 then
      -- session rejected / expired: start a new one
      Conn.session = 0
      SetPhase("login")
      SendNow({ session = 0 })
      return
    end
  end

  if data.forceLogin then
    SetPhase("login")
    SendLogin()
    return
  end

  if data.responseType == "login" then
    if data.result then
      Log(1, "Logged in")
      SetError("")
      Conn.attempt = 0
      Conn.lastKeepalive = Now
      Conn.nextCycle = Now
      SetPhase("ready")
      SetStatus(STATUS.OK, "OK")
    else
      SetError("Login failed - check username / password")
      Disconnect()
      SetPhase("waiting")
      Conn.attempt = #BACKOFF  -- do not hammer the console with wrong credentials
      Conn.retryAt = Now + BACKOFF[#BACKOFF]
      ShowAllOffline()
      SetStatus(STATUS.Fault, "Login failed - check username / password")
    end
  end
end

---------------------------------------------------------------------------
-- Main timer
---------------------------------------------------------------------------
local MainTimer = Timer.New()
MainTimer.EventHandler = function()
  Now = Now + TICK

  if Conn.phase == "waiting" and Conn.retryAt and Now >= Conn.retryAt then
    Conn.reconnects = Conn.reconnects + 1
    SetString("Reconnects", tostring(Conn.reconnects))
    Connect()
    return
  end

  if (Conn.phase == "connecting" or Conn.phase == "login") and Now - Conn.phaseSince > CONNECT_TIMEOUT then
    SetError(Conn.phase == "connecting" and "No answer from console (web remote enabled?)" or "Login timed out")
    Disconnect()
    ScheduleRetry("Not reachable")
    return
  end

  if Conn.phase == "ready" then
    if Now - Conn.lastRx > RX_TIMEOUT then
      SetError("Console stopped responding")
      Disconnect()
      ScheduleRetry("Timeout")
      return
    end
    if Now - Conn.lastKeepalive >= KEEPALIVE then
      Conn.lastKeepalive = Now
      SendNow({ session = Conn.session }, true)
    end
    -- poll cycle
    if Conn.pollWaiting and Now - Conn.pollSentAt > 1 then
      Conn.pollWaiting = false  -- lost response, carry on
    end
    if Now >= Conn.nextCycle and #Conn.pollQueue == 0 then
      Conn.nextCycle = Now + PollInterval
      for _, req in ipairs(PollPlan) do Conn.pollQueue[#Conn.pollQueue + 1] = req end
    end
    DrainQueue()
    NextPoll()
  end
end

---------------------------------------------------------------------------
-- User input
---------------------------------------------------------------------------
local function UserInput(slot, t, fields, coalesceKey)
  if slot.page < 1 or slot.exec < 1 then return end
  local msg = {
    requestType = "playbacks_userInput",
    execIndex = slot.exec - 1,
    pageIndex = slot.page - 1,
    ["type"] = t,
    session = Conn.session,
    maxRequests = 0,
  }
  for k, v in pairs(fields) do msg[k] = v end
  if Conn.phase ~= "ready" then
    Log(1, ("Not connected - input on exec %s dropped"):format(slot.key))
    return
  end
  Enqueue(msg, coalesceKey)
end

local function Press(slot, buttonId, func, pressed)
  UserInput(slot, 0, { pressed = pressed, released = not pressed, buttonId = buttonId })
  if pressed and Conn.phase == "ready" then
    local r = LastResult[slot.key]
    local predicted = MA2State.PredictPress(func, r and r.active)
    if predicted ~= nil then
      Tracker:SetOptimistic(slot.key, predicted, Now)
      RefreshKey(slot.key)
    end
    Log(1, ("Exec %s button %d (%s)"):format(slot.key, buttonId + 1, func ~= "" and func or "?"))
  end
end

local function SendCommand(cmd)
  cmd = (cmd or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if cmd == "" then return end
  if Conn.phase ~= "ready" then
    Log(1, "Not connected - command dropped: " .. cmd)
    return
  end
  Log(1, "Command: " .. cmd)
  Enqueue({ requestType = "command", command = cmd, session = Conn.session, maxRequests = 0 })
end

local function WireSlotHandlers()
  for i = 1, Counts.Faders do
    local p = "Fader " .. i .. " "
    Controls[p .. "Level"].EventHandler = function(c)
      local slot = FaderSlot(i)
      slot.touchedAt = Now
      UserInput(slot, 1, { faderValue = c.Position }, "fader:" .. slot.key)
    end
    for b = 1, 3 do
      Controls[p .. "Button " .. b].EventHandler = function(c)
        local slot = FaderSlot(i)
        Press(slot, b - 1, Controls[p .. "Button " .. b .. " Label"].String, c.Boolean)
      end
    end
  end
  for i = 1, Counts.Buttons do
    local p = "Button " .. i .. " "
    Controls[p .. "Press"].EventHandler = function(c)
      local slot = ButtonSlot(i)
      Press(slot, 0, Controls[p .. "Function"].String, c.Boolean)
    end
  end
  for i = 1, Counts.Macros do
    Controls["Macro " .. i .. " Trigger"].EventHandler = function()
      local n = math.floor(Controls["Macro " .. i .. " Number"].Value)
      if n >= 1 then SendCommand("Go Macro " .. n) end
    end
  end
  for i = 1, Counts.Commands do
    Controls["Command " .. i .. " Send"].EventHandler = function()
      SendCommand(Controls["Command " .. i .. " Text"].String)
    end
  end

  -- re-assignment of page / exec at runtime
  local function OnAssign()
    RebuildSlots()
    Tracker:Reset()
    LastEntry, LastResult = {}, {}
    for _, slot in ipairs(Slots) do ShowSlot(slot, nil, OFFLINE) end
    Conn.pollQueue = {}
    Conn.nextCycle = Now
  end
  for _, kind in ipairs({ "Fader", "Button" }) do
    local n = kind == "Fader" and Counts.Faders or Counts.Buttons
    for i = 1, n do
      Controls[kind .. " " .. i .. " Page"].EventHandler = OnAssign
      Controls[kind .. " " .. i .. " Exec"].EventHandler = OnAssign
    end
  end
end

Controls["Command TX"].EventHandler = function(c)
  local cmd = c.String
  c.String = ""
  SendCommand(cmd)
end

local function OnConnectionSetting()
  Conn.attempt = 0
  Connect()
end
Controls["IP Address"].EventHandler = OnConnectionSetting
Controls.Port.EventHandler = OnConnectionSetting
Controls.Username.EventHandler = OnConnectionSetting
Controls.Password.EventHandler = OnConnectionSetting
Controls.Reconnect.EventHandler = function() Reconnect(true) end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
SetString("Reconnects", "0")
SetError("")
RebuildSlots()
for _, slot in ipairs(Slots) do ShowSlot(slot, nil, OFFLINE) end
WireSlotHandlers()
Log(1, ("Started, build %s - %d fader(s), %d button(s), %d macro(s), %d command(s)"):format(
  PluginInfo.BuildVersion, Counts.Faders, Counts.Buttons, Counts.Macros, Counts.Commands))
MainTimer:Start(TICK)
Connect()
