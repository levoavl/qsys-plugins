-- (c) levo AVL | Elias Jenny - MIT License
-- Runtime code: only runs on the Core or in Emulation mode.

local DebugLevel = ({ None = 0, Basic = 1, Verbose = 2 })[Properties["Debug Print"].Value] or 0

local function Log(level, msg)
  if level <= DebugLevel then print("[levo] " .. msg) end
end

local function SetStatus(value, text)
  Controls.Status.Value = value  -- 0 OK, 1 Compromised, 2 Fault, 3 Not present, 4 Missing, 5 Initializing
  Controls.Status.String = text or ""
end

SetStatus(0, "Template loaded")
Log(1, "Template plugin started, build " .. PluginInfo.BuildVersion)

Controls.IPAddress.EventHandler = function(ctl)
  Log(1, "IP address set to " .. ctl.String)
end
