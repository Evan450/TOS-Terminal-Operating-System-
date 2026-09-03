-- TOS OpenOS Compatibility - colors
local colors = {
  white      = 0, orange   = 1, magenta    = 2, lightblue  = 3,
  yellow     = 4, lime     = 5, pink       = 6, gray       = 7,
  silver     = 8, cyan     = 9, purple     = 10, blue      = 11,
  brown      = 12, green   = 13, red       = 14, black     = 15,
}
-- Reverse lookup (number -> name).
--! Snapshot the names FIRST, then write. Inserting a NEW key into a table
--! that is being walked by pairs() is undefined behaviour in Lua ("you may
--! clear or modify existing fields, but not add new ones"), and here it bit:
--! the rehash triggered by the first insert made next() skip entries, so
--! anywhere from 0 to 13 of the 16 reverse entries silently went missing —
--! a DIFFERENT set on every boot, because string hashing is seeded per
--! process. OpenOS's own lib/colors.lua collects the keys into a separate
--! array for exactly this reason; so do we. Same fix in sides.lua and
--! keyboard.lua. (test_compat_tables.lua)
do
  local names = {}
  for name in pairs(colors) do names[#names + 1] = name end
  for _, name in ipairs(names) do
    local num = colors[name]
    if colors[num] == nil then colors[num] = name end
  end
end
return colors
