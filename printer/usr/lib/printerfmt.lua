













local fmt = {}

fmt._VERSION = "1.0.0"






fmt.MAX_LINES = 20    
fmt.MAX_WIDTH = 164   














local W = {
  [32] = 3, [33] = 1, [34] = 3, [39] = 1, [40] = 3, [41] = 3, [42] = 3,
  [44] = 1, [46] = 1, [58] = 1, [59] = 1, [60] = 4, [62] = 4, [64] = 6,
  [73] = 3, [91] = 3, [93] = 3, [96] = 2, [102] = 4, [105] = 1,
  [107] = 4, [108] = 2, [116] = 3, [123] = 3, [124] = 1, [125] = 3,
  [126] = 6,
}
local DEFAULT_CHAR_WIDTH = 5





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




function fmt.width(s)
  if type(s) ~= "string" then return 0 end
  local total = 0
  for _, c in ipairs(codepoints(s)) do
    total = total + (W[c] or DEFAULT_CHAR_WIDTH)
  end
  return total
end



function fmt.charCount(s)
  if type(s) ~= "string" then return 0 end
  return #codepoints(s)
end











function fmt.sanitize(s, opts)
  if type(s) ~= "string" then return "" end
  opts = opts or {}
  local tabWidth = tonumber(opts.tabWidth) or 4
  s = s:gsub("\t", string.rep(" ", math.max(1, math.min(16, tabWidth))))
  
  
  s = s:gsub("[%z\1-\31\127]", "")
  if opts.strip then
    
    s = s:gsub("\194\167.", "")
  end
  return s
end





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














function fmt.wrap(line, maxPx, measure)
  measure = measure or fmt.width
  maxPx = tonumber(maxPx) or fmt.MAX_WIDTH
  if type(line) ~= "string" then return { "" } end
  if line == "" then return { "" } end
  if maxPx <= 0 then return { line } end

  local out, cur = {}, ""

  
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






local ALIGNMENTS = { left = true, center = true }

function fmt.align(a)
  if a == nil then return "left" end
  if type(a) ~= "string" then return nil, "alignment must be a string" end
  local v = a:lower()
  if ALIGNMENTS[v] then return v end
  return nil, "unknown alignment '" .. a .. "' (left, center)"
end







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
