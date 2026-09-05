-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS printer driver  (require("printer"))                    ║
-- ║                                                              ║
-- ║  TOS has no baked-in printer support, the same way it has no ║
-- ║  baked-in mouse support. This is the DOS-style driver for    ║
-- ║  OpenPrinter (PC-Logix): it turns the raw `openprinter`      ║
-- ║  component into a job you can hand a document to, and it     ║
-- ║  refuses jobs the machine cannot finish instead of leaving   ║
-- ║  half a document in the output chest.                        ║
-- ║                                                              ║
-- ║  Layout (wrapping, pagination, costing) lives next door in   ║
-- ║  printerfmt.lua and is pure; this file is the hardware, the  ║
-- ║  capability check and the job.                               ║
-- ║                                                              ║
-- ║  Quick use:                                                  ║
-- ║    local p = require("printer")                              ║
-- ║    if p.available() then                                     ║
-- ║      p.printText("Hello, base.", { title = "Note" })         ║
-- ║    end                                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- #SEC — WHY THIS FILE POLICES ITSELF.
-- A library under /usr/lib is resolved by the sandbox's user-lib path and
-- then loaded through the REAL require (kernel.sandbox ~line 674), so the
-- code you are reading runs with ambient authority: its `component` is the
-- unfiltered one, not the caps-filtered proxy the calling package sees.
-- That is deliberate and is how every full-privilege add-on lib works —
-- but it means the `peripheral.printer` capability added to
-- GATED_COMPONENT_TYPES would buy nothing here. Any package holding
-- fs.read could require("printer") and print.
--
-- So this module re-checks the capability itself, per call, exactly as
-- tos/peripheral/redstone.lua does for #SEC H34 and for the same reason.
-- The check is folded into proxy resolution so there is ONE gate and no
-- entry point can route around it. If you add a function that reaches the
-- hardware, reach it through getProxy(); do not cache a proxy of your own.

local fmt = require("printerfmt")

local printer = {}

printer._VERSION = "1.0.0"
printer.fmt = fmt          -- layout helpers, for callers that want them

local COMPONENT_TYPE = "openprinter"

-- Bound on a single job, in PAGES. OpenPrinter's print() takes a copy
-- count and does not bound it; a loop bug or a fat-fingered `printer file
-- x --copies 9999` would grind through every sheet of paper in the
-- printer and then keep asking. 64 is a stack — past that, an operator
-- should mean it, so `force` is required.
local MAX_JOB_PAGES = 64

local proxy       -- cached component proxy
local features    -- method-name -> true, probed once per proxy

-- #SEC L — drop the cached proxy on hot-plug, so a printer that is broken
-- and replaced does not leave every later call swinging at a dead address.
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

-- ── Capability gate ───────────────────────────────────────────────────
-- Kernel context (no current process) is implicitly allowed, matching
-- peripheral.redstone. A process without the cap gets a clean refusal
-- rather than a hardware action.
local function hasCap()
  local okP, procMod = pcall(require, "kernel.process")
  if not (okP and procMod and procMod.current) then
    return true   -- no process module (early boot / off-box tests)
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

--- Which optional methods this printer actually has. OpenPrinter grew
--- width/maxWidth/scanBook after the 1.7 builds, so feature-DETECT rather
--- than guessing from a version we cannot see.
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

-- Every OpenPrinter callback signals failure by THROWING (see PrinterTE:
-- "Please load Ink.", "To many lines.", "no empty output slot"), which
-- surfaces in Lua as an error from the component call. Nothing in this
-- module may call the proxy directly — call() converts that into the
-- nil, reason convention the rest of TOS uses, and strips the Java noise
-- off the front of the message so the operator reads the sentence the mod
-- actually wrote.
local function call(method, ...)
  local p, err = getProxy()
  if not p then return nil, err end
  if type(p[method]) ~= "function" then
    return nil, "this printer has no " .. method .. "()"
  end
  local res = table.pack(pcall(p[method], ...))
  if not res[1] then
    local msg = tostring(res[2] or "printer error")
    msg = msg:gsub("^.-:%d+:%s*", "")           -- lua chunk prefix
    msg = msg:gsub("^java%.lang%.%w+:%s*", "")  -- java exception class
    return nil, msg
  end
  return table.unpack(res, 2, res.n)
