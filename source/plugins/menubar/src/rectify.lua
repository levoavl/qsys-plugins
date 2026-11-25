-- (c) levo AVL | Elias Jenny - MIT License
props["Layer Transition"].IsHidden = props["Navigation"].Value ~= "Layer"
if props.plugin_show_debug.Value == false then
  props["Debug Print"].IsHidden = true
end
