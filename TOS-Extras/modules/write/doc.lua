-- ╔══════════════════════════════════════════════════════════════╗
-- ║  write — the document model                                  ║
-- ║                                                              ║
-- ║  Pure: parsing the source, resolving formatting, and asking  ║
-- ║  printerfmt where the pages fall. No component, no fs, no    ║
-- ║  drawing — so it unit-tests off-box (test_write.lua) and the ║
-- ║  page ruler works on a machine with no printer attached.     ║
-- ║                                                              ║
-- ║  THE FILE FORMAT IS PLAIN TEXT, and that is a decision, not  ║
-- ║  a shortcut. A .txt you can `cat`, `grep`, `edit` and mail   ║
-- ║  is worth more than a binary that only this program opens,   ║
-- ║  and a document that is never executable cannot become an    ║
-- ║  attack surface the way a load()-based format would (same    ║
-- ║  argument calc makes about formulas). Formatting rides on    ║
-- ║  DOT COMMANDS in column one — the roff idiom, which is both  ║
-- ║  period-appropriate and, more to the point, still legible    ║
-- ║  when the file is opened by something that has never heard   ║
-- ║  of this program.                                            ║
-- ║                                                              ║
-- ║    .title My Report      page title (the printed item name)  ║
-- ║    .center / .left       alignment, from here on             ║
-- ║    .color 0xFF0000       colour, from here on (.color off)   ║
-- ║    .page                 start a new page                    ║
-- ║    ..                    a literal line starting with a dot  ║
-- ╚══════════════════════════════════════════════════════════════╝

local fmt = require("printerfmt")

local doc = {}
doc._VERSION = "1.0.0"

doc.MAX_LINES = fmt.MAX_LINES
doc.MAX_WIDTH = fmt.MAX_WIDTH

