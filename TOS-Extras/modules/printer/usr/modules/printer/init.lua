-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: printer — the `printer` command                 ║
-- ║                                                              ║
-- ║  Operator front end over the driver in /usr/lib/printer.lua. ║
-- ║  The driver is the API; this is the thing you type.          ║
-- ║                                                              ║
-- ║    printer                 what is attached, and its levels  ║
-- ║    printer test            one page, to prove the wiring     ║
-- ║    printer file <path>     print a text file                 ║
-- ║    printer preview <path>  paginate it WITHOUT printing      ║
-- ║    printer scan [<path>]   read the page in the input slot   ║
-- ║    printer tag <text>      print a name tag                  ║
-- ║    printer clear           empty the printer's buffer        ║
-- ║                                                              ║
-- ║  `preview` exists because paper is a real resource: the way  ║
-- ║  to find out that your 3-line footer pushed the document to  ║
-- ║  a fourth sheet should not be finding a fourth sheet in the  ║
-- ║  output chest.                                               ║
-- ╚══════════════════════════════════════════════════════════════╝

local P   = require("printer")
local fmt = require("printerfmt")

local C_ERR   = 0xFF5555
local C_WARN  = 0xFF9900
local C_OK    = 0x55FF55
local C_DIM   = 0xAAAAAA
local C_TITLE = 0xFFFF55
local C_FG    = 0xFFFFFF

