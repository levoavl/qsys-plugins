-- levo AVL Q-SYS plugin - Art-Net sender
-- Built into a single .qplug by tools/build.py (resolves the #include lines).
-- (c) levo AVL | Elias Jenny - MIT License

--[[ #include "info.lua" ]]
--[[ #include "levo_brand.lua" ]]
--[[ #include "artnet_protocol.lua" ]]

-- One page per universe, then Setup and About
function PageList(props)
  local pages = {}
  for u = 1, props["Universe Count"].Value do
    table.insert(pages, "Universe " .. u)
  end
  table.insert(pages, "Setup")
  table.insert(pages, "About")
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
  --[[ #include "runtime.lua" ]]
end
