
















local render = {}






local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'",
  nbsp = " ", mdash = "-", ndash = "-", minus = "-",
  hellip = "...", copy = "(c)", reg = "(R)", trade = "(TM)",
  lsquo = "'", rsquo = "'", ldquo = "\"", rdquo = "\"",
  sbquo = "'", bdquo = "\"",
  laquo = "<<", raquo = ">>", middot = "*", bull = "*",
  deg = " deg", plusmn = "+/-", times = "x", divide = "/",
  frac12 = "1/2", frac14 = "1/4", frac34 = "3/4",
}





function render.decodeEntities(s)
  s = s:gsub("&#x(%x+);", function(h)
    local n = tonumber(h, 16)
    if n and n >= 32 and n < 127 then return string.char(n) end
    return n and "?" or "&#x" .. h .. ";"
  end)
  s = s:gsub("&#(%d+);", function(d)
    local n = tonumber(d)
    if n and n >= 32 and n < 127 then return string.char(n) end
    return n and "?" or "&#" .. d .. ";"
  end)
  s = s:gsub("&(%a+);", function(name)
    local sub = ENTITIES[name:lower()]
    if sub then return sub end
    return "?"
  end)
  return s
end








local function tokenize(html)
  local tokens = {}
  local pos, n = 1, #html
  while pos <= n do
    local lt = html:find("<", pos)
    if not lt then
      tokens[#tokens + 1] = { type = "text", text = html:sub(pos) }
      break
    end
    if lt > pos then
      tokens[#tokens + 1] = { type = "text", text = html:sub(pos, lt - 1) }
    end
    if html:sub(lt, lt + 3) == "<!--" then
      local close = html:find("%-%->", lt + 4)
      pos = close and (close + 3) or (n + 1)
    elseif html:sub(lt, lt + 1) == "<!" then
      local gt = html:find(">", lt + 1)
      pos = gt and (gt + 1) or (n + 1)
    else
      local gt = html:find(">", lt + 1)
      if not gt then
        
        
        tokens[#tokens + 1] = { type = "text", text = html:sub(lt) }
        pos = n + 1
      else
        local raw = html:sub(lt + 1, gt - 1)
        local closing = raw:sub(1, 1) == "/"
        if closing then raw = raw:sub(2) end
        local selfclose = raw:sub(-1) == "/"
        if selfclose then raw = raw:sub(1, -2) end
        local name = raw:match("^%s*([%a][%w%-]*)")
        if name then
          tokens[#tokens + 1] = { type = "tag", name = name:lower(),
            closing = closing, selfclose = selfclose, raw = raw }
        end
        pos = gt + 1
      end
    end
  end
  return tokens
end




local function attrOf(raw, key)
  local lower = raw:lower()
  local i = lower:find(key, 1, true)
  while i do
    local before = raw:sub(i - 1, i - 1)
    local after = lower:sub(i + #key, i + #key)
    if (i == 1 or before:match("[%s\"']")) and after ~= "-" then
      local rest = raw:sub(i + #key)
      local v = rest:match("^%s*=%s*\"([^\"]*)\"")
        or rest:match("^%s*=%s*'([^']*)'")
        or rest:match("^%s*=%s*([^%s>]+)")
      if v then return v end
    end
    i = lower:find(key, i + 1, true)
  end
  return nil
end
render._attrOf = attrOf   



local SKIP_ELEMENT = { script = true, style = true, head = true, title = true,
  table = true, form = true, select = true, noscript = true }




local BLOCK_TAG = { p = true, div = true, section = true, article = true,
  header = true, footer = true, nav = true, blockquote = true,
  h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true }

local VOID_TAG = { br = true, hr = true, img = true, input = true,
  meta = true, link = true, area = true, base = true, col = true,
  embed = true, source = true, track = true, wbr = true }






local function newState()
  return {
    blocks = {},
    links = {},          
    buf = {},             
    kind = "p",
    skip = nil,            
    skipDepth = 0,
    inPre = false,
    preLines = nil,
    preLine = nil,
    linkStack = {},        
    curLinkUrl = nil,
    listStack = {},        
    liDepth = 0,
  }
end

local function flushInline(st)
  local text = table.concat(st.buf)
  
  
  
  
  
  text = text:gsub("%s+", " ")
  text = text:gsub(" ?\1 ?", "\n")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text ~= "" then
    local prefix = nil
    if st.kind == "li" then
      local top = st.listStack[#st.listStack]
      if top and top.kind == "ol" then
        top.n = top.n + 1
        prefix = top.n .. ". "
      else
        prefix = "- "
      end
      prefix = string.rep("  ", math.max(0, #st.listStack - 1)) .. prefix
    end
    st.blocks[#st.blocks + 1] = { kind = st.kind, text = text, prefix = prefix }
  end
  st.buf = {}
end

local function flushPre(st)
  if st.preLine then
    st.preLines[#st.preLines + 1] = table.concat(st.preLine)
    st.preLine = nil
  end
  if st.preLines and #st.preLines > 0 then
    st.blocks[#st.blocks + 1] = { kind = "pre", lines = st.preLines }
  end
  st.preLines = nil
  st.inPre = false
end

local function startTag(st, tok)
  local name = tok.name
  if st.skip then
    if name == st.skip and not tok.selfclose then st.skipDepth = st.skipDepth + 1 end
    return
  end
  if SKIP_ELEMENT[name] and not tok.selfclose then
    st.skip = name
    st.skipDepth = 1
    return
  end
  if VOID_TAG[name] or tok.selfclose then
    if name == "br" then
      if st.inPre then
        if st.preLine then st.preLines[#st.preLines + 1] = table.concat(st.preLine) end
        st.preLine = {}
      else
        
        
        
        
        st.buf[#st.buf + 1] = "\1"
      end
    end
    return
  end
  if name == "pre" then
    flushInline(st)
    st.inPre = true
    st.preLines, st.preLine = {}, {}
    return
  end
  if name == "ul" or name == "ol" then
    flushInline(st)
    st.listStack[#st.listStack + 1] = { kind = name, n = 0 }
    return
  end
  if name == "li" then
    flushInline(st)
    st.kind = "li"
    return
  end
  if name == "a" then
    local href = attrOf(tok.raw, "href")
    if href and href ~= "" and not href:match("^#") and not href:match("^javascript:") then
      st.curLinkUrl = href
      
      
      
      
      st.linkBufStart = #st.buf + 1
    end
    return
  end
  if BLOCK_TAG[name] then
    flushInline(st)
    st.kind = name:match("^h%d$") and name or "p"
    return
  end
  
  
end

local function endTag(st, tok)
  local name = tok.name
  if st.skip then
    if name == st.skip then
      st.skipDepth = st.skipDepth - 1
      if st.skipDepth <= 0 then st.skip = nil end
    end
    return
  end
  if name == "pre" then flushPre(st); return end
  if name == "a" then
    if st.curLinkUrl then
      local start = st.linkBufStart or (#st.buf + 1)
      local text = table.concat(st.buf, "", start):gsub("^%s+", ""):gsub("%s+$", "")
      st.links[#st.links + 1] = { url = st.curLinkUrl, text = text ~= "" and text or st.curLinkUrl }
      st.buf[#st.buf + 1] = string.format(" [%d] ", #st.links)
      st.curLinkUrl = nil
      st.linkBufStart = nil
    end
    return
  end
  if name == "li" then
    flushInline(st)
    st.kind = "p"
    return
  end
  if name == "ul" or name == "ol" then
    if #st.listStack > 0 then st.listStack[#st.listStack] = nil end
    return
  end
  if BLOCK_TAG[name] then
    flushInline(st)
    st.kind = "p"
  end
end

local function addText(st, text)
  if st.skip then return end
  text = render.decodeEntities(text)
  if st.inPre then
    for i = 1, #text do
      local c = text:sub(i, i)
      if c == "\n" then
        st.preLines[#st.preLines + 1] = table.concat(st.preLine)
        st.preLine = {}
      else
        st.preLine[#st.preLine + 1] = c
      end
    end
  else
    st.buf[#st.buf + 1] = text
  end
end



function render.toBlocks(html)
  local st = newState()
  for _, tok in ipairs(tokenize(html)) do
    if tok.type == "text" then
      addText(st, tok.text)
    elseif tok.closing then
      endTag(st, tok)
    else
      startTag(st, tok)
    end
  end
  if st.inPre then flushPre(st) else flushInline(st) end
  return st.blocks, st.links
end











function render.wrapText(text, width)
  width = math.max(1, width)
  local out = {}
  for rawLine in (text .. "\n"):gmatch("(.-)\n") do
    if rawLine == "" then
      out[#out + 1] = ""
    else
      local line = ""
      for word in rawLine:gmatch("%S+") do
        local candidate = (line == "") and word or (line .. " " .. word)
        if #candidate <= width then
          line = candidate
        else
          if line ~= "" then out[#out + 1] = line end
          line = word
          while #line > width do
            out[#out + 1] = line:sub(1, width)
            line = line:sub(width + 1)
          end
        end
      end
      out[#out + 1] = line
    end
  end
  return out
end










function render.render(html, width)
  html = type(html) == "string" and html or ""
  width = math.max(10, math.floor(tonumber(width) or 80))
  local usable = width - 1   

  local blocks, links = render.toBlocks(html)
  local lines = {}
  local prevKind = nil
  for _, b in ipairs(blocks) do
    local isHeading = b.kind and b.kind:match("^h%d$") ~= nil
    if isHeading and #lines > 0 then lines[#lines + 1] = "" end
    if b.kind == "pre" then
      if #lines > 0 then lines[#lines + 1] = "" end
      for _, l in ipairs(b.lines) do lines[#lines + 1] = l end
      lines[#lines + 1] = ""
    else
      local prefix = b.prefix or ""
      local wrapped = render.wrapText(b.text, math.max(1, usable - #prefix))
      for i, l in ipairs(wrapped) do
        lines[#lines + 1] = (i == 1) and (prefix .. l) or (string.rep(" ", #prefix) .. l)
      end
      if isHeading then lines[#lines + 1] = "" end
    end
    prevKind = b.kind
  end
  
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end

  if #links > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "References:"
    for i, l in ipairs(links) do
      for _, wl in ipairs(render.wrapText(string.format("[%d] %s -- %s", i, l.text, l.url), usable)) do
        lines[#lines + 1] = wl
      end
    end
  end

  return { lines = lines, links = links }
end

return render
