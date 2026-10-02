local M = {}

local function isAscii(s)
  return not s:find("[\128-\255]")
end
M.isAscii = isAscii

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

function M.cells(s)
  if isAscii(s) then return #s end
  local count, i, n = 0, 1, #s
  while i <= n do
    i = i + (unitAt(s, i))
    count = count + 1
  end
  return count
end

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

function M.nextCol(s, col)
  if col > #s then return #s + 1 end
  local len = unitAt(s, col)
  return col + math.max(1, len)
end

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
