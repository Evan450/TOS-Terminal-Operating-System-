-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Module: stock — what is in my base, and what is short   ║
-- ║                                                              ║
-- ║  Scans every inventory adjacent to a transposer or inventory ║
-- ║  controller, totals each item across all of them, and flags  ║
-- ║  anything below a threshold you set.                          ║
-- ║                                                              ║
-- ║  Runs fully inside the pkg sandbox: reads hardware through   ║
-- ║  peripheral.inventory (which enforces the peripheral.        ║
-- ║  inventory cap), draws through the sandboxed component GPU   ║
-- ║  proxy, and saves watches through the session-bound `fs` —   ║
-- ║  so the list is always written with the calling user's        ║
-- ║  permissions.                                                 ║
-- ║                                                              ║
-- ║  Aggregation, thresholds and formatting live in stock.lua —  ║
-- ║  pure, and unit-tested off-box by test_stock.lua. This file  ║
-- ║  is scanning, drawing and input.                              ║
-- ╚══════════════════════════════════════════════════════════════╝

local component = require("component")
local computer  = require("computer")
local S         = require("stock.stock")

local WATCH_FILE = "/etc/stock-watch.cfg"

-- ── Screen acquisition over a raw GPU proxy (same kit the game ────────
-- ── packages use; duplicated rather than shared so installing  ────────
-- ── `stock` pulls in nothing else). ───────────────────────────────────
local function screen(o, minW, minH)
  local gpuAddr = component.list and component.list("gpu")()
  if not gpuAddr then o("No GPU found.", 0xFF0000); return nil end
  local okG, gpu = pcall(component.proxy, gpuAddr)
  if not okG or not gpu then o("Cannot open the GPU.", 0xFF0000); return nil end
  local W, H = gpu.getResolution()
  if not W or not H then o("Cannot detect screen size.", 0xFF0000); return nil end
  if W < minW or H < minH then
    o(string.format("Screen too small: need %dx%d, have %dx%d.", minW, minH, W, H), 0xFF6600)
    return nil
  end
  local okD, depth = pcall(gpu.getDepth)
  local tier = (okD and type(depth) == "number")
    and (depth <= 1 and 1 or (depth <= 4 and 2 or 3)) or 1
  local T = (tier == 1) and {
    fg = 0xFFFFFF, dim = 0xFFFFFF, border = 0xFFFFFF, title = 0xFFFFFF,
    hi = 0xFFFFFF, warn = 0xFFFFFF, bg = 0x000000, sel = 0xFFFFFF,
  } or {
    fg = 0xFFFFFF, dim = 0xAAAAAA, bg = 0x000000,
    border = tier == 2 and 0x55FFFF or 0x00FFFF,
    title  = tier == 2 and 0xFFFF55 or 0xFFFF00,
    hi     = tier == 2 and 0x55FF55 or 0x00FF00,
    warn   = tier == 2 and 0xFF5555 or 0xFF4040,
    sel    = tier == 2 and 0x336699 or 0x2A4A6A,
  }
  local BOX = (tier >= 2)
    and { tl = "┌", tr = "┐", bl = "└", br = "┘", h = "─", v = "│" }
    or  { tl = "+", tr = "+", bl = "+", br = "+", h = "-", v = "|" }
  local D = { W = W, H = H, tier = tier, T = T, BOX = BOX, gpu = gpu }
  function D.set(x, y, s, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.set, x, y, s)
  end
  function D.fill(x, y, w, h, ch, fg, bg)
    if fg then pcall(gpu.setForeground, fg) end
    if bg then pcall(gpu.setBackground, bg) end
    pcall(gpu.fill, x, y, w, h, ch or " ")
  end
  function D.clear() D.fill(1, 1, W, H, " ", T.fg, T.bg) end
  return D
end