-- ── Parsing ───────────────────────────────────────────────────────────
--- Parse source text into a title plus a flat list of formatted blocks.
-- @return { title=, blocks = { { text=, align=, color=, page=bool } }, warnings = {} }
--
-- Unknown or malformed dot commands are WARNINGS, never errors, and the
-- offending line is kept as literal text. A word processor that refuses
-- to open a document because line 40 has a typo has failed at its one
-- job; the warnings surface in the editor's status row instead.
function doc.parse(text)
  local out = { title = nil, blocks = {}, warnings = {} }
  local align, color = "left", nil

  local function warn(n, msg)
    out.warnings[#out.warnings + 1] = { line = n, text = msg }
  end

  -- Every block records the SOURCE LINE it came from. Source lines and
  -- blocks are not 1:1 — .title and .center produce no block at all — so
  -- the editor cannot use its cursor row as a block index, and carrying
  -- the number here is what stops the page ruler drifting the moment a
  -- document acquires its first dot command.
  for n, raw in ipairs(fmt.lines(text or "")) do
    if raw:sub(1, 2) == ".." then
      -- Escaped literal: ".." at the start means one leading dot.
      out.blocks[#out.blocks + 1] =
        { text = raw:sub(2), align = align, color = color, srcLine = n }
    elseif raw:sub(1, 1) == "." then
      local cmd, rest = raw:match("^%.(%a+)%s*(.*)$")
      cmd = cmd and cmd:lower() or nil
      if cmd == "title" then
        if rest == "" then warn(n, ".title with no text") else out.title = rest end
      elseif cmd == "center" or cmd == "centre" then
        align = "center"
      elseif cmd == "left" then
        align = "left"
      elseif cmd == "page" then
        out.blocks[#out.blocks + 1] = { page = true, srcLine = n }
      elseif cmd == "color" or cmd == "colour" then
        if rest == "" or rest:lower() == "off" then
          color = nil
        else
          local v = tonumber(rest) or tonumber(rest, 16)
          if v then
            color = math.floor(v) & 0xFFFFFF
          else
            warn(n, "'" .. rest .. "' is not a colour (try 0xFF0000)")
          end
        end
      else
        warn(n, "unknown command '" .. raw:match("^(%S+)") .. "'")
        out.blocks[#out.blocks + 1] =
          { text = raw, align = align, color = color, srcLine = n }
      end
    else
      out.blocks[#out.blocks + 1] =
        { text = raw, align = align, color = color, srcLine = n }
    end
  end
  return out
end

-- ── Layout ────────────────────────────────────────────────────────────
--- Lay a parsed document out into printed pages.
-- @param parsed  from doc.parse
-- @param opts    { measure=, maxWidth=, perPage= }
-- @return pages — array of arrays of { text=, align=, color=, src= }
--
-- Every emitted line carries `src`, the SOURCE LINE NUMBER it came from.
-- That back-reference is the whole point of doing layout here rather
-- than handing the text straight to the driver: it is what lets the
-- editor answer "the line under the cursor prints on page 2, line 7",
-- which is the one question a word processor exists to answer and a
-- plain text editor cannot.
function doc.layout(parsed, opts)
  opts = opts or {}
  local measure  = opts.measure or fmt.width
  local maxWidth = tonumber(opts.maxWidth) or fmt.MAX_WIDTH
  local perPage  = tonumber(opts.perPage) or fmt.MAX_LINES

  local pages, page = {}, {}
  local function flush()
    if #page > 0 then pages[#pages + 1] = page; page = {} end
  end
  local function emit(entry)
    page[#page + 1] = entry
    if #page >= perPage then flush() end
  end

  for _, b in ipairs(parsed.blocks or {}) do
    if b.page then
      flush()
    else
      local clean = fmt.sanitize(b.text or "")
      for _, piece in ipairs(fmt.wrap(clean, maxWidth, measure)) do
        emit({ text = piece, align = b.align or "left",
               color = b.color, src = b.srcLine })
      end
    end
  end
  flush()
  if #pages == 0 then pages[1] = {} end
  return pages
end

-- ── Where does a source line print? ───────────────────────────────────
--- Where source line `srcLine` lands in the printed output.
-- @return page, lineOnPage — nil, nil when that line prints nothing (a
--         .title or .center directive, or a line past the end)
--
-- A source line that WRAPS produces several printed lines; this returns
-- the first, which is what "where does my cursor print" means.
function doc.locate(pages, srcLine)
  if not srcLine then return nil, nil end
  for p, page in ipairs(pages or {}) do
    for l, entry in ipairs(page) do
      if entry.src == srcLine then return p, l end
    end
  end
  return nil, nil
end

--- The page a source line prints on, falling back to the nearest EARLIER
--- line that does print. The editor's ruler needs an answer even when
--- the cursor is sitting on a `.center` — "no page" would make the
--- indicator blink out exactly while you are formatting.
function doc.pageFor(pages, srcLine)
  if not srcLine then return nil end
  local best, bestSrc = nil, -1
  for p, page in ipairs(pages or {}) do
    for _, entry in ipairs(page) do
      if entry.src and entry.src <= srcLine and entry.src > bestSrc then
        best, bestSrc = p, entry.src
      end
    end
  end
  return best
end

-- ── Costing ───────────────────────────────────────────────────────────
--- What printing this document will consume.
function doc.cost(pages, copies) return fmt.cost(pages, copies) end

--- Statistics for the status rail. Words are whitespace-separated runs
--- of the PRINTED text, so dot commands do not inflate the count.
function doc.stats(parsed, pages)
  local words, chars = 0, 0
  for _, b in ipairs(parsed.blocks or {}) do
    if b.text then
      chars = chars + fmt.charCount(b.text)
      for _ in b.text:gmatch("%S+") do words = words + 1 end
    end
  end
  local lines = 0
  for _, p in ipairs(pages or {}) do lines = lines + #p end
  return { words = words, chars = chars, lines = lines, pages = #(pages or {}) }
end

-- ── Serializing ───────────────────────────────────────────────────────
--- Rebuild source text from the editor's line buffer. Trivial by design:
--- the buffer IS the source, so saving is a join and there is no lossy
--- model to round-trip through.
function doc.serialize(lines)
  return table.concat(lines or {}, "\n")
end

--- Split loaded text into the editor's line buffer. An empty file opens
--- as one empty line, not zero lines — a buffer with no lines has no
--- cursor position and every editor that allows it grows a special case.
function doc.toBuffer(text)
  local lines = fmt.lines(text or "")
  if #lines == 0 then lines[1] = "" end
  return lines
end

return doc
