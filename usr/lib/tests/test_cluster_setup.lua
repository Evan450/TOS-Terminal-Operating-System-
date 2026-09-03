-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: shell.clustersetup (the cluster wizard)      ║
-- ║                                                                ║
-- ║  The wizard takes every side effect through an injected ctx,   ║
-- ║  so the WHOLE flow runs here against scripted answers — no     ║
-- ║  shell, no display, no network, no packages installed.         ║
-- ║                                                                ║
-- ║  What matters most, and what this pins:                        ║
-- ║   * with nothing installed it explains what to install where   ║
-- ║     (the question operators actually get stuck on)             ║
-- ║   * the Master prints its FULL modem address — the old         ║
-- ║     installer truncated it into a command that looked          ║
-- ║     copy-pasteable and wasn't                                  ║
-- ║   * "start at boot?" is actually honoured, via the rc marker,  ║
-- ║     not the package-enable byte the old installer wrote        ║
-- ║   * a shortened Master address is rejected with a reason       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_setup.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_cluster_setup.lua"
local base = here:gsub("[^/\\]*$", "")
local wiz
for _, p in ipairs({ base .. "../../../tos/shell/clustersetup.lua",
    "tos/shell/clustersetup.lua", "TOS-Dev/tos/shell/clustersetup.lua" }) do
  local chunk = loadfile(p); if chunk then wiz = chunk(); break end
