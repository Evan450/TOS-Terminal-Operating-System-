-- TOS OpenOS Compatibility - sides
-- Maps side names to numbers for redstone/inventory operations.
local sides = {
  bottom = 0, down  = 0,
  top    = 1, up    = 1,
  back   = 2, north = 2,
  front  = 3, south = 3,
  right  = 4, west  = 4,
  left   = 5, east  = 5,
}
-- Reverse lookup
for name, num in pairs(sides) do
  if not sides[num] then sides[num] = name end
end
return sides
