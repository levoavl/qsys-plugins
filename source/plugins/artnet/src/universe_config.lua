-- (c) levo AVL | Elias Jenny - MIT License
-- Per-universe configuration from the properties. Used by controls, layout and
-- runtime alike, so all three always agree on modes and channel ranges.

ArtNetConfig = {}

-- props: the property table (Designer) or Properties (runtime).
-- Returns { mode = "Send" | "Receive", first = n, last = n, count = n }
function ArtNetConfig.Universe(props, u)
  local mode = props["Mode U" .. u] and props["Mode U" .. u].Value or "Send"
  local first = props["Start Channel U" .. u] and props["Start Channel U" .. u].Value or 1
  first = math.max(1, math.min(512, first))
  local count = math.max(1, math.min(props["Channels U" .. u].Value, 513 - first))
  return { mode = mode, first = first, last = first + count - 1, count = count }
end

function ArtNetConfig.Count(props)
  return props["Universe Count"].Value
end

function ArtNetConfig.HasMode(props, mode)
  for u = 1, ArtNetConfig.Count(props) do
    if ArtNetConfig.Universe(props, u).mode == mode then return true end
  end
  return false
end
