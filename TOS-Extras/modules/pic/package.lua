-- Optional Utilities — pic: pictures on a text screen.
--
-- Shows a MineOS .pic or a PNG on any GPU: 256 colours on tier 3, 16 on
-- tier 2, dithered black and white on tier 1. A PNG needs nothing else on
-- the machine: the inflate, the filters and the dithering are plain Lua,
-- so `pic <url>` works with an internet card and no service behind it.
-- `pic convert` writes a .pic, which opens faster and can go on a floppy.
--
-- Runs inside the pkg sandbox. component for the GPU; fs.read for the
-- pictures and fs.write for `pic convert`; internet for `pic <url>` and
-- nothing else, since a picture never sends anything back. No `load`: a
-- picture is data and is never executed.
return {
  name        = "pic",
  version     = "1.0.1",
  kind        = "command",
  category    = "productivity",
  description = "Picture viewer: MineOS .pic and PNG on any GPU, from disk or a URL, and PNG to .pic.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/pic/init.lua",
    "/usr/modules/pic/ocif.lua",
    "/usr/modules/pic/png.lua",
    "/usr/modules/pic/convert.lua",
  },
  fullscreen  = true,
  -- Nothing here changes while it is not looked at.
  background  = "freeze",

  commands     = { pic = "/usr/modules/pic/init.lua" },
  handles      = {
    { ext = { "pic" }, as = "native" },
    { ext = { "png" }, as = "native" },
  },
  capabilities = { "fs.read", "fs.write", "component", "internet" },
  requires    = {},
}
