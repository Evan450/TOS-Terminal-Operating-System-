local logo = {}

logo.MARK = {
  "████████  ████████  ████████",
  "   ██     ██    ██  ██      ",
  "   ██     ██    ██  ████████",
  "   ██     ██    ██        ██",
  "   ██     ████████  ████████",
}
logo.MARK_W = 28

logo.MARK_ASCII = {
  "TTTTTTT  OOOOOO  SSSSSS",
  "   T     O    O  S     ",
  "   T     O    O  SSSSSS",
  "   T     O    O       S",
  "   T     OOOOOO  SSSSSS",
}
logo.MARK_ASCII_W = 23

logo.TAGLINE = "Terminal Operating System"
logo.VENDOR  = "Strata Systems LLC"
logo.MOTTO   = "Firmware with a will of its own."

logo.COLORS = {
  mark = 0x00AAFF, tagline = 0xFFFFFF, vendor = 0x00FF66, motto = 0x888888,
  blank = 0xFFFFFF,
}

local function lead(vis, width, indent)
  if indent ~= nil then return string.rep(" ", indent) end
  if not width or width <= vis then return "" end
  return string.rep(" ", math.floor((width - vis) / 2))
end

function logo.banner(opts)
  opts = opts or {}
  local width  = opts.width or 50
  local mark   = opts.ascii and logo.MARK_ASCII   or logo.MARK
  local markW  = opts.ascii and logo.MARK_ASCII_W or logo.MARK_W
  local out = {}
  for _, ln in ipairs(mark) do
    out[#out + 1] = { lead(markW, width, opts.indent) .. ln, "mark" }
  end
  out[#out + 1] = { "", "blank" }
  out[#out + 1] = { lead(#logo.TAGLINE, width, opts.indent) .. logo.TAGLINE, "tagline" }
  if not opts.compact then
    out[#out + 1] = { lead(#logo.VENDOR, width, opts.indent) .. logo.VENDOR, "vendor" }
    out[#out + 1] = { lead(#logo.MOTTO,  width, opts.indent) .. logo.MOTTO,  "motto" }
  end
  return out
end

return logo
