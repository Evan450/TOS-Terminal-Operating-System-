-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Unicode-aware string helpers           ║
-- ║                                                      ║
-- ║  The shell's layout math is BYTE math (#s, :sub,     ║
-- ║  padR) — correct for ASCII, wrong for translated     ║
-- ║  text: Cyrillic is 2 bytes/char in UTF-8, so a naive ║
-- ║  :sub(1, W) slices a letter in half, and #s-based    ║
-- ║  centring drifts left. These helpers count DISPLAY   ║
-- ║  COLUMNS via OC's `unicode` API when present (which  ║
-- ║  also handles double-width CJK cells), and fall back ║
-- ║  to plain byte ops off-box so unit tests and ASCII   ║
-- ║  callers behave identically to before.               ║
-- ║                                                      ║
-- ║  Use these at any draw site that renders i18n.t()    ║
-- ║  output. ASCII-only sites may keep byte math.        ║
-- ╚══════════════════════════════════════════════════════╝

local ustr = {}

-- OC provides a global/module `unicode` (wlen/wtrunc/len/sub). Probe once;
-- absent (off-box tests, exotic hosts) → byte fallback.
local U = nil
do
  local ok, mod = pcall(require, "unicode")
  if ok and type(mod) == "table" and mod.len and mod.sub then U = mod end
end

--- Number of CHARACTERS in s (not bytes).
function ustr.len(s)
  s = tostring(s or "")
  if U then
    local ok, n = pcall(U.len, s)
    if ok and n then return n end
  end
  return #s
end

--- Display WIDTH of s in screen columns (wide CJK cells count as 2).
function ustr.width(s)
  s = tostring(s or "")
  if U and U.wlen then
    local ok, n = pcall(U.wlen, s)
    if ok and n then return n end
  end
  return ustr.len(s)
end

--- Character-indexed substring (like string.sub but per character).
function ustr.sub(s, i, j)
  s = tostring(s or "")
  if U then
    local ok, r = pcall(U.sub, s, i, j)
    if ok and r then return r end
  end
  return s:sub(i, j)
end

--- Truncate s so it renders in at most `cols` display columns.
--- Never cuts a multi-byte character in half.
function ustr.fit(s, cols)
  s = tostring(s or "")
  cols = math.max(0, math.floor(cols or 0))
  if ustr.width(s) <= cols then return s end
  if cols == 0 then return "" end
  if U and U.wtrunc then
    -- OC semantics: wtrunc(value, count) truncates to be LESS than
    -- `count` wide, i.e. the result fits in count-1 columns.
    local ok, r = pcall(U.wtrunc, s, cols + 1)
    if ok and r then return r end
  end
  -- Fallback: walk characters until the budget is spent.
  local out, used = "", 0
  for i = 1, ustr.len(s) do
    local ch = ustr.sub(s, i, i)
    local w = ustr.width(ch)
    if used + w > cols then break end
    out = out .. ch
    used = used + w
  end
  return out
end

--- Pad-right / pad-left to an exact column width (fits first).
function ustr.padR(s, cols)
  s = ustr.fit(s, cols)
  return s .. string.rep(" ", cols - ustr.width(s))
end

function ustr.padL(s, cols)
  s = ustr.fit(s, cols)
  return string.rep(" ", cols - ustr.width(s)) .. s
end

--- Starting column that centres s inside `cols` columns (1-based offset 0).
function ustr.centerOffset(s, cols)
  return math.max(0, math.floor((cols - ustr.width(s)) / 2))
end

return ustr
