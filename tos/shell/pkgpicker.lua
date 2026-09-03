-- ╔══════════════════════════════════════════════════════════════╗
-- ║  TOS Shell — the package picker (Optional Utilities & friends)║
-- ║                                                                ║
-- ║  The pick-and-choose installer, modelled on the MS-DOS 6.22    ║
-- ║  Supplemental Utilities Disk: a list of add-ons, a detail      ║
-- ║  panel, tick what you want, install the set.                   ║
-- ║                                                                ║
-- ║  IT LIVES IN THE BASE IMAGE, and that is the point. It used   ║
-- ║  to ship as a copy on every Optional Utilities floppy AND as   ║
-- ║  a ~40 KB string embedded in kernel/pkg.lua, kept              ║
-- ║  byte-identical by a test whose whole job was policing the     ║
-- ║  duplication. Both copies were pointless: the picker's first   ║
-- ║  act is `require("kernel.pkg")`, so it can only ever run on a  ║
-- ║  TOS machine — which already has this file. The floppy was     ║
-- ║  carrying 40 KB of installer to a machine that had one.        ║
-- ║                                                                ║
-- ║  So: one copy, here, and the disks got their space back.       ║
-- ║                                                                ║
-- ║  It draws through a RAW GPU proxy rather than the shell's      ║
-- ║  display, so it renders identically from the panels shell, the ║
-- ║  CLI shell and a recovery shell without fighting whoever owns  ║
-- ║  the screen; the caller repaints afterwards. Prompts that need ║
-- ║  a decision go through shell.panels.dialogs — the real         ║
-- ║  DOS-style modal, driven with a synthetic shell-state table    ║
-- ║  (it only needs D/T/W/H), so an operator being asked which     ║
-- ║  floppy to insert gets a proper framed box with room to say    ║
-- ║  which packages are waiting on it.                             ║
-- ╚══════════════════════════════════════════════════════════════╝

local M = {}