-- ── Flag parsing ──────────────────────────────────────────────────────
-- Long flags only, `--name` or `--name=value`. Positional arguments keep
-- their order. Deliberately small: TOS has no shared getopt yet, and this
-- command is not the place to invent one.
local function parseArgs(args)
  local pos, flags = {}, {}
  for i = 1, #args do
    local a = tostring(args[i])
    local key, val = a:match("^%-%-([%w%-]+)=(.*)$")
    if key then
      flags[key] = val
    elseif a:match("^%-%-[%w%-]+$") then
      flags[a:sub(3)] = true
    else
      pos[#pos + 1] = a
    end
  end
  return pos, flags
end

local function haveFs() return fs and fs.readFile and fs.exists end

-- ── Status ────────────────────────────────────────────────────────────
local function cmdStatus(o)
  local st, err = P.status()
  if not st then
    o("No printer available: " .. tostring(err), C_ERR)
    if tostring(err):find("cap") then
      o("This program was not granted the peripheral.printer capability.", C_DIM)
    else
      o("Place an OpenPrinter next to (or on the network with) this computer.", C_DIM)
    end
    return
  end
  o("Printer " .. tostring(st.address):sub(1, 8) .. "...", C_TITLE)
  local function level(name, v, lowAt)
    if v == nil then
      o(string.format("  %-12s %s", name, "(not reported by this printer)"), C_DIM)
    else
      o(string.format("  %-12s %d", name, v), v <= lowAt and C_WARN or C_FG)
    end
  end
  level("paper",     st.paper, 4)
  level("black ink", st.black, 10)
  level("colour ink", st.color, 10)
  o(string.format("  %-12s %d px x %d lines", "page", st.maxWidth, st.maxLines), C_FG)
  -- Which optional methods this build has. It reads as trivia until the
  -- day `printer scan` says "this printer cannot scan" and nobody can
  -- tell whether that is the mod version or a broken block.
  local missing = {}
  for _, m in ipairs({ "width", "maxWidth", "scan", "scanBook", "printTag" }) do
    if not st.features[m] then missing[#missing + 1] = m end
  end
  if #missing > 0 then
    o("  older build: no " .. table.concat(missing, ", "), C_DIM)
  end
end

-- ── Reading a document ────────────────────────────────────────────────
local MAX_DOC_BYTES = 64 * 1024   -- a page holds ~20 short lines; 64K is
                                  -- already ~100 sheets. Reading more into
                                  -- one Lua string on a T1 is how you OOM
                                  -- the box before you print anything.

local function readDoc(path, o)
  if not haveFs() then
    o("No filesystem access.", C_ERR); return nil
  end
  if not fs.exists(path) then
    o("No such file: " .. path, C_ERR); return nil
  end
  local ok, data = pcall(fs.readFile, path)
  if not ok or not data then
    o("Cannot read " .. path .. (ok and "" or (": " .. tostring(data))), C_ERR)
    return nil
  end
  if #data > MAX_DOC_BYTES then
    o(string.format("%s is %d bytes; the limit is %d.", path, #data, MAX_DOC_BYTES), C_ERR)
    o("Split it, or print the part you want with `head`/`tail` into a file.", C_DIM)
    return nil
  end
  return data
end

local function layoutOpts(flags)
  local opts = {
    title  = flags.title ~= true and flags.title or nil,
    align  = flags.center and "center" or "left",
    wrap   = not flags["no-wrap"],
    force  = flags.force == true,
  }
  if flags.copies then
    opts.copies = tonumber(flags.copies)
    if not opts.copies then return nil, "--copies needs a number" end
  end
  if flags.color then
    -- Accept 0xRRGGBB or plain decimal. A colour here colours EVERY line
    -- and costs a colour-ink unit per line; the cost report says so.
    opts.color = tonumber(flags.color) or tonumber(flags.color, 16)
    if not opts.color then return nil, "--color needs a number like 0xFF0000" end
  end
  return opts
end

local function reportCost(cost, o)
  o(string.format("  %d sheet(s), %d black, %d colour",
    cost.paper, cost.black, cost.color), C_DIM)
end

-- ── printer file ──────────────────────────────────────────────────────
local function cmdFile(pos, flags, o)
  local path = pos[2]
  if not path then o("Usage: printer file <path> [--title=T] [--copies=N] [--center]", C_DIM); return end
  local data = readDoc(path, o); if not data then return end
  local opts, oErr = layoutOpts(flags)
  if not opts then o(tostring(oErr), C_ERR); return end
  opts.title = opts.title or path:match("[^/]+$")

  if not P.available() then
    o("No printer available: " .. tostring(P.unavailableReason()), C_ERR)
    o("`printer preview " .. path .. "` still works without one.", C_DIM)
    return
  end

  local job = P.job(opts.title)
  local ok, err = job:text(data, opts)
  if not ok then o(tostring(err), C_ERR); return end
  if opts.copies then
    local okC, cErr = job:copies(opts.copies)
    if not okC then o(tostring(cErr), C_ERR); return end
  end

  local cost = job:cost()
  if flags["dry-run"] then
    o("Would print:", C_TITLE); reportCost(cost, o); return
  end

  local okCheck, why = job:check()
  if not okCheck and not opts.force then
    o("Refused: " .. tostring(why), C_ERR)
    reportCost(cost, o)
    o("Load more, or pass --force to try anyway.", C_DIM)
    return
  end

  local printed, pErr, partial = job:commit(opts)
  if not printed then
    o("Print failed: " .. tostring(pErr), C_ERR)
    -- The partial count is the whole reason commit returns three values.
    if (partial or 0) > 0 then
      o(string.format("%d page(s) DID print — check the output slots before reprinting.",
        partial), C_WARN)
    end
    return
  end
  o(string.format("Printed %d page(s) of %s.", printed, path), C_OK)
end

-- ── printer preview ───────────────────────────────────────────────────
local function cmdPreview(pos, flags, o)
  local path = pos[2]
  if not path then o("Usage: printer preview <path> [--center] [--no-wrap]", C_DIM); return end
  local data = readDoc(path, o); if not data then return end
  local opts, oErr = layoutOpts(flags)
  if not opts then o(tostring(oErr), C_ERR); return end

  -- Measure with the real printer when one is attached, and SAY which
  -- measure was used. A preview laid out from the fallback table can
  -- disagree with the hardware by a pixel or two per line, which is
  -- exactly enough to move a word onto the next sheet.
  local measure, source = fmt.width, "estimated widths"
  if P.available() then
    local _, src = P.width("M")
    measure = P.measurer()
    if src == "component" then source = "the attached printer's own metrics" end
    opts.maxWidth = P.maxWidth()
  end
  opts.measure = measure

  local pages, lErr = fmt.layout(data, opts)
  if not pages then o(tostring(lErr), C_ERR); return end

  for i, page in ipairs(pages) do
    o(string.format("── page %d/%d ─────────────────", i, #pages), C_TITLE)
    for _, line in ipairs(page) do
      o("  " .. (line.text ~= "" and line.text or "~"), line.text ~= "" and C_FG or C_DIM)
    end
  end
  local cost = fmt.cost(pages, opts.copies or 1)
  o(string.format("%d page(s), laid out using %s.", #pages, source), C_DIM)
  reportCost(cost, o)
end

-- ── printer test ──────────────────────────────────────────────────────
local function cmdTest(flags, o)
  if not P.available() then
    o("No printer available: " .. tostring(P.unavailableReason()), C_ERR); return
  end
  local job = P.job("TOS test page")
  job:line("TOS PRINTER TEST", nil, "center")
  job:blank()
  job:line("If you are reading this off a printed page, the")
  job:line("driver, the capability and the printer all work.")
  job:blank()
  job:line("Left aligned.")
  job:line("Centred.", nil, "center")
  job:blank()
  job:line("Widest line the page will hold:")
  -- Fill exactly one line to the printer's real budget, so a clipped
  -- test page is itself the diagnostic: if the row of #s is cut short,
  -- our measure and the printer's disagree.
  local budget, row = P.maxWidth(), ""
  -- Bounded: a printer whose width() answered 0 would otherwise spin here
  -- forever, and a hung `printer test` is a worse diagnostic than a short
  -- row of #s. maxWidth is in pixels and no glyph is narrower than 1.
  for _ = 1, budget do
    local w = (P.width(row .. "#"))
    if w > budget then break end
    row = row .. "#"
  end
  job:line(row)

  local cost = job:cost()
  if flags["dry-run"] then
    o("Would print the test page:", C_TITLE); reportCost(cost, o); return
  end
  local printed, err, partial = job:commit(flags)
  if not printed then
    o("Test print failed: " .. tostring(err), C_ERR)
    if (partial or 0) > 0 then o("(some pages did come out)", C_WARN) end
    return
  end
  o("Test page printed. Check the output slots.", C_OK)
end

-- ── printer scan ──────────────────────────────────────────────────────
local function cmdScan(pos, o)
  local lines, err = P.scan()
  if not lines then o("Scan failed: " .. tostring(err), C_ERR); return end
  if type(lines) ~= "table" then
    o("Nothing in the input slot.", C_WARN); return
  end
  local out = pos[2]
  if out then
    if not (fs and fs.writeFile) then o("No filesystem access.", C_ERR); return end
    local body = table.concat(lines, "\n")
    local ok, wErr = pcall(fs.writeFile, out, body)
    if not ok then o("Cannot write " .. out .. ": " .. tostring(wErr), C_ERR); return end
    o(string.format("Scanned %d line(s) into %s.", #lines, out), C_OK)
    return
  end
  for i, line in ipairs(lines) do
    o(string.format("%3d  %s", i, tostring(line)), C_FG)
  end
  if #lines == 0 then o("(the page is blank)", C_DIM) end
end

-- ── printer tag ───────────────────────────────────────────────────────
local function cmdTag(args, o)
  local text = table.concat({ table.unpack(args, 2) }, " ")
  if text == "" then o("Usage: printer tag <text>", C_DIM); return end
  local ok, err = P.tag(text)
  if not ok then o("Tag failed: " .. tostring(err), C_ERR); return end
  o("Name tag printed.", C_OK)
end

-- ── Dispatch ──────────────────────────────────────────────────────────
local function help(o)
  o("printer — OpenPrinter driver", C_TITLE)
  o("  printer                    Attached printer and its levels", C_FG)
  o("  printer test               Print one test page", C_FG)
  o("  printer file <path>        Print a text file", C_FG)
  o("  printer preview <path>     Paginate it without printing", C_FG)
  o("  printer scan [<path>]      Read the page in the input slot", C_FG)
  o("  printer tag <text>         Print a name tag", C_FG)
  o("  printer clear              Empty the printer's buffer", C_FG)
  o("Flags for file/preview:", C_DIM)
  o("  --title=T  --copies=N  --center  --color=0xRRGGBB", C_DIM)
  o("  --no-wrap  --dry-run   --force", C_DIM)
  o("Colour costs one unit of colour ink PER LINE; leave it off for black.", C_DIM)
end

local function printerCmd(args, o)
  args = args or {}
  local pos, flags = parseArgs(args)
  local sub = pos[1]

  if sub == nil or sub == "status" then cmdStatus(o)
  elseif sub == "help" then help(o)
  elseif sub == "test" then cmdTest(flags, o)
  elseif sub == "file" or sub == "print" then cmdFile(pos, flags, o)
  elseif sub == "preview" then cmdPreview(pos, flags, o)
  elseif sub == "scan" then cmdScan(pos, o)
  elseif sub == "tag" then cmdTag(pos, o)
  elseif sub == "clear" then
    local ok, err = P.clear()
    if ok == nil and err then o("Clear failed: " .. tostring(err), C_ERR)
    else o("Printer buffer cleared.", C_OK) end
  else
    o("Unknown subcommand: " .. tostring(sub), C_ERR)
    o("Try 'printer help'.", C_DIM)
  end
end

return { commands = { printer = printerCmd } }
