-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the installer asks WHICH drive, and bootstrap ║
-- ║  answers --help                                                 ║
-- ║                                                                ║
-- ║  install.lua wrote to "/" and nothing else: the drive OpenOS   ║
-- ║  booted from. That is the wrong drive whenever the machine has ║
-- ║  another one the player means to use, and a dead end when the  ║
-- ║  boot drive is too small, where the only option was to stop.   ║
-- ║  It now lists the writable drives, prices each with the same   ║
-- ║  spaceNeeded() the copy uses, and asks. bootstrap.lua read     ║
-- ║  "-h" and "--help" as a malformed owner/repo and carried on.   ║
-- ║                                                                ║
-- ║  The functions are LIFTED from install.lua and bootstrap.lua  ║
-- ║  and run against a fake machine; the real thing is exercised   ║
-- ║  on OpenOS by build/headless-session.py --os openos.           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_target.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readFile(name)
  local f = io.open(name, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return (s:gsub("\r\n", "\n"))
end
local install, bootstrap = readFile("install.lua"), readFile("bootstrap.lua")
test("install.lua and bootstrap.lua readable", install ~= nil and bootstrap ~= nil)
if not (install and bootstrap) then print("*** TESTS FAILED ***"); return false end

-- ── A fake machine ────────────────────────────────────────────────────
local BOOT, TMP = "boot-0000", "tmp-0000"
local out, answers

local function newMachine(drives)
  -- drives: { addr = { label, total, used, ro, mount = path|nil, files = {...} } }
  local order = {}
  for addr in pairs(drives) do order[#order + 1] = addr end
  table.sort(order)
  local m = { drives = drives }
  m.component = {
    list = function(kind)
      local i = 0
      return function() i = i + 1; return order[i] end
    end,
    proxy = function(addr)
      local d = drives[addr]
      if not d then error("no such component") end
      return {
        address = addr,
        isReadOnly = function() return d.ro or false end,
        getLabel = function() return d.label end,
        spaceTotal = function() return d.total end,
        spaceUsed = function() return d.used end,
        exists = function(p) return d.files and d.files[p] ~= nil or false end,
      }
    end,
  }
  m.computer = { getBootAddress = function() return BOOT end, tmpAddress = function() return TMP end }
  -- OpenOS yields (proxy, path); that is the order the real machine uses.
  m.fs = {
    mounts = function()
      local list = {}
      for _, addr in ipairs(order) do
        local d = drives[addr]
        if addr == BOOT then list[#list + 1] = { m.component.proxy(addr), "/" } end
        if d.mount then list[#list + 1] = { m.component.proxy(addr), d.mount } end
      end
      local i = 0
      return function() i = i + 1; if list[i] then return list[i][1], list[i][2] end end
    end,
    exists = function(p) return m.files[p] ~= nil end,
    size = function(p) return m.files[p] end,
  }
  m.files = {}
  return m
end

local MANIFEST = { { path = "/init.lua" }, { path = "/tos/a.lua" }, { path = "/tos/b.lua" } }
local SRC = "/mnt/d15"

local function lift(m)
  local from = install:find("local FILE_COST", 1, true)
  local to = install:find("local function copyFromDisk", 1, true)
  assert(from and to and from < to, "markers moved in install.lua")
  local env = {
    fs = m.fs, component = m.component, computer = m.computer,
    ipairs = ipairs, pairs = pairs, pcall = pcall, type = type, tostring = tostring,
    tonumber = tonumber, string = string, table = table, math = math,
    color = function() end,
    print = function(s) out[#out + 1] = tostring(s or "") end,
    warn = function(s) out[#out + 1] = "WARN " .. tostring(s) end,
    fail = function(s) out[#out + 1] = "FAIL " .. tostring(s) end,
    -- like the real ask(): a blank answer (or none left) is the default
    ask = function(q, _, def)
      out[#out + 1] = "ASK " .. q
      local a = table.remove(answers, 1)
      if a == nil or a == "" then return def end
      return a
    end,
  }
  local chunk = assert(load(install:sub(from, to - 1)
    .. "\nreturn { spaceNeeded = spaceNeeded, rankTargets = rankTargets, classifyArgs = classifyArgs,"
    .. " mountPaths = mountPaths, listTargets = listTargets, chooseTarget = chooseTarget,"
    .. " freeOnTarget = freeOnTarget, describeTarget = describeTarget,"
    .. " chooseConfigTarget = chooseConfigTarget }", "=install-lift", "t", env))
  return chunk()
end

local function text() return table.concat(out, "\n") end
local function fresh() out, answers = {}, {} end

-- manifest sources: 3 files of known size on the install disk
local function stock(m, sizes)
  m.files[SRC .. "/init.lua"], m.files[SRC .. "/tos/a.lua"], m.files[SRC .. "/tos/b.lua"] = 1000, 40000, 60000
end
-- 3 files = 101000 bytes + 3*512 + dirs (/tos) 512 = 103,... ; compute through the real function:
local function needOf(L, m, root) return L.spaceNeeded(SRC, MANIFEST, m.fs.size, m.fs.exists, root) end

print("=== rankTargets: which drive is the default, and which fit ===")
do
  local m = newMachine({}); fresh(); local L = lift(m)
  local d, f = L.rankTargets({ { isBoot = true, free = 500, need = 100 } })
  test("a lone drive with room is the default", d == 1 and f[1] == true)
  d, f = L.rankTargets({ { isBoot = true, free = 50, need = 100 }, { isBoot = false, free = 500, need = 100 } })
  test("a boot drive that is too small is not the default; the next that fits is", d == 2 and f[1] == false and f[2] == true)
  d = L.rankTargets({ { isBoot = false, free = 900, need = 100 }, { isBoot = true, free = 150, need = 100 } })
  test("the boot drive stays the default when it fits, even beside a bigger one", d == 2)
  d = L.rankTargets({ { isBoot = true, free = 50, need = 100 }, { isBoot = false, free = 60, need = 100 } })
  test("no drive fits: no default, rather than a guess", d == nil)
  d, f = L.rankTargets({ { isBoot = true, free = nil, need = 100 } })
  test("an unknown size is let through, as freeOnTarget returning nil already is", d == 1 and f[1] == true)
end

print("=== classifyArgs: --help is help, not a path or a repo ===")
do
  local m = newMachine({}); local L = lift(m)
  for _, flag in ipairs({ "-h", "--help", "-?", "/?" }) do
    test("install.lua reads " .. flag .. " as a help request", L.classifyArgs({ flag }).help == true)
  end
  local r = L.classifyArgs({ "--wat" })
  test("an unknown option is reported, not taken as a directory", r.unknown == "--wat" and #r.positional == 0)
  r = L.classifyArgs({ "/tmp/tos-netinstall" })
  test("a source directory is still positional", r.positional[1] == "/tmp/tos-netinstall" and not r.help and not r.unknown)

  -- bootstrap.lua carries its own copy; both must agree, and keep an empty
  -- subdir ("") in position since `bootstrap.lua o/r main ""` is meaningful.
  local from = bootstrap:find("local function classifyArgs", 1, true)
  local _, to = bootstrap:find("--[[/TEST-EXTRACT]]", from, true)
  test("classifyArgs can be lifted out of bootstrap.lua", from ~= nil and to ~= nil)
  local B = assert(load(bootstrap:sub(from, to) .. "\nreturn classifyArgs", "=bs", "t",
    { ipairs = ipairs, type = type }))()
  test("bootstrap.lua: -h and --help are help", B({ "-h" }).help and B({ "--help" }).help)
  test("bootstrap.lua: an unknown option is not a repository", B({ "--x" }).unknown == "--x")
  r = B({ "o/r", "main", "" })
  test("bootstrap.lua: o/r main \"\" keeps all three in order", #r.positional == 3 and r.positional[3] == "")
  test("bootstrap.lua: --help wins even beside a repo", B({ "o/r", "--help" }).help == true)
  local a, b = B({ "--help", "--x" }), L.classifyArgs({ "--help", "--x" })
  test("both scripts classify the same way", a.help == b.help and a.unknown == b.unknown)
end

print("=== spaceNeeded prices any drive, not just the boot drive ===")
do
  local m = newMachine({}); stock(m); local L = lift(m)
  local base = needOf(L, m, nil)
  test("no root and root \"\" are the same arithmetic as before", base == needOf(L, m, "") and base > 101000)
  m.files["/mnt/e7a/tos/a.lua"] = 40000   -- already on the target: only growth counts
  test("a file already on THAT drive is not charged again", needOf(L, m, "/mnt/e7a") < base)
  m.files["/tos/a.lua"] = 1               -- on the boot drive: irrelevant to the other drive
  test("files on the boot drive do not change another drive's price",
    needOf(L, m, "/mnt/e7a") == base - 40000 - 0 or needOf(L, m, "/mnt/e7a") < base)
end

print("=== mountPaths reads OpenOS's (proxy, path) order ===")
do
  local m = newMachine({ [BOOT] = { total = 4e6, used = 1e6 }, ["e7a0"] = { total = 2e6, used = 0, mount = "/mnt/e7a" } })
  local L = lift(m)
  local p = L.mountPaths()
  test("the boot drive is found at /", p[BOOT] and p[BOOT][1] == "/")
  test("another drive is found at its mount point", p["e7a0"] and p["e7a0"][1] == "/mnt/e7a")
  -- the old scan read (path, proxy); a table where a string was expected must not be trusted
  m.fs.mounts = function()
    local done = false
    return function() if done then return nil end done = true; return "/mnt/zzz", m.component.proxy("e7a0") end
  end
  test("the reverse order is tolerated too", L.mountPaths()["e7a0"][1] == "/mnt/zzz")
end

print("=== listTargets: only drives TOS could go on ===")
do
  local drives = {
    [BOOT] = { label = "OpenOS", total = 4e6, used = 1e6, files = { ["/init.lua"] = true } },
    [TMP] = { label = "tmpfs", total = 6e5, used = 0, mount = "/tmp" },
    ["rom0"] = { label = "rom", total = 1e5, used = 1e5, ro = true, mount = "/mnt/rom" },
    ["d15x"] = { label = "install", total = 2e6, used = 1.5e6, mount = SRC },
    ["e7a0"] = { label = "store", total = 2e6, used = 0, mount = "/mnt/e7a" },
    ["gone"] = { label = "unmounted", total = 2e6, used = 0 },
  }
  local m = newMachine(drives); stock(m); fresh(); local L = lift(m)
  local cands, unmounted = L.listTargets(SRC, MANIFEST)
  local seen = {}
  for _, c in ipairs(cands) do seen[c.address] = c end
  test("the boot drive is listed first, at the root", cands[1] and cands[1].address == BOOT and cands[1].prefix == "" and cands[1].isBoot)
  test("a second writable drive is listed at its mount point", seen["e7a0"] and seen["e7a0"].prefix == "/mnt/e7a")
  test("the scratch tmpfs is not offered", seen[TMP] == nil)
  test("a read-only drive is not offered", seen["rom0"] == nil)
  test("the install disk is not offered as its own target", seen["d15x"] == nil)
  test("a drive that is not mounted is counted, not offered", seen["gone"] == nil and unmounted == 1)
  test("each drive is priced for itself", seen["e7a0"].need > 0 and seen[BOOT].need > 0)
  test("free space and what is already there are read", seen[BOOT].free == 3e6 and seen[BOOT].hasInit == true and seen["e7a0"].hasInit == false)
  test("describeTarget names the drive and its label", L.describeTarget(seen["e7a0"]):find('/mnt/e7a', 1, true) and L.describeTarget(seen["e7a0"]):find('"store"', 1, true))
end

print("=== chooseTarget: asks only when there is something to choose ===")
local function world(bootFree, secondFree, third)
  local drives = {
    [BOOT] = { label = "OpenOS", total = 4e6, used = 4e6 - bootFree, files = { ["/init.lua"] = true } },
    ["e7a0"] = { label = "store", total = 4e6, used = 4e6 - secondFree, mount = "/mnt/e7a" },
    ["d15x"] = { label = "install", total = 2e6, used = 1.5e6, mount = SRC },
  }
  if third then drives["f00d"] = { label = "tiny", total = 5e4, used = 0, mount = "/mnt/f00" } end
  local m = newMachine(drives); stock(m); fresh()
  return m, lift(m)
end
do
  -- one writable drive that fits: exactly the old behaviour, no question
  local m = newMachine({ [BOOT] = { label = "OpenOS", total = 4e6, used = 1e6 }, ["d15x"] = { total = 2e6, used = 1.5e6, mount = SRC } })
  stock(m); fresh(); local L = lift(m)
  local c = L.chooseTarget(SRC, MANIFEST)
  test("one drive that fits: chosen silently as the boot drive", c and c.isBoot and c.prefix == "" and #out == 0)

  m, L = world(3e6, 3e6)
  answers = { "" }
  c = L.chooseTarget(SRC, MANIFEST)
  test("two drives: the question is asked", text():find("Where should TOS go", 1, true) ~= nil)
  test("pressing Enter takes the boot drive", c and c.isBoot)

  m, L = world(3e6, 3e6); answers = { "2" }
  c = L.chooseTarget(SRC, MANIFEST)
  test("choosing 2 installs on the other drive", c and not c.isBoot and c.prefix == "/mnt/e7a" and c.address == "e7a0")

  m, L = world(3e6, 3e6); answers = { "0" }
  test("0 cancels", L.chooseTarget(SRC, MANIFEST) == nil)

  m, L = world(3e6, 3e6); answers = { "x", "9", "1" }
  c = L.chooseTarget(SRC, MANIFEST)
  test("junk and out-of-range answers are asked again", c and c.isBoot and text():find("Type a number", 1, true) ~= nil)

  -- the case that used to be a dead end: the boot drive is too small
  m, L = world(5e4, 3e6); answers = { "" }
  c = L.chooseTarget(SRC, MANIFEST)
  test("boot drive too small: the OTHER drive is the default", c and c.prefix == "/mnt/e7a")
  test("...and the player is told why, not just offered it", text():find("boot drive has", 1, true) ~= nil)

  m, L = world(5e4, 3e6, true); answers = { "3", "" }
  c = L.chooseTarget(SRC, MANIFEST)
  test("a drive that is too small is refused with its price, then asked again",
    c and c.prefix == "/mnt/e7a" and text():find("too small: needs", 1, true) ~= nil)

  m, L = world(5e4, 5e4); answers = {}
  test("no drive has room: nothing is offered and the player is told", L.chooseTarget(SRC, MANIFEST) == nil
    and text():find("None of these drives has room", 1, true) ~= nil)
end

print("=== configuration mode finds the TOS to configure ===")
do
  -- No install disk: only drives that already hold TOS are offered. It
  -- was the boot drive, always, so a TOS on a second drive could not be
  -- reconfigured from OpenOS.
  local TOS = { ["/init.lua"] = true, ["/tos/kernel/init.lua"] = true }
  local function cfgWorld(bootHasTos, secondHasTos)
    local m = newMachine({
      [BOOT] = { label = "OpenOS", total = 4e6, used = 1e6,
                 files = bootHasTos and TOS or { ["/init.lua"] = true } },
      ["e7a0"] = { label = "store", total = 2e6, used = 1.4e6, mount = "/mnt/e7a",
                   files = secondHasTos and TOS or nil },
    })
    fresh()
    return lift(m)
  end
  local L = cfgWorld(false, true)
  local c = L.chooseConfigTarget()
  test("TOS on the second drive only: that drive is configured, nothing asked",
    c and c.prefix == "/mnt/e7a" and not c.isBoot and not text():find("ASK", 1, true))
  L = cfgWorld(true, false)
  c = L.chooseConfigTarget()
  test("TOS on the boot drive only: the boot drive, as before", c and c.isBoot and c.prefix == "")
  L = cfgWorld(true, true); answers = { "2" }
  c = L.chooseConfigTarget()
  test("TOS on both: the player is asked, and 2 is the second drive",
    c and c.prefix == "/mnt/e7a" and text():find("Which TOS should be configured", 1, true) ~= nil)
  L = cfgWorld(true, true); answers = { "0" }
  test("...and 0 cancels", L.chooseConfigTarget() == nil)
  L = cfgWorld(false, false)
  test("no TOS anywhere: nothing is configured, and the player is told",
    L.chooseConfigTarget() == nil and text():find("No drive holds a TOS", 1, true) ~= nil)
  local a = L.classifyArgs({ "--configure" })
  test("--configure is an option, not an unknown one", a.configure == true and a.unknown == nil)
  test("...and it skips the install-disk search",
    install:find("(not parsed.configure) and findInstallDisk(", 1, true) ~= nil)
  test("the configuration branch uses it, not the boot drive",
    install:find("targetDrive = chooseConfigTarget()", 1, true) ~= nil
    and not install:find("must already be present on the boot drive", 1, true))
end

print("=== OpenOS leftovers and the old /init.lua are handled on the CHOSEN drive ===")
do
  local from = install:find("local OPENOS_ONLY_TREES", 1, true)
  local to = select(2, install:find("\n  return removed\nend\n", from, true))
  local files = {
    ["/init.lua"] = "boot drive loader", ["/lib/core.lua"] = "x",
    ["/mnt/e7a/init.lua"] = "OpenOS loader on the second drive", ["/mnt/e7a/lib/core.lua"] = "y", ["/mnt/e7a/bin/ls.lua"] = "z",
  }
  local function under(p, d) return p:sub(1, #d + 1) == d .. "/" end
  local F = {
    exists = function(p) if files[p] then return true end for k in pairs(files) do if under(k, p) then return true end end return false end,
    remove = function(p) files[p] = nil for k in pairs(files) do if under(k, p) then files[k] = nil end end return true end,
  }
  local io_ = { open = function(p, mode)
    if mode == "r" then local d = files[p]; if not d then return nil end return { read = function() return d end, close = function() end } end
    local buf = {}
    return { write = function(_, s) buf[#buf + 1] = s end, close = function() files[p] = table.concat(buf) end }
  end }
  local env = { fs = F, io = io_, pcall = pcall, ipairs = ipairs }
  local fns = assert(load(install:sub(from, to) .. "\nreturn preserveForeignInit, hasOpenOsLeftovers, cleanOpenOsLeftovers, PRE_TOS",
    "=lift2", "t", env))
  local preserve, has, clean, PRE = fns()
  test("the second drive's loader is kept there", preserve("/mnt/e7a") == true and files["/mnt/e7a" .. PRE] == "OpenOS loader on the second drive")
  test("...and the boot drive's loader is not touched", files["/init.lua"] == "boot drive loader" and files[PRE] == nil)
  test("leftovers are looked for on the chosen drive", has("/mnt/e7a") == true)
  local removed = clean("/mnt/e7a")
  test("cleaning removes the chosen drive's /bin and /lib", files["/mnt/e7a/lib/core.lua"] == nil and files["/mnt/e7a/bin/ls.lua"] == nil and #removed >= 2)
  test("...and leaves the boot drive's /lib alone", files["/lib/core.lua"] == "x")
end

print()
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then print("*** TESTS FAILED ***"); return false end
print("All tests passed.")
return true
