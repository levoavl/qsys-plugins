-- (c) levo AVL | Elias Jenny - MIT License
--
-- Command-line output to MA consoles.
--   grandMA2: Telnet (TCP, default port 30000), login with user/password, replies are
--             read line by line (Telnet negotiation and ANSI codes stripped).
--   grandMA3: OSC over UDP (default port 8000), address "/cmd" or "/<prefix>/cmd",
--             type string. MA3 sends no reply - "sent" is all we can know.
--
-- Commands are queued with a coalescing key (a newer tempo replaces a pending one) and
-- sent no faster than MIN_SPACING. Reconnect with backoff is handled here.
--
--   local out = MAOutput.New("grandMA2", {
--     Log = function(level, msg) end,
--     OnState = function(state) end,    -- { code, text, connected, loggedIn }
--     OnReply = function(line) end,     -- MA2 only
--     OnError = function(text) end,
--   })
--   out:Configure({ ip = "10.0.0.5", port = 30000, user = "administrator", pass = "" })
--   out:Tick(now)                       -- call regularly (main timer)
--   out:Send("SpecialMaster 3.1 At 128", "tempo")

MAOutput = {}
MAOutput.__index = MAOutput

local STATUS = { OK = 0, Compromised = 1, Fault = 2, Missing = 4, Initializing = 5 }
MAOutput.Status = STATUS

local BACKOFF = { 1, 2, 4, 8, 15, 30 }
local CONNECT_TIMEOUT = 6     -- TCP connect must finish within this time (s)
local LOGIN_GRACE = 3         -- no login answer within this time: assume logged in (s)
local KEEPALIVE = 20          -- empty line to the MA2 command line (s)
local MIN_SPACING = 0.25      -- minimum time between two commands (s)

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Remove Telnet negotiation (IAC sequences) and ANSI escape codes
function MAOutput.CleanTelnet(data)
  data = data:gsub("\255\250.-\255\240", "")         -- IAC SB ... IAC SE
  data = data:gsub("\255[\251-\254].", "")           -- IAC WILL/WONT/DO/DONT opt
  data = data:gsub("\255[\241-\249]", "")            -- other two-byte IAC commands
  data = data:gsub("\27%[[%d;?]*[%a]", "")           -- ANSI CSI
  return data
end