end

-- ============================================================
-- Presence and state
-- ============================================================

--- True when a printer is attached AND this caller may use it.
function printer.available()
  return (getProxy()) ~= nil
end

--- Why printer.available() is false, or nil when it is true. Callers
--- should show this rather than "no printer": "you lack the capability"
--- and "there is no printer in this base" are different problems and a
--- driver that conflates them sends someone hunting for a block that is
--- already placed.
function printer.unavailableReason()
  local p, err = getProxy()
  if p then return nil end
  return err or "no printer attached"
end

--- Consumables and identity.
-- @return { address=, paper=, black=, color=, maxWidth=, features={} }
-- Individual level reads are tolerated as nil: an older printer without a
-- getter must still report the levels it does have.
function printer.status()
  local p, err = getProxy()
  if not p then return nil, err end
  local function level(name)
    if not feat(name) then return nil end
    local v = call(name)
    return tonumber(v)
  end
  -- Force the probe before copying: `features` is filled lazily by the
  -- first feat() call, and a status built before one has run would report
  -- an empty feature set as "this printer has nothing".
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

--- Pixel budget for one line. The component's own maxWidth() when it has
--- one, else the documented 164.
function printer.maxWidth()
  if feat("maxWidth") then
    local v = call("maxWidth")
    if tonumber(v) then return math.floor(v) end
  end
  return fmt.MAX_WIDTH
end

--- Pixel width of `s`, measured by the printer itself when it can and by
--- printerfmt's transcribed table when it cannot. Returned alongside a
--- second value saying WHICH, because a preview drawn from an estimate
--- and one drawn from the hardware are not equally trustworthy.
-- @return pixels, "component"|"estimate"
function printer.width(s)
  if feat("width") then
    local v = call("width", tostring(s or ""))
    if tonumber(v) then return math.floor(v), "component" end
  end
  return fmt.width(tostring(s or "")), "estimate"
end

--- A measure function bound to this printer, for handing to fmt.wrap /
--- fmt.layout so layout done here matches what the hardware will render.
function printer.measurer()
  if feat("width") then
    return function(s) return (printer.width(s)) end
  end
  return fmt.width
end

-- ============================================================
-- Jobs
-- ============================================================
-- A job is built in memory and committed in one go. That ordering is the
-- point: the printer's buffer is a real, shared, persistent thing, so
-- writing straight into it means a job that fails halfway has already
-- half-written someone else's page. Build, check, then commit.

local Job = {}
Job.__index = Job

--- Start a job. `title` is optional and may be set later.
-- Pages are kept SEPARATE rather than as one flat line list with the
-- pagination inferred at commit time. The difference shows up the moment
-- a caller mixes :line() with :text(): a flat list has to be padded out
-- to a page boundary and then un-padded again so the document does not
-- end on a blank sheet, and every one of those pads is a chance to emit
-- a page of nothing. An explicit page is just a page.
function printer.job(title)
  local self = setmetatable({
    _title  = nil,
    _pages  = { {} },   -- array of pages; each page an array of lines
    _copies = 1,
  }, Job)
  if title ~= nil then self:title(title) end
  return self
end

