-- ╔═══════════════════════════════════════════╗
-- ║  TOS kernel.logo — shared ASCII branding                  ║
-- ║                                                           ║
-- ║  One wordmark for the boot splash, the AMIBIOS-style      ║
-- ║  configuration POST screen, and the login screen, so TOS  ║
-- ║  presents one identity everywhere. Skynet / American      ║
-- ║  Megatrends flavour: a solid block wordmark over a vendor ║
-- ║  line that winks at both.                                 ║
-- ║                                                           ║
-- ║  DEPENDENCY-FREE on purpose — it is required during early ║
-- ║  boot (before most of the kernel is up) and from the      ║
-- ║  installer, so it pulls in nothing and every caller       ║
-- ║  pcall-requires it with a graceful fallback.              ║
-- ╚═══════════════════════════════════════════╝

local logo = {}

-- Full-block "TOS" wordmark — 5 rows, 28 DISPLAY columns wide. Each U+2588
-- glyph is one screen cell but 3 UTF-8 bytes, so centre on logo.MARK_W, never
-- on #string.
logo.MARK = {
  "████████  ████████  ████████",
  "   ██     ██    ██  ██      ",
  "   ██     ██    ██  ████████",
  "   ██     ██    ██        ██",
  "   ██     ████████  ████████",
}
logo.MARK_W = 28

-- ASCII-only fallback for monochrome (T1) screens, where solid blocks render
-- as featureless bars. 23 columns wide.
logo.MARK_ASCII = {
  "TTTTTTT  OOOOOO  SSSSSS",
  "   T     O    O  S     ",
  "   T     O    O  SSSSSS",
  "   T     O    O       S",
  "   T     OOOOOO  SSSSSS",
}
logo.MARK_ASCII_W = 23

logo.TAGLINE = "Terminal Operating System"
logo.VENDOR  = "Strata Systems LLC"   -- vendor line (splash/POST/login)
logo.MOTTO   = "Firmware with a will of its own."   -- Skynet wink

-- Suggested colours per role. Callers on themed surfaces may override to stay
-- palette-safe; boot/installer use these directly.
logo.COLORS = {
  mark = 0x00AAFF, tagline = 0xFFFFFF, vendor = 0x00FF66, motto = 0x888888,
  blank = 0xFFFFFF,
}

-- Leading pad for a line of visual width `vis`: centre within `width`, or a
-- fixed left `indent` when one is given (boot log style).
local function lead(vis, width, indent)
  if indent ~= nil then return string.rep(" ", indent) end
  if not width or width <= vis then return "" end
  return string.rep(" ", math.floor((width - vis) / 2))
end

--- The banner as role-tagged, pre-padded lines for a LINE-BASED caller (the
--- boot splash, the installer). role ∈ "mark"|"tagline"|"vendor"|"motto"|
--- "blank". opts: { ascii=bool, compact=bool (drop vendor/motto), indent=N
--- (left-align instead of centre), width=N }.
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
