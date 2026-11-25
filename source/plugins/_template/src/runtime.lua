-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime code: only runs on the Core or in Emulation mode.

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0
local TICK = 0.1   -- main timer (s)

local function Log(level, msg)
  if level <= DebugLevel then print("[levo] " .. msg) end
end

-- 0 OK, 1 Compromised, 2 Fault, 3 Not present, 4 Missing, 5 Initializing.
-- Always use this writer: it compares with what it wrote, not with the read-back
-- (the Core reads Status back as "State - text").
local SetStatus = LevoHealth.StatusWriter(Controls.Status)

local MainTimer = Timer.New()
local Health = LevoHealth.New({
  name = "levo Template", tag = "[levo]", timer = MainTimer, tick = TICK, controls = Controls,
  onReset = function(reason) Log(1, "Reset: " .. reason) end,   -- drop device state, reconnect
})
-- Keep long-lived objects reachable from a global: objects only held by locals
-- can be garbage collected on the Core and silently stop working.
TemplateRuntime = { Timer = MainTimer, Health = Health.Timer }

local function MainTick()
  -- periodic work goes here (protected: errors are reported, counted and reset)
end

MainTimer.EventHandler = Health.MainHandler(MainTick)

Controls.IPAddress.EventHandler = Health.Handler("ip", function(ctl)
  Log(1, "IP address set to " .. ctl.String)
end)

SetStatus(0, "Template loaded")
Log(1, "Template plugin started, build " .. PluginInfo.BuildVersion)
MainTimer:Start(TICK)
Health.Start()