end
if not wiz then
  print("FAIL: could not load clustersetup.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local FULL_ADDR = "3f8a1c2d-44b5-4e0a-9c11-77aa0099bbcd"   -- 36 chars

print("=== cluster setup wizard Tests ===")
print()

-- ============================================================
-- 1. The explainer
-- ============================================================
print("-- what do I install, and where --")

do
  local topo = wiz.topology()
  eq("two roles", 2, #topo)
  eq("Master is first", "Master", topo[1].role)
  eq("Master installs cluster-master", "cluster-master", topo[1].pkg)
  test("Master is documented as exactly one", topo[1].one == true)
  eq("Manager installs cluster-manager", "cluster-manager", topo[2].pkg)
  test("Manager is documented as many", topo[2].one == false)
  -- The rc service stem is NOT the package name for the Master, and getting
  -- that wrong is what made the old boot-enable write the wrong file.
  eq("Master's service is clusterd", "clusterd", topo[1].svc)
  eq("Manager's service is cluster-manager", "cluster-manager", topo[2].svc)

  local text = table.concat(wiz.explain(), "\n")
  test("explains the install command for Master",
    text:find("pkg install cluster-master", 1, true) ~= nil)
  test("explains the install command for Manager",
    text:find("pkg install cluster-manager", 1, true) ~= nil)
  test("says where the packages come from",
    text:find("Optional Utilities", 1, true) ~= nil)
  -- The operator's literal question was whether they have to move files.
  test("says you never copy files by hand",
    text:find("never copy files by hand", 1, true) ~= nil)
end

-- ============================================================
-- 2. Validation
-- ============================================================
print()
print("-- answers that would break the cluster --")

do
  test("a full address is accepted", (wiz.checkMasterAddress(FULL_ADDR)))
  eq("...and comes back cleaned", FULL_ADDR,
    select(2, wiz.checkMasterAddress("  " .. FULL_ADDR .. "  ")))

  -- Every TOS listing abbreviates addresses to 8 chars + "...", so pasting
  -- one back is THE mistake to catch, by name.
  local ok, why = wiz.checkMasterAddress("3f8a1c2d...")
  test("a truncated address is rejected", not ok)
  test("...and says it looks shortened", why:find("shortened", 1, true) ~= nil)

  ok, why = wiz.checkMasterAddress("3f8a1c2d")
  test("a short address is rejected", not ok)
  test("...and says how long a real one is", why:find("36", 1, true) ~= nil)

  ok, why = wiz.checkMasterAddress("not-an-address-!!!!!!!!!!!!!!!!!!!!!!")
  test("a non-hex address is rejected", not ok)
  test("empty is rejected", not (wiz.checkMasterAddress("")))
  test("nil is rejected", not (wiz.checkMasterAddress(nil)))

  test("a plausible pairing code is accepted", (wiz.checkPairingCode("ABC123XYZ")))
  ok, why = wiz.checkPairingCode("abc")
  test("a too-short code is rejected", not ok)
  test("...and names the command that prints one",
    why:find("cluster pair start", 1, true) ~= nil)
end

do
  local c = wiz.masterConfig({ threads = 999, heartbeat = 0, degraded = "x" })
  eq("thread budget clamped", 64, c.host_thread_budget)
  eq("heartbeat clamped up", 1, c.heartbeat_interval)
  eq("non-numeric falls back to the default", 15, c.heartbeat_degraded_after)
  local d = wiz.masterConfig({})
  eq("default threads", 4, d.host_thread_budget)

  local m = wiz.managerConfig({ master = FULL_ADDR, profile = "nonsense", workers = 99 })
  eq("bad profile falls back to mixed", "mixed", m.compute_profile)
  eq("worker count clamped", 16, m.worker_count)
  eq("master address carried", FULL_ADDR, m.master_address)
  eq("a real profile is kept", "io_bound",
    wiz.managerConfig({ profile = "io_bound" }).compute_profile)
end

do
  local enc = wiz.encodeConfig({ b = 2, a = "x", c = true })
  test("config is a loadable chunk", enc:match("^%-%-.-\nreturn {") ~= nil)
  local fn = load(enc, "=cfg", "t")
  test("config compiles", fn ~= nil)
  local t = fn()
  eq("string round-trips", "x", t.a)
  eq("number round-trips", 2, t.b)
  eq("boolean round-trips", true, t.c)
  -- Sorted keys so a regenerated config diffs cleanly.
  test("keys are sorted", enc:find("a =", 1, true) < enc:find("b =", 1, true))
end

-- ============================================================
-- 3. The flow
-- ============================================================
-- A recording ctx. `answers` is consumed in order by ask(); `picks` by
-- choose(). Everything else is recorded for assertions.
local function newCtx(opts)
  opts = opts or {}
  local c = {
    said = {}, installedPkgs = {}, files = {}, started = {},
    bootStart = {}, paired = nil, pairingOpened = false,
    _answers = opts.answers or {}, _picks = opts.picks or {},
    _have = opts.have or {},
  }
  c.say = function(text, kind) c.said[#c.said + 1] = { text = text or "", kind = kind } end
  c.choose = function()
    local p = table.remove(c._picks, 1)
    return p or 1
  end
  c.ask = function(_, dflt)
    if #c._answers == 0 then return dflt end
    local a = table.remove(c._answers, 1)
    if a == "\0CANCEL" then return nil end
    if a == "\0DEFAULT" then return dflt end
    return a
  end
  c.installed = function(n) return c._have[n] == true end
  c.install = function(n)
    if opts.installFails then return false, "no repo" end
    c._have[n] = true; c.installedPkgs[#c.installedPkgs + 1] = n; return true
  end
  c.writeFile = function(p, d) c.files[p] = d; return true end
  c.startService = function(s) c.started[#c.started + 1] = s; return true end
  c.setBootStart = function(s, on) c.bootStart[s] = on; return true end
  c.modemCount = function() return opts.modems or 1, opts.wireless or 1 end
  c.myModemAddress = function() return opts.myAddr or FULL_ADDR end
  c.hostname = function() return "node-a" end
  c.startPairing = function()
    c.pairingOpened = true
    if opts.pairingFails then return nil, "daemon not up" end
    return "PAIR-CODE-42", 300
  end
  c.pairWith = function(addr, code)
    c.paired = { addr = addr, code = code }
    if opts.pairFails then return false, "no answer" end
    return true
  end
  return c
end
local function saidText(c)
  local out = {}
  for _, s in ipairs(c.said) do out[#out + 1] = s.text end
  return table.concat(out, "\n")
end

print()
print("-- Master flow --")

do
  local c = newCtx({ picks = { 1, 1 } })     -- role=Master, boot=Yes
  local okRun = wiz.run(c)
  test("master setup completes", okRun)
  eq("installed the master package", "cluster-master", c.installedPkgs[1])
  test("wrote the master config", c.files["/etc/cluster-master.cfg"] ~= nil)
  eq("started the daemon by its rc NAME", "clusterd", c.started[1])
  eq("boot-start honoured (yes)", true, c.bootStart["clusterd"])
  test("opened a pairing window", c.pairingOpened)

  local text = saidText(c)
  -- THE regression: the address the operator has to type into each Manager
  -- must be complete. The old installer printed myAddr:sub(1,12).."..."
  -- inside a command line, which read as copy-pasteable and was not.
  test("the FULL master address is printed", text:find(FULL_ADDR, 1, true) ~= nil)
  -- The precise old bug: a PREFIX of the address followed by "...", which
  -- reads as a copy-pasteable value and isn't. (A bare "..." elsewhere is
  -- fine — "Installing cluster-master ..." is a progress line, not an
  -- address, so asserting on any ellipsis at all would be noise.)
  test("no truncated form of the address is printed",
    text:find(FULL_ADDR:sub(1, 8) .. "%S-%.%.%.") == nil)
  test("the pairing code is printed", text:find("PAIR-CODE-42", 1, true) ~= nil)

  local cfg = load(c.files["/etc/cluster-master.cfg"], "=c", "t")()
  eq("master config has a thread budget", 4, cfg.host_thread_budget)
end

do
  local c = newCtx({ picks = { 1, 2 } })     -- role=Master, boot=No
  wiz.run(c)
  -- The old installer asked this and then wrote the package-enable byte
  -- instead of the rc marker, so the answer changed nothing either way.
  eq("boot-start honoured (no)", false, c.bootStart["clusterd"])
  test("...but the service still started now", c.started[1] == "clusterd")
end

do
  local c = newCtx({ picks = { 1, 1 }, pairingFails = true })
  test("master setup still completes if pairing can't open", wiz.run(c))
  test("...and says how to open it later",
    saidText(c):find("cluster pair start", 1, true) ~= nil)
end

print()
print("-- Manager flow --")

do
  local c = newCtx({ picks = { 2, 1 },
    answers = { FULL_ADDR, "\0DEFAULT", "\0DEFAULT", "PAIR-CODE-42" } })
  local okRun = wiz.run(c)
  test("manager setup completes", okRun)
  eq("installed the manager package", "cluster-manager", c.installedPkgs[1])
  eq("started the manager service", "cluster-manager", c.started[1])
  test("wrote the manager config", c.files["/etc/cluster-manager.cfg"] ~= nil)

  local cfg = load(c.files["/etc/cluster-manager.cfg"], "=c", "t")()
  eq("config carries the full master address", FULL_ADDR, cfg.master_address)
  eq("config picked up the hostname", "node-a", cfg.hostname)
  eq("default profile", "mixed", cfg.compute_profile)

  test("paired with the master", c.paired ~= nil)
  eq("paired against the full address", FULL_ADDR, c.paired.addr)
  eq("paired with the operator's code", "PAIR-CODE-42", c.paired.code)
end

do
  -- A truncated address must be re-asked, not written into the config.
  local c = newCtx({ picks = { 2, 1 },
    answers = { "3f8a1c2d...", FULL_ADDR, "\0DEFAULT", "\0DEFAULT", "PAIR-CODE-42" } })
  test("manager setup recovers from a bad address", wiz.run(c))
  test("the operator was told what was wrong",
    saidText(c):find("shortened", 1, true) ~= nil)
  local cfg = load(c.files["/etc/cluster-manager.cfg"], "=c", "t")()
  eq("the GOOD address was written", FULL_ADDR, cfg.master_address)
end

do
  -- Cancelling at the address prompt must abort cleanly, writing nothing.
  local c = newCtx({ picks = { 2 }, answers = { "\0CANCEL" } })
  eq("cancelling aborts", false, wiz.run(c))
  eq("nothing was written", nil, c.files["/etc/cluster-manager.cfg"])
  eq("no service was started", 0, #c.started)
end

do
  -- Skipping pairing is allowed; the config is still written and the
  -- operator is told how to finish.
  local c = newCtx({ picks = { 2, 1 },
    answers = { FULL_ADDR, "\0DEFAULT", "\0DEFAULT", "\0CANCEL" } })
  test("manager setup completes without pairing", wiz.run(c))
  eq("nothing was paired", nil, c.paired)
  test("told how to pair later",
    saidText(c):find("cluster%-manager pair") ~= nil)
end

do
  -- A pair round-trip failure is a warning, not a failed setup: the local
  -- trust entry is written either way.
  local c = newCtx({ picks = { 2, 1 }, pairFails = true,
    answers = { FULL_ADDR, "\0DEFAULT", "\0DEFAULT", "PAIR-CODE-42" } })
  test("setup survives a failed pair round-trip", wiz.run(c))
  test("...and explains what to check",
    saidText(c):find("re%-run cluster%-setup") ~= nil)
end

print()
print("-- refusals --")

do
  local c = newCtx({ picks = { 1, 1 }, modems = 0, wireless = 0 })
  eq("no modem aborts", false, wiz.run(c))
  test("...saying every node needs one",
    saidText(c):find("needs one", 1, true) ~= nil)
  eq("nothing was installed", 0, #c.installedPkgs)
end

do
  local c = newCtx({ picks = { 1, 1 }, modems = 1, wireless = 0 })
  test("a wired-only cluster is allowed", wiz.run(c))
  test("...but warns every node must be cabled",
    saidText(c):find("cabled", 1, true) ~= nil)
end

do
  local c = newCtx({ picks = { 1, 1 }, installFails = true })
  eq("a failed install aborts", false, wiz.run(c))
  test("...and points at the Optional Utilities disk",
    saidText(c):find("Optional Utilities", 1, true) ~= nil)
end

do
  local c = newCtx({ picks = { 3 } })        -- Cancel at the role prompt
  eq("cancelling at the role prompt aborts", false, wiz.run(c))
  eq("nothing installed", 0, #c.installedPkgs)
end

do
  -- Already installed: the wizard must NOT ask which role — the machine has
  -- already committed, and asking invites a mismatched config.
  local c = newCtx({ picks = { 1 }, have = { ["cluster-master"] = true } })
  test("an installed Master is reconfigured directly", wiz.run(c))
  eq("did not reinstall", 0, #c.installedPkgs)
  eq("still wrote the master config side",
    "clusterd", c.started[1])
end

do
  -- Both installed is a misconfiguration the wizard should name rather than
  -- silently picking one.
  local c = newCtx({ have = { ["cluster-master"] = true, ["cluster-manager"] = true } })
  eq("both packages installed is refused", false, wiz.run(c))
  test("...and says a machine is one role",
    saidText(c):find("not both", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***") end
return failed == 0
