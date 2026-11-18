-- (c) levo AVL | Elias Jenny - MIT License
local count = props["Universe Count"].Value
for u = 1, 4 do
  props["Channels U" .. u].IsHidden = u > count
end
if props.plugin_show_debug.Value == false then
  props["Debug Print"].IsHidden = true
end
