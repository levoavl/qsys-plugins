-- (c) levo AVL | Elias Jenny - MIT License
local n         = props["Menu Count"].Value
local content   = props["Content"].Value
local indicator = props["Indicator Style"].Value
local nav       = props["Navigation"].Value

props["Rounded Corners"].IsHidden  = props["Corner Radius"].Value == 0
props["Font"].IsHidden             = content == "Icon"
props["Font Size"].IsHidden        = content == "Icon"
props["Bold Active"].IsHidden      = content == "Icon"
props["Icon Size"].IsHidden        = content == "Text"
props["Fill Active Icon"].IsHidden = content == "Text"
props["Line Position"].IsHidden    = indicator ~= "Line"
props["Indicator Size"].IsHidden   = indicator ~= "Line"
props["Indicator Margin"].IsHidden = indicator == "None"
props["Color Indicator"].IsHidden  = indicator == "None"
props["Divider Length"].IsHidden   = not props["Dividers"].Value
props["Divider Width"].IsHidden    = not props["Dividers"].Value
props["Color Divider"].IsHidden    = not props["Dividers"].Value
props["Panels"].IsHidden           = nav ~= "Page"
props["UCI Name"].IsHidden         = nav ~= "Layer"
props["Layer Transition"].IsHidden = nav ~= "Layer"

for i = 1, 12 do
  local used = i <= n
  props[("Menu %d Label"):format(i)].IsHidden  = not used or content == "Icon"
  props[("Menu %d Icon"):format(i)].IsHidden   = not used or content == "Text"
  props[("Menu %d Page"):format(i)].IsHidden   = not used or nav == "Output Only"
  props[("Menu %d Layers"):format(i)].IsHidden = not used or nav ~= "Layer"
end

if props.plugin_show_debug.Value == false then
  props["Debug Print"].IsHidden = true
end
