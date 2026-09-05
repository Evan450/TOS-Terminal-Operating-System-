-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS printer layout  (require("printerfmt"))                 ║
-- ║                                                              ║
-- ║  The PURE half of the printing driver: measuring, wrapping,  ║
-- ║  paginating and costing a document. No component, no fs, no  ║
-- ║  require of anything — so it unit-tests off-box (see         ║
-- ║  test_printer.lua) and the word processor can lay out a      ║
-- ║  page on a machine with no printer attached to it at all.    ║
-- ║                                                              ║
-- ║  printer.lua (the hardware half) requires this; nothing      ║
-- ║  here requires printer.lua. Keep it that way — the moment    ║
-- ║  layout needs a proxy it stops being testable.               ║
-- ╚══════════════════════════════════════════════════════════════╝

local fmt = {}

fmt._VERSION = "1.0.0"

-- ── The page, as OpenPrinter defines it ───────────────────────────────
-- Both numbers are the MOD's, not ours, and both are enforced by it
-- THROWING rather than returning an error: writeln past the 20th line
-- raises "To many lines.", so a caller that does not paginate loses the
-- tail of the document with an exception instead of a short page.
fmt.MAX_LINES = 20    -- lines per printed page
fmt.MAX_WIDTH = 164   -- pixels per line (component maxWidth(), where present)

-- ── Character widths ──────────────────────────────────────────────────
-- Transcribed from OpenPrinter's util/CharacterWidth: every character is
-- 5 pixels wide unless listed here, and calculateWidth simply SUMS them
-- with no inter-character spacing.
--
-- This table is a FALLBACK, and it matters which way round that is. The
-- component exposes width()/maxWidth() from 1.9.4 onward and those are
-- ground truth — printer.lua prefers them and only falls back to this
-- when the attached printer is an older build that lacks the method, or
-- when there is no printer attached at all (composing offline). An
-- estimate that disagrees with the printer costs you a clipped line, so
-- fmt.wrap takes a `measure` function rather than reaching for this
-- directly: the driver passes the real one when it has it.
local W = {
  [32] = 3, [33] = 1, [34] = 3, [39] = 1, [40] = 3, [41] = 3, [42] = 3,
  [44] = 1, [46] = 1, [58] = 1, [59] = 1, [60] = 4, [62] = 4, [64] = 6,
  [73] = 3, [91] = 3, [93] = 3, [96] = 2, [102] = 4, [105] = 1,
  [107] = 4, [108] = 2, [116] = 3, [123] = 3, [124] = 1, [125] = 3,
  [126] = 6,
}
local DEFAULT_CHAR_WIDTH = 5

