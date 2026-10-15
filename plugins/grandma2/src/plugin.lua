-- levo AVL Q-SYS plugin - grandMA2 (web remote)
-- Built into a single .qplug by tools/build.py (resolves the #include lines).
-- (c) levo AVL | Elias Jenny - MIT License
--
-- WebSocket / web remote protocol handling is based on "MA2 Remote" by
-- Locimation Pty Ltd (https://github.com/locimation/qsys-plugins), MIT License,
-- Copyright 2020 Locimation Pty Ltd. See README.md for the full notice.

--[[ #include "info.lua" ]]
--[[ #include "levo_brand.lua" ]]

-- Slot counts from the properties (also used at runtime via `Properties`)
function SlotCounts(props)
  local function n(name)
    local p = props[name]
    return math.max(0, math.floor(tonumber(p and p.Value) or 0))
  end
  return {
    Faders = n("Fader Count"),
    Buttons = n("Button Count"),
    Macros = n("Macro Count"),
    Commands = n("Command Count"),
  }
end

-- Pages without slots are hidden
function PageList(props)
  local c = SlotCounts(props)
  local pages = {}
  if c.Faders > 0 then pages[#pages + 1] = "Faders" end
  if c.Buttons > 0 then pages[#pages + 1] = "Buttons" end
  if c.Macros > 0 then pages[#pages + 1] = "Macros" end
  if c.Commands > 0 then pages[#pages + 1] = "Commands" end
  pages[#pages + 1] = "Setup"
  pages[#pages + 1] = "About"
  return pages
end

function GetColor(props)
  return LevoBrand.Colors.Atlantic
end

function GetPrettyName(props)
  return PluginInfo.Name:gsub("^.-~", "") .. "\n" .. PluginInfo.BuildVersion
end

function GetPages(props)
  local pages = {}
  for _, name in ipairs(PageList(props)) do
    table.insert(pages, { name = name })
  end
  return pages
end

function GetProperties()
  local props = {}
  --[[ #include "properties.lua" ]]
  return props
end

function RectifyProperties(props)
  --[[ #include "rectify.lua" ]]
  return props
end

function GetPins(props)
  local pins = {}
  return pins
end

function GetControls(props)
  local ctrls = {}
  --[[ #include "controls.lua" ]]
  return ctrls
end

function GetControlLayout(props)
  local layout, graphics = {}, {}
  local CurrentPage = PageList(props)[props["page_index"].Value] or "Setup"
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

if Controls then
  --[[ #include "levo_websocket.lua" ]]
  --[[ #include "ma2_state.lua" ]]
  --[[ #include "runtime.lua" ]]
end