-- OSC message with a single string argument
function MAOutput.EncodeOsc(address, text)
  local function pad(s)
    s = s .. "\0"
    return s .. string.rep("\0", (4 - #s % 4) % 4)
  end
  return pad(address) .. pad(",s") .. pad(text)
end

function MAOutput.New(kind, handlers)
  local self = setmetatable({
    kind = kind,
    h = handlers or {},
    cfg = {},
    now = 0,
    phase = "idle",         -- idle | connecting | login | ready | waiting
    phaseSince = 0,
    attempt = 0,
    retryAt = nil,
    sock = nil,
    udp = nil,
    buffer = "",
    lastTx = -100,
    lastKeepalive = 0,
    order = {}, pending = {}, seq = 0,
    state = { code = STATUS.Initializing, text = "Starting", connected = false, loggedIn = false },
  }, MAOutput)
  return self
end

function MAOutput:Log(level, msg)
  if self.h.Log then self.h.Log(level, msg) end
end

function MAOutput:SetState(code, text, connected, loggedIn)
  local s = self.state
  if s.code == code and s.text == text and s.connected == connected and s.loggedIn == loggedIn then return end
  self.state = { code = code, text = text, connected = connected, loggedIn = loggedIn }
  if self.h.OnState then self.h.OnState(self.state) end
end

function MAOutput:Error(text)
  self:Log(1, "Error: " .. text)
  if self.h.OnError then self.h.OnError(text) end
end

function MAOutput:SetPhase(p)
  self.phase, self.phaseSince = p, self.now
end

-- cfg: ip, port, user, pass (MA2), prefix (MA3). Reconnects only when something changed.
function MAOutput:Configure(cfg)
  local c = {
    ip = trim(cfg.ip), port = math.floor(tonumber(cfg.port) or 0),
    user = trim(cfg.user), pass = cfg.pass or "", prefix = trim(cfg.prefix),
  }
  local o = self.cfg
  if o.ip == c.ip and o.port == c.port and o.user == c.user and o.pass == c.pass and o.prefix == c.prefix then return end
  self.cfg = c
  self.attempt = 0
  self:Start()
end

function MAOutput:Start()
  self:Close()
  self.retryAt = nil
  local c = self.cfg
  if c.ip == "" then
    self:SetPhase("idle")
    self:SetState(STATUS.Missing, "No IP address set", false, false)
    return
  end
  if self.kind == "grandMA3" then
    self:StartOsc()
  else
    self:StartTelnet()
  end
end

function MAOutput:Close()
  if self.sock then
    local s = self.sock
    self.sock = nil   -- the event handler ignores events from other sockets
    pcall(function() s:Disconnect() end)
  end
  self.buffer = ""
end

function MAOutput:ScheduleRetry(reason)
  self:Close()
  self.attempt = self.attempt + 1
  local delay = BACKOFF[math.min(self.attempt, #BACKOFF)]
  self.retryAt = self.now + delay
  self:SetPhase("waiting")
  self:SetState(STATUS.Missing, ("%s - retry in %ds"):format(reason, delay), false, false)
  self:Log(1, ("%s, retry in %ds"):format(reason, delay))
end

function MAOutput:Reconnect()
  self.attempt = 0
  self:Start()
end

---------------------------------------------------------------------------
-- grandMA3: OSC over UDP
---------------------------------------------------------------------------
function MAOutput:StartOsc()
  if not self.udp then
    local udp = UdpSocket.New()
    -- Open() without arguments binds to any local interface and a free port.
    local ok, err = pcall(function() udp:Open() end)
    if not ok then
      self:SetPhase("idle")
      self:SetState(STATUS.Fault, "UDP socket could not be opened", false, false)
      self:Error("UDP open failed: " .. tostring(err))
      return
    end
    self.udp = udp
  end
  self:SetPhase("ready")
  local port = self.cfg.port > 0 and self.cfg.port or 8000
  self:SetState(STATUS.OK, ("Sending OSC to %s:%d (MA3 sends no reply)"):format(self.cfg.ip, port), true, true)
end

---------------------------------------------------------------------------
-- grandMA2: Telnet
---------------------------------------------------------------------------
function MAOutput:StartTelnet()
  local c = self.cfg
  local port = c.port > 0 and c.port or 30000
  local sock = TcpSocket.New()
  sock.ReadTimeout = 0
  sock.WriteTimeout = 0
  sock.ReconnectTimeout = 0  -- reconnect is handled here
  self.sock = sock
  self:SetPhase("connecting")
  self:SetState(STATUS.Initializing, ("Connecting to %s:%d"):format(c.ip, port), false, false)
  self:Log(1, ("Telnet connecting to %s:%d"):format(c.ip, port))
  sock.EventHandler = function(s, evt, err)
    if self.sock ~= s then return end  -- stale socket
    if evt == TcpSocket.Events.Connected then
      self:OnConnected()
    elseif evt == TcpSocket.Events.Data then
      local n = s.BufferLength
      if n and n > 0 then self:OnData(s:Read(n) or "") end
    elseif evt == TcpSocket.Events.Closed then
      self:Error("connection closed by console")
      self:ScheduleRetry("Connection lost")
    elseif evt == TcpSocket.Events.Error then
      self:Error("socket error: " .. tostring(err))
      self:ScheduleRetry("Connection error")
    elseif evt == TcpSocket.Events.Timeout then
      self:ScheduleRetry("Socket timeout")
    end
  end
  sock:Connect(c.ip, port)
end

function MAOutput:WriteLine(line, quiet)
  if not self.sock then return false end
  if not quiet then self:Log(2, "> " .. line) end
  self.sock:Write(line .. "\r\n")
  return true
end

function MAOutput:OnConnected()
  self.lastKeepalive = self.now
  local c = self.cfg
  if c.user == "" then
    self:SetPhase("ready")
    self:SetState(STATUS.OK, "Connected (no login)", true, true)
    return
  end
  self:SetPhase("login")
  self:SetState(STATUS.Initializing, "Connected, logging in as " .. c.user, true, false)
  local function q(s) return '"' .. tostring(s):gsub('"', "") .. '"' end
  self:WriteLine("Login " .. q(c.user) .. " " .. q(c.pass), true)
  self:Log(2, "> Login " .. q(c.user) .. " \"***\"")
end

function MAOutput:OnData(data)
  self.buffer = self.buffer .. MAOutput.CleanTelnet(data)
  if #self.buffer > 16384 then self.buffer = self.buffer:sub(-4096) end
  while true do
    local i = self.buffer:find("[\r\n]")
    if not i then break end
    local line = trim(self.buffer:sub(1, i - 1))
    self.buffer = self.buffer:sub(i + 1)
    if line ~= "" then self:OnLine(line) end
  end
end

function MAOutput:OnLine(line)
  self:Log(2, "< " .. line)
  if self.h.OnReply then self.h.OnReply(line) end
  local lower = line:lower()
  if self.phase == "login" then
    if lower:find("logged in") then
      self:SetPhase("ready")
      self:SetState(STATUS.OK, "Logged in as " .. self.cfg.user, true, true)
      return
    end
    if lower:find("error") or lower:find("denied") or lower:find("failed") or lower:find("wrong") then
      self:SetPhase("idle")
      self:Close()
      self:SetState(STATUS.Fault, "Login failed - check user and password", false, false)
      self:Error("login failed: " .. line)
      return
    end
  end
  if lower:find("^error") or lower:find("error #") then self:Error(line) end
end

---------------------------------------------------------------------------
-- Queue and timer
---------------------------------------------------------------------------
-- Queue a command line. Commands with the same key replace each other while pending.
function MAOutput:Send(cmd, key)
  cmd = trim(cmd)
  if cmd == "" then return end
  if not key then self.seq = self.seq + 1; key = "#" .. self.seq end
  if self.pending[key] == nil then self.order[#self.order + 1] = key end
  self.pending[key] = cmd
end

function MAOutput:IsReady()
  return self.phase == "ready"
end

function MAOutput:Transmit(cmd)
  if self.kind == "grandMA3" then
    local c = self.cfg
    local address = (c.prefix ~= "" and ("/" .. c.prefix:gsub("^/+", ""):gsub("/+$", "")) or "") .. "/cmd"
    local port = c.port > 0 and c.port or 8000
    local ok, err = pcall(function() self.udp:Send(c.ip, port, MAOutput.EncodeOsc(address, cmd)) end)
    if not ok then
      self:Error("UDP send failed: " .. tostring(err))
      self:SetState(STATUS.Fault, "UDP send failed", false, false)
      return false
    end
    self:Log(2, ("> %s %s"):format(address, cmd))
    return true
  end
  return self:WriteLine(cmd)
end

function MAOutput:Tick(now)
  self.now = now
  if self.phase == "waiting" and self.retryAt and now >= self.retryAt then
    self:Start()
  elseif self.phase == "connecting" and now - self.phaseSince > CONNECT_TIMEOUT then
    self:Error("connect timeout")
    self:ScheduleRetry("No answer from console")
  elseif self.phase == "login" and now - self.phaseSince > LOGIN_GRACE then
    -- the MA2 login answer is not documented; no error within the grace time = logged in
    self:Log(1, "No login confirmation received, assuming logged in")
    self:SetPhase("ready")
    self:SetState(STATUS.OK, "Connected as " .. self.cfg.user, true, true)
  end

  if self.phase ~= "ready" then return end
  if self.kind == "grandMA2" and now - self.lastKeepalive >= KEEPALIVE then
    self.lastKeepalive = now
    self:WriteLine("", true)
  end
  if #self.order > 0 and now - self.lastTx >= MIN_SPACING then
    local key = table.remove(self.order, 1)
    local cmd = self.pending[key]
    self.pending[key] = nil
    if cmd and self:Transmit(cmd) then
      self.lastTx = now
      if self.h.OnSent then self.h.OnSent(cmd) end
    end
  end
end