--- Codepoints of `s`, as an array. Uses utf8 where the host has it and
--- degrades to raw bytes where it does not; a multi-byte character
--- measured byte-by-byte would be counted several times over, which is
--- the difference between a conservative estimate and a wrong one.
local function codepoints(s)
  local out = {}
  if utf8 and utf8.codes then
    local ok = pcall(function()
      for _, c in utf8.codes(s) do out[#out + 1] = c end
    end)
    if ok then return out end
    out = {}
  end
  for i = 1, #s do out[i] = s:byte(i) end
  return out
end

--- Estimated pixel width of `s` on the printer's font.
-- Non-ASCII codepoints fall to the 5-pixel default, same as the mod's
-- own unlisted case.
function fmt.width(s)
  if type(s) ~= "string" then return 0 end
  local total = 0
  for _, c in ipairs(codepoints(s)) do
    total = total + (W[c] or DEFAULT_CHAR_WIDTH)
  end
  return total
end

--- Number of codepoints in `s` (the printer's charCount, computed here so
--- an offline preview can show it without a component).
function fmt.charCount(s)
  if type(s) ~= "string" then return 0 end
  return #codepoints(s)
end

-- ── Sanitizing ────────────────────────────────────────────────────────
-- Control bytes are stripped, always, and this is not cosmetic: the text
-- written to a page becomes part of an ITEM's NBT, and the title becomes
-- its display name. A stray \r or \0 in there is a corrupt item, not a
-- typo, and it is not visible to whoever typed it. \t expands to spaces
-- because the printer has no tab stops — it would otherwise land as a
-- single 5-pixel blob.
-- The section sign (§) is left ALONE on purpose: it is OpenPrinter's
-- colour/bold escape and stripping it would silently delete formatting a
-- document meant to have. Callers who do not want that pass strip = true.
function fmt.sanitize(s, opts)
  if type(s) ~= "string" then return "" end
  opts = opts or {}
  local tabWidth = tonumber(opts.tabWidth) or 4
  s = s:gsub("\t", string.rep(" ", math.max(1, math.min(16, tabWidth))))
  -- Strip C0 controls and DEL. Newlines are handled by the caller
  -- (fmt.lines) before this runs, so a surviving \n here is junk.
  s = s:gsub("[%z\1-\31\127]", "")
  if opts.strip then
    -- Also drop the formatting escape and everything it would consume.
    s = s:gsub("\194\167.", "")
  end
  return s
end

--- Split a document into logical lines on \n, tolerating \r\n and lone
--- \r. Returns an array; a trailing newline does NOT produce a final
--- empty line (a file that ends in \n is not a document with a blank
--- last line, and printing one wastes a line of a 20-line page).
function fmt.lines(text)
  if type(text) ~= "string" then return {} end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  if #out > 0 and out[#out] == "" then table.remove(out) end
  return out
end

-- ── Wrapping ──────────────────────────────────────────────────────────
--- Greedy word wrap of ONE logical line to `maxPx`.
-- @param line   string
-- @param maxPx  number  pixel budget (default fmt.MAX_WIDTH)
-- @param measure function(string) -> pixels (default fmt.width)
-- @return array of strings (at least one entry; an empty line wraps to
--         a single empty line, which is a deliberate blank on the page)
--
-- A word too long to fit on a line of its own is HARD-SPLIT rather than
-- dropped or left to overflow. Overflowing is what the mod does if you
-- hand it an over-wide string — the tail is simply not rendered — and a
-- URL or a hash silently losing its end is the worst of the three
-- outcomes, because the page still looks finished.
function fmt.wrap(line, maxPx, measure)
  measure = measure or fmt.width
  maxPx = tonumber(maxPx) or fmt.MAX_WIDTH
  if type(line) ~= "string" then return { "" } end
  if line == "" then return { "" } end
  if maxPx <= 0 then return { line } end

  local out, cur = {}, ""

  -- Split a single over-wide token into as many pieces as it takes.
  local function hardSplit(word)
    local piece = ""
    for _, c in ipairs(codepoints(word)) do
      local ch = (utf8 and utf8.char) and utf8.char(c) or string.char(c % 256)
      if measure(piece .. ch) > maxPx and piece ~= "" then
        out[#out + 1] = piece
        piece = ch
      else
        piece = piece .. ch
      end
    end
    return piece
  end

  for word in line:gmatch("%S+") do
    local candidate = (cur == "") and word or (cur .. " " .. word)
    if measure(candidate) <= maxPx then
      cur = candidate
    else
      if cur ~= "" then out[#out + 1] = cur; cur = "" end
      if measure(word) > maxPx then
        cur = hardSplit(word)
      else
        cur = word
      end
    end
  end
  if cur ~= "" then out[#out + 1] = cur end
  if #out == 0 then out[#out + 1] = "" end
  return out
end

-- ── Alignment ─────────────────────────────────────────────────────────
-- The mod accepts ANY string for the alignment argument and only acts on
-- "center"; anything else falls through to left. We refuse unknown values
-- instead of forwarding them, because a caller who typed "centre" or
-- "middle" gets a silently left-aligned page and no way to tell why.
local ALIGNMENTS = { left = true, center = true }

function fmt.align(a)
  if a == nil then return "left" end
  if type(a) ~= "string" then return nil, "alignment must be a string" end
  local v = a:lower()
  if ALIGNMENTS[v] then return v end
  return nil, "unknown alignment '" .. a .. "' (left, center)"
end

-- ── Pagination ────────────────────────────────────────────────────────
--- Chunk `lines` into pages of at most `perPage` entries.
-- Entries may be plain strings or { text=, color=, align= } tables; both
-- pass through untouched. An empty input yields ONE empty page rather
-- than none, so "print this" on an empty document is still a decision the
-- caller makes rather than a silent no-op.
function fmt.paginate(lines, perPage)
  perPage = tonumber(perPage) or fmt.MAX_LINES
  if perPage < 1 then perPage = 1 end
  local pages, page = {}, {}
  for _, l in ipairs(lines or {}) do
    page[#page + 1] = l
    if #page >= perPage then pages[#pages + 1] = page; page = {} end
  end
  if #page > 0 or #pages == 0 then pages[#pages + 1] = page end
  return pages
end

-- ── Whole-document layout ─────────────────────────────────────────────
--- Turn a document into printable pages.
-- @param text string
-- @param opts table|nil
--   maxWidth  pixel budget per line     (default fmt.MAX_WIDTH)
--   perPage   lines per page            (default fmt.MAX_LINES)
--   measure   function(s) -> pixels     (default fmt.width)
--   align     default alignment for every line
--   color     default colour (integer) or nil for the black cartridge
--   pageBreak string; a logical line equal to this forces a new page
--             (default "\f" — form feed, the obvious thing and one a
--             text editor can insert)
--   wrap      set false to leave over-wide lines alone (the printer will
--             clip them; only useful for pre-formatted material)
-- @return pages — array of arrays of { text=, color=, align= }
-- @return nil, err on an unusable option (a misspelled alignment is a
--         refusal here rather than a silently left-aligned page)
function fmt.layout(text, opts)
  opts = opts or {}
  local measure  = opts.measure or fmt.width
  local maxWidth = tonumber(opts.maxWidth) or fmt.MAX_WIDTH
  local perPage  = tonumber(opts.perPage) or fmt.MAX_LINES
  local align, aErr = fmt.align(opts.align)
  if not align then return nil, aErr end
  local color    = opts.color
  local brk      = opts.pageBreak or "\f"
  local doWrap   = opts.wrap ~= false

  local pages, page = {}, {}
  local function flush()
    -- A forced break on an already-empty page would emit a blank sheet;
    -- that costs real paper, so it is collapsed.
    if #page > 0 then pages[#pages + 1] = page; page = {} end
  end

  for _, logical in ipairs(fmt.lines(text)) do
    if logical == brk then
      flush()
    else
      local clean = fmt.sanitize(logical, opts)
      local parts = doWrap and fmt.wrap(clean, maxWidth, measure) or { clean }
      for _, p in ipairs(parts) do
        page[#page + 1] = { text = p, color = color, align = align }
        if #page >= perPage then flush() end
      end
    end
  end
  flush()
  if #pages == 0 then pages[1] = {} end
  return pages
end

-- ── Consumables ───────────────────────────────────────────────────────
--- What a job will cost, so the driver can refuse BEFORE it starts.
-- @param pages   array of pages (from fmt.layout / fmt.paginate)
-- @param copies  number of copies (default 1)
-- @return { paper = n, black = n, color = n }
--
-- The colour count is per COLOURED LINE, not per page: OpenPrinter
-- charges one unit of colour ink for each writeln that carries a colour
-- argument. That is why the driver never passes a colour it was not
-- explicitly given — defaulting to "black" in the caller would otherwise
-- burn a colour cartridge on an all-black document.
function fmt.cost(pages, copies)
  copies = math.max(1, math.floor(tonumber(copies) or 1))
  local black, color = 0, 0
  for _, page in ipairs(pages or {}) do
    for _, line in ipairs(page) do
      if type(line) == "table" and line.color ~= nil then
        color = color + 1
      else
        black = black + 1
      end
    end
  end
  return {
    paper = #(pages or {}) * copies,
    black = black * copies,
    color = color * copies,
  }
end

return fmt
