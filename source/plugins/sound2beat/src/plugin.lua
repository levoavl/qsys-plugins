-- levo AVL Q-SYS plugin - Sound2Beat (beat / BPM detection, tempo sync to grandMA2/3)
-- Built into a single .qplug by tools/build.py (resolves the #include lines).
-- (c) levo AVL | Elias Jenny - MIT License

--[[ #include "info.lua" ]]
--[[ #include "levo_brand.lua" ]]

PageNames = { "Control", "Setup", "Debug", "About" }

-- Property values used by controls, layout and runtime
function Options(props)
  local function v(name, default)
    local p = props[name]
    return p and p.Value or default
  end
  return {
    LevelSource = v("Level Source", "Wired Pin"),
    Console = v("Console Type", "grandMA2"),
  }
end

function GetColor(props)
  return LevoBrand.Colors.Atlantic
end

function GetPrettyName(props)
  return PluginInfo.Name:gsub("^.-~", "") .. "\n" .. PluginInfo.BuildVersion
end

function GetPages(props)
  local pages = {}
  for _, name in ipairs(PageNames) do
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
  local CurrentPage = PageNames[props["page_index"].Value] or "Control"
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

if Controls then
  --[[ #include "beat_engine.lua" ]]
  --[[ #include "ma_output.lua" ]]
  --[[ #include "runtime.lua" ]]
end
