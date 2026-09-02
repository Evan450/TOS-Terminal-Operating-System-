local sel = {}

function sel.range(anchor, cursor)
  if type(anchor) ~= "number" or type(cursor) ~= "number" then return nil end
  local from, to = anchor, cursor
  if from > to then from, to = to, from end
  if from == to then return nil end
  return from, to
end

function sel.text(s, anchor, cursor)
  local from, to = sel.range(anchor, cursor)
  if not from then return nil end
  return tostring(s or ""):sub(from, to - 1)
end

function sel.remove(s, anchor, cursor)
  s = tostring(s or "")
  local from, to = sel.range(anchor, cursor)
  if not from then return s, nil, cursor end
  return s:sub(1, from - 1) .. s:sub(to), s:sub(from, to - 1), from
end

function sel.insert(s, at, text)
  s = tostring(s or "")
  text = tostring(text or "")
  at = math.max(1, math.min(#s + 1, at or (#s + 1)))
  return s:sub(1, at - 1) .. text .. s:sub(at), at + #text
end

function sel.replace(s, anchor, cursor, text)
  local cut, _, at = sel.remove(s, anchor, cursor)
  return sel.insert(cut, at or cursor, text)
end

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

function sel.contains(a, b, row, col)
  local first, last = sel.orderPos(a, b)
  if not first then return false end
  if row < first.row or row > last.row then return false end
  if row == first.row and col < first.col then return false end
  if row == last.row and col >= last.col then return false end
  return true
end

function sel.lineRange(anchor, cursor)
  if type(anchor) ~= "number" or type(cursor) ~= "number" then return nil end
  if anchor > cursor then return cursor, anchor end
  return anchor, cursor
end

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
