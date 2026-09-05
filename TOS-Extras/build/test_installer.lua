-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: the Optional Utilities picker (install.lua)           ║
-- ║                                                              ║
-- ║  Drives the REAL installer script with stubbed kernel deps   ║
-- ║  and a scripted keyboard, so the parts that used to only be  ║
-- ║  checked by eye are pinned:                                  ║
-- ║    • the pick-list is GROUPED BY CATEGORY (header rows drawn ║
-- ║      per bucket, in the preferred order);                    ║
-- ║    • arrow navigation SKIPS the header rows (you can't rest  ║
-- ║      a selection on a category label);                       ║
-- ║    • Space selects and Enter installs exactly the chosen     ║
-- ║      package, via the pkg backend.                           ║
-- ║                                                              ║
-- ║  install.lua only require()s at RUN time, so stubbing the    ║
-- ║  deps in package.loaded first lets it run headless here.     ║
-- ║  It is byte-identical to kernel/pkg.lua's PICKER_SRC          ║
-- ║  (test_picker_sync), so this covers that copy too.           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua build/test_installer.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- ── A fake GPU that records every set() so we can inspect the screen ──
local drawn = {}          -- array of { x, y, text }
local function fakeGpu()
  return {
    getResolution = function() return 80, 25 end,
    getDepth      = function() return 4 end,
    setForeground = function() end,
    setBackground = function() end,
    fill          = function() end,
    set           = function(x, y, s) drawn[#drawn + 1] = { x = x, y = y, text = s } end,
  }
end

-- ── A scripted keyboard: each pullSignal() pops the next event ──
local keyq = {}   -- reassigned per multi-disk case (see below)
local function key_code(code) keyq[#keyq + 1] = { "key_down", "kb", 0, code } end
local function key_char(ch)   keyq[#keyq + 1] = { "key_down", "kb", ch, 0 } end

package.loaded["component"] = {
  list = function(t)
    local a = (t == "gpu") and { "gpu-1" } or {}
    local i = 0
    return function() i = i + 1; return a[i] end
  end,
  proxy = function() return fakeGpu() end,
}
package.loaded["computer"] = {
  pullSignal = function()
    local e = table.remove(keyq, 1)
    if not e then error("TEST: key queue underflow (picker never exited)", 0) end
    -- A queued event may carry a side effect to run when it is delivered —
    -- that's how the multi-disk cases below simulate the operator actually
    -- swapping the floppy at the moment they answer the swap prompt.
    if e.onPop then e.onPop() end
    return e[1], e[2], e[3], e[4]
  end,
}
package.loaded["unicode"] = nil    -- exercise the byte-fallback path
package.loaded["kernel.display"] = { getTheme = function() return {} end }

-- ── A stub pkg backend with a MULTI-CATEGORY available set ──
local installedNames = {}
local INSTALL_LOG = {}
package.loaded["kernel.pkg"] = {
  installByName = function(name)
    INSTALL_LOG[#INSTALL_LOG + 1] = name
    installedNames[name] = true
    return true, { installed = { name }, skipped = {} }
  end,
  info = function(name) return installedNames[name] and { name = name } or nil end,
  listAllAvailable = function()
    -- Intentionally out of both category- and name-order, and with the
    -- installed one present, so the picker's own sort + grouping is what's
    -- under test (not the caller's ordering).
    -- `root` mimics listAllAvailable's provenance field (the set spans two
    -- floppies now). `requires`/`recommends` exercise the dependency
    -- auto-select and the reverse-recommendation index; `drive` requires
    -- blockfs, and both string and table require forms appear because
    -- manifests carry both depending on where they were normalized.
    return {
      { name = "mail",   version = "1.0.0", category = "network",      description = "mesh email",
        root = "/mnt/disk1", recommends = { "mouse" } },
      { name = "ttt",    version = "1.0.0", category = "games",        description = "tic-tac-toe",
        root = "/mnt/disk2", recommends = { "mouse" } },
      { name = "calc",   version = "1.0.0", category = "productivity", description = "spreadsheet",
        root = "/mnt/disk1", recommends = { "mouse" } },
      { name = "snake",  version = "1.0.0", category = "games",        description = "snake",
        root = "/mnt/disk2" },
      { name = "mouse",  version = "1.0.0", category = "drivers",      description = "mouse driver",
        root = "/mnt/disk2" },
      { name = "blockfs",version = "1.0.0", category = "storage",      description = "tbfs",
        root = "/mnt/disk1" },
      { name = "drive",  version = "1.0.0", category = "storage",      description = "raw drive tool",
        root = "/mnt/disk1", requires = { { name = "blockfs" } } },
      { name = "orphan", version = "1.0.0", category = "misc",         description = "wants a missing dep",
        root = "/mnt/disk1", requires = { "nosuchpkg >= 1.0" } },
    }
  end,
}
package.loaded["kernel.users"] = {
  currentSession = function() return { user = "root", tier = 2 } end,
  TIER = { ADMIN = 2 },
}

-- ── Script the run: move down past a header, select, install ──
-- The list is grouped GAMES(snake, ttt) · PRODUCTIVITY(calc) · NETWORK
-- (mail) · STORAGE(blockfs) · DRIVERS(mouse). Selection starts on the
-- first package (snake). Down 3 crosses at least one category header
-- (proving header-skip); then Space selects, Enter installs, and the
-- "done" screen waits for one more key.
key_code(208)   -- Down
key_code(208)   -- Down
key_code(208)   -- Down
key_char(32)    -- Space: toggle whatever we landed on
key_code(28)    -- Enter: install
key_char(32)    -- dismiss the "Press any key" done screen

print("=== Optional Utilities picker Tests ===")
print()

-- ── Run the real installer ──
-- The picker is a BASE-IMAGE module now (it used to be a copy on every
-- floppy plus a 40 KB string inside kernel/pkg.lua). Load it and call run()
-- exactly as pkg.runInstaller does.
local picker
for _, p in ipairs({ "../TOS-Dev/tos/shell/pkgpicker.lua", "../tos/shell/pkgpicker.lua",
    "TOS-Dev/tos/shell/pkgpicker.lua", "tos/shell/pkgpicker.lua" }) do
  local c = loadfile(p); if c then picker = c(); break end
end
local chunk = picker and picker.run
test("shell/pkgpicker.lua loads", chunk ~= nil)
if not chunk then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

local ok, err = pcall(chunk)
test("the picker ran to completion without error", ok)
if not ok then print("        " .. tostring(err)) end

-- ── Category headers were drawn, in the preferred order ──
local function drewText(sub)
  for _, d in ipairs(drawn) do
    if type(d.text) == "string" and d.text:find(sub, 1, true) then return d end
  end
end
test("a GAMES header was drawn", drewText("Games") ~= nil)
test("a NETWORK header was drawn", drewText("Network") ~= nil)
test("a PRODUCTIVITY header was drawn", drewText("Productivity") ~= nil)
test("a STORAGE header was drawn", drewText("Storage") ~= nil)
test("a DRIVERS header was drawn", drewText("Drivers") ~= nil)

-- The preferred order (games before productivity before network …) is the
-- order the headers were first drawn on the initial paint.
do
  local order = {}
  local seen = {}
  for _, d in ipairs(drawn) do
    for _, cat in ipairs({ "Games", "Productivity", "Network", "Storage", "Drivers" }) do
      if not seen[cat] and type(d.text) == "string" and d.text == cat then
        seen[cat] = true; order[#order + 1] = cat
      end
    end
  end
  local expected = { "Games", "Productivity", "Network", "Storage", "Drivers" }
  local inOrder = (#order == #expected)
  for i = 1, #expected do if order[i] ~= expected[i] then inOrder = false end end
  test("headers appear in the preferred category order"
    .. "  [" .. table.concat(order, " ") .. "]", inOrder)
end

-- ── Navigation skipped headers + exactly one package installed ──
eq("exactly one package was installed", 1, #INSTALL_LOG)
-- Down×3 from snake, skipping the "Productivity"/"Network"/… header rows,
-- lands on a real package (never a category label). We don't over-pin
-- WHICH one — the guarantee under test is that it's a package at all.
do
  local names = { snake=true, ttt=true, calc=true, mail=true, blockfs=true, mouse=true }
  test("the installed target is a real package, not a header ("
    .. tostring(INSTALL_LOG[1]) .. ")", names[INSTALL_LOG[1]] == true)
end

-- ── Rail labels must sit EXACTLY on the rail's own copy ──────────────
-- Visual grammar rule 2 draws a dim rail that already CONTAINS the label
-- ("──┤ 6 add-ons ├──", "── Games ─────"), then re-draws that label
-- brighter on top. If the bright copy lands one column off, the rail's
-- copy pokes out past the end and the last character reads twice — the
-- operator saw "13 add-onss", "9 selectedd", "Gamess", "Productivityy".
-- Both copies are drawn to the same row, so the check is exact: the
-- label's x must equal the rail's x plus the label's CHARACTER offset
-- inside the rail text (character, not byte — the rails are box-drawing
-- glyphs, 3 bytes each in UTF-8).
do
  local function ulen(s)
    local n = 0
    for i = 1, #s do
      local b = s:byte(i)
      if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
  end
  local function ucharIndex(hay, needle)
    local b = hay:find(needle, 1, true)
    if not b then return nil end
    return ulen(hay:sub(1, b - 1)) + 1
  end

  -- A rail is the full-width dim string the frame draws first; it always
  -- starts at column 1 with the horizontal glyph. Only those count — a
  -- package name that happens to occur inside its own description is not
  -- a label-over-rail pair.
  local DASH = "\226\148\128"                        -- U+2500 ─
  local function isRail(s) return s:sub(1, #DASH) == DASH or s:sub(1, 1) == "-" end

  local checked, misaligned = 0, {}
  for i, d in ipairs(drawn) do
    if type(d.text) == "string" and #d.text > 0 and d.text:match("^[%w][%w%s%-]*$") then
      -- Walk backwards for the rail this label is painted over.
      for j = i - 1, 1, -1 do
        local r = drawn[j]
        if type(r.text) == "string" and r.y == d.y and r.x == 1 and isRail(r.text)
           and ulen(r.text) > ulen(d.text) and r.text:find(d.text, 1, true) then
          checked = checked + 1
          local want = r.x + ucharIndex(r.text, d.text) - 1
          if d.x ~= want then
            misaligned[#misaligned + 1] = string.format(
              "%q at x=%d, rail wants x=%d (row %d)", d.text, d.x, want, d.y)
          end
          break
        end
      end
    end
  end
  test("some rail labels were actually inspected (" .. checked .. ")", checked > 0)
  test("every rail label sits exactly on the rail's own copy", #misaligned == 0)
  for _, m in ipairs(misaligned) do print("        " .. m) end
end

-- ── The detail panel (two-pane layout at 80 columns) ────────────────
-- The list is on the left and a real panel on the right. These check the
-- panel actually carries the things the operator needs to decide with —
-- especially WHICH DISK a package is on, which the picker used to know
-- (listAllAvailable records it) and never show.
do
  local function drewExact(s)
    for _, d in ipairs(drawn) do if d.text == s then return d end end
  end
  test("the panel labels a Status field", drewExact("Status    ") ~= nil
    or drewText("Status") ~= nil)
  test("the panel labels where the package came FROM", drewText("From") ~= nil)
  -- The provenance value itself, not just the label.
  test("a source disk is shown", drewText("/mnt/disk") ~= nil)
  test("the legend explains the [+] dependency mark",
    drewText("needed by one") ~= nil)
  test("the key bar offers the suggestions key", drewText("+Suggested") ~= nil)
end

-- ── A second run: dependency auto-select + reverse recommendations ──
-- Re-running the whole picker with a fresh script is the only way to drive
-- a different selection, since the script runs top-to-bottom.
do
  drawn = {}
  INSTALL_LOG = {}
  installedNames = {}
  -- Rebind the log the stub closes over.
  package.loaded["kernel.pkg"].installByName = function(name)
    INSTALL_LOG[#INSTALL_LOG + 1] = name
    installedNames[name] = true
    return true, { installed = { name }, skipped = {} }
  end

  -- Down moves package-to-package (headers are skipped), so from snake the
  -- package order is: snake(0) ttt(1) calc(2) mail(3) blockfs(4) drive(5)
  -- mouse(6) orphan(7). Five downs lands exactly on `drive`.
  for _ = 1, 5 do key_code(208) end
  key_char(32)     -- Space: select drive (blockfs should follow)
  key_code(208)    -- Down to mouse, so the panel draws ITS detail too
  key_code(28)     -- Enter: install
  key_char(32)     -- dismiss "Press any key"

  local ok2 = pcall(chunk)
  test("second run completed", ok2)

  local log = table.concat(INSTALL_LOG, ",")
  test("the selected package was installed (" .. log .. ")",
    log:find("drive", 1, true) ~= nil)
  -- THE behaviour under test: a dependency the operator never ticked comes
  -- along, and is counted, rather than surfacing as a surprise in the log.
  test("its blockfs dependency was pulled in automatically",
    log:find("blockfs", 1, true) ~= nil)
  eq("exactly the pick plus its dependency", 2, #INSTALL_LOG)

  -- The panel, while resting on `drive`, must say what it needs.
  local sawNeeds, sawWanted, sawMissing = false, false, false
  for _, d in ipairs(drawn) do
    if type(d.text) == "string" then
      if d.text:find("Needs", 1, true) then sawNeeds = true end
      -- ...and while resting on `mouse`, who wants it. mouse is recommended
      -- by mail, ttt AND calc — none of which is what we're installing,
      -- which is exactly the case the operator asked to be shown.
      if d.text:find("Wanted by", 1, true) then sawWanted = true end
      if d.text:find("blockfs", 1, true) then sawMissing = true end
    end
  end
  test("the panel names what a package Needs", sawNeeds)
  test("the panel names who else Wants a package", sawWanted)
  test("the dependency is named by name in the panel", sawMissing)
end

-- ── An unsatisfiable dependency is reported, not silently failed ────
do
  drawn = {}
  INSTALL_LOG = {}
  installedNames = {}
  package.loaded["kernel.pkg"].installByName = function(name)
    INSTALL_LOG[#INSTALL_LOG + 1] = name
    installedNames[name] = true
    return true, { installed = { name }, skipped = {} }
  end
  -- `orphan` requires "nosuchpkg", which is on no inserted disk. Seven
  -- downs from snake lands on it (it is last, in the Other bucket).
  for _ = 1, 7 do key_code(208) end
  key_code(1)      -- Esc: quit without installing; we only want the panel
  local ok3 = pcall(chunk)
  test("third run completed", ok3)
  eq("quitting installed nothing", 0, #INSTALL_LOG)
  local sawWarning = false
  for _, d in ipairs(drawn) do
    if type(d.text) == "string"
       and d.text:find("not on any inserted disk", 1, true) then sawWarning = true end
  end
  -- A dependency sitting on the OTHER floppy is the common case in a
  -- two-disk set, and saying so beats letting the install fail.
  test("an unsatisfiable dependency is called out in the panel", sawWarning)
end

-- ══════════════════════════════════════════════════════════════════
-- Multi-disk: the set spans two floppies and only one is inserted
-- ══════════════════════════════════════════════════════════════════
-- The picker reads the builder's set manifest, so it lists packages that
-- live on a disk which ISN'T in the drive, lets you pick them anyway,
-- installs what it can, and then asks for the other disk — with abort and
-- undo.
--
-- Each case gets a COMPLETELY FRESH backend from this helper. The earlier
-- cases in this file share module-level stubs, and mutating one of them
-- per-case let state leak across runs (a stale `listAllAvailable` made a
-- package look reachable when the case meant it to be on the other disk,
-- so the swap prompt never fired and the case silently tested nothing).
-- Building the whole backend per case removes that class of bug.

local SET_SRC = [[return {
  set = "optional-utilities",
  disks = 2,
  packages = {
    ["snake"] = { disk = 1, version = "1.0.0", category = "games", kind = "command",
      description = "snake", requires = { }, recommends = { } },
    ["tetris"] = { disk = 2, version = "1.0.0", category = "games", kind = "command",
      description = "tetris", requires = { }, recommends = { } },
  },
}]]

local SNAKE  = { name = "snake",  version = "1.0.0", category = "games",
                 description = "snake",  root = "/mnt/disk1" }
local TETRIS = { name = "tetris", version = "1.0.0", category = "games",
                 description = "tetris", root = "/mnt/disk2" }

--- Fresh backend. `env.swapped` flips when the operator "inserts disk 2".
local function newEnv()
  local env = { installs = {}, uninstalls = {}, installed = {}, swapped = false }
  package.loaded["kernel.fs"] = {
    list     = function(p) if p == "/mnt" then return { "disk1" } end return {} end,
    exists   = function(p) return p == "/mnt/disk1/optutil-set.lua" end,
    readFile = function(p)
      if p == "/mnt/disk1/optutil-set.lua" then return SET_SRC end
    end,
    -- The authoritative mount table. On a live machine boot-time mounts
    -- appear ONLY here — listing the mount directory finds nothing,
    -- because fs.mount() creates no directory. That is the bug this
    -- mock now reproduces rather than papers over; see
    -- test_pkg_repo_roots.lua.
    mounts   = function() return { { mountPoint = "/" }, { mountPoint = "/mnt/disk1" } } end,
  }
  package.loaded["kernel.pkg"] = {
    installByName = function(name)
      env.installs[#env.installs + 1] = name
      env.installed[name] = true
      return true, { installed = { name } }
    end,
    uninstall = function(name)
      env.uninstalls[#env.uninstalls + 1] = name
      env.installed[name] = nil
      return true
    end,
    info = function(name) return env.installed[name] and { name = name } or nil end,
    listAllAvailable = function()
      if env.swapped then return { SNAKE, TETRIS } end
      return { SNAKE }
    end,
    -- The picker asks kernel.pkg where packages can be, rather than
    -- enumerating mounts itself — it used to have its own copy, and that
    -- copy could not see boot-time mounts, so a two-floppy set looked
    -- like a one-floppy set on a real machine. Mirrors the real
    -- pkg.repoRoots: mount table first, then any real /mnt entries.
    repoRoots = function()
      local fsMod = package.loaded["kernel.fs"]
      local roots, seen = { "/usr/repo", "/var/repo" }, {}
      for _, r in ipairs(roots) do seen[r] = true end
      for _, m in ipairs(fsMod.mounts()) do
        if m.mountPoint ~= "/" and not seen[m.mountPoint] then
          seen[m.mountPoint] = true
          roots[#roots + 1] = m.mountPoint
        end
      end
      return roots
    end,
  }
  return env
end

-- The real serializer, so the set manifest is parsed exactly as TOS parses it.
do
  local ser
  for _, p in ipairs({ "../TOS-Dev/tos/kernel/serialize.lua", "../tos/kernel/serialize.lua",
      "TOS-Dev/tos/kernel/serialize.lua" }) do
    local c = loadfile(p); if c then ser = c(); break end
  end
  test("serializer loaded for the set manifest", ser ~= nil)
  package.loaded["kernel.serialize"] = ser
end

-- ── Case 1: swap the disk and finish the job ──
do
  local env = newEnv()
  drawn = {}
  keyq = {}
  package.loaded["computer"] = {
    pullSignal = function()
      local e = table.remove(keyq, 1)
      if not e then error("TEST: key queue underflow", 0) end
      if e.onPop then e.onPop() end
      return e[1], e[2], e[3], e[4]
    end,
  }
  key_char(97)     -- A: select everything, including the off-disk package
  key_code(28)     -- Enter: install
  -- The swap prompt reads a key directly. `onPop` fires as that keypress is
  -- delivered — exactly when the operator would have swapped the floppy.
  keyq[#keyq + 1] = { "key_down", "kb", 0, 28,
    onPop = function() env.swapped = true end }
  key_char(32)     -- dismiss the done screen

  local okM, merr = pcall(chunk)
  test("multi-disk run completed", okM)
  if not okM then print("        " .. tostring(merr)) end
  local log = table.concat(env.installs, ",")
  test("the reachable package installed first (" .. log .. ")",
    log:find("snake", 1, true) ~= nil)
  -- THE point of the feature: the second disk's package installs after the
  -- swap, in the same run, without starting over.
  test("the other disk's package installed after the swap",
    log:find("tetris", 1, true) ~= nil)
  eq("nothing was rolled back", 0, #env.uninstalls)

  local listed = false
  for _, d in ipairs(drawn) do
    if type(d.text) == "string" and d.text:find("tetris", 1, true) then listed = true end
  end
  -- With one floppy in the drive the operator can still SEE and choose the
  -- other floppy's contents — that is what the set manifest buys.
  test("a package on an un-inserted disk was still listed", listed)
end

-- ── Case 2: abort — stop, but keep what already installed ──
do
  local env = newEnv()
  drawn = {}
  keyq = {}
  key_char(97)     -- A: select all
  key_code(28)     -- Enter: install
  key_char(97)     -- swap prompt: 'a' = stop, keep what's installed
  key_char(32)     -- dismiss done

  local okA = pcall(chunk)
  test("abort run completed", okA)
  test("what was reachable stayed installed",
    table.concat(env.installs, ","):find("snake", 1, true) ~= nil)
  eq("abort removed nothing", 0, #env.uninstalls)
  eq("...and the installed package is still installed", true, env.installed.snake)
  eq("the off-disk package was NOT installed", nil, env.installed.tetris)
end

-- ── Case 3: undo — roll the whole run back ──
do
  local env = newEnv()
  drawn = {}
  keyq = {}
  key_char(97)     -- A: select all
  key_code(28)     -- Enter: install
  key_char(117)    -- swap prompt: 'u' = undo everything
  key_char(32)     -- dismiss done

  local okU = pcall(chunk)
  test("undo run completed", okU)
  test("the package that HAD installed was removed again",
    table.concat(env.uninstalls, ","):find("snake", 1, true) ~= nil)
  eq("undo left nothing installed", nil, env.installed.snake)
  eq("exactly what was installed got removed", #env.installs, #env.uninstalls)
end

-- ══════════════════════════════════════════════════════════════════
-- Group selection (G) and filtering (/)
-- ══════════════════════════════════════════════════════════════════
-- Both act on WHAT IS VISIBLE, which is the interaction that makes them
-- worth having together: filter to a category, press A, install it.

local function freshBackend()
  local env = { installs = {}, installed = {} }
  package.loaded["kernel.fs"] = nil
  package.loaded["kernel.pkg"] = {
    installByName = function(name)
      env.installs[#env.installs + 1] = name
      env.installed[name] = true
      return true, { installed = { name } }
    end,
    uninstall = function() return true end,
    info = function(name) return env.installed[name] and { name = name } or nil end,
    listAllAvailable = function()
      return {
        { name = "snake",  version = "1.0.0", category = "games",
          description = "classic snake", root = "/mnt/d1" },
        { name = "tetris", version = "1.0.0", category = "games",
          description = "falling blocks", root = "/mnt/d1" },
        { name = "ttt",    version = "1.0.0", category = "games",
          description = "tic tac toe", root = "/mnt/d1" },
        { name = "mail",   version = "1.0.0", category = "network",
          description = "mesh email", root = "/mnt/d1" },
        { name = "mouse",  version = "1.0.0", category = "drivers",
          description = "pointer driver", root = "/mnt/d1" },
      }
    end,
  }
  return env
end
local function sortedInstalls(env)
  local c = {}
  for _, n in ipairs(env.installs) do c[#c + 1] = n end
  table.sort(c)
  return table.concat(c, ",")
end

-- ── G selects a whole category ──
do
  local env = freshBackend()
  drawn = {}; keyq = {}
  -- Cursor starts on the first package (snake, in Games). G takes the group.
  key_char(103)    -- g
  key_code(28)     -- Enter: install
  key_char(32)     -- dismiss done
  local ok = pcall(chunk)
  test("group-select run completed", ok)
  eq("G selected every package in the category", "snake,tetris,ttt", sortedInstalls(env))
end

-- ── G again clears the group ──
do
  local env = freshBackend()
  drawn = {}; keyq = {}
  key_char(103)    -- g: select Games
  key_char(103)    -- g: and clear it again
  key_code(28)     -- Enter
  key_char(32)
  local ok = pcall(chunk)
  test("second G run completed", ok)
  eq("pressing G twice leaves the group unselected", 0, #env.installs)
end

-- ── G on a different category takes only that one ──
do
  local env = freshBackend()
  drawn = {}; keyq = {}
  -- Games(snake,tetris,ttt) Network(mail) Drivers(mouse): 3 downs -> mail.
  for _ = 1, 3 do key_code(208) end
  key_char(103)    -- g
  key_code(28)
  key_char(32)
  local ok = pcall(chunk)
  test("third run completed", ok)
  eq("G took only the cursor's category", "mail", sortedInstalls(env))
end

-- ── / filters, and A then takes only what matched ──
do
  local env = freshBackend()
  drawn = {}; keyq = {}
  key_char(47)                          -- /
  for _, c in ipairs({ 109, 111, 117 }) do key_char(c) end   -- "mou"
  key_code(28)                          -- Enter: keep the filter
  key_char(97)                          -- A: select all VISIBLE
  key_code(28)                          -- Enter: install
  key_char(32)
  local ok = pcall(chunk)
  test("filter run completed", ok)
  -- The whole point: A under a filter must not also take the nine packages
  -- the operator just filtered away.
  eq("A under a filter takes only the matches", "mouse", sortedInstalls(env))
end

-- ── the filter matches descriptions, not just names ──
do
  local env = freshBackend()
  drawn = {}; keyq = {}
  key_char(47)                          -- /
  for _, c in ipairs({ 98, 108, 111, 99, 107 }) do key_char(c) end  -- "block"
  key_code(28)
  key_char(97)                          -- A
  key_code(28)
  key_char(32)
  local ok = pcall(chunk)
  test("description-filter run completed", ok)
  -- "falling blocks" is tetris's DESCRIPTION; its name contains no "block".
  eq("the filter searches descriptions too", "tetris", sortedInstalls(env))
end

-- ── a filter that matches nothing says so, and Esc clears it ──
do
  local env = freshBackend()
  drawn = {}; keyq = {}
  key_char(47)                          -- /
  for _, c in ipairs({ 122, 122, 122 }) do key_char(c) end   -- "zzz"
  key_code(28)                          -- keep it
  key_code(1)                           -- Esc: clears the FILTER, not the app
  key_char(97)                          -- A: everything is visible again
  key_code(28)                          -- Enter: install
  key_char(32)
  local ok = pcall(chunk)
  test("no-match run completed", ok)
  local said = false
  for _, d in ipairs(drawn) do
    if type(d.text) == "string" and d.text:find("Nothing matches", 1, true) then
      said = true
    end
  end
  test("an empty result explains itself", said)
  -- Esc cleared the filter instead of quitting the installer...
  eq("Esc cleared the filter, and A then took everything",
    "mail,mouse,snake,tetris,ttt", sortedInstalls(env))
end

-- ── the rail shows the filter is on ──
do
  freshBackend()
  drawn = {}; keyq = {}
  key_char(47)
  for _, c in ipairs({ 103, 97, 109 }) do key_char(c) end    -- "gam"
  key_code(28)
  key_char(113)                         -- q: quit without installing
  local ok = pcall(chunk)
  test("rail run completed", ok)
  local shown = false
  for _, d in ipairs(drawn) do
    if type(d.text) == "string" and d.text:find("match 'gam'", 1, true) then
      shown = true
    end
  end
  -- A filter you forgot about looks exactly like a disk missing packages,
  -- so the count rail has to say the list is narrowed.
  test("the rail says how many of how many match", shown)
end

-- ── the key bar advertises both ──
do
  local found = { g = false, slash = false }
  for _, d in ipairs(drawn) do
    if type(d.text) == "string" then
      if d.text:find("G Group", 1, true) then found.g = true end
      if d.text:find("/ Filter", 1, true) then found.slash = true end
    end
  end
  test("the key bar offers G Group", found.g)
  test("the key bar offers / Filter", found.slash)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
