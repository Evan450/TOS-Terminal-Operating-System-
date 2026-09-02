local ustr = {}

local U = nil
do
  local ok, mod = pcall(require, "unicode")
  if ok and type(mod) == "table" and mod.len and mod.sub then U = mod end
end

function ustr.len(s)
  s = tostring(s or "")
  if U then
    local ok, n = pcall(U.len, s)
    if ok and n then return n end
  end
  return #s
end

function ustr.width(s)
  s = tostring(s or "")
  if U and U.wlen then
    local ok, n = pcall(U.wlen, s)
    if ok and n then return n end
  end
  return ustr.len(s)
end

function ustr.sub(s, i, j)
  s = tostring(s or "")
  if U then
    local ok, r = pcall(U.sub, s, i, j)
    if ok and r then return r end
  end
  return s:sub(i, j)
end

function ustr.fit(s, cols)
  s = tostring(s or "")
  cols = math.max(0, math.floor(cols or 0))
  if ustr.width(s) <= cols then return s end
  if cols == 0 then return "" end
  if U and U.wtrunc then

    local ok, r = pcall(U.wtrunc, s, cols + 1)
    if ok and r then return r end
  end

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

function ustr.padR(s, cols)
  s = ustr.fit(s, cols)
  return s .. string.rep(" ", cols - ustr.width(s))
end

function ustr.padL(s, cols)
  s = ustr.fit(s, cols)
  return string.rep(" ", cols - ustr.width(s)) .. s
end

function ustr.centerOffset(s, cols)
  return math.max(0, math.floor((cols - ustr.width(s)) / 2))
end

return ustr