local function pad(s, w)
  s = tostring(s or "")
  if #s > w then return s:sub(1, math.max(1, w - 1)) .. "…" end
  return s .. string.rep(" ", w - #s)
end
local function padL(s, w)
  s = tostring(s or "")
  if #s > w then s = s:sub(1, w) end
  return string.rep(" ", w - #s) .. s
end

-- ── Hardware scan ─────────────────────────────────────────────────────
-- peripheral.inventory does the component work AND enforces the
-- peripheral.inventory capability, so this never touches a raw proxy.
local function scan(onProgress)
  local okI, inv = pcall(require, "peripheral.inventory")
  if not okI or not inv then
    return nil, "inventory support unavailable"
  end
  if not inv.available() then
    return nil, "no inventory controller or transposer attached"
  end
  local sides = inv.sides()
  if #sides == 0 then
    return nil, "no inventories found on any side"
  end
  local readings, scanned = {}, {}
  for _, sd in ipairs(sides) do
    if onProgress then onProgress(sd.name) end
    local stacks = inv.stacks(sd.side)
    if stacks then
      scanned[#scanned + 1] = sd.name
      for _, st in ipairs(stacks) do
        st.sideName = sd.name
        st.side = sd.side
        readings[#readings + 1] = st
      end
    end
  end
  return readings, nil, scanned
end

-- ── Watch list persistence ────────────────────────────────────────────
-- Stored as plain tab-separated lines (see stock.lua): hand-editable, and
-- never executable. Reads/writes go through the sandbox's session-bound
-- `fs`, so an operator without write access to /etc simply cannot save —
-- which is the correct outcome, not a bug to work around.
-- `fs` is the sandbox's session-bound securefs (the fs.read/fs.write
-- caps), reached as a bare global exactly as calc does.
local function haveFs() return fs and fs.readFile and fs.writeFile end

local function loadWatches()
  if not haveFs() or not fs.exists or not fs.exists(WATCH_FILE) then return {}, {} end
  local ok, data = pcall(fs.readFile, WATCH_FILE)
  if not ok or not data then return {}, {} end
  return S.decodeWatches(data)
end

local function saveWatches(watches, labels)
  if not haveFs() then return false, "no filesystem access" end
  --! Writes through the CALLER's securefs session, so a non-admin simply
  --! cannot change the thresholds — /etc is admin-writable. That is the
  --! right outcome for a base-wide alarm level rather than a bug to route
  --! around, and the caller surfaces the refusal instead of pretending the
  --! setting was saved.
  local ok, err = pcall(fs.writeFile, WATCH_FILE, S.encodeWatches(watches, labels))
  if not ok then return false, tostring(err or "write failed") end
  return true
end

-- ── Key decoding ──────────────────────────────────────────────────────

-- ── Standard TOS shortcuts ────────────────────────────────────────────
-- Shared with the shell (tos/shell/keys.lua), so ^Q closes this the same
-- way it closes everything else TOS ships — and an operator who rebinds
-- `quit` with `keys set` has it reach here too.
--
-- Plain Q still works: it is what this program has always used and
-- taking it away would break muscle memory for no gain. What changed is
-- which one is ADVERTISED, because a shortcut you have to remember per
-- program is not a shortcut, it is trivia.
local KEYS do local okK, m = pcall(require, "shell.keys"); KEYS = okK and m or nil end
local function stdQuit(ch, code)
  if KEYS and KEYS.is then return KEYS.is("quit", ch, code) end
  return ch == 17 or code == 68 or code == 1   -- ^Q / F10 / Esc
end
local function quitLabel()
  if KEYS and KEYS.label then
    local l = KEYS.label("quit")
    if l ~= "" then return l end
  end
  return "^Q"
end

local function keyName(ch, code)
  if code == 200 then return "up"    elseif code == 208 then return "down"
  elseif code == 201 then return "pgup" elseif code == 209 then return "pgdn"
  elseif code == 199 then return "home" elseif code == 207 then return "end"
  -- #FIX (real Minecraft, 2026-08-11) — ^Q (char 17) and F10 also read
  -- as "esc". Esc itself never arrives: it closes the screen GUI, so
  -- every cancel and quit that listened only for it was unreachable.
  -- Mapping them here fixes every call site at once.
  elseif code == 28 then return "enter"
  elseif stdQuit(ch, code) then return "esc"
  elseif code == 14 then return "back"
  elseif ch and ch > 0 then return string.char(ch):lower() end
  return nil
end

-- ══════════════════════════════════════════════════════════════════════
-- The monitor
-- ══════════════════════════════════════════════════════════════════════
local function monitor(o)
  local D = screen(o, 50, 16)
  if not D then return end
  local T, W, H = D.T, D.W, D.H

  local watches, labels = loadWatches()
  local rows, err, scanned = {}, nil, {}
  local cursor, top = 1, 1
  local query, typing = "", false
  local lowOnly = false
  local lastScan = 0
  local status = nil

  local listTop, listBottom = 5, H - 2
  local pageSize = listBottom - listTop + 1

  local function refresh()
    local readings, sErr, sc = scan()
    if not readings then rows, err = {}, sErr; return end
    err, scanned = nil, sc or {}
    rows = S.applyWatches(S.aggregate(readings), watches, labels)
    lastScan = computer.uptime()
    if cursor > #rows then cursor = math.max(1, #rows) end
  end

  local function visible()
    local list = S.filter(rows, query)
    if lowOnly then list = S.lowStock(list) end
    return list
  end

  local function draw()
    local list = visible()
    D.clear()
    -- Header
    D.fill(1, 1, W, 1, " ", T.bg, T.border)
    D.set(2, 1, "STOCK", T.bg, T.border)
    local t = S.totals(rows)
    local summary = string.format("%d kinds  %s items  %d slots",
      t.distinct, S.fmtCount(t.items), t.slots)
    D.set(math.max(8, W - #summary - 1), 1, summary, T.bg, T.border)

    -- Where the numbers came from. A total with no provenance is a total
    -- you cannot trust when a chest quietly stops being detected.
    local src = (#scanned > 0)
      and ("sides: " .. table.concat(scanned, ", "))
      or "no inventories detected"
    D.set(2, 2, pad(src, W - 2), T.dim, T.bg)

    -- Filter / mode line
    local mode = {}
    if query ~= "" then mode[#mode + 1] = "filter '" .. query .. "'" end
    if lowOnly then mode[#mode + 1] = "LOW ONLY" end
    local modeLine = (#mode > 0) and table.concat(mode, "  ·  ") or ""
    if typing then modeLine = "/" .. query .. "_" end
    D.set(2, 3, pad(modeLine, W - 2), typing and T.title or T.hi, T.bg)

    -- Column heads
    local wCount, wStacks, wMin = 9, 8, 7
    local wName = W - 2 - wCount - wStacks - wMin - 12
    D.set(2, 4, pad("ITEM", wName) .. padL("COUNT", wCount)
      .. padL("STACKS", wStacks) .. padL("MIN", wMin) .. "  WHERE", T.title, T.bg)

    if err then
      D.set(2, listTop + 1, err, T.warn, T.bg)
      D.set(2, listTop + 3, "Attach a transposer or inventory controller", T.dim, T.bg)
      D.set(2, listTop + 4, "with a chest next to it, then press R.", T.dim, T.bg)
    elseif #list == 0 then
      D.set(2, listTop + 1,
        (query ~= "" or lowOnly) and "Nothing matches." or "No items found.",
        T.dim, T.bg)
    else
      if cursor < top then top = cursor end
      if cursor > top + pageSize - 1 then top = cursor - pageSize + 1 end
      for i = 0, pageSize - 1 do
        local idx = top + i
        local row = list[idx]
        if not row then break end
        local y = listTop + i
        local sel = (idx == cursor)
        local fg = row.low and T.warn or T.fg
        if row.absent then fg = T.warn end
        local bg = sel and T.sel or T.bg
        if sel then D.fill(1, y, W, 1, " ", fg, bg) end
        local where = (#row.sides > 0) and table.concat(row.sides, ",") or "-"
        if row.absent then where = "(none)" end
        D.set(2, y,
          pad(row.label, wName)
          .. padL(S.fmtCount(row.total), wCount)
          .. padL(S.fmtStacks(row.total, 64), wStacks)
          .. padL(row.min and tostring(row.min) or "-", wMin)
          .. "  " .. where,
          fg, bg)
      end
      -- Scroll hint
      if #list > pageSize then
        D.set(W - 10, 4, string.format("%d/%d", cursor, #list), T.dim, T.bg)
      end
    end

    -- Footer
    D.fill(1, H, W, 1, " ", T.bg, T.border)
    local help = typing
      and "Enter=apply  Esc=cancel"
      or ("R refresh · / filter · L low-only · W watch · U unwatch · ^B bg · "
          .. quitLabel() .. " quit")
    D.set(2, H, pad(help, W - 2), T.bg, T.border)
    if status then
      D.set(2, H - 1, pad(status, W - 2), T.hi, T.bg)
    end
  end

  -- Prompt for a number, inline on the status row.
  local function promptNumber(label, default)
    local buf = tostring(default or "")
    while true do
      D.fill(1, H - 1, W, 1, " ", T.fg, T.bg)
      D.set(2, H - 1, label .. " " .. buf .. "_", T.title, T.bg)
      local e = { computer.pullSignal() }
      if e[1] == "key_down" then
        local k = keyName(e[3], e[4])
        if k == "enter" then return tonumber(buf) end
        if k == "esc" then return nil end
        if k == "back" then buf = buf:sub(1, -2)
        elseif k and k:match("^%d$") then buf = buf .. k end
      elseif e[1] == "interrupted" then
        return nil
      end
    end
  end

  refresh()
  draw()

  local REFRESH_EVERY = 10   -- seconds
  while true do
    local e = { computer.pullSignal(1) }
    local sig = e[1]

    if sig == "key_down" then
      local k = keyName(e[3], e[4])
      status = nil
      if typing then
        if k == "enter" then typing = false
        elseif k == "esc" then typing = false; query = ""
        elseif k == "back" then query = query:sub(1, -2)
        elseif k and #k == 1 then query = query .. k end
        cursor, top = 1, 1
      elseif k == "q" then
        break
      elseif k == "r" then
        refresh(); status = "Rescanned."
      elseif k == "/" then
        typing = true
      elseif k == "l" then
        lowOnly = not lowOnly; cursor, top = 1, 1
      elseif k == "up" then
        cursor = math.max(1, cursor - 1)
      elseif k == "down" then
        cursor = math.min(math.max(1, #visible()), cursor + 1)
      elseif k == "pgup" then
        cursor = math.max(1, cursor - pageSize)
      elseif k == "pgdn" then
        cursor = math.min(math.max(1, #visible()), cursor + pageSize)
      elseif k == "home" then
        cursor = 1
      elseif k == "end" then
        cursor = math.max(1, #visible())
      elseif k == "w" then
        local row = visible()[cursor]
        if row then
          local n = promptNumber("Warn when '" .. row.label .. "' drops below:",
            row.min or 64)
          if n then
            watches[row.key] = n
            labels[row.key] = row.label
            local ok, sErr = saveWatches(watches, labels)
            status = ok and ("Watching " .. row.label .. " (min " .. n .. ").")
              or ("Not saved (needs admin): " .. tostring(sErr))
            refresh()
          end
        end
      elseif k == "u" then
        local row = visible()[cursor]
        if row and watches[row.key] then
          watches[row.key] = nil
          labels[row.key] = nil
          local ok, sErr = saveWatches(watches, labels)
          status = ok and ("Stopped watching " .. row.label .. ".")
            or ("Could not save: " .. tostring(sErr))
          refresh()
        end
      end
      draw()

    elseif sig == "interrupted" then
      break

    elseif sig == "tos_focus" then
      -- Came back from the background: the screen belongs to someone
      -- else's leftovers until we repaint it.
      draw()

    elseif sig == nil or sig == "timer" then
      -- Idle tick. Rescanning is a lot of component calls, so it happens
      -- on a slow timer rather than every frame.
      if computer.uptime() - lastScan >= REFRESH_EVERY then
        refresh(); draw()
      end
    end
  end

  D.clear()
  pcall(D.gpu.setForeground, 0xFFFFFF)
  pcall(D.gpu.setBackground, 0x000000)
end

-- ══════════════════════════════════════════════════════════════════════
-- Command entry
-- ══════════════════════════════════════════════════════════════════════
local function cmdStock(args, o)
  local sub = args and args[1] and tostring(args[1]):lower() or nil

  if sub == "help" then
    o("stock — what is in your base, and what is running short.", 0xFFFF55)
    o("", 0xAAAAAA)
    o("  stock            Open the live monitor (full screen)", 0xFFFFFF)
    o("  stock list       One-shot listing to the shell", 0xFFFFFF)
    o("  stock low        Only what is below its watch threshold", 0xFFFFFF)
    o("  stock sides      Which inventories are attached", 0xFFFFFF)
    o("", 0xAAAAAA)
    o("In the monitor: R rescan · / filter · L low-only · W set a", 0xAAAAAA)
    o("threshold on the highlighted item · U remove it · "
      .. quitLabel() .. " quit.", 0xAAAAAA)
    o("Thresholds are saved in " .. WATCH_FILE .. ".", 0xAAAAAA)
    o("", 0xAAAAAA)
    o("Needs a transposer or inventory controller with at least one", 0xAAAAAA)
    o("inventory next to it. Items are totalled by their registry", 0xAAAAAA)
    o("name, so two mods' identically-named items stay separate.", 0xAAAAAA)
    return
  end

  if sub == "sides" then
    local okI, inv = pcall(require, "peripheral.inventory")
    if not okI or not inv or not inv.available() then
      o("No inventory controller or transposer attached.", 0xFF5555); return
    end
    local sides = inv.sides()
    if #sides == 0 then o("No inventories on any side.", 0xAAAAAA); return end
    o(string.format(" %-8s %s", "side", "slots"), 0xFFFF55)
    for _, sd in ipairs(sides) do
      o(string.format(" %-8s %d", sd.name, sd.size), 0xFFFFFF)
    end
    return
  end

  if sub == "list" or sub == "low" then
    local readings, err, scanned = scan()
    if not readings then o(tostring(err), 0xFF5555); return end
    local watches, labels = loadWatches()
    local rows = S.applyWatches(S.aggregate(readings), watches, labels)
    if sub == "low" then
      rows = S.lowStock(rows)
      if #rows == 0 then
        o("Nothing is below its threshold.", 0x55FF55)
        local n = 0; for _ in pairs(watches) do n = n + 1 end
        if n == 0 then
          o("(No thresholds set — open 'stock' and press W on an item.)", 0xAAAAAA)
        end
        return
      end
    end
    if #rows == 0 then o("No items found.", 0xAAAAAA); return end
    o(string.format(" %-30s %9s %8s %6s", "item", "count", "stacks", "min"), 0xFFFF55)
    local shown = 0
    for _, row in ipairs(rows) do
      if shown >= 40 then
        o(string.format(" ... and %d more (use 'stock' for the full list)",
          #rows - shown), 0xAAAAAA)
        break
      end
      o(string.format(" %-30s %9s %8s %6s",
        tostring(row.label):sub(1, 30),
        S.fmtCount(row.total),
        S.fmtStacks(row.total, 64),
        row.min and tostring(row.min) or "-"),
        row.low and 0xFF5555 or 0xFFFFFF)
      shown = shown + 1
    end
    local t = S.totals(rows)
    o(string.format(" %d kinds, %s items across %s",
      t.distinct, S.fmtCount(t.items),
      (#(scanned or {}) > 0) and table.concat(scanned, ", ") or "?"), 0xAAAAAA)
    return
  end

  if sub then
    o("Unknown subcommand: " .. sub, 0xFF5555)
    o("Try 'stock help'.", 0xAAAAAA)
    return
  end

  monitor(o)
end

return { commands = { stock = cmdStock } }
