--! The number -> name direction is written out LITERALLY rather than derived
--! from the name -> number entries. Deriving it needs a pairs() walk, and
--! (a) adding keys during that walk is undefined behaviour that silently
--! dropped entries — sides[2] came back nil on roughly a third of boots —
--! and (b) every side here has two names, so even when the walk did finish
--! the winner was whichever pairs() happened to reach first: sides[0] was
--! "bottom" one boot and "down" the next. OpenOS's lib/sides.lua spells the
--! canonical names out; matching it is the only way the reverse map is
--! stable AND agrees with what an OpenOS program expects to read.
--! (test_compat_tables.lua)
local sides = {
  [0] = "bottom",
  [1] = "top",
  [2] = "back",
  [3] = "front",
  [4] = "right",
  [5] = "left",

  bottom = 0, down  = 0,
  top    = 1, up    = 1,
  back   = 2, north = 2,
  front  = 3, south = 3,
  right  = 4, west  = 4,
  left   = 5, east  = 5,
}
return sides
