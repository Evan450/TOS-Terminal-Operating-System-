




































local fmt = require("printerfmt")

local printer = {}

printer._VERSION = "1.0.0"
printer.fmt = fmt          

local COMPONENT_TYPE = "openprinter"






local MAX_JOB_PAGES = 64

local proxy       
local features    



do
  local okE, eventMod = pcall(require, "kernel.event")
  if okE and eventMod and eventMod.on then
    local function reset(_, _addr, ctype)
      if ctype == COMPONENT_TYPE then proxy, features = nil, nil end
    end
    eventMod.on("component_removed", reset, "printer.driver")
    eventMod.on("component_added",   reset, "printer.driver")
  end
end





local function hasCap()
  local okP, procMod = pcall(require, "kernel.process")
  if not (okP and procMod and procMod.current) then
    return true   
  end
  local cur = procMod.current()
  if not cur then return true end
  if cur.caps and cur.caps["peripheral.printer"] then return true end
  return false
end

local function getProxy()
  if not hasCap() then return nil, "peripheral.printer cap required" end
  if proxy then return proxy end
  local okC, component = pcall(require, "component")
  if not okC or not component or not component.list then
    return nil, "no component API"
  end
  local addr = component.list(COMPONENT_TYPE)()
  if not addr then return nil, "no printer attached" end
  local okP, p = pcall(component.proxy, addr)
  if not okP or not p then return nil, "cannot open the printer" end
  proxy = p
  features = nil
  return proxy
end




local function feat(name)
  local p = getProxy()
  if not p then return false end
  if not features then
    features = {}
    for _, m in ipairs({ "writeln", "print", "setTitle", "clear",
                         "getPaperLevel", "getBlackInkLevel",
                         "getColorInkLevel", "charCount", "width",
                         "maxWidth", "scan", "scanLine", "scanBook",
                         "printTag" }) do
      features[m] = type(p[m]) == "function"
    end
  end
  return features[name] == true
end








local function call(method, ...)
  local p, err = getProxy()
  if not p then return nil, err end
  if type(p[method]) ~= "function" then
    return nil, "this printer has no " .. method .. "()"
  end
  local res = table.pack(pcall(p[method], ...))
  if not res[1] then
    local msg = tostring(res[2] or "printer error")
    msg = msg:gsub("^.-:%d+:%s*", "")           
    msg = msg:gsub("^java%.lang%.%w+:%s*", "")  
    return nil, msg
  end
  return table.unpack(res, 2, res.n)
end






function printer.available()
  return (getProxy()) ~= nil
end






function printer.unavailableReason()
  local p, err = getProxy()
  if p then return nil end
  return err or "no printer attached"
end





function printer.status()
  local p, err = getProxy()
  if not p then return nil, err end
  local function level(name)
    if not feat(name) then return nil end
    local v = call(name)
    return tonumber(v)
  end
  
  
  
  feat("writeln")
  local featCopy = {}
  for k, v in pairs(features or {}) do featCopy[k] = v end
  return {
    address  = p.address,
    paper    = level("getPaperLevel"),
    black    = level("getBlackInkLevel"),
    color    = level("getColorInkLevel"),
    maxWidth = printer.maxWidth(),
    maxLines = fmt.MAX_LINES,
    features = featCopy,
  }
end



function printer.maxWidth()
  if feat("maxWidth") then
    local v = call("maxWidth")
    if tonumber(v) then return math.floor(v) end
  end
  return fmt.MAX_WIDTH
end






function printer.width(s)
  if feat("width") then
    local v = call("width", tostring(s or ""))
    if tonumber(v) then return math.floor(v), "component" end
  end
  return fmt.width(tostring(s or "")), "estimate"
end



function printer.measurer()
  if feat("width") then
    return function(s) return (printer.width(s)) end
  end
  return fmt.width
end









local Job = {}
Job.__index = Job








function printer.job(title)
  local self = setmetatable({
    _title  = nil,
    _pages  = { {} },   
    _copies = 1,
  }, Job)
  if title ~= nil then self:title(title) end
  return self
end


