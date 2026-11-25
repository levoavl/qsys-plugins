-- (c) levo AVL | Elias Jenny - MIT License
local W, H = 420, 340
local C = LevoBrand.Colors
LevoBrand.Background(graphics, W, H)
local y = LevoBrand.Header(graphics, W, LevoBrand.PluginName(PluginInfo), CurrentPage) + 16

local function Label(text, x, ly, w)
  table.insert(graphics, {
    Type = "Text", Text = text, Position = { x, ly }, Size = { w, 20 },
    FontSize = 12, HTextAlign = "Right", Color = C.Onyx,
  })
end

if CurrentPage == "Control" then
  Label("Status", 16, y, 100)
  layout["Status"] = { PrettyName = "Status", Position = { 124, y }, Size = { 280, 20 } }

elseif CurrentPage == "Setup" then
  Label("IP Address", 16, y, 100)
  layout["IPAddress"] = {
    PrettyName = "Setup~IP Address", Style = "Text",
    Position = { 124, y }, Size = { 140, 20 },
  }

  -- health readouts (levo_health.lua)
  for i, name in ipairs(LevoHealth.CONTROLS) do
    Label(name, 16, y + 28 * i, 100)
    layout[name] = { PrettyName = "Debug~" .. name, Style = "Text", Position = { 124, y + 28 * i }, Size = { 100, 20 } }
  end

elseif CurrentPage == "About" then
  LevoBrand.About(graphics, 16, y, W - 32, PluginInfo)
end
