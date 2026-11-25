-- (c) levo AVL | Elias Jenny - MIT License
local count = props["Universe Count"].Value
for u = 1, 4 do
  local hidden = u > count
  props["Mode U" .. u].IsHidden = hidden
  props["Start Channel U" .. u].IsHidden = hidden
  props["Channels U" .. u].IsHidden = hidden
end
local anySend = false
for u = 1, count do
  if props["Mode U" .. u].Value == "Send" then anySend = true end
end
props["Send Mode"].IsHidden = not anySend
props["Refresh Rate (Hz)"].IsHidden = not anySend
if props.plugin_show_debug.Value == false then
  props["Debug Print"].IsHidden = true
end