function Job:_cur() return self._pages[#self._pages] end



function Job:title(t)
  local clean = fmt.sanitize(tostring(t or ""), { strip = true })
  if #clean > 64 then clean = clean:sub(1, 64) end
  self._title = clean
  return self
end




function Job:line(text, color, align)
  local a, err = fmt.align(align)
  if not a then return nil, err end
  if color ~= nil then
    color = tonumber(color)
    if not color then return nil, "colour must be a number (0xRRGGBB)" end
    color = math.floor(color) & 0xFFFFFF
  end
  local page = self:_cur()
  if #page >= fmt.MAX_LINES then
    page = {}
    self._pages[#self._pages + 1] = page
  end
  page[#page + 1] = {
    text  = fmt.sanitize(tostring(text or "")),
    color = color,
    align = a,
  }
  return self
end


function Job:blank() return self:line("") end



function Job:pageBreak()
  if #self:_cur() > 0 then self._pages[#self._pages + 1] = {} end
  return self
end




function Job:text(body, opts)
  opts = opts or {}
  opts.measure  = opts.measure or printer.measurer()
  opts.maxWidth = opts.maxWidth or printer.maxWidth()
  local pages, err = fmt.layout(body, opts)
  if not pages then return nil, err end
  for _, page in ipairs(pages) do
    if #page > 0 then
      self:pageBreak()
      local cur = self:_cur()
      for _, l in ipairs(page) do cur[#cur + 1] = l end
    end
  end
  return self
end


function Job:copies(n)
  n = math.floor(tonumber(n) or 1)
  if n < 1 then return nil, "copies must be at least 1" end
  self._copies = n
  return self
end



function Job:pages()
  local out = {}
  for _, page in ipairs(self._pages) do
    if #page > 0 then out[#out + 1] = page end
  end
  return out
end


function Job:cost()
  return fmt.cost(self:pages(), self._copies)
end







function Job:check()
  local st, err = printer.status()
  if not st then return false, err end
  local c = self:cost()
  if c.paper > MAX_JOB_PAGES then
    return false, string.format("job is %d pages (limit %d; pass force=true to override)",
      c.paper, MAX_JOB_PAGES)
  end
  if st.paper and c.paper > st.paper then
    return false, string.format("needs %d sheets, %d loaded", c.paper, st.paper)
  end
  if st.black and c.black > st.black then
    return false, string.format("needs %d black ink, %d left", c.black, st.black)
  end
  if st.color and c.color > st.color then
    return false, string.format("needs %d colour ink, %d left", c.color, st.color)
  end
  return true
end











function Job:commit(opts)
  opts = opts or {}
  local p, err = getProxy()
  if not p then return nil, err, 0 end
  if not opts.force then
    local ok, why = self:check()
    if not ok then return nil, why, 0 end
  end
  local pages = self:pages()
  local done = 0

  for _, page in ipairs(pages) do
    
    
    
    local okC, cErr = call("clear")
    if okC == nil and cErr then return nil, cErr, done end
    if self._title and feat("setTitle") then
      local _, tErr = call("setTitle", self._title)
      if tErr then return nil, tErr, done end
    end
    for _, line in ipairs(page) do
      local r, wErr
      if line.color ~= nil then
        r, wErr = call("writeln", line.text, line.color, line.align or "left")
      elseif (line.align or "left") ~= "left" then
        
        
        
        
        r, wErr = call("writeln", line.text, 0x000000, line.align)
      else
        r, wErr = call("writeln", line.text)
      end
      if r == nil and wErr then return nil, wErr, done end
    end
    local _, pErr = call("print", self._copies)
    if pErr then return nil, pErr, done end
    done = done + self._copies
  end
  return done
end









function printer.printText(body, opts)
  opts = opts or {}
  local job = printer.job(opts.title)
  local ok, err = job:text(body, opts)
  if not ok then return nil, err, 0 end
  if opts.copies then
    local okC, cErr = job:copies(opts.copies)
    if not okC then return nil, cErr, 0 end
  end
  return job:commit(opts)
end


function printer.clear() return call("clear") end






function printer.scan()
  if not feat("scan") then return nil, "this printer cannot scan" end
  return call("scan")
end


function printer.scanLine(n)
  if not feat("scanLine") then return nil, "this printer cannot scan" end
  n = math.floor(tonumber(n) or 1)
  if n < 1 then return nil, "line number must be at least 1" end
  return call("scanLine", n)
end


function printer.scanBook()
  if not feat("scanBook") then return nil, "this printer cannot scan books" end
  return call("scanBook")
end


function printer.tag(text)
  if not feat("printTag") then return nil, "this printer cannot print tags" end
  local clean = fmt.sanitize(tostring(text or ""), { strip = true })
  if clean == "" then return nil, "a name tag needs some text" end
  if #clean > 64 then clean = clean:sub(1, 64) end
  return call("printTag", clean)
end



function printer.refresh()
  proxy, features = nil, nil
  return printer.available()
end

return printer