--- Run the picker. Returns true when it completed (including a clean
--- cancel); false plus a reason when it could not start.
function M.run(opts)
  opts = opts or {}
  local hasIO = io and io.read and io.write
  local function out(s) if hasIO then io.write((s or "") .. "\n") else print(s or "") end end
  local function raw(s) if hasIO then io.write(s or "") end end
  local function die(msg) out("ERROR: " .. msg); return end

  -- ── Preconditions: TOS + admin session ─────────────────────────────
  local okP, pkg = pcall(require, "kernel.pkg")
  if not okP or not pkg or not pkg.installByName then
    return die("kernel.pkg unavailable — run this on a TOS machine.")
  end
  local okU, users = pcall(require, "kernel.users")
  if not okU or not users then
    return die("kernel.users unavailable — run this on a TOS machine.")
  end

  local session = select(1, users.currentSession and users.currentSession() or nil)
  local ADMIN = (users.TIER and users.TIER.ADMIN) or 2
  if not session then
    return die("no logged-in session. Log in (admin/root), then re-run.")
  end
  if (session.tier or 0) < ADMIN then
    return die("installing packages requires admin/root.")
  end

  -- ── Discover installable packages (repos + every mounted disk) ─────
  local okFS, ufs = pcall(require, "kernel.fs")
  local okSer, userialize = pcall(require, "kernel.serialize")

  --- Read the SET manifest (optutil-set.lua) off any mounted disk. The
  --- builder writes the same one onto every disk of a multi-disk set, so
  --- whichever floppy is in the drive describes the WHOLE set. Without it
  --- the picker can only see what is mounted, which on a two-floppy set
  --- means showing half the catalogue with no hint the rest exists.
  --! #FIX (real Minecraft, 2026-08-11) — THIS FUNCTION USED TO
  --! ENUMERATE MOUNTS BY LISTING THE MOUNT DIRECTORY, and that is why a
  --! two-floppy set behaved as though the second floppy did not exist.
  --! Boot-time mounts are VIRTUAL: kernel/init.lua calls fs.mount()
  --! without creating a physical directory, so that listing comes back
  --! empty and the set manifest was never found. SET stayed nil, no
  --! off-disk packages were listed, and the swap prompt could never fire
  --! — the operator saw half a catalogue with nothing to say the rest
  --! existed, which is the exact failure the manifest exists to prevent.
  --!
  --! pkg.lua already knew this. Its mountedRepoRoots carries the comment
  --! "boot-time mounts are virtual and don't appear in fs.list" and
  --! consults the authoritative mount table first. The knowledge was
  --! there; this file just had its own second copy of the enumeration.
  --! Now there is one, exported as pkg.repoRoots().
  local function readSet()
    if not (okFS and okSer and ufs and userialize) then return nil end
    local roots = (pkg.repoRoots and pkg.repoRoots()) or { "/usr/repo", "/var/repo" }
    for _, r in ipairs(roots) do
      local p = r .. "/optutil-set.lua"
      if ufs.exists(p) then
        local raw = ufs.readFile(p)
        if type(raw) == "string" then
          -- Data only, parsed with the safe decoder (never load()ed): this
          -- file arrives on removable media.
          local okD, t = pcall(userialize.decode, raw:gsub("^%s*%-%-[^\n]*\n", ""),
            { maxBytes = 64 * 1024 })
          if okD and type(t) == "table" and type(t.packages) == "table" then
            return t
          end
        end
      end
    end
  end

  local SET = readSet()

  local avail = (pkg.listAllAvailable and pkg.listAllAvailable()) or {}
  -- Everything reachable RIGHT NOW is what listAllAvailable returned; mark it
  -- so the rest of the picker can tell "here" from "on the other floppy".
  local here = {}
  for _, e in ipairs(avail) do e.reachable = true; here[e.name] = true end

  -- Fold in catalogue entries for packages that belong to this set but live
  -- on a disk that isn't inserted. They are listed, selectable, and carry
  -- their disk number so the installer can ask for it by name.
  if SET then
    for name, meta in pairs(SET.packages) do
      if not here[name] then
        avail[#avail + 1] = {
          name = name, version = meta.version, description = meta.description,
          category = (type(meta.category) == "string" and meta.category ~= "")
                     and meta.category or "misc",
          kind = meta.kind, requires = meta.requires, recommends = meta.recommends,
          disk = meta.disk, reachable = false,
        }
      else
        for _, e in ipairs(avail) do
          if e.name == name then e.disk = meta.disk end
        end
      end
    end
  end

  if #avail == 0 then
    out("No installable packages found.")
    out("Insert the Optional Utilities disk (it auto-mounts under /mnt) and re-run.")
    -- ...and REPORT the refusal rather than returning a silent success.
    -- The picker draws through a raw GPU proxy, so its caller repaints the
    -- shell the instant run() returns (it has to -- the seat's shadow
    -- buffer no longer matches the panel). That repaint erases the two
    -- lines above before anyone can read them, which is why inserting a
    -- disk with no TOS packages on it -- an OPPM disk, say -- looked like
    -- `pkg install` refusing in total silence.
    --
    -- Signalling lets the caller say it through ordinary shell output,
    -- which survives the repaint, and fall back to the prompt scan.
    return false, "no installable packages found"
  end
  -- Group by CATEGORY, then name. A preferred order puts the common buckets
  -- first; anything unlisted sorts alphabetically after them (so a
  -- third-party category still appears, just below the built-ins).
  local CAT_ORDER = { games = 1, productivity = 2, network = 3, storage = 4,
                      security = 5, drivers = 6, control = 7, misc = 99 }
  local function catRank(c) return CAT_ORDER[c or "misc"] or 50 end
  table.sort(avail, function(a, b)
    local ra, rb = catRank(a.category), catRank(b.category)
    if ra ~= rb then return ra < rb end
    if (a.category or "") ~= (b.category or "") then
      return (a.category or "") < (b.category or "")
    end
    return (a.name or "") < (b.name or "")
  end)

  -- Human labels for the category headers the picker draws.
  local CAT_LABEL = {
    games = "Games", productivity = "Productivity", network = "Network",
    storage = "Storage", security = "Security", drivers = "Drivers",
    control = "Control", misc = "Other",
  }
  local function catLabel(c)
    return CAT_LABEL[c or "misc"] or ((c or "misc"):gsub("^%l", string.upper))
  end

  -- The display ROWS: a category header (not selectable) before each group,
  -- then a row per package. Selection tracks a row index; `selected` still
  -- keys by the package's index into `avail`, so A/N and the install loop
  -- are unchanged.
  local ROWS = {}
  local filter = ""            -- active search text ("" = show everything)

  --- Does a package match the current filter? Pure. Matches the name,
  --- the description and the category, all case-insensitively, because an
  --- operator hunting for "the spreadsheet one" will type any of the three
  --- and should not have to guess which field the author used.
  local function matches(e, f)
    if f == "" then return true end
    f = f:lower()
    local function has(s) return s and tostring(s):lower():find(f, 1, true) ~= nil end
    return has(e.name) or has(e.description) or has(e.category)
  end

  --- Rebuild the display rows for the current filter. A category header is
  --- emitted only when the group still has a visible member, so filtering
  --- never leaves an empty "Games" heading behind.
  --- `selected` keys by the index into `avail`, NOT by row, so ticks
  --- survive every filter change — you can filter, tick, refilter, tick,
  --- and install the union.
  local function buildRows()
    ROWS = {}
    local lastCat = nil
    for i, e in ipairs(avail) do
      if matches(e, filter) then
        if e.category ~= lastCat then
          lastCat = e.category
          ROWS[#ROWS + 1] = { header = catLabel(e.category), cat = e.category }
        end
        ROWS[#ROWS + 1] = { ai = i, cat = e.category }
      end
    end
  end
  buildRows()

  local selected = {}          -- ai -> true, chosen by the operator
  local autoSel  = {}          -- ai -> true, pulled in as a dependency
  local function isInstalled(name) return pkg.info and pkg.info(name) ~= nil end

  -- ── Dependency + recommendation indices ────────────────────────────
  -- `requires` entries come in two shapes depending on where the manifest
  -- was normalized: { name=, version= } or the "name >= 1.0" string form.
  -- Both are reduced to a bare name here, the same way the pkg command does.
  local function depName(r)
    if type(r) == "table" then return r.name end
    if type(r) == "string" then return (r:match("^(%S+)")) end
  end

  local byName = {}                     -- package name -> index into avail
  for i, e in ipairs(avail) do byName[e.name] = i end

  -- Reverse recommendations: "who wants THIS?". The operator asked for this
  -- explicitly — a package can be recommended by something OTHER than what
  -- you're installing right now, and knowing that mouse is wanted by four
  -- add-ons you already have is the argument for installing it.
  local recBy = {}
  for _, e in ipairs(avail) do
    for _, r in ipairs(e.recommends or {}) do
      recBy[r] = recBy[r] or {}
      recBy[r][#recBy[r] + 1] = e.name
    end
  end
  for _, list in pairs(recBy) do table.sort(list) end

  --- Every not-yet-installed package `ai` needs, transitively. Returns a set
  --- of indices. Cycle-safe: a manifest pair that requires each other would
  --- otherwise recurse forever.
  local function depsOf(ai, acc, seen)
    acc, seen = acc or {}, seen or {}
    local e = avail[ai]
    if not e or seen[ai] then return acc end
    seen[ai] = true
    for _, r in ipairs(e.requires or {}) do
      local n = depName(r)
      local di = n and byName[n]
      if di and not isInstalled(avail[di].name) then
        acc[di] = true
        depsOf(di, acc, seen)
      end
    end
    return acc
  end

  --- Recompute which packages are along for the ride. Called after every
  --- toggle so the list always shows the TRUE install set rather than
  --- surprising the operator in the install log.
  local function recomputeAuto()
    autoSel = {}
    for ai in pairs(selected) do
      for di in pairs(depsOf(ai)) do
        if not selected[di] then autoSel[di] = true end
      end
    end
  end

  --- Requirements that are NOT satisfiable from what's mounted. A dependency
  --- on a package sitting on the OTHER floppy is the common case, and saying
  --- so beats a failed install.
  local function missingDeps(e)
    local out = {}
    for _, r in ipairs(e.requires or {}) do
      local n = depName(r)
      if n and not byName[n] and not isInstalled(n) then out[#out + 1] = n end
    end
    return out
  end

  -- Shared post-install reporting: which rc.d services a chosen set left
  -- registered-but-disabled. The service name is the STEM of the package's
  -- /etc/rc.d/<name>.lua file, NOT the package name — cluster-master ships
  -- clusterd.lua, so the operator runs `service start clusterd`.
  local function serviceNamesFor(name)
    local svcs = {}
    local info = pkg.info and pkg.info(name)
    if info and info.kind == "service" then
      for _, f in ipairs(info.files or {}) do
        local svc = tostring(f):match("^/etc/rc%.d/(.+)%.lua$")
        if svc then svcs[#svcs + 1] = svc end
      end
      if #svcs == 0 then svcs[1] = name end
    end
    return svcs
  end

  -- ══════════════ Full-screen TUI ══════════════
  -- Drawn straight through a component GPU proxy: this script runs
  -- full-priv (it requires kernel.pkg), but going through the raw proxy
  -- means it renders identically from the panels shell, the CLI shell and
  -- a recovery shell, without fighting whoever owns the screen. The caller
  -- repaints after we return (panels does this for every command).
  local function tuiRun()
    local okC, component = pcall(require, "component")
    local okCm, computer = pcall(require, "computer")
    if not (okC and okCm and component and computer) then return nil end
    -- #FIX (emulator round 7) — the CALLING SEAT's GPU, not the bus's first
    -- one. `pkg install` runs this full-priv (outside the sandbox's
    -- seat-scoping), so on a two-seat machine the picker used to open on
    -- seat 1's screen no matter who typed the command. kernel.screen knows
    -- which seat owns the calling process; fall back to the old lookup when
    -- it can't say (single seat, boot, or the disk copy on a foreign OS).
    local gpuAddr
    do
      local okS, scr = pcall(require, "kernel.screen")
      if okS and type(scr) == "table" and scr.callerDevices then
        local okD, dev = pcall(scr.callerDevices)
        if okD and type(dev) == "table" then gpuAddr = dev.gpu end
      end
    end
    gpuAddr = gpuAddr or (component.list and component.list("gpu")())
    if not gpuAddr then return nil end
    local okG, gpu = pcall(component.proxy, gpuAddr)
    if not okG or not gpu or not gpu.getResolution then return nil end
    local W, H = gpu.getResolution()
    if not W or not H or W < 40 or H < 12 then return nil end

    -- Theme: borrow the live TOS palette when it's reachable so the
    -- installer matches the operator's chosen theme; fall back to the
    -- stock colours otherwise. Mono (T1) collapses to black/white.
    local depth = 8
    pcall(function() depth = gpu.getDepth() end)
    local mono = (depth or 8) <= 1
    local T = {
      bg = 0x000000, fg = 0xC0C0C0, dim = 0x555555, title = 0x00AAFF,
      sel_fg = 0x000000, sel_bg = 0x00AAFF, ok = 0x00FF00, warn = 0xFFAA00,
      err = 0xFF0000, panel = 0x1A1A1A,
    }
    local okD, disp = pcall(require, "kernel.display")
    if okD and disp and disp.getTheme then
      local th = disp.getTheme()
      if type(th) == "table" then
        T.bg = th.bg or T.bg; T.fg = th.fg or T.fg; T.dim = th.dim or T.dim
        T.title = th.title or T.title
        T.sel_fg = th.sel_fg or T.sel_fg; T.sel_bg = th.sel_bg or T.sel_bg
        T.ok = th.highlight or T.ok; T.warn = th.warning or T.warn
        T.err = th.error or T.err; T.panel = th.panel_bg or T.panel
      end
    end
    if mono then
      T = { bg = 0x000000, fg = 0xFFFFFF, dim = 0xFFFFFF, title = 0xFFFFFF,
            sel_fg = 0x000000, sel_bg = 0xFFFFFF, ok = 0xFFFFFF,
            warn = 0xFFFFFF, err = 0xFFFFFF, panel = 0x000000 }
    end

    local function set(x, y, s, fg, bg)
      if fg then pcall(gpu.setForeground, fg) end
      if bg then pcall(gpu.setBackground, bg) end
      pcall(gpu.set, x, y, s)
    end
    local function fill(x, y, w, h, ch, fg, bg)
      if fg then pcall(gpu.setForeground, fg) end
      if bg then pcall(gpu.setBackground, bg) end
      pcall(gpu.fill, x, y, w, h, ch or " ")
    end
    -- Column-safe truncation. Descriptions are operator-authored text and
    -- may be multi-byte; a byte-slice could cut a character in half.
    local uni = nil
    do local okU2, u = pcall(require, "unicode"); if okU2 then uni = u end end
    -- #FIX (emulator round 7) — the no-`unicode` fallback used #s, i.e. BYTES.
    -- Every rail in here is built from box-drawing glyphs (3 bytes each), so
    -- byte lengths made the frame maths wrong by ~2/3 of the rail width and
    -- the counts rail landed short of the right-hand edge. Count CHARACTERS
    -- instead: in UTF-8 a character is any byte that isn't a 10xxxxxx
    -- continuation byte. (These are all single-WIDTH glyphs, so characters
    -- and columns agree; `unicode` is still preferred when present because
    -- it also knows about wide CJK cells in operator-authored descriptions.)
    local function bytesLen(s)
      local n = 0
      for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
      end
      return n
    end
    local function bytesSub(s, a, b)
      -- Character-indexed slice over the same rule.
      local starts, n = {}, 0
      for i = 1, #s do
        local by = s:byte(i)
        if by < 0x80 or by >= 0xC0 then n = n + 1; starts[n] = i end
      end
      starts[n + 1] = #s + 1
      a = math.max(1, a or 1)
      b = math.min(n, b or n)
      if a > b then return "" end
      return s:sub(starts[a], starts[b + 1] - 1)
    end
    local function ulen(s) return uni and uni.len(s) or bytesLen(s) end
    local function usub(s, a, b) return uni and uni.sub(s, a, b) or bytesSub(s, a, b) end
    local function fitTo(s, n)
      s = tostring(s or "")
      if ulen(s) <= n then return s end
      if n <= 1 then return usub(s, 1, n) end
      return usub(s, 1, n - 1) .. (mono and ">" or "…")
    end

    local LIST_TOP = 4
    local BAR      = H              -- ramp key bar
    -- Two-pane when there's room: the list on the LEFT, a proper detail panel
    -- on the RIGHT. Below 60 columns there isn't room for both, so the old
    -- single-column layout with a two-line footer stays — a T1 screen is
    -- 50x16 and must still be usable.
    local twoPane  = W >= 60
    local LISTW    = twoPane and math.max(26, math.floor(W * 0.42)) or W
    local PANEX    = LISTW + 2      -- first column of the detail panel
    local PANEW    = W - PANEX      -- its usable width
    local FOOT     = twoPane and (H - 1) or (H - 2)
    local listH    = math.max(1, FOOT - LIST_TOP)
    local scroll = 0

    -- `sel` is a ROW index; headers are not selectable. Seed it on the
    -- first package row and provide skip-the-headers movement.
    local function firstPkgRow()
      for i, r in ipairs(ROWS) do if r.ai then return i end end
      return 1
    end
    local function nextPkgRow(from, dir)
      local i = from
      while true do
        local j = i + dir
        if j < 1 or j > #ROWS then return i end   -- clamp at the ends
        i = j
        if ROWS[i] and ROWS[i].ai then return i end
      end
    end
    local sel = firstPkgRow()
    local function curPkg()
      local r = ROWS[sel]
      return r and r.ai and avail[r.ai] or nil, r and r.ai or nil
    end

    local function countSelected()
      local n = 0
      for _ in pairs(selected) do n = n + 1 end
      for _ in pairs(autoSel) do n = n + 1 end
      return n
    end

    -- ── Group + filter operations ──────────────────────────────────
    -- These act on what is VISIBLE. Filtering to "game" and pressing A is
    -- meant to take the games — an A that quietly also ticked the twelve
    -- packages you had just filtered away would be the opposite of a
    -- filter's purpose.

    --- Every avail index currently on screen (filter applied).
    local function visibleIndices()
      local out = {}
      for _, r in ipairs(ROWS) do if r.ai then out[#out + 1] = r.ai end end
      return out
    end

    --- Indices in a category, respecting the filter.
    local function groupIndices(cat)
      local out = {}
      for _, r in ipairs(ROWS) do
        if r.ai and r.cat == cat then out[#out + 1] = r.ai end
      end
      return out
    end

    --- Toggle a whole category: if anything in it is untouched, select the
    --- lot; if everything selectable is already ticked, clear them. Acting
    --- on "is anything left to add?" rather than a stored per-group flag
    --- keeps it predictable when the group is half-ticked already.
    local function toggleGroup(cat)
      local idx = groupIndices(cat)
      local anyOff = false
      for _, ai in ipairs(idx) do
        if not isInstalled(avail[ai].name) and not selected[ai] then anyOff = true end
      end
      for _, ai in ipairs(idx) do
        if not isInstalled(avail[ai].name) then
          selected[ai] = anyOff and true or nil
        end
      end
      recomputeAuto()
      return anyOff, #idx
    end

    --- Category of whatever the cursor is on (package row or header).
    local function curCategory()
      local r = ROWS[sel]
      return r and r.cat
    end

    local function drawFrame()
      fill(1, 1, W, H, " ", T.fg, T.bg)
      -- Rule 1 — a system surface that owns the screen gets the double line.
      local title = " TOS Optional Utilities "
      local line = (mono and "=" or "═")
      set(1, 1, string.rep(line, W), T.title, T.bg)
      set(math.max(1, math.floor((W - #title) / 2)), 1, title, T.title, T.bg)
      -- Rule 2 — a dim rail carries the counts; labels re-drawn brighter.
      -- With a filter on, the left count says "showing N of M" so it is
      -- always obvious the list is not the whole set — a filter you forgot
      -- about looks exactly like a disk that is missing packages.
      local shown = 0
      for _, r in ipairs(ROWS) do if r.ai then shown = shown + 1 end end
      local left
      if filter ~= "" then
        left = string.format("%d of %d match '%s'", shown, #avail, filter)
      else
        left = string.format("%d add-ons", #avail)
      end
      local right = string.format("%d selected", countSelected())
      local dash = (mono and "-" or "─")
      local lt, rt = (mono and "|" or "┤"), (mono and "|" or "├")
      local railLeft = dash .. lt .. " " .. left .. " " .. rt
      local railRight = lt .. " " .. right .. " " .. rt .. dash
      local mid = W - ulen(railLeft) - ulen(railRight)
      set(1, 2, railLeft .. string.rep(dash, math.max(0, mid)) .. railRight, T.dim, T.bg)
      -- #FIX (emulator round 7) — these re-draws must land EXACTLY on the
      -- label already inside the rail, or the rail's copy shows past the end
      -- of the bright one and the last character reads twice ("13 add-onss").
      -- railLeft  = dash lt SPACE <left>  -> the label starts at column 4.
      -- railRight = lt SPACE <right> ...  -> it starts 2 in from railRight's
      -- own first column, which is W - ulen(railRight) + 1.
      set(4, 2, left, T.fg, T.bg)
      set(W - ulen(railRight) + 3, 2, right, T.fg, T.bg)
      -- [+] earns its place in the legend: a dependency the picker selected
      -- FOR you is the one mark whose meaning isn't guessable.
      set(2, 3, fitTo("[*] installed  [x] selected  [+] needed by one  [ ] available",
        W - 3), T.dim, T.bg)
    end

    local function drawList()
      if sel < scroll + 1 then scroll = sel - 1 end
      if sel > scroll + listH then scroll = sel - listH end
      if scroll < 0 then scroll = 0 end
      for r = 0, listH - 1 do
        local ridx = scroll + r + 1
        local y = LIST_TOP + r
        local row = ROWS[ridx]
        fill(1, y, LISTW, 1, " ", T.fg, T.bg)
        if row and row.header then
          -- Rule 2 — a category header is a dim rail: ── Games ─────────
          local dash = (mono and "-" or "─")
          local label = " " .. row.header .. " "
          set(1, y, dash .. dash .. label
            .. string.rep(dash, math.max(0, LISTW - 3 - ulen(label))), T.dim, T.bg)
          -- Same off-by-one as the counts rail: label = SPACE <header> SPACE
          -- after two dashes, so the header itself starts at column 4.
          set(4, y, row.header, T.title, T.bg)
        elseif row and row.ai then
          local ai = row.ai
          local e = avail[ai]
          local installed = isInstalled(e.name)
          local mark = installed and "[*]"
            or (selected[ai] and "[x]" or (autoSel[ai] and "[+]" or "[ ]"))
          local isSel = (ridx == sel)
          -- A package on a disk that isn't in the drive is dimmed but still
          -- listed and still selectable — the point is that you can plan the
          -- whole install from one floppy.
          local fg = isSel and T.sel_fg
            or ((installed or e.reachable == false) and T.dim or T.fg)
          local bg = isSel and T.sel_bg or T.bg
          if isSel then fill(1, y, LISTW, 1, " ", fg, bg) end
          local markColor = isSel and fg
            or (installed and T.ok
            or (selected[ai] and T.warn or (autoSel[ai] and T.title or T.dim)))
          -- Indent one column under the header so the grouping reads.
          set(3, y, mark, markColor, bg)
          -- In two-pane mode the description lives in the panel, so the row
          -- is just mark + name + version and can be much narrower.
          local nameW = twoPane and (LISTW - 16) or 17
          set(7, y, fitTo(e.name or "?", math.max(4, nameW)), fg, bg)
          local ver = e.version and ("v" .. tostring(e.version)) or ""
          if twoPane then
            set(LISTW - 8, y, fitTo(ver, 8), isSel and fg or T.dim, bg)
          else
            set(25, y, fitTo(ver, 8), isSel and fg or T.dim, bg)
            set(34, y, fitTo(e.description or "", math.max(0, W - 35)),
              isSel and fg or T.dim, bg)
          end
        end
      end
      -- Scroll thumb so a long list reads as scrollable (rule 4: chrome dim).
      if #ROWS > listH then
        local pos = math.floor((scroll / math.max(1, #ROWS - listH)) * (listH - 1) + 0.5)
        for r = 0, listH - 1 do
          set(LISTW, LIST_TOP + r,
            (r == pos) and (mono and "#" or "█") or (mono and "|" or "│"), T.dim, T.bg)
        end
      end
      -- A filter that matches nothing must SAY so. An empty list under a
      -- rail reading "0 of 14" is decipherable; an empty list with no
      -- explanation reads as a broken disk.
      if #ROWS == 0 then
        set(2, LIST_TOP, fitTo("Nothing matches '" .. filter .. "'.", LISTW - 3),
          T.warn, T.bg)
        set(2, LIST_TOP + 1, fitTo("Esc clears the filter, / edits it.", LISTW - 3),
          T.dim, T.bg)
      end
      -- The divider between the panes.
      if twoPane then
        for r = 0, listH - 1 do
          set(LISTW + 1, LIST_TOP + r, mono and "|" or "│", T.dim, T.bg)
        end
      end
    end

    -- ── Detail panel (right pane) ────────────────────────────────────
    -- Everything the operator needs to decide, in one place: what it is, how
    -- big the commitment is, WHICH DISK it came from (the set spans two
    -- floppies now), what it drags in, and what else on this disk wants it.
    local function drawPanel()
      if not twoPane then return end
      local e = curPkg()
      for r = 0, listH - 1 do fill(PANEX, LIST_TOP + r, PANEW, 1, " ", T.fg, T.bg) end
      if not e then return end
      local y = LIST_TOP

      local function line(text, color, indent)
        if y >= LIST_TOP + listH then return end
        set(PANEX + (indent or 0), y, fitTo(text or "", PANEW - (indent or 0)),
          color or T.fg, T.bg)
        y = y + 1
      end
      local function field(label, value, color)
        if value == nil or value == "" then return end
        if y >= LIST_TOP + listH then return end
        set(PANEX, y, fitTo(label, 10), T.dim, T.bg)
        set(PANEX + 10, y, fitTo(tostring(value), PANEW - 10), color or T.fg, T.bg)
        y = y + 1
      end
      local function wrap(text, color)
        -- Greedy word wrap; descriptions are a sentence or two.
        local w = PANEW
        local cur = ""
        for word in tostring(text or ""):gmatch("%S+") do
          if cur == "" then cur = word
          elseif ulen(cur) + 1 + ulen(word) <= w then cur = cur .. " " .. word
          else line(cur, color); cur = word end
        end
        if cur ~= "" then line(cur, color) end
      end

      line(e.name or "?", T.title)
      line(string.rep(mono and "-" or "─", math.min(PANEW, 40)), T.dim)
      wrap(e.description or "(no description)", T.fg)
      line("", nil)

      local installed = isInstalled(e.name)
      local ai = select(2, curPkg())
      local state = installed and "already installed"
        or (selected[ai] and "selected to install"
        or (autoSel[ai] and "needed by another choice" or "available"))
      field("Status", state,
        installed and T.ok or ((selected[ai] or autoSel[ai]) and T.warn or T.dim))
      field("Version", e.version)
      field("Category", catLabel(e.category))
      field("Kind", e.kind)
      field("Author", e.author)
      -- Which disk this one is on. listAllAvailable already spans every
      -- mounted repo; the picker just never said so, which made a two-floppy
      -- set look like one disk with things mysteriously missing.
      if e.reachable then
        field("From", e.root or (e.disk and ("disk " .. e.disk)))
      else
        -- Not in the drive. Say which floppy to fetch — and that picking it
        -- anyway is fine, because the installer will ask for the disk.
        field("On disk", tostring(e.disk or "?") .. "  (not inserted)", T.warn)
        line("selectable — the installer will ask for it", T.dim, 10)
      end

      local reqs = {}
      for _, r in ipairs(e.requires or {}) do
        local n = depName(r)
        if n then reqs[#reqs + 1] = n end
      end
      if #reqs > 0 then
        field("Needs", table.concat(reqs, ", "))
        local miss = missingDeps(e)
        if #miss > 0 then
          line("not on any inserted disk: " .. table.concat(miss, ", "), T.err, 10)
        end
      end
      if e.recommends and #e.recommends > 0 then
        field("Suggests", table.concat(e.recommends, ", "), T.dim)
      end
      local wanted = recBy[e.name]
      if wanted and #wanted > 0 then
        -- The reverse view. This is what makes a recommendation actionable:
        -- "four things you're installing want this" is an argument, where
        -- "mouse is suggested" alone is noise.
        field("Wanted by", table.concat(wanted, ", "), T.dim)
      end
    end

    local function drawFoot()
      -- Narrow screens keep the two-line description footer; wide ones have
      -- the detail panel instead and use the space for the key bar alone.
      if not twoPane then
        local e = curPkg()
        fill(1, FOOT, W, 1, " ", T.fg, T.bg)
        fill(1, FOOT + 1, W, 1, " ", T.fg, T.bg)
        if e then
          local d = e.description or "(no description)"
          set(2, FOOT, fitTo(d, W - 3), T.fg, T.bg)
          local meta = {}
          if e.category then meta[#meta + 1] = catLabel(e.category) end
          if isInstalled(e.name) then meta[#meta + 1] = "already installed" end
          if e.root then meta[#meta + 1] = tostring(e.root) end
          if e.kind then meta[#meta + 1] = tostring(e.kind) end
          if #meta > 0 then
            set(2, FOOT + 1, fitTo(table.concat(meta, "  ·  "), W - 3), T.dim, T.bg)
          end
        end
      end
      -- Rule 3 — ramp caps at the EDGES of the key bar, never inside.
      fill(1, BAR, W, 1, mono and " " or "░", T.dim, T.bg)
      if not mono then
        set(1, BAR, "▓▒░", T.dim, T.bg)
        if W > 6 then set(W - 2, BAR, "░▒▓", T.dim, T.bg) end
      end
      local keys = " Space · G Group · / Filter · A All · N None · R +Suggested · Enter Install · Q Quit "
      set(5, BAR, fitTo(keys, W - 9), T.fg, T.bg)
    end

    local function redraw() drawFrame(); drawList(); drawPanel(); drawFoot() end

    --- Inline filter prompt on the key bar. Reads keys directly (the picker
    --- has no stdin — that is the whole reason it is a TUI), applies live so
    --- the list narrows as you type, and leaves the filter in place on
    --- Enter. Esc restores whatever was active when you started, so a
    --- half-typed search never destroys the one you had.
    local function promptFilter()
      local before = filter
      local buf = filter
      while true do
        buildRows()
        sel = firstPkgRow(); scroll = 0
        drawFrame(); drawList(); drawPanel()
        fill(1, BAR, W, 1, " ", T.fg, T.bg)
        set(2, BAR, fitTo("Filter: " .. buf .. "_", W - 22), T.title, T.bg)
        set(math.max(2, W - 19), BAR, "Enter=keep Esc=undo", T.dim, T.bg)
        local ev2, _, ch2, co2 = computer.pullSignal()
        if ev2 == "key_down" then
          if co2 == 28 then filter = buf; break                  -- Enter
          elseif co2 == 1 then filter = before; break            -- Esc
          elseif co2 == 14 then                                  -- Backspace
            buf = buf:sub(1, -2); filter = buf
          elseif ch2 and ch2 >= 32 and ch2 < 127 then
            buf = buf .. string.char(ch2); filter = buf
          end
        end
      end
      buildRows()
      sel = firstPkgRow(); scroll = 0
      redraw()
    end

    redraw()
    while true do
      local ev, _, ch, code = computer.pullSignal()
      if ev == "key_down" then
        local function move(f) f(); drawList(); drawPanel(); drawFoot() end
        if code == 200 then move(function() sel = nextPkgRow(sel, -1) end)
        elseif code == 208 then move(function() sel = nextPkgRow(sel, 1) end)
        elseif code == 201 then                                -- PgUp
          move(function() for _ = 1, listH do sel = nextPkgRow(sel, -1) end end)
        elseif code == 209 then                                -- PgDn
          move(function() for _ = 1, listH do sel = nextPkgRow(sel, 1) end end)
        elseif code == 199 then move(function() sel = firstPkgRow() end)
        elseif code == 207 then                                -- End
          move(function() for _ = 1, #ROWS do sel = nextPkgRow(sel, 1) end end)
        elseif ch == 32 then                                  -- Space toggles
          local e, ai = curPkg()
          if e and ai and not isInstalled(e.name) then
            selected[ai] = not selected[ai] or nil
            -- Dependencies follow the choice immediately, so the counts rail
            -- and the [+] marks always describe what will ACTUALLY install.
            recomputeAuto()
          end
          redraw()
        elseif ch == 103 or ch == 71 then                     -- g = group
          -- Select/deselect every package in the category the cursor is in.
          local cat = curCategory()
          if cat then
            local turnedOn, n = toggleGroup(cat)
            redraw()
            set(2, BAR, fitTo(string.format(" %s %d in %s ",
              turnedOn and "Selected" or "Cleared", n, catLabel(cat)), W - 6),
              T.title, T.bg)
          end
        elseif ch == 47 or ch == 63 then                      -- / or ? = filter
          promptFilter()
        elseif ch == 97 or ch == 65 then                      -- a = all
          -- VISIBLE only, so "filter, then A" means "take these" rather
          -- than "take these and also the dozen I just filtered away".
          for _, i in ipairs(visibleIndices()) do
            if not isInstalled(avail[i].name) then selected[i] = true end
          end
          recomputeAuto()
          redraw()
        elseif ch == 110 or ch == 78 then                     -- n = none
          -- Symmetric with A: clears what is on screen. With no filter
          -- active that is everything, exactly as before.
          if filter == "" then selected = {}
          else
            for _, i in ipairs(visibleIndices()) do selected[i] = nil end
          end
          recomputeAuto()
          redraw()
        elseif ch == 114 or ch == 82 then                     -- r = take suggestions
          -- Add everything RECOMMENDED by the current selection. Opt-in on a
          -- key, never automatic: a recommendation that installed itself
          -- would just be a dependency wearing a softer word.
          local add = {}
          for ai in pairs(selected) do
            for _, r in ipairs(avail[ai].recommends or {}) do
              local ri = byName[r]
              if ri and not isInstalled(avail[ri].name) then add[ri] = true end
            end
          end
          for ri in pairs(add) do selected[ri] = true end
          recomputeAuto()
          redraw()
        elseif (code == 1 or ch == 17) and filter ~= "" then  -- ^Q / Esc clears the filter
          -- ...rather than quitting. A filter that matched nothing leaves an
          -- empty list, and Esc is exactly what you reach for there; exiting
          -- the installer instead would be a nasty surprise. Esc still quits
          -- when no filter is active, and Q always quits.
          filter = ""
          buildRows(); sel = firstPkgRow(); scroll = 0
          redraw()
        elseif ch == 113 or ch == 81 or ch == 17 or code == 1 then  -- q / ^Q / Esc
          fill(1, 1, W, H, " ", T.fg, T.bg)
          return "cancel"
        elseif code == 28 then                                -- Enter = install
          local total = 0
          return "install", function(name, status, detail)
            -- Progress callback: a real bar plus a per-package log. `detail`
            -- is the 1-based index of the package being worked on, and
            -- `total` is stashed on "begin" so the bar has a denominator.
            local function bar(done)
              local BARY = H - 1
              local w = math.max(10, W - 18)
              local frac = (total > 0) and math.min(1, done / total) or 0
              local fillN = math.floor(w * frac + 0.5)
              fill(1, BARY, W, 1, " ", T.fg, T.bg)
              set(2, BARY, "[" .. string.rep(mono and "#" or "█", fillN)
                .. string.rep(" ", w - fillN) .. "]", T.title, T.bg)
              set(w + 5, BARY, string.format("%d/%d", done, total), T.dim, T.bg)
            end
            if status == "swap" then
              -- A DECISION, so it gets the real DOS-style modal instead of
              -- two lines painted over the log: framed, titled, shadowed,
              -- with room to name the disk AND every package waiting on it,
              -- and buttons rather than letters you have to remember.
              --
              -- dialogs.dialog only reads D/T/W/H off the shell state, so a
              -- synthetic one built from this picker's own draw primitives
              -- drives the GENUINE renderer — no second dialog implementation
              -- to drift from the first.
              local okDlg, dialogs = pcall(require, "shell.panels.dialogs")
              if okDlg and dialogs and dialogs.dialog then
                local fakeS = { W = W, H = H, T = T, D = { set = set, fill = fill } }
                local pick = dialogs.dialog(fakeS, {
                  style   = "install",
                  title   = "Next disk",
                  message = tostring(name)
                    .. "\n\nSwap the floppy, then choose Continue."
                    .. "\nStopping here keeps everything already installed.",
                  buttons = { "Continue", "Stop (keep)", "Undo all" },
                  default = 1, escIndex = 2,
                })
                return (pick == 3 and "undo") or (pick == 2 and "abort") or "retry"
              end
              -- No dialogs module (a stripped or recovery image): fall back
              -- to the two-line prompt rather than losing the step entirely.
              local y0 = math.max(2, H - 6)
              fill(1, y0, W, 4, " ", T.fg, T.bg)
              set(2, y0, fitTo(tostring(name), W - 4), T.warn, T.bg)
              set(2, y0 + 1, fitTo(
                "Enter = continue   A = stop, keep what's installed   U = undo all",
                W - 4), T.fg, T.bg)
              while true do
                local ev2, _, ch2, co2 = computer.pullSignal()
                if ev2 == "key_down" then
                  if co2 == 28 then return "retry" end
                  if ch2 == 97 or ch2 == 65 or co2 == 1 then return "abort" end
                  if ch2 == 117 or ch2 == 85 then return "undo" end
                end
              end
            elseif status == "begin" then
              total = detail or 0
              fill(1, 1, W, H, " ", T.fg, T.bg)
              set(2, 1, "Installing…", T.title, T.bg)
              bar(0)
            elseif status == "row" then
              local y = 2 + (detail or 0)
              if y < H - 2 then set(2, y, fitTo(name, W - 20), T.fg, T.bg) end
              bar((detail or 1) - 1)
            elseif status == "ok" then
              local y = 2 + (detail or 0)
              if y < H - 2 then set(W - 16, y, "installed", T.ok, T.bg) end
              bar(detail or 0)
            elseif status == "fail" then
              local y = 2 + (detail or 0)
              if y < H - 2 then set(W - 16, y, fitTo(tostring(name), 15), T.err, T.bg) end
              bar(detail or 0)
            elseif status == "done" then
              bar(total)
              set(2, H, fitTo(tostring(name) .. "   Press any key…", W - 4), T.fg, T.bg)
              while true do
                local e2 = computer.pullSignal()
                if e2 == "key_down" then break end
              end
              fill(1, 1, W, H, " ", T.fg, T.bg)
            end
          end
        end
      end
    end
  end

  -- ══════════════ Line-mode fallback ══════════════
  local function lineRun()
    if not hasIO then
      out("No GPU for the menu and no interactive input here.")
      out("Install from the disk with:")
      out("  pkg from-floppy        installs the whole disk, with prompts")
      out("  pkg install <name>     one package, e.g.  pkg install tetris")
      return "cancel"
    end
    local function render()
      out("")
      out("=== TOS Optional Utilities ===")
      out("  [*] already installed   [x] selected   [ ] available")
      -- Same grouping as the TUI, shown as "-- Category --" section headers
      -- so the numbered list reads by bucket.
      local lastCat = nil
      for i, e in ipairs(avail) do
        if e.category ~= lastCat then
          lastCat = e.category
          out("  -- " .. catLabel(e.category) .. " --")
        end
        local mark
        if isInstalled(e.name) then mark = "[*]"
        elseif selected[i]     then mark = "[x]"
        elseif autoSel[i]      then mark = "[+]"
        else                        mark = "[ ]" end
        out(string.format("   %2d %s %-16s %s", i, mark,
          e.name or "?", (e.description or ""):sub(1, 42)))
      end
      out("")
      out("  <number> toggle  ·  a all  ·  n none  ·  i install  ·  q quit")
    end
    while true do
      render()
      raw("> ")
      local line = io.read()
      if not line then
        out("")
        out("No interactive input here (panels shell). Install from the disk with:")
        out("  pkg from-floppy        installs the whole disk, with prompts")
        out("  pkg install <name>     one package, e.g.  pkg install tetris")
        return "cancel"
      end
      line = line:gsub("%s+", "")
      if line == "q" then out("Cancelled — nothing installed."); return "cancel"
      elseif line == "i" then return "install"
      elseif line == "a" then
        for i, e in ipairs(avail) do if not isInstalled(e.name) then selected[i] = true end end
        recomputeAuto()
      elseif line == "n" then selected = {}; recomputeAuto()
      else
        local n = tonumber(line)
        if n and avail[n] then
          if isInstalled(avail[n].name) then out("  (" .. avail[n].name .. " is already installed)")
          else selected[n] = not selected[n] or nil; recomputeAuto() end
        else out("  ? unrecognised — enter a number, or a/n/i/q") end
      end
    end
  end

  -- ══════════════ Drive the chosen front-end ══════════════
  --
  -- The TUI paints with RAW gpu calls on purpose: it has to work in an
  -- emergency shell where kernel.display may not be up. The cost is that
  -- it moves the hardware behind the back of everything that caches what
  -- the hardware looks like -- kernel.display's colour pair, and the
  -- seat proxy's dirty-cell shadow. Neither notices, so the first repaint
  -- after the picker closes can be skipped as "already correct" and the
  -- shell comes back wearing the picker's colours. Hand the screen back
  -- properly: say, out loud, that nobody's cache is valid any more.
  local function releaseScreen()
    local okD, disp = pcall(require, "kernel.display")
    if okD and disp and disp.invalidateColors then pcall(disp.invalidateColors) end
    local okS, scr = pcall(require, "kernel.screen")
    if okS and scr and scr.invalidateAll then pcall(scr.invalidateAll) end
  end

  local action, progress = tuiRun()
  releaseScreen()
  if action == nil then action = lineRun() end
  if action ~= "install" then return end

  -- Both the operator's picks AND the dependencies they implied. installByName
  -- would pull the deps in regardless; listing them here means the progress
  -- bar counts them and the log names them, instead of the operator watching
  -- "3 selected" install five things.
  local chosen = {}
  for i, e in ipairs(avail) do
    if selected[i] or autoSel[i] then chosen[#chosen + 1] = e end
  end
  if #chosen == 0 then
    if progress then progress("Nothing selected.", "done") else out("Nothing selected.") end
    return
  end

  if progress then progress(nil, "begin", #chosen) else
    out(""); out("Installing " .. #chosen .. " package(s)...")
  end

  -- ── Install, across as many disks as the selection spans ───────────
  -- The set can be bigger than one floppy, so a selection can legitimately
  -- name packages that aren't in the drive. Install everything reachable
  -- now, then ask for the next disk. The operator always has three ways
  -- out: continue, stop and KEEP what's installed, or undo the whole run.
  local okCount, failCount, services = 0, 0, {}
  local installedThisRun = {}          -- for undo, in install order
  local row = 0

  --- Is this package installable right now? Re-checked between disks: the
  --- answer changes the moment a floppy is swapped.
  local function reachableNow(name)
    for _, e in ipairs((pkg.listAllAvailable and pkg.listAllAvailable()) or {}) do
      if e.name == name then return true end
    end
    return false
  end

  local function installOne(e)
    row = row + 1
    if progress then progress(e.name, "row", row) else raw(string.format("  %-16s ", e.name)) end
    -- installByName resolves deps + verifies hashes + enforces the admin
    -- gate via the threaded session.
    local ok, res = pkg.installByName(e.name, { session = session })
    if ok then
      okCount = okCount + 1
      installedThisRun[#installedThisRun + 1] = e.name
      if progress then progress(e.name, "ok", row) else out("installed") end
      for _, s in ipairs(serviceNamesFor(e.name)) do services[#services + 1] = s end
    else
      failCount = failCount + 1
      if progress then progress(tostring(res), "fail", row) else out("FAILED: " .. tostring(res)) end
    end
  end

  --- Roll back everything this run installed, newest first so a package is
  --- always removed before whatever it depended on (pkg.uninstall refuses to
  --- strand a reverse dependency, and honouring that ordering is what makes
  --- the undo actually complete).
  local function undoAll()
    local undone, failed2 = 0, {}
    for i = #installedThisRun, 1, -1 do
      local n = installedThisRun[i]
      local ok = pkg.uninstall and pkg.uninstall(n, { session = session })
      if ok then undone = undone + 1 else failed2[#failed2 + 1] = n end
    end
    return undone, failed2
  end

  local pending = {}
  for _, e in ipairs(chosen) do pending[#pending + 1] = e end
  local aborted, undone = false, nil

  while #pending > 0 do
    -- Everything we can do with the disk that's in the drive.
    local stillPending = {}
    for _, e in ipairs(pending) do
      if reachableNow(e.name) then installOne(e) else stillPending[#stillPending + 1] = e end
    end
    pending = stillPending
    if #pending == 0 then break end

    -- Name the disk to fetch, and what's still waiting on it.
    local wantDisk, names = nil, {}
    for _, e in ipairs(pending) do
      wantDisk = wantDisk or e.disk
      names[#names + 1] = e.name
    end
    local askText = string.format("Insert disk %s for: %s",
      tostring(wantDisk or "?"), table.concat(names, ", "))

    local choice
    if progress then choice = progress(askText, "swap")
    else
      out("")
      out(askText)
      out("  [Enter] continue   [a] stop, keep what's installed   [u] undo everything")
      raw("> ")
      local line = io.read()
      if line == nil then choice = "abort"
      else
        line = line:gsub("%s+", ""):lower()
        choice = (line == "u" and "undo") or (line == "a" and "abort") or "retry"
      end
    end

    if choice == "undo" then
      local n, failedNames = undoAll()
      undone = n
      if #failedNames > 0 then
        out("Could NOT remove: " .. table.concat(failedNames, ", "))
      end
      aborted = true
      break
    elseif choice == "abort" then
      aborted = true
      break
    end
    -- "retry": loop and re-probe the mounts. If the operator pressed Enter
    -- without actually swapping, nothing becomes reachable and they are
    -- asked again — which is the correct behaviour, not a spin: each pass
    -- blocks on their keypress.
  end

  local summary
  if undone then
    summary = string.format("Undone: %d package(s) removed, nothing kept.", undone)
  elseif aborted then
    summary = string.format("Stopped: %d installed and kept, %d not installed.",
      okCount, #pending)
  else
    summary = string.format("Done: %d installed, %d failed.", okCount, failCount)
  end
  if not undone and #services > 0 then
    summary = summary .. "  Start service(s): " .. table.concat(services, ", ")
  end
  if progress then
    progress(summary, "done")
    releaseScreen()   -- the progress screen drew raw too
  else
    out(""); out(summary)
    if #services > 0 then
      out("Service packages installed DISABLED. They register on the next reboot;")
      out("then enable (and persist) one with:")
      for _, s in ipairs(services) do out("  service start " .. s) end
    end
  end
end

return M
