



















local S = require("calc.sheet")
local P = {}

P.CHAR_PX = 5        
P.SPACE_PX = 3       
P.GAP_PX = 3         




function P.headerParts(spec, page)
  spec = tostring(spec or ""):gsub("#", tostring(page or 1))
  local parts = {}
  for part in (spec .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
  if #parts == 1 then return parts[1], "", "" end
  return parts[1] or "", parts[2] or "", parts[3] or ""
end


local function alignText(text, align, w, measure, padUnit)
  local tw = measure(text)
  if tw > w then
    
    local out = ""
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      if measure(out .. ch) > w then break end
      out = out .. ch
    end
    return out, measure(out)
  end
  return text, tw, align
end


function P.fileRow(sh, ctx, r, c1, c2)
  local parts = {}
  for c = c1, c2 do
    local w = S.width(sh, c)
    local text, align = S.cellText(sh, ctx, c, r, w)
    if #text > w then text = text:sub(1, w) end
    local pad = w - #text
    if align == "R" then text = string.rep(" ", pad) .. text
    elseif align == "C" then
      local l = math.floor(pad / 2)
      text = string.rep(" ", l) .. text .. string.rep(" ", pad - l)
    else text = text .. string.rep(" ", pad) end
    parts[#parts + 1] = text
  end
  return (table.concat(parts, " "):gsub("%s+$", ""))
end




function P.pixelRow(sh, ctx, r, cols, measure)
  local line, pos = "", 0
  for _, col in ipairs(cols) do
    local text, align = S.cellText(sh, ctx, col.c, r, S.width(sh, col.c))
    local t, tw = alignText(text, align, col.w, measure)
    local target = col.x
    if align == "R" then target = col.x + col.w - tw
    elseif align == "C" then target = col.x + math.floor((col.w - tw) / 2) end
    if t ~= "" then
      if target > pos then
        local n = math.floor((target - pos) / P.SPACE_PX + 0.5)
        line = line .. string.rep(" ", n)
        pos = measure(line)
      end
      line = line .. t
      pos = measure(line)
    end
  end
  return (line:gsub("%s+$", ""))
end


function P.formulaLines(sh, c1, r1, c2, r2)
  local out = {}
  for r = r1, r2 do
    for c = c1, c2 do
      local raw = sh.cells[S._key(c, r)]
      if raw then
        local f = sh.fmt[S._key(c, r)]
        out[#out + 1] = S.refName(c, r) .. ": " .. (f and ("(" .. f .. ") ") or "") .. raw
      end
    end
  end
  return out
end









function P.pages(sh, ctx, c1, r1, c2, r2, opts)
  opts = opts or {}
  local target = opts.target or "file"
  local perPage = opts.perPage or (target == "file" and 0 or 20)
  local headLines = (opts.header and opts.header ~= "") and 2 or 0
  local footLines = (opts.footer and opts.footer ~= "") and 2 or 0
  local body = (perPage > 0) and math.max(1, perPage - headLines - footLines) or math.huge
  local measure = opts.measure or function(s) return #s * P.CHAR_PX end
  local maxW = opts.maxWidth or 164

  
  local bands = {}
  if opts.formulas then
    bands[1] = P.formulaLines(sh, c1, r1, c2, r2)
  elseif target == "file" then
    local rows = {}
    for r = r1, r2 do rows[#rows + 1] = P.fileRow(sh, ctx, r, c1, c2) end
    bands[1] = rows
  else
    
    local c = c1
    while c <= c2 do
      local cols, x = {}, 0
      while c <= c2 do
        local w = S.width(sh, c) * P.CHAR_PX
        if #cols > 0 and x + w > maxW then break end
        cols[#cols + 1] = { c = c, x = x, w = math.min(w, maxW) }
        x = x + w + P.GAP_PX
        c = c + 1
      end
      local rows = {}
      for r = r1, r2 do rows[#rows + 1] = P.pixelRow(sh, ctx, r, cols, measure) end
      bands[#bands + 1] = rows
    end
  end

  local pages = {}
  local function frame(lines, which)
    local spec = which == "head" and opts.header or opts.footer
    if not spec or spec == "" then return end
    local l, m, rr = P.headerParts(spec, #pages + 1)
    local text
    if target == "file" then
      local width = 0
      for cc = c1, c2 do width = width + S.width(sh, cc) + 1 end
      local mid = math.max(0, math.floor((width - #m) / 2) - #l)
      text = l .. string.rep(" ", mid) .. m
      local rest = math.max(1, width - #text - #rr)
      text = (text .. string.rep(" ", rest) .. rr):gsub("%s+$", "")
    else
      text = l
      local function placeAt(px, s)
        local n = math.max(1, math.floor((px - measure(text)) / P.SPACE_PX + 0.5))
        text = text .. string.rep(" ", n) .. s
      end
      if m ~= "" then placeAt(math.floor((maxW - measure(m)) / 2), m) end
      if rr ~= "" then placeAt(maxW - measure(rr), rr) end
    end
    if which == "head" then lines[#lines + 1] = text; lines[#lines + 1] = ""
    else lines[#lines + 1] = ""; lines[#lines + 1] = text end
  end
  for _, rows in ipairs(bands) do
    
    local last = #rows
    while last > 0 and rows[last] == "" do last = last - 1 end
    if last == 0 then last = 1 end
    local i = 1
    repeat
      local page = {}
      frame(page, "head")
      local n = 0
      while i <= last and n < body do
        page[#page + 1] = rows[i]; i = i + 1; n = n + 1
      end
      frame(page, "foot")
      pages[#pages + 1] = page
    until i > last
  end
  return pages
end



function P.toText(pages)
  local out = {}
  for i, page in ipairs(pages) do
    if i > 1 then out[#out + 1] = "\f" end
    for _, l in ipairs(page) do out[#out + 1] = l end
  end
  return table.concat(out, "\n") .. "\n"
end



function P.toWrite(pages, title)
  local out = {}
  if title and title ~= "" then out[1] = ".title " .. title end
  for i, page in ipairs(pages) do
    if i > 1 then out[#out + 1] = ".page" end
    for _, l in ipairs(page) do
      if l:sub(1, 1) == "." then l = "." .. l end
      out[#out + 1] = l
    end
  end
  return table.concat(out, "\n") .. "\n"
end

return P
