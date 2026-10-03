-- ╔══════════════════════════════════════════════════════════╗
-- ║  Unit Test: kernel.selftest — the in-emulator battery      ║
-- ║                                                            ║
-- ║  The runner is the one part of the self-test machinery      ║
-- ║  that CAN be proven off-box, and it is the part that must   ║
-- ║  not be wrong: if the reporting is broken, an in-emulator   ║
-- ║  round produces a confident answer about nothing.           ║
-- ║                                                            ║
-- ║  Three properties matter most:                              ║
-- ║   1. Gating. No marker, no load — a production boot must    ║
-- ║      never pay for this.                                    ║
-- ║   2. Stall attribution. `RUN <name>` is written and         ║
-- ║      flushed BEFORE the body runs, so a machine that wedges ║
-- ║      leaves a file whose last line names the culprit and    ║
-- ║      has no SELFTEST END.                                    ║
-- ║   3. Isolation. A check may stub package.loaded freely      ║
-- ║      without the next check, or the live shell, inheriting  ║
-- ║      it. In-emulator that runs on a machine you still need. ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_selftest.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1
    print("  PASS: " .. name .. "  (got " .. tostring(actual) .. ")")
  else failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")") end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_selftest.lua"
local base = here:gsub("[^/\\]*$", "")
local function tryload(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
end

local selftest = tryload("tos/kernel/selftest.lua")()

-- ── A RAM filesystem that records appends in order ─────────────────
local function ramFS(seed)
  local files = {}
  for k, v in pairs(seed or {}) do files[k] = v end
  -- `_virtual` models the thing that actually bit us: a path whose
  -- CHILDREN exist while the path itself does not. That is precisely
  -- what a kernel-time mount is -- /mnt/disk_x/foo resolves through the
  -- mount table, and /mnt is not a directory at all. Without this the
  -- fake derives exists("/mnt") from its children, models /mnt as a
  -- real tree, and the regression it was written for cannot fail.
  local F = { _files = files, _virtual = {} }
  function F.exists(p)
    if F._virtual[p] then return false end
    if files[p] ~= nil then return true end
    for k in pairs(files) do
      if k:sub(1, #p + 1) == p .. "/" then return true end
    end
    return false
  end
  function F.isDirectory(p) return files[p] == nil and F.exists(p) end
  function F.readFile(p) return files[p] end
  function F.writeFile(p, d) files[p] = d; return true end
  function F.appendFile(p, d) files[p] = (files[p] or "") .. d; return true end
  -- The authoritative mount list. A kernel-time mount is VIRTUAL: it is
  -- in this table and NOT a real /mnt/<label> directory, which is the
  -- whole point of the regression below.
  F._mounts = {}
  function F.mounts() return F._mounts end
  function F.list(p)
    if F._virtual[p] then return {} end
    local out, seen = {}, {}
    local prefix = (p == "/") and "/" or (p .. "/")
    for k in pairs(files) do
      if k:sub(1, #prefix) == prefix then
        local rest = k:sub(#prefix + 1)
        local head = rest:match("^([^/]+)")
        if head and not seen[head] then seen[head] = true; out[#out + 1] = head end
      end
    end
    table.sort(out)
    return out
  end
  return F
end

local _uptime = 0
local comp = { uptime = function() return _uptime end,
               freeMemory = function() return 500000 end }

local function lines(fs)
  local out = {}
  for l in (fs._files["/var/selftest.log"] or ""):gmatch("[^\n]+") do out[#out+1] = l end
  return out
end

print("=== kernel.selftest Tests ===")
print()

-- ── 1. Gating ──────────────────────────────────────────────────────
print("-- the marker gate --")
do
  test("no marker -> disabled", not selftest.enabled(ramFS({})))
  test("marker present -> enabled",
    selftest.enabled(ramFS({ ["/etc/selftest.on"] = "" })))

  local cfg = selftest.readMarker(ramFS({ ["/etc/selftest.on"] = "" }))
  test("empty marker parses",      type(cfg) == "table")
  test("...shutdown defaults off", cfg.shutdown == false)
  eq("...only defaults to nil",    nil, cfg.only)

  local cfg2 = selftest.readMarker(ramFS({
    ["/etc/selftest.on"] = "shutdown=true\nonly=20-\n" }))
  test("shutdown=true parses", cfg2.shutdown == true)
  eq("only= parses",           "20-", cfg2.only)

  -- A typo in the marker must not stop the machine booting.
  local cfg3 = selftest.readMarker(ramFS({
    ["/etc/selftest.on"] = "shutdwn = yes\n???\n" }))
  test("a malformed marker still yields a config", type(cfg3) == "table")
  test("...and does not enable shutdown by accident", cfg3.shutdown == false)
end

-- ── 2. Discovery ───────────────────────────────────────────────────
print()
print("-- discovery --")
do
  local fs = ramFS({
    ["/usr/lib/selftest/10-a.lua"] = "",
    ["/usr/lib/selftest/20-b.lua"] = "",
    ["/usr/lib/selftest/notes.txt"] = "",
    ["/mnt/testdisk/selftest/30-c.lua"] = "",
  })
  local found = selftest.discover(fs)
  eq("finds every .lua across roots", 3, #found)
  test("ignores non-lua", not table.concat(found, " "):find("notes.txt", 1, true))
  test("picks up a mounted test disk",
    table.concat(found, " "):find("/mnt/testdisk/selftest/30-c.lua", 1, true) ~= nil)
  -- Deterministic order: a stall has to be reproducible to be diagnosable.
  eq("sorted", true, found[1] < found[2] and found[2] < found[3])
end

-- ── 3. Reporting, including the stall line ─────────────────────────
print()
print("-- reporting --")
do
  -- Check sources live in the FAKE FILESYSTEM, not in real temp files.
  -- That matters: the runner reads with fs.readFile and compiles with
  -- load(), because loadfile() does not exist in OpenComputers. A test
  -- built on real files and loadfile passes happily off-box while the
  -- kernel path is broken -- which is exactly what happened, and cost a
  -- whole emulator round to find.
  local okPass, okFail = "/d/pass.lua", "/d/fail.lua"
  local fs = ramFS({
    [okPass] = "return function(t) t.ok('always true', true) end",
    [okFail] = "return function(t) t.ok('deliberately false', false) end",
  })

  -- The tree under test, as init.lua's _TOS carries it in a release.
  local savedTOS = rawget(_G, "_TOS")
  _G._TOS = { version = "9.9.9", build = "abc1234", variant = "minified" }
  local st = selftest.run({ fs = fs, computer = comp, cfg = { shutdown = false },
                            files = { okPass, okFail } })
  _G._TOS = savedTOS
  eq("one pass recorded", 1, st.pass)
  eq("one fail recorded", 1, st.fail)

  local L = lines(fs)
  test("begins with SELFTEST BEGIN", L[1]:find("^SELFTEST BEGIN") ~= nil)
  -- A result from a boot disk that was behind the source must say so in
  -- its first line. (test_build_stamp.lua)
  test("BEGIN names the build under test",
    L[1]:find("version=9.9.9 build=abc1234 variant=minified", 1, true) ~= nil)
  test("ends with SELFTEST END",     L[#L]:find("^SELFTEST END") ~= nil)
  test("END carries the totals",     L[#L]:find("pass=1 fail=1") ~= nil)

  -- The stall mechanism: every check is announced BEFORE it runs.
  local runIdx, resIdx
  for i, l in ipairs(L) do
    if l:find("^RUN ") and not runIdx then runIdx = i end
    if (l:find("^PASS ") or l:find("^FAIL ")) and not resIdx then resIdx = i end
  end
  test("a RUN line exists",  runIdx ~= nil)
  test("RUN precedes its result", runIdx and resIdx and runIdx < resIdx)
  test("the failing check is named in the tail",
    (fs._files["/var/selftest.log"] or ""):find("deliberately false", 1, true) ~= nil)

end

do
  -- A check that THROWS is a failure, not a crashed battery: one bad
  -- file must not cost you the results of every file after it.
  local boom, after = "/d/boom.lua", "/d/after.lua"
  local fs = ramFS({
    [boom]  = "return function(t) error('boom') end",
    [after] = "return function(t) t.ok('ran anyway', true) end",
  })
  local st = selftest.run({ fs = fs, computer = comp, cfg = {},
                            files = { boom, after } })
  eq("the throwing check counted as a failure", 1, st.fail)
  eq("the check after it still ran",            1, st.pass)
  test("the error text is reported",
    (fs._files["/var/selftest.log"] or ""):find("boom", 1, true) ~= nil)
  test("the run still finished",
    (fs._files["/var/selftest.log"] or ""):find("SELFTEST END", 1, true) ~= nil)
end

-- ── 4. Isolation ───────────────────────────────────────────────────
print()
print("-- module isolation --")
do
  local iso = selftest._internal.withIsolatedModules
  package.loaded["_probe_real"] = "REAL"

  iso(function()
    package.loaded["_probe_real"] = "STUBBED"
    package.loaded["_probe_new"] = "ADDED"
  end)

  eq("a stubbed module is restored", "REAL", package.loaded["_probe_real"])
  eq("a module the check ADDED is removed", nil, package.loaded["_probe_new"])

  -- Restoration must survive the check throwing, which is exactly when
  -- it matters most.
  iso(function()
    package.loaded["_probe_real"] = "STUBBED AGAIN"
    error("check exploded")
  end)
  eq("restored even when the check errors", "REAL", package.loaded["_probe_real"])
  package.loaded["_probe_real"] = nil
end

-- ── 5. skip is not fail ────────────────────────────────────────────
print()
print("-- skip --")
do
  local sk = "/d/skip.lua"
  local fs = ramFS({ [sk] = "return function(t) t.skip('no printer', 'not installed') end" })
  local st = selftest.run({ fs = fs, computer = comp, cfg = {}, files = { sk } })
  eq("skip counted as skip", 1, st.skip)
  eq("...and not as a failure", 0, st.fail)
  test("END reports it", (fs._files["/var/selftest.log"] or ""):find("skip=1") ~= nil)
end

-- ── 6. only= filter ────────────────────────────────────────────────
print()
print("-- only= --")
do
  local a = "/d/a.lua"
  local fs = ramFS({ [a] = "return function(t) t.ok('a', true) end" })
  local st = selftest.run({ fs = fs, computer = comp,
                            cfg = { only = "zz" }, files = { a } })
  eq("a non-matching file is skipped entirely", 0, st.pass)
  test("and says so", (fs._files["/var/selftest.log"] or ""):find("SKIPFILE") ~= nil)
end

-- ── Virtual mounts: the disk must be found via fs.mounts() ───────
-- A disk mounted by the KERNEL at boot never creates a real
-- /mnt/<label> directory -- fs.exists("/mnt") is false and
-- fs.list("/mnt") is empty. Discovery that lists /mnt therefore cannot
-- see a test disk that is physically in the drive with the checks and
-- the marker on it, which is what blocked every attempted round.
--
-- kernel/pkg.lua documents this exact trap in mountedRepoRoots, having
-- been caught by it first. This pins that selftest does not repeat it.
print()
print("-- virtual mount points --")
do
  -- No /mnt directory at all, exactly as a boot-time mount leaves things.
  local fs = ramFS({
    ["/mnt/disk_a5b2/selftest.on"]     = "",
    ["/mnt/disk_a5b2/10-boot.lua"]     = "",
    ["/mnt/disk_a5b2/70-screen.lua"]   = "",
  })
  -- /mnt is NOT a directory: only the mount table knows the disk is there.
  fs._virtual["/mnt"] = true
  fs._mounts = { { mountPoint = "/mnt/disk_a5b2" }, { mountPoint = "/" } }

  -- The disk's marker is SEEN on a virtual mount (the regression this
  -- section was written for) -- but seeing it arms nothing: see the #SEC
  -- section below.
  eq("the disk's marker is seen through the mount table",
    "/mnt/disk_a5b2/selftest.on", (selftest.diskMarkers and selftest.diskMarkers(fs) or {})[1])
  test("...and does not arm the machine by itself", not selftest.enabled(fs))
  fs._files["/etc/selftest.on"] = ""
  test("an armed machine runs it", selftest.enabled(fs))
  eq("...and names the machine's marker", "/etc/selftest.on",
    selftest.activeMarker(fs))

  local found = selftest.discover(fs)
  eq("finds both checks at the disk root", 2, #found)
  test("...by their real paths",
    table.concat(found, " "):find("/mnt/disk_a5b2/10-boot.lua", 1, true) ~= nil)
end

do
  -- Checks in a selftest/ subfolder work too, and do NOT need the disk
  -- to declare itself at its root.
  local fs = ramFS({
    ["/mnt/d/selftest/selftest.on"] = "",
    ["/mnt/d/selftest/10-a.lua"]    = "",
  })
  fs._virtual["/mnt"] = true
  fs._mounts = { { mountPoint = "/mnt/d" } }
  test("a marker inside selftest/ does not arm by itself", not selftest.enabled(fs))
  fs._files["/etc/selftest.on"] = ""
  test("an armed machine takes it", selftest.enabled(fs))
  eq("finds the check in the subfolder", 1, #selftest.discover(fs))
end

do
  -- THE DANGEROUS CASE. A disk root is scanned for checks ONLY when that
  -- disk carries selftest.on at its own root -- the disk declaring
  -- itself a test disk. Without that condition, EVERY mounted disk's
  -- root .lua files get loaded and executed during boot.
  --
  -- Note the root filesystem "/" is not the case to test: mountRoots
  -- skips it outright, so /init.lua and /install.lua are never
  -- reachable either way. The real hazard is an ORDINARY DATA DISK
  -- someone left in the drive, whose .lua files are programs, not
  -- checks. Written against "/" first, which proved nothing.
  local fs = ramFS({
    ["/install.lua"]                = "",
    ["/mnt/testdisk/selftest.on"]   = "",
    ["/mnt/testdisk/10-a.lua"]      = "",
    ["/mnt/datadisk/payload.lua"]   = "",
    ["/mnt/datadisk/autorun.lua"]   = "",
  })
  fs._virtual["/mnt"] = true
  fs._mounts = { { mountPoint = "/" },
                 { mountPoint = "/mnt/testdisk" },
                 { mountPoint = "/mnt/datadisk" } }

  local found = selftest.discover(fs)
  local blob = table.concat(found, " ")
  test("an undeclared data disk's payload.lua is NOT collected",
    blob:find("payload.lua", 1, true) == nil)
  test("...nor its autorun.lua", blob:find("autorun.lua", 1, true) == nil)
  test("...and the root filesystem is never scanned",
    blob:find("install.lua", 1, true) == nil)
  eq("only the declared test disk's check is found", 1, #found)
end

do
  -- THE OPTIONAL UTILITIES DISK. A pack disk keeps each package in a
  -- folder named after it, so disk2 carries selftest/ -- the selftest
  -- PACKAGE: package.lua, package.sig, and its checks under
  -- usr/lib/selftest/ for pkg to install. Discovery took that folder for
  -- a test disk's: on the headless machine `selftest list` showed
  -- package.lua as a check, and an armed boot with the disk in would run
  -- the manifest and log "FAIL package :: check file returned neither a
  -- function nor { run = f }".
  local fs = ramFS({
    ["/mnt/pack/optutil-set.lua"]                       = "",
    ["/mnt/pack/selftest/package.lua"]                  = "return { name = 'selftest' }",
    ["/mnt/pack/selftest/package.sig"]                  = "",
    ["/mnt/pack/selftest/usr/lib/selftest/10-boot.lua"] = "",
    ["/mnt/testdisk/selftest/10-a.lua"]                 = "",
  })
  fs._virtual["/mnt"] = true
  fs._mounts = { { mountPoint = "/mnt/pack" }, { mountPoint = "/mnt/testdisk" } }
  local found = selftest.discover(fs)
  local blob = table.concat(found, " ")
  test("a pack disk's selftest package is not taken for checks",
    blob:find("package.lua", 1, true) == nil)
  eq("...while a test disk's selftest/ still is", 1, #found)
end

-- ── #SEC: a disk never arms the battery ──────────────────────────
-- Checks run INSIDE the kernel (no environment, on purpose), and every
-- non-boot disk is mounted at boot. When a selftest.on on a disk armed the
-- battery, a floppy carrying one plus any .lua was kernel code execution
-- at the next boot: no login, nothing typed. Arming is the machine's call
-- (/etc/selftest.on); the disk only chooses what runs.
--
-- The kernel does not ask selftest.enabled -- it gates INLINE, so that a
-- production boot never loads this module -- so both copies of the rule
-- are driven here: the module's, and the real block cut out of
-- tos/kernel/init.lua and executed against the same disks.
print()
print("-- #SEC: a disk never arms the battery --")
do
  local function hostile()
    local fs = ramFS({
      ["/mnt/floppy/selftest.on"] = "shutdown=true",
      ["/mnt/floppy/pwn.lua"]     = "return function(t) _G.PWNED = true end",
    })
    fs._virtual["/mnt"] = true
    fs._mounts = { { mountPoint = "/" }, { mountPoint = "/mnt/floppy" } }
    return fs
  end

  local fs = hostile()
  test("a floppy with selftest.on does NOT arm the machine", not selftest.enabled(fs))
  test("...activeMarker names nothing", selftest.activeMarker(fs) == nil)
  eq("...though the disk marker is still visible (for the boot hint)",
    1, #(selftest.diskMarkers and selftest.diskMarkers(fs) or {}))

  -- The kernel's own gate, from the real file.
  local initSrc
  for _, p in ipairs({ base .. "../../../tos/kernel/init.lua", "tos/kernel/init.lua",
                       "TOS-Dev/tos/kernel/init.lua" }) do
    local h = io.open(p, "rb")
    if h then initSrc = h:read("*a"); h:close(); break end
  end
  test("tos/kernel/init.lua readable", initSrc ~= nil)
  -- Anchored on the section banner, then the block's own pcall(function()
  -- and the first `if okS and st` after it -- text every version of the
  -- gate has, so this drives the pre-fix block too.
  local banner = initSrc and initSrc:find("In-emulator self-test battery", 1, true)
  local HEAD = "= pcall(function()"
  local s = banner and initSrc:find(HEAD, banner, true)
  local e = s and initSrc:find("if okS and st", s, true)
  test("the kernel's selftest gate block is found", s ~= nil and e ~= nil)
  local gate
  if s and e then
    -- Everything between `pcall(function()` and its closing `end)`.
    local body = initSrc:sub(s + #HEAD, e - 1):gsub("end%)%s*$", "")
    local chunk, cerr = load("return function(fsMod) _G._TOS = { fs = fsMod }\n"
      .. "return (function() " .. body .. " end)() end",
      "=init.lua:selftest-gate", "t",
      { _G = {}, pcall = pcall, type = type, ipairs = ipairs, tostring = tostring,
        require = function(name) return { loaded = name } end })
    test("...and compiles on its own" .. (cerr and (" (" .. cerr .. ")") or ""),
      chunk ~= nil)
    gate = chunk and chunk()
  end
  if gate then
    local mod, where = gate(hostile())
    test("kernel gate: a floppy alone does NOT load the battery", mod == false)
    eq("...and names the ignored disk for the boot hint", "/mnt/floppy", where)

    local armed = hostile()
    armed._files["/etc/selftest.on"] = ""
    local mod2 = gate(armed)
    test("kernel gate: /etc/selftest.on loads the battery",
      type(mod2) == "table" and mod2.loaded == "kernel.selftest")
    test("...and the module agrees", selftest.enabled(armed))

    local none = gate(ramFS({}))
    test("kernel gate: nothing present, nothing loaded", none == nil)
  end

  -- Options still ride in on the disk once the machine is armed: CI puts
  -- shutdown=true on the test disk and an EMPTY /etc/selftest.on on the box.
  local armed = hostile()
  armed._files["/etc/selftest.on"] = ""
  test("an empty machine marker keeps the disk's shutdown=true",
    selftest.readMarker(armed).shutdown == true)
  armed._files["/etc/selftest.on"] = "shutdown=false"
  test("...and the machine's marker can override it",
    selftest.readMarker(armed).shutdown == false)

  -- Arming is granting kernel authority to whatever sits on a test disk,
  -- and an ADMIN can write a mounted disk -- so only ROOT may arm, or the
  -- battery is an ADMIN -> kernel path. The real ACL, through securefs.
  package.path = "tos/?.lua;" .. base .. "../../../tos/?.lua;" .. package.path
  package.loaded["computer"] = package.loaded["computer"]
    or { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
  package.loaded["component"] = package.loaded["component"]
    or { list = function() return function() end end, proxy = function() end }
  package.loaded["kernel.process"] = package.loaded["kernel.process"]
    or { currentSession = function() return nil end, yieldCooperative = function() end }
  local kfs = require("kernel.fs")
  local users = require("kernel.users")
  users.init({ fs = { normalize = kfs.normalize, exists = function() return false end,
    readFile = function() return nil end, writeFile = function() return true end,
    makeDirectory = function() return true end },
    crypto = { init = function() end, hasHardware = function() return false end,
      salt = function(n) return string.rep("s", n or 16) end,
      hashPassword = function(pw, s) return "h:" .. pw .. s end } })
  local T = users.TIER
  local admin = { user = "adam", tier = T.ADMIN, home = "/home/adam" }
  local root  = { user = "root", tier = T.ROOT,  home = "/root" }
  test("an ADMIN may not arm the battery",
    not users.canAccessAs(admin, "/etc/selftest.on", "w"))
  test("...nor through a spelling the disk folds",
    not users.canAccessAs(admin, "/ETC/SelfTest.on", "w"))
  test("...nor through its atomic-save temp",
    not users.canAccessAs(admin, "/etc/selftest.on.tos-tmp", "w"))
  test("ROOT may", users.canAccessAs(root, "/etc/selftest.on", "w") == true)
  test("anyone may still READ it", users.canAccessAs(admin, "/etc/selftest.on", "r") == true)
end

-- ── Loading must not depend on loadfile() ────────────────────
-- The first real round failed all seven checks with "could not load:
-- attempt to call a nil value" -- pcall reporting an attempt to CALL
-- loadfile, which is nil in OpenComputers because it is backed by io.
-- The runner reads with fs.readFile and compiles with load() now, and
-- the fixtures above live in the fake filesystem so this suite drives
-- that same path rather than a friendlier one.
print()
print("-- source loading --")
do
  local fs = ramFS({ ["/d/ok.lua"] = "return function(t) t.ok('x', true) end" })
  local st = selftest.run({ fs = fs, computer = comp, cfg = {}, files = { "/d/ok.lua" } })
  eq("a check read from the filesystem runs", 1, st.pass)

  -- A file the filesystem cannot produce is reported as unreadable, not
  -- as a syntax error: different causes, different fixes.
  local fs2 = ramFS({})
  local st2 = selftest.run({ fs = fs2, computer = comp, cfg = {}, files = { "/d/gone.lua" } })
  eq("a missing check is one failure", 1, st2.fail)
  test("...reported as unreadable",
    (fs2._files["/var/selftest.log"] or ""):find("unreadable", 1, true) ~= nil)

  -- And a genuine syntax error still says so, with Lua's own message.
  local fs3 = ramFS({ ["/d/bad.lua"] = "return function(t) this is not lua" })
  local st3 = selftest.run({ fs = fs3, computer = comp, cfg = {}, files = { "/d/bad.lua" } })
  eq("a malformed check is one failure", 1, st3.fail)
  local log3 = fs3._files["/var/selftest.log"] or ""
  test("...reported as a load error", log3:find("could not load", 1, true) ~= nil)
  test("...and NOT as unreadable", log3:find("unreadable", 1, true) == nil)

  -- The regression itself: nothing in the load path may call loadfile.
  local src = tryload("tos/kernel/selftest.lua")
  local body = io.open((base .. "../../../tos/kernel/selftest.lua"), "r")
  if body then
    local text = body:read("*a"); body:close()
    -- Strip comments before searching: the fix's own comment explains
    -- why loadfile is not used, so a naive search finds itself.
    local NL = string.char(10)
    local code = {}
    for line in (text .. NL):gmatch("([^" .. NL .. "]*)" .. NL) do
      code[#code + 1] = line:match("^(.-)%-%-") or line
    end
    test("selftest.lua never calls loadfile()",
      table.concat(code, " "):find("loadfile", 1, true) == nil)
  end
end

-- ── screen= reaches the checks ───────────────────────────
-- Checks that paint the boot console are opt-in, so they have to be
-- able to SEE the option. A flag the marker parses but never delivers
-- would leave them silently disabled forever.
print()
print("-- the screen option --")
do
  local cfgOff = selftest.readMarker(ramFS({ ["/etc/selftest.on"] = "" }))
  test("screen defaults off", cfgOff.screen == false)
  local cfgOn = selftest.readMarker(ramFS({ ["/etc/selftest.on"] = "screen=true" }))
  test("screen=true parses", cfgOn.screen == true)

  -- And a check actually receives it.
  local probe = "/d/probe.lua"
  local fs = ramFS({ [probe] =
    "return function(t) t.ok('saw screen=' .. tostring(t.cfg and t.cfg.screen), " ..
    "t.cfg ~= nil and t.cfg.screen == true) end" })
  local st = selftest.run({ fs = fs, computer = comp,
                            cfg = { screen = true }, files = { probe } })
  eq("a check can read cfg.screen", 1, st.pass)

  local fs2 = ramFS({ [probe] =
    "return function(t) t.ok('off', t.cfg ~= nil and t.cfg.screen == false) end" })
  local st2 = selftest.run({ fs = fs2, computer = comp,
                             cfg = { screen = false }, files = { probe } })
  eq("...and sees it off when it is off", 1, st2.pass)
end

-- ── t.note reaches the report ──────────────────────────────────
-- Only failure and skip NAMES were written out, so an answer a check
-- tucked into a passing assertion's name never reached the log: the
-- first real round's reading of coroutine.isyieldable() was lost that
-- way (92-term, 2026-09-25).
print()
print("-- t.note --")
do
  local probe = "/d/note.lua"
  local fs = ramFS({ [probe] =
    "return function(t) t.note('isyieldable here: true'); t.ok('a', true) end" })
  local st = selftest.run({ fs = fs, computer = comp, cfg = {}, files = { probe } })
  local log = fs.readFile(selftest.RESULTS) or ""
  test("a note is written to the report", log:find("  i isyieldable here: true", 1, true) ~= nil)
  eq("...and counts as nothing", 1, st.n)
  eq("...not as a pass", 1, st.pass)
end

-- ── shutdown=true goes through the REAL shutdown path ──────────────
-- Regression for the first real emulator round: a raw computer.shutdown()
-- skips kernel.shutdown's own "stamp /var/run/pwrstate clean" step, so
-- every armed battery reported its OWN deliberate shutdown as unsafe
-- (warning + beeps) on the very next boot. selftest.run() must prefer
-- _G._TOS.kernel.shutdown when it exists, and fall back to a raw
-- computer.shutdown() only when it does not (e.g. this very test, which
-- has no kernel table at all).
print()
print("-- shutdown goes through kernel.shutdown when available --")
do
  local a = "/d/a.lua"
  local fs = ramFS({ [a] = "return function(t) t.ok('a', true) end" })

  -- No _G._TOS at all: must fall back to the raw computer.shutdown
  -- rather than erroring out on a nil kernel table.
  _G._TOS = nil
  local rawCalls = {}
  local compRaw = { uptime = function() return 0 end, freeMemory = function() return 500000 end,
                    shutdown = function(reboot) rawCalls[#rawCalls + 1] = reboot end }
  selftest.run({ fs = fs, computer = compRaw, cfg = { shutdown = true }, files = { a } })
  eq("falls back to raw computer.shutdown with no kernel table", 1, #rawCalls)
  eq("...requesting power-off, not reboot", false, rawCalls[1])

  -- _G._TOS.kernel.shutdown present: THAT must be called, and the raw
  -- computer.shutdown must NOT be -- calling both would shut down twice
  -- (the second call meaningless, but a sign the preference is not wired).
  local kernelCalls, rawCalls2 = {}, {}
  local compBoth = { uptime = function() return 0 end, freeMemory = function() return 500000 end,
                     shutdown = function(reboot) rawCalls2[#rawCalls2 + 1] = reboot end }
  _G._TOS = { kernel = { shutdown = function(reboot) kernelCalls[#kernelCalls + 1] = reboot end } }
  selftest.run({ fs = fs, computer = compBoth, cfg = { shutdown = true }, files = { a } })
  eq("prefers kernel.shutdown when it exists", 1, #kernelCalls)
  eq("...with power-off, not reboot", false, kernelCalls[1])
  eq("...and never falls through to the raw call too", 0, #rawCalls2)
  _G._TOS = nil

  -- cfg.shutdown = false: neither path fires.
  local rawCalls3 = {}
  local compOff = { uptime = function() return 0 end, freeMemory = function() return 500000 end,
                    shutdown = function(reboot) rawCalls3[#rawCalls3 + 1] = reboot end }
  selftest.run({ fs = fs, computer = compOff, cfg = { shutdown = false }, files = { a } })
  eq("shutdown=false calls neither shutdown path", 0, #rawCalls3)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
