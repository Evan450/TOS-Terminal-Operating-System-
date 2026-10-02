-- ╔══════════════════════════════════════╗
-- ║  TOS Shell - Text columns            ║
-- ╚══════════════════════════════════════╝
-- The editor's two column models, and the one map between them.
--
-- A line is a string of BYTES, and every edit (insert, delete, find,
-- selection) is a byte operation -- so the cursor is a byte index. The
-- screen is CELLS: kernel.screen paints one character per cell. Those
-- are the same number only while a line is ASCII; from the first é on,
-- a byte count draws text, the cursor and the scroll edge in the wrong
-- place (AUDIT 5, "the editor counts bytes where the screen counts
-- characters").
--
-- So a byte column here always sits on a UNIT boundary, and everything
-- drawn is measured in units, where one unit is exactly one cell:
--   * an ASCII byte, or a well-formed UTF-8 sequence (2-4 bytes), is one
--     unit and is drawn as itself;
--   * any other byte -- a stray continuation, a truncated sequence, a
--     byte no UTF-8 starts with -- is one unit of its own, drawn as "?".
--     It stays visible, and the cursor can stop on it and delete it,
--     instead of vanishing into the screen's own UTF-8 split.
-- Pure ASCII lines take a fast path everywhere: on them bytes ARE cells.
--
-- Why not kernel.ustr: it measures through OC's `unicode` API and falls
-- back to BYTES when that is absent, so off-box -- every test -- the
-- editor would be byte-counting again; and it counts a wide CJK glyph as
-- two columns, where kernel.screen's shadow buffer stores one character
-- per cell. This module follows the screen, in plain Lua.

local M = {}

local function isAscii(s)
  return not s:find("[\128-\255]")
end
M.isAscii = isAscii

-- Length in bytes of the unit starting at byte i, and whether it is a
-- well-formed character (false: an invalid byte, drawn as "?").
local function unitAt(s, i)
  local b = s:byte(i)
  if not b then return 0, false end
  if b < 0x80 then return 1, true end
  local n = (b >= 0xC2 and b <= 0xDF) and 2
         or (b >= 0xE0 and b <= 0xEF) and 3
         or (b >= 0xF0 and b <= 0xF4) and 4
         or 1
  if n == 1 then return 1, false end
  for k = 1, n - 1 do
    local c = s:byte(i + k)
    if not c or c < 0x80 or c > 0xBF then return 1, false end
  end
  return n, true
end
M.unitAt = unitAt

--- Every unit of `s`: starts[k] is the byte where cell k begins, disps[k]
--- what that cell shows.
function M.units(s)
  local starts, disps = {}, {}
  local i, n = 1, #s
  while i <= n do
    local len, ok = unitAt(s, i)
    starts[#starts + 1] = i
    disps[#disps + 1] = ok and s:sub(i, i + len - 1) or "?"
    i = i + len
  end
  return starts, disps
end

--- How many cells `s` takes on screen.
function M.cells(s)
  if isAscii(s) then return #s end
  local count, i, n = 0, 1, #s
  while i <= n do
    i = i + (unitAt(s, i))
    count = count + 1
  end
  return count
end

--- The cell a byte column sits in. Past the end counts on from there, so
--- the cursor after the last character is cells + 1.
function M.cellOf(s, col)
  if col <= 1 then return 1 end
  if isAscii(s) then return col end
  local cell, i, n = 1, 1, #s
  while i < col and i <= n do
    i = i + (unitAt(s, i))
    cell = cell + 1
  end
  if col > n + 1 then cell = cell + (col - (n + 1)) end
  return cell
end

--- The byte column where cell `cell` begins; one past the end of the
--- line for any cell beyond it.
function M.colOf(s, cell)
  if cell <= 1 then return 1 end
  if isAscii(s) then return math.min(cell, #s + 1) end
  local i, n, c = 1, #s, 1
  while c < cell and i <= n do
    i = i + (unitAt(s, i))
    c = c + 1
  end
  return i
end

--- The byte column of the next unit after `col` (col is on a boundary).
function M.nextCol(s, col)
  if col > #s then return #s + 1 end
  local len = unitAt(s, col)
  return col + math.max(1, len)
end

--- The byte column of the unit before `col`.
function M.prevCol(s, col)
  if col <= 1 then return 1 end
  if isAscii(s) then return col - 1 end
  local i, prev, n = 1, 1, #s
  while i < col and i <= n do
    prev = i
    i = i + (unitAt(s, i))
  end
  return prev
end

--- What cells fromCell..toCell of `s` show, as one string.
function M.slice(s, fromCell, toCell)
  if fromCell < 1 then fromCell = 1 end
  if toCell < fromCell then return "" end
  if isAscii(s) then return s:sub(fromCell, toCell) end
  local out, i, n, cell = {}, 1, #s, 1
  while i <= n and cell <= toCell do
    local len, ok = unitAt(s, i)
    if cell >= fromCell then out[#out + 1] = ok and s:sub(i, i + len - 1) or "?" end
    i = i + len
    cell = cell + 1
  end
  return table.concat(out)
end

return M
