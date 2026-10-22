-- levo AVL Q-SYS plugin - Advanced Color Picker
-- Built into a single .qplug by tools/build.py (resolves the #include lines).
-- (c) levo AVL | Elias Jenny - MIT License

--[[ #include "info.lua" ]]
--[[ #include "levo_brand.lua" ]]
--[[ #include "color_math.lua" ]]
--[[ #include "presets.lua" ]]
--[[ #include "picker_images.lua" ]]

PageNames = { "Presets", "Picker", "Outputs", "Setup", "About" }

-- LED layouts that always get level outputs
OutputLayouts = { "RGB", "RGBW", "RGBA", "RGBWA" }
ChannelNames = { R = "Red", G = "Green", B = "Blue", W = "White", A = "Amber", D = "Dimmer" }

-- Settings derived from the properties (also used at runtime via `Properties`)
function PickerConfig(props)
  local function num(name, default, min, max)
    local p = props[name]
    local v = math.floor(tonumber(p and p.Value) or default)
    return math.max(min, math.min(max, v))
  end
  local function str(name, default)
    local p = props[name]
    return (p and p.Value) or default
  end
  local cfg = {
    UserPresets = num("User Presets", 8, 0, 32),
    WheelSize = num("Picker Resolution", 21, 11, 41),
    SeparateDimmer = str("Dimmer", "Scale Outputs") == "Separate Output",
    Subtract = str("White/Amber Mixing", "Subtract (accurate)") == "Subtract (accurate)",
    LinkLayout = str("Console Link", "RGB"),
  }
  if cfg.WheelSize % 2 == 0 then cfg.WheelSize = cfg.WheelSize + 1 end  -- odd: one centre cell
  -- channels of the console link, in order (D = dimmer when it is a separate output)
  cfg.LinkChannels = {}
  if cfg.LinkLayout ~= "Off" then
    for ch in cfg.LinkLayout:gmatch(".") do cfg.LinkChannels[#cfg.LinkChannels + 1] = ch end
    if cfg.SeparateDimmer then cfg.LinkChannels[#cfg.LinkChannels + 1] = "D" end
  end
  return cfg
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
  local CurrentPage = PageNames[props["page_index"].Value]
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

if Controls then
  --[[ #include "runtime.lua" ]]
end
