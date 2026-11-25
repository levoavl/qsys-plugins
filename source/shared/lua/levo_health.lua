-- (c) levo AVL | Elias Jenny - MIT License
-- levo AVL plugin health: shared by all plugins with a runtime timer.
-- Included once at the top of plugin.lua (after levo_brand.lua).
--
--  * LevoHealth.StatusWriter  Status control setter that works on the Core
--  * LevoHealth.New           error recovery, main timer watchdog, memory guard,
--                             readouts (Lua Memory / Plugin Uptime / Internal Errors)
--                             and Core event log entries
--
-- Why: the Core reads a Status control back with the state in front
-- ("Missing - text"), so "write only if c.String differs" never matches and a
-- status updated from a timer is rewritten on every tick. ATEM 1.0 did that
-- 50 times a second and grew to several hundred MB until the Core hung.

LevoHealth = {
  -- names of the readout controls (text outputs); add them with LevoHealth.AddControls
  CONTROLS = { "Lua Memory", "Plugin Uptime", "Internal Errors" },
  MEM_WARN_KB = 10 * 1024,     -- normal plugins use about 1 MB: warn above this
  MEM_LIMIT_KB = 32 * 1024,    -- above this: onReset()
  GC_EVERY = 60,               -- s, full garbage collection
  STALL_AFTER = 3,             -- s without a main timer tick -> restart the timer
  EVENT_LOG_EVERY = 600,       -- s, at most one event log entry per kind
}

-- Control definitions for GetControls: add(def) inserts one definition
function LevoHealth.AddControls(add)
  for _, name in ipairs(LevoHealth.CONTROLS) do
    add({ Name = name, ControlType = "Indicator", IndicatorType = "Text", PinStyle = "Output", UserPin = true, Count = 1 })
  end
end

-- Status setter: compares with what it wrote last, never with the read-back
function LevoHealth.StatusWriter(control)
  local last = {}
  return function(value, text)
    local c = type(control) == "function" and control() or control
    if not c then return end
    text = text or ""
    if last.value ~= value then
      c.Value = value
      last.value = value
    end
    if last.text ~= text then
      c.String = text
      last.text = text
    end
  end
end

local function FormatUptime(s)
  s = math.floor(s)
  return ("%d:%02d:%02d"):format(s // 3600, s % 3600 // 60, s % 60)
end
LevoHealth.FormatUptime = FormatUptime

-- opts:
--   name      text in front of event log entries, e.g. "ATEM Switcher"
--   tag       print prefix, e.g. "[ATEM]"
--   timer     main Timer (watchdog restarts it), interval = opts.tick (s)
--   clock     function() -> seconds (optional, e.g. Timer.Now): Plugin Uptime from this
--             clock at the last main tick instead of ticks x interval
--   controls  Controls table (readouts are written when the controls exist)
--   onError   function(msg)    e.g. show in "Last Error" (optional)
--   onReset   function(reason) drop device state and reconnect (optional)
function LevoHealth.New(opts)
  local h = { ticks = 0, seenTicks = 0, stalled = 0, seconds = 0, errors = 0 }
  local startClock = opts.clock and opts.clock() or 0
  local lastClock = startClock
  local lastPrint, lastPrintAt = nil, -1e9
  local logged = {}           -- [kind] = seconds of the last event log entry
  local hasGc = type(collectgarbage) == "function"
  local healthTimer = Timer.New()
  h.Timer = healthTimer       -- keep reachable from the plugin's global runtime table

  local function MemoryKB() return hasGc and collectgarbage("count") or 0 end

  local function SetText(name, s)
    local c = opts.controls and opts.controls[name]
    if c and c.String ~= s then c.String = s end
  end

  -- Core event log (Core Manager > Event Log), plain print as fallback
  local function EventLog(kind, msg)
    local last = logged[kind]
    if last and h.seconds - last < LevoHealth.EVENT_LOG_EVERY then return end
    logged[kind] = h.seconds
    local text = opts.name .. ": " .. msg
    local logger = type(Log) == "table" and (Log.Error or Log.Message)
    local ok = logger and pcall(logger, text)
    if not ok then print(opts.tag .. " (event log) " .. text) end
  end

  -- Problems: always printed (independent of Debug Print, max once a minute per
  -- message) and written to the event log (max every 10 minutes per kind)
  function h.Report(msg, kind)
    if msg ~= lastPrint or h.seconds - lastPrintAt >= 60 then
      print(opts.tag .. " " .. msg)
      lastPrint, lastPrintAt = msg, h.seconds
    end
    EventLog(kind or msg, msg)
  end

  local function Reset(reason)
    if not opts.onReset then return end
    local ok, err = pcall(opts.onReset, reason)
    if not ok then h.Report("Recovery failed: " .. tostring(err), "recovery") end
  end

  function h.OnError(where, err)
    h.errors = h.errors + 1
    local msg = ("Internal error (%s): %s"):format(where, tostring(err))
    h.Report(msg, "error " .. where)
    if opts.onError then pcall(opts.onError, msg) end
    Reset("Internal error")
  end

  -- Run fn(...) protected; on error report + reset. Returns true if fn ran clean.
  function h.Run(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then h.OnError(where, err) end
    return ok
  end

  -- EventHandler for the main timer: counts ticks (watchdog, uptime) and protects fn
  function h.MainHandler(fn)
    return function(...)
      h.ticks = h.ticks + 1
      if opts.clock then lastClock = opts.clock() end
      h.Run("timer", fn, ...)
    end
  end

  -- Same protection for socket / control handlers
  function h.Handler(where, fn)
    return function(...) h.Run(where, fn, ...) end
  end

  local function Check()
    h.seconds = h.seconds + 1
    -- main timer watchdog
    if opts.timer then
      if h.ticks == h.seenTicks then
        h.stalled = h.stalled + 1
        if h.stalled >= LevoHealth.STALL_AFTER then
          h.Report("Main timer stalled - restarting it", "stall")
          opts.timer:Stop()
          opts.timer:Start(opts.tick)
          h.stalled = 0
        end
      else
        h.stalled = 0
      end
      h.seenTicks = h.ticks
    end
    -- memory: measured right after a full collection (live data, no garbage)
    local kb = MemoryKB()
    local collect = h.seconds % LevoHealth.GC_EVERY == 0
    if hasGc and (collect or kb > LevoHealth.MEM_LIMIT_KB) then
      collectgarbage("collect")
      kb = MemoryKB()
      if kb > LevoHealth.MEM_LIMIT_KB then
        h.Report(("Memory limit reached (%.1f MB) - resetting"):format(kb / 1024), "memory limit")
        Reset("Memory limit reached")
        collectgarbage("collect")
        kb = MemoryKB()
      elseif collect and kb > LevoHealth.MEM_WARN_KB then
        h.Report(("High memory use: %.1f MB (normal is about 1 MB)"):format(kb / 1024), "memory warn")
      end
    end
    -- readouts; Plugin Uptime follows the main timer, so it stops if the plugin hangs
    SetText("Lua Memory", hasGc and ("%.1f MB"):format(kb / 1024) or "n/a")
    local up = opts.clock and (lastClock - startClock) or (opts.timer and h.ticks * opts.tick) or h.seconds
    SetText("Plugin Uptime", FormatUptime(up))
    SetText("Internal Errors", tostring(h.errors))
  end

  healthTimer.EventHandler = function()
    local ok, err = pcall(Check)
    if not ok then h.Report("Health check failed: " .. tostring(err), "health") end
  end

  function h.Start() healthTimer:Start(1) end

  return h
end
