-- (c) levo AVL | Elias Jenny - MIT License
local custom = props["Model"].Value == AtemTopology.CUSTOM
for _, name in ipairs({
  "Custom M/Es", "Custom Inputs", "Custom Keyers per M/E", "Custom Downstream Keyers",
  "Custom Aux Outputs", "Custom Media Players", "Custom SuperSources", "Custom Audio",
  "Custom Streaming / Recording",
}) do
  props[name].IsHidden = not custom
end
if props.plugin_show_debug.Value == false then
  props["Debug Print"].IsHidden = true
end
