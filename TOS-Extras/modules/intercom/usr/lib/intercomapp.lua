-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Intercom — panels TAB (the announcement post)                ║
-- ║                                                                ║
-- ║  A persistent tab with the cue list on the left and the        ║
-- ║  announcement log on the right. Enter announces the selected   ║
-- ║  cue for real; T tests it (plays the recording here, tells     ║
-- ║  nobody), which is how you check that the positions you wrote  ║
-- ║  down actually bracket the recording you meant.                ║
-- ║                                                                ║
-- ║  Registered through the app registry exactly like the mail tab ║
-- ║  (apps.lua resolves the bare name "intercomapp" under /usr/lib ║
-- ║  and pcall-skips it when this package isn't installed).        ║
-- ╚══════════════════════════════════════════════════════════════╝

-- The standard quit key (tos/shell/keys.lua), so `keys set quit F4`
-- closes this as it closes the rest of TOS. `typing`: text is being read
-- there, so a printable binding is a letter, not quit. Falls back to
-- ^Q / Esc where the key table is unavailable. (test_keys_readers.lua)
local function isQuit(ch, code, typing)
  if typing and ch and ch >= 32 and ch < 127 then return false end
  local ok, keys = pcall(require, "shell.keys")
  if ok and keys and keys.is then return keys.is("quit", ch, code) end
  return ch == 17 or code == 1
end
local function quitHint()
  local ok, keys = pcall(require, "shell.keys")
  local l = ok and keys and keys.label and keys.label("quit") or ""
  l = l:gsub(" / .*", "")
  return l ~= "" and l or "^Q"
end

local tabsMod  = require("shell.panels.tabs")
local ic       = require("intercom")

local M = {}

local function fsMod() return _G._TOS and _G._TOS.fs end

-- ── Pure-ish model helpers (exposed for tests) ──────────────

--- Tab label. Pure.
function M.label() return "Intercom" end

--- Truncate `s` to `width` with a trailing "~" when it doesn't fit, same
--- convention as every other list row in this shell (mail's inboxRow,
--- chat's old per-line truncation before it learned to wrap). Used for
--- the Heard log (Area 5 sweep: that line had no marker at all, so an
--- entry past the fold looked complete when it wasn't) and by cueRow
--- below, so the two rails of this tab cut text the same way. Pure.
function M.fitLine(s, width)
  s = tostring(s or "")
  width = width or 40
  if #s > width then return s:sub(1, math.max(1, width - 1)) .. "~" end
  return s
end

--- One cue row, fitted to `width`. Pure.
--- The severity is shown as a fixed-width tag rather than only a colour:
--- the announcement post is exactly the sort of machine that ends up on a
--- 1-bit monochrome screen in a corridor, where colour says nothing.
function M.cueRow(cue, width)
  width = width or 40
  local tag = (cue.severity or "info"):sub(1, 4):upper()
  local line = string.format(" %-4s %-14s %s", tag, cue.name:sub(1, 14), cue.text)
  return M.fitLine(line, width)
end

-- ── Open / lifecycle ────────────────────────────────────────

function M.open(S)
  local idx = tabsMod.find(S, "intercom")
  if idx then S.activeTab = idx; return S.tabs[idx] end
  local tab = {
    type = "intercom", label = M.label(),
    sel = 1, scroll = 0, interval = 2,
    cues = {}, errors = {}, log = {}, status = nil,
  }
  M.refresh(tab)
  S.tabs[#S.tabs + 1] = tab
  S.activeTab = #S.tabs
  return tab
end

--- Reload the catalog and the heard-log from disk.
function M.refresh(tab)
  local store = fsMod()
  tab.cues, tab.errors = ic.loadCatalog(store)
  tab.log = ic.loadSpool(store)
  tab.cfg = ic.loadCfg(store)
end

-- ── Draw ────────────────────────────────────────────────────

function M.draw(S, tab)
  local D, T, W, H = S.D, S.T, S.W, S.H
  local top = 2
  local bottom = H - 1
  -- display.fill/set are (x, y, w, h, char, FG, BG) / (x, y, text, FG, BG) —
  -- the background is the LAST argument, not the first colour.
  D.fill(1, top, W, bottom - top + 1, " ", T.fg, T.bg)

  local split = math.max(24, math.floor(W * 0.55))

  -- Header
  local drive = ic.findDrive()
  local ready = drive and drive.isReady and drive.isReady()
  local head = ready and "TAPE READY" or (drive and "NO TAPE" or "NO DRIVE — text only")
  D.set(2, top, "Announcements", T.title, T.bg)
  D.set(math.max(2, split - #head - 1), top, head,
    ready and T.highlight or T.warning, T.bg)
  D.set(split, top, "| Heard", T.title, T.bg)

  -- Cue list (left)
  local rows = bottom - top - 2
  local first = 1 + (tab.scroll or 0)
  for i = 0, rows - 1 do
    local cue = tab.cues[first + i]
    if cue then
      local selected = (first + i) == tab.sel
      -- Selection styling matches the Monitor tab (T.sel_fg / T.sel_bg with
      -- the same fallbacks), so the shell looks like one program.
      local fg = selected and (T.sel_fg or T.bg) or T.fg
      local bg = selected and (T.sel_bg or T.highlight) or T.bg
      if selected then D.fill(1, top + 1 + i, split - 1, 1, " ", fg, bg) end
      D.set(1, top + 1 + i, M.cueRow(cue, split - 2), fg, bg)
    end
  end
  if #tab.cues == 0 then
    D.set(2, top + 1, "No cues catalogued.", T.warning, T.bg)
    D.set(2, top + 2, "Describe the tape in " .. ic.CUES_PATH .. ":", T.dim, T.bg)
    D.set(2, top + 3, 'fuel-low [0001] "Reactor fuel low." [0005] warn', T.dim, T.bg)
  end
  for i, e in ipairs(tab.errors) do
    if top + rows - i >= top + 1 then
      D.set(2, top + rows - i + 1, ("line %d: %s"):format(e.line, e.why):sub(1, split - 3),
        T.error, T.bg)
    end
  end

  -- Heard log (right), newest last
  local logRows = rows
  local startIdx = math.max(1, #tab.log - logRows + 1)
  for i = 0, logRows - 1 do
    local a = tab.log[startIdx + i]
    if a then
      local sev = a.severity or "info"
      local color = (sev == "critical" or sev == "alert") and T.error
        or (sev == "warn") and T.warning or T.dim
      D.set(split + 2, top + 1 + i, M.fitLine(ic.formatLine(a), W - split - 2), color, T.bg)
    end
  end

  -- Status / keys
  local hint = tab.status
    or "Enter announce  |  T test (local only)  |  R reload  |  " .. quitHint() .. " close"
  D.fill(1, bottom, W, 1, " ", T.fg, T.bg)
  D.set(2, bottom, hint:sub(1, W - 2), tab.statusColor or T.dim, T.bg)
end

-- ── Input ───────────────────────────────────────────────────

local function selectedCue(tab) return tab.cues[tab.sel] end

function M.handleKey(S, tab, ch, co)
  local T = S.T
  if isQuit(ch, co, true) then                        -- the quit key
    tabsMod.close(S); return 3
  elseif co == 200 then                               -- Up
    tab.sel = math.max(1, (tab.sel or 1) - 1)
    if tab.sel <= (tab.scroll or 0) then tab.scroll = tab.sel - 1 end
    return 3
  elseif co == 208 then                               -- Down
    tab.sel = math.min(#tab.cues, (tab.sel or 1) + 1)
    return 3
  elseif ch == 114 or ch == 82 then                   -- R: reload
    M.refresh(tab)
    tab.status = "Catalog reloaded (" .. #tab.cues .. " cues)."
    tab.statusColor = T.highlight
    return 3
  elseif ch == 116 or ch == 84 then                   -- T: test
    local cue = selectedCue(tab)
    if not cue then return 0 end
    local rep = ic.announce({ cue = cue, localOnly = true })
    tab.status = rep.played
      and ("Testing '" .. cue.name .. "' — playing here, nobody told.")
      or ("Test failed: " .. (rep.errors[1] or "?"))
    tab.statusColor = rep.played and T.highlight or T.error
    return 3
  elseif co == 28 then                                -- Enter: announce
    local cue = selectedCue(tab)
    if not cue then return 0 end
    local rep = ic.announce({ cue = cue })
    if rep.sent then
      tab.status = "Announced '" .. cue.name .. "' (" .. cue.severity .. ")"
        .. (rep.played and " + tape" or " — text only")
      tab.statusColor = T.highlight
    else
      tab.status = "Not announced: " .. (rep.errors[1] or "?")
      tab.statusColor = T.error
    end
    M.refresh(tab)
    return 3
  end
  return 0
end

function M.handleScroll(S, tab, ev)
  local dir = (ev.dir or 0) > 0 and -1 or 1
  local newScroll = math.max(0, math.min(math.max(0, #tab.cues - 1),
    (tab.scroll or 0) + dir))
  if newScroll == tab.scroll then return 0 end
  tab.scroll = newScroll
  return 3
end

--- Live: pull in newly heard announcements while this tab is front.
function M.tick(S, tab)
  local before = #(tab.log or {})
  tab.log = ic.loadSpool(fsMod())
  if #tab.log ~= before then return 3 end
  return 0
end

return M
