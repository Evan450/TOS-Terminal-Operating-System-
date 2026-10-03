

























local fmt = require("printerfmt")

local doc = {}
doc._VERSION = "1.0.0"

doc.MAX_LINES = fmt.MAX_LINES
doc.MAX_WIDTH = fmt.MAX_WIDTH









function doc.parse(text)
  local out = { title = nil, blocks = {}, warnings = {} }
  local align, color = "left", nil

  local function warn(n, msg)
    out.warnings[#out.warnings + 1] = { line = n, text = msg }
  end

  
  
  
  
  
  for n, raw in ipairs(fmt.lines(text or "")) do
    if raw:sub(1, 2) == ".." then
      
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








function doc.locate(pages, srcLine)
  if not srcLine then return nil, nil end
  for p, page in ipairs(pages or {}) do
    for l, entry in ipairs(page) do
      if entry.src == srcLine then return p, l end
    end
  end
  return nil, nil
end





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



function doc.cost(pages, copies) return fmt.cost(pages, copies) end



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





function doc.serialize(lines)
  return table.concat(lines or {}, "\n")
end




function doc.toBuffer(text)
  local lines = fmt.lines(text or "")
  if #lines == 0 then lines[1] = "" end
  return lines
end

return doc
