-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Shell — text selection maths                            ║
-- ║                                                              ║
-- ║  Three surfaces let you select text — the command prompt (one║
-- ║  line), the editor (a rectangle of lines) and a view buffer   ║
-- ║  (whole lines of read-only output) — and all three need the  ║
-- ║  same handful of operations: normalise an anchor and a cursor ║
-- ║  into a range, pull the text out of it, take it out of the    ║
-- ║  buffer, put other text in its place.                         ║
-- ║                                                              ║
-- ║  Written once, here, PURE: no requires, no globals, no draw   ║
-- ║  calls. Three copies of "which end of the selection is the    ║
-- ║  start" is three places for an off-by-one to hide, and this   ║
-- ║  is exactly the kind of index arithmetic that unit tests are  ║
-- ║  good at and a person reading code is not.                    ║
-- ║                                                              ║
-- ║  CONVENTIONS, and they are the same everywhere:              ║
-- ║    · a one-line offset is a CURSOR position, 1..#s+1, the     ║
-- ║      same space S.cmdCursor already lives in — so "select     ║
-- ║      from 3 to 5" covers the two characters 3 and 4           ║
-- ║    · a position in a buffer is { row = r, col = c }, with col ║
-- ║      in the same 1..#line+1 cursor space                       ║
-- ║    · an anchor of nil means "no selection", never "0"         ║
-- ╚══════════════════════════════════════════════════════════════╝

local sel = {}

-- ============================================================
-- One line (the command prompt)
-- ============================================================

--- Normalise anchor + cursor into (from, to), from <= to. Returns nil
--- when there is no selection or it is empty — an empty selection is
--- NOT a selection, so copy falls back to "the whole line" instead of
--- putting nothing on the clipboard.
function sel.range(anchor, cursor)
  if type(anchor) ~= "number" or type(cursor) ~= "number" then return nil end
  local from, to = anchor, cursor
  if from > to then from, to = to, from end
  if from == to then return nil end
  return from, to
end

--- The selected text of `s`, or nil.
function sel.text(s, anchor, cursor)
  local from, to = sel.range(anchor, cursor)
  if not from then return nil end
  return tostring(s or ""):sub(from, to - 1)
end

--- Remove the selection. Returns (newString, removedText, newCursor).
--- With no selection the string is returned untouched, so a caller can
--- run this unconditionally on "typed a character" without checking.
function sel.remove(s, anchor, cursor)
  s = tostring(s or "")
  local from, to = sel.range(anchor, cursor)
  if not from then return s, nil, cursor end
  return s:sub(1, from - 1) .. s:sub(to), s:sub(from, to - 1), from
end

--- Insert `text` at `at`. Returns (newString, newCursor).
function sel.insert(s, at, text)
  s = tostring(s or "")
  text = tostring(text or "")
  at = math.max(1, math.min(#s + 1, at or (#s + 1)))
  return s:sub(1, at - 1) .. text .. s:sub(at), at + #text
end

--- Replace the selection (if any) with `text`.
--- Returns (newString, newCursor).
function sel.replace(s, anchor, cursor, text)
  local cut, _, at = sel.remove(s, anchor, cursor)
  return sel.insert(cut, at or cursor, text)
end

-- ============================================================
-- A buffer of lines (the editor)
-- ============================================================

--- Order two { row, col } positions. Returns (first, second) as plain
--- tables; nil when either is missing or they are the same point.
function sel.orderPos(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return nil end
  local ar, ac = a.row or 1, a.col or 1
  local br, bc = b.row or 1, b.col or 1
  if ar == br and ac == bc then return nil end
  if ar > br or (ar == br and ac > bc) then
    ar, ac, br, bc = br, bc, ar, ac
  end
  return { row = ar, col = ac }, { row = br, col = bc }
end

--- The selected text as an array of lines, or nil.
function sel.extract(lines, a, b)
  local first, last = sel.orderPos(a, b)
  if not first then return nil end
  lines = lines or {}
  if first.row == last.row then
    local l = lines[first.row] or ""
    return { l:sub(first.col, last.col - 1) }
  end
  local out = { (lines[first.row] or ""):sub(first.col) }
  for r = first.row + 1, last.row - 1 do out[#out + 1] = lines[r] or "" end
  out[#out + 1] = (lines[last.row] or ""):sub(1, last.col - 1)
  return out
end

--- Remove the selection from `lines` IN PLACE. Returns (removedLines,
--- row, col) — the position the cursor should land on — or nil when
--- there was no selection. The buffer never becomes empty: an editor
--- with zero lines has no line to type on.
function sel.removeBlock(lines, a, b)
  local first, last = sel.orderPos(a, b)
  if not first then return nil end
  local removed = sel.extract(lines, first, last)
  local head = (lines[first.row] or ""):sub(1, first.col - 1)
  local tail = (lines[last.row] or ""):sub(last.col)
  for _ = first.row + 1, last.row do table.remove(lines, first.row + 1) end
  lines[first.row] = head .. tail
  if #lines == 0 then lines[1] = "" end
  return removed, first.row, first.col
end

--- Insert an array of lines at { row, col } IN PLACE.
--- Returns (row, col) after the inserted text.
function sel.insertBlock(lines, row, col, block)
  lines = lines or {}
  block = block or {}
  if #block == 0 then return row, col end
  if #lines == 0 then lines[1] = "" end
  row = math.max(1, math.min(#lines, row or 1))
  local line = lines[row] or ""
  col = math.max(1, math.min(#line + 1, col or 1))
  local head, tail = line:sub(1, col - 1), line:sub(col)

  if #block == 1 then
    lines[row] = head .. block[1] .. tail
    return row, col + #block[1]
  end
  lines[row] = head .. block[1]
  for i = 2, #block do
    table.insert(lines, row + i - 1, block[i])
  end
  local lastRow = row + #block - 1
  local lastCol = #block[#block] + 1
  lines[lastRow] = block[#block] .. tail
  return lastRow, lastCol
end

--- Is (row, col) inside the selection? Used by the renderer, one cell at
--- a time, so it stays a comparison and never allocates.
function sel.contains(a, b, row, col)
  local first, last = sel.orderPos(a, b)
  if not first then return false end
  if row < first.row or row > last.row then return false end
  if row == first.row and col < first.col then return false end
  if row == last.row and col >= last.col then return false end
  return true
end

-- ============================================================
-- Whole lines (a read-only view buffer)
-- ============================================================

--- Normalise two line indices into an inclusive (from, to). Unlike the
--- character ranges above, a single line IS a selection here: there is
--- no cursor to distinguish "on line 4" from "line 4 selected", so the
--- anchor being set is the whole signal.
function sel.lineRange(anchor, cursor)
  if type(anchor) ~= "number" or type(cursor) ~= "number" then return nil end
  if anchor > cursor then return cursor, anchor end
  return anchor, cursor
end

--- Pull an inclusive line range out of a view buffer. `content` rows are
--- either plain strings or { text, colour } pairs, which is how view
--- tabs store them; both are accepted and only the text comes back.
function sel.lines(content, anchor, cursor)
  local from, to = sel.lineRange(anchor, cursor)
  if not from then return nil end
  content = content or {}
  local out = {}
  for i = math.max(1, from), math.min(#content, to) do
    local row = content[i]
    if type(row) == "table" then out[#out + 1] = tostring(row[1] or "")
    else out[#out + 1] = tostring(row or "") end
  end
  if #out == 0 then return nil end
  return out
end

return sel