-- The page currently being filled.
function Job:_cur() return self._pages[#self._pages] end

--- Set the page title — this becomes the printed item's display name, so
--- it is sanitized hard and length-capped. OpenPrinter enforces neither.
function Job:title(t)
  local clean = fmt.sanitize(tostring(t or ""), { strip = true })
  if #clean > 64 then clean = clean:sub(1, 64) end
  self._title = clean
  return self
end

--- Append one line. `color` is an 0xRRGGBB integer or nil; passing nil
--- uses the BLACK cartridge, and that is the default on purpose — see
--- fmt.cost for why a colour default would quietly drain colour ink.
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

--- Append a blank line.
function Job:blank() return self:line("") end

--- Start a new page. A no-op when the current page is already empty —
--- two breaks in a row must not cost a blank sheet.
function Job:pageBreak()
  if #self:_cur() > 0 then self._pages[#self._pages + 1] = {} end
  return self
end

--- Append a whole document, wrapped to this printer's real line width.
--- Each of the document's pages lands on its own sheet, starting from a
--- fresh one.
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

--- Number of copies of the whole job.
function Job:copies(n)
  n = math.floor(tonumber(n) or 1)
  if n < 1 then return nil, "copies must be at least 1" end
  self._copies = n
  return self
end

--- The pages this job will produce, for a preview. A trailing empty page
--- (the one :pageBreak() opened and nothing filled) is not a page.
function Job:pages()
  local out = {}
  for _, page in ipairs(self._pages) do
    if #page > 0 then out[#out + 1] = page end
  end
  return out
end

--- What this job will consume.
function Job:cost()
  return fmt.cost(self:pages(), self._copies)
end

--- Pre-flight: can this job finish with what is loaded right now?
-- @return true | false, reason
-- Deliberately advisory in ONE direction only: an unreadable level (an
-- older printer with no getter) does NOT block the job, because refusing
-- to print on a machine that cannot report its paper would make the
-- driver useless there. A level we CAN read and that is short does block.
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

--- Commit the job to the printer.
-- @param opts { force = bool }  force skips the pre-flight page cap and
--        the consumables check. It does NOT skip the mod's own limits —
--        those still throw and are still reported.
-- @return pagesPrinted | nil, err, pagesPrinted
--
-- The third return is the one that matters when things go wrong: a
-- five-page job that fails on page four has ALREADY put three pages in
-- the output chest. Reporting only "failed" would have the operator
-- reprint the whole thing.
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
    -- clear() first: the printer's buffer persists across programs and
    -- across reboots, so anything a previous job left behind would be
    -- printed at the top of ours.
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
        -- The alignment argument is positional and sits AFTER the colour,
        -- so a centred black line has to name a colour. Black it is —
        -- and it costs a colour-ink unit, which is exactly why fmt.cost
        -- counts any line carrying a colour against the colour cartridge.
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

-- ============================================================
-- One-call convenience
-- ============================================================

--- Print a whole document. The 90% path.
-- @param body string
-- @param opts { title=, align=, color=, copies=, force=, wrap= }
-- @return pagesPrinted | nil, err, pagesPrinted
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

--- Clear whatever is sitting in the printer's buffer.
function printer.clear() return call("clear") end

-- ============================================================
-- Scanning (input tray)
-- ============================================================

--- Scan the page in the input slot. @return array of lines | nil, err
function printer.scan()
  if not feat("scan") then return nil, "this printer cannot scan" end
  return call("scan")
end

--- Scan one line of the page in the input slot.
function printer.scanLine(n)
  if not feat("scanLine") then return nil, "this printer cannot scan" end
  n = math.floor(tonumber(n) or 1)
  if n < 1 then return nil, "line number must be at least 1" end
  return call("scanLine", n)
end

--- Scan a book in the input slot. Not present on older builds.
function printer.scanBook()
  if not feat("scanBook") then return nil, "this printer cannot scan books" end
  return call("scanBook")
end

--- Print a name tag.
function printer.tag(text)
  if not feat("printTag") then return nil, "this printer cannot print tags" end
  local clean = fmt.sanitize(tostring(text or ""), { strip = true })
  if clean == "" then return nil, "a name tag needs some text" end
  if #clean > 64 then clean = clean:sub(1, 64) end
  return call("printTag", clean)
end

--- Forget the cached proxy — for an operator who just replaced the block
--- and does not want to wait for the hot-plug event.
function printer.refresh()
  proxy, features = nil, nil
  return printer.available()
end

return printer
