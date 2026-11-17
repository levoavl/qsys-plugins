-- levo AVL Q-SYS plugin - Blackmagic ATEM switchers
-- Built into a single .qplug by tools/build.py (resolves the #include lines).
-- (c) levo AVL | Elias Jenny - MIT License
--
-- ATEM protocol handling is based on Sofie ATEM Connection
-- (https://github.com/Sofie-Automation/sofie-atem-connection, MIT License,
-- Copyright (c) 2023 Norsk rikskringkasting AS). The model table is generated
-- from the Bitfocus Companion module bmd-atem (MIT License, Copyright (c) 2018
-- Bitfocus AS, William Viker & Hakon Nessjoen). See README.md for the notices.

--[[ #include "info.lua" ]]
--[[ #include "levo_brand.lua" ]]
--[[ #include "atem_models.lua" ]]
--[[ #include "atem_topology.lua" ]]

function PageList(props)
  return AtemTopology.Pages(AtemTopology.Resolve(props))
end

function GetColor(props)
  return LevoBrand.Colors.Atlantic
end

function GetPrettyName(props)
  local model = props and props["Model"] and props["Model"].Value or ""
  return PluginInfo.Name:gsub("^.-~", "") .. "\n" .. model .. "\n" .. PluginInfo.BuildVersion
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
  --[[ #include "atem_protocol.lua" ]]
  --[[ #include "atem_state.lua" ]]
  --[[ #include "runtime.lua" ]]
end
