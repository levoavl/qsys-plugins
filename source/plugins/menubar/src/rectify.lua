-- (c) levo AVL | Elias Jenny - MIT License
local content   = props["Content"].Value
local indicator = props["Indicator Style"].Value

props["Rounded Corners"].IsHidden  = props["Corner Radius"].Value == 0
props["Font"].IsHidden             = content == "Icon"
props["Font Size"].IsHidden        = content == "Icon"
props["Bold Active"].IsHidden      = content == "Icon"
props["Icon Size"].IsHidden        = content == "Text"
props["Fill Active Icon"].IsHidden = content == "Text"
props["Line Position"].IsHidden    = indicator ~= "Line"
props["Indicator Size"].IsHidden   = indicator ~= "Line"
props["Indicator Margin"].IsHidden = indicator == "None"
props["Divider Length"].IsHidden   = not props["Dividers"].Value
props["Divider Width"].IsHidden    = not props["Dividers"].Value
props["Layer Transition"].IsHidden = props["Navigation"].Value ~= "Layer"
if props.plugin_show_debug.Value == false then
  props["Debug Print"].IsHidden = true
end
