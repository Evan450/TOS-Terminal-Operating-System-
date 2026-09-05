-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: cluster-worker-setup (OpenOS worker wizard) ║
-- ║                                                                ║
-- ║  The load-bearing part is the OS check. A worker is an OpenOS  ║
-- ║  program; someone running it on TOS is on the wrong machine    ║
-- ║  entirely, and deserves to be told WHICH OS this is, HOW the   ║
-- ║  script can tell, and WHAT to run instead — not a stack trace  ║
-- ║  from a missing require.                                       ║
-- ║                                                                ║
-- ║  Detection is capability probes (both OSes expose `component`  ║
-- ║  and `computer`, so only the differences discriminate), and    ║
-- ║  the probe is injected — so every environment is testable      ║
-- ║  here without either OS present.                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua TOS-Extras/cluster/openos/test_worker_setup.lua

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

local here = (arg and arg[0]) or "TOS-Extras/cluster/openos/test_worker_setup.lua"
local base = here:gsub("[^/\\]*$", "")
local M
for _, p in ipairs({ base .. "cluster-worker-setup.lua",
    "TOS-Extras/cluster/openos/cluster-worker-setup.lua",
    "cluster/openos/cluster-worker-setup.lua" }) do
  local chunk = loadfile(p)
  -- Pass a name so the file's `if not (...)` entry guard treats it as a
  -- library load and does NOT run the interactive flow.
  if chunk then M = chunk("test"); break end
end
if not M then
  print("FAIL: could not load cluster-worker-setup.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== OpenOS worker setup Tests ===")
print()

-- ============================================================
-- 1. Which OS am I on?
-- ============================================================
print("-- OS detection --")

local OPENOS = { ooFilesystem = true, ooShell = true, ooTerm = true, ooLibCore = true }
local TOS    = { tosGlobal = true, tosPkg = true, tosUsers = true, tosKernel = true }

do
  local os1, conf, reasons = M.classify(OPENOS)
  eq("a clean OpenOS box is openos", "openos", os1)
  test("confident about it", conf >= 3)
  test("says what it saw", #reasons >= 3)

  local os2, _, r2 = M.classify(TOS)
  eq("a clean TOS box is tos", "tos", os2)
  test("names TOS-only evidence",
    table.concat(r2, "\n"):find("kernel.pkg", 1, true) ~= nil)
end

do
  -- A bare machine where nothing loads: unknown, and it must SAY that
  -- rather than reporting a verdict with no evidence behind it.
  local os3, conf, reasons = M.classify({})
  eq("a bare machine is unknown", "unknown", os3)
  eq("no confidence", 0, conf)
  test("still explains itself",
    table.concat(reasons, "\n"):find("neither", 1, true) ~= nil)
end

do
  -- TOS running the OpenOS compat layer answers to SOME OpenOS names. A tie
  -- is genuinely ambiguous and must not be guessed either way.
  local mixed = { tosGlobal = true, tosPkg = true,
                  ooFilesystem = true, ooTerm = true }
  eq("an even split is unknown, not a guess", "unknown", (M.classify(mixed)))
end

do
  -- The realistic TOS-with-compat case: TOS evidence still outweighs.
  local tosCompat = { tosGlobal = true, tosPkg = true, tosUsers = true,
                      tosKernel = true, ooFilesystem = true, ooTerm = true }
  eq("TOS with compat still reads as TOS", "tos", (M.classify(tosCompat)))
end

-- The refusal message is the whole point of the feature.
do
  local _, _, reasons = M.classify(TOS)
  local msg = table.concat(M.wrongOsMessage("tos", reasons), "\n")
  test("says this machine is TOS", msg:find("running TOS", 1, true) ~= nil)
  test("explains HOW it can tell", msg:find("How I can tell", 1, true) ~= nil)
  test("cites specific evidence", msg:find("kernel.pkg", 1, true) ~= nil)
  -- The actionable half: what to run INSTEAD.
  test("names cluster-setup", msg:find("cluster-setup", 1, true) ~= nil)
  test("says TOS boxes are Managers", msg:find("MANAGER", 1, true) ~= nil)
  test("explains why workers are OpenOS-native",
    msg:find("OpenOS%-native") ~= nil)

  local msg2 = table.concat(M.wrongOsMessage("unknown", { "x" }), "\n")
  test("an unknown OS is told to use OpenOS",
    msg2:find("OpenOS machine", 1, true) ~= nil)
end

-- ============================================================
-- 2. Answers that would silently break the worker
-- ============================================================
print()
print("-- validation --")

do
  test("a long secret is accepted", (M.checkSecret(("k"):rep(M.MIN_SECRET))))
  local ok, why = M.checkSecret("short")
  test("a short secret is rejected", not ok)
  test("...and says it is the HMAC key", why:find("HMAC", 1, true) ~= nil)
  test("...and gives both numbers", why:find(tostring(M.MIN_SECRET), 1, true) ~= nil)

  ok, why = M.checkSecret("has a space in it 12345678")
  test("a secret with spaces is rejected", not ok)
  test("...because it must match exactly", why:find("exactly", 1, true) ~= nil)
  test("empty secret rejected", not (M.checkSecret("")))
  test("nil secret rejected", not (M.checkSecret(nil)))
end

do
  eq("domain 0 is fine", 0, select(2, M.checkDomain("0")))
  eq("domain parses to a number", 7, select(2, M.checkDomain("7")))
  test("a fractional domain is rejected", not (M.checkDomain("1.5")))
  test("a negative domain is rejected", not (M.checkDomain("-1")))
  test("a huge domain is rejected", not (M.checkDomain("100000")))
  test("a non-numeric domain is rejected", not (M.checkDomain("abc")))
end

do
  eq("a plain hostname is fine", "wk-a", select(2, M.checkHostname("wk-a")))
  test("spaces are rejected", not (M.checkHostname("wk a")))
  test("punctuation is rejected", not (M.checkHostname("wk!")))
  test("empty is rejected", not (M.checkHostname("  ")))
  test("over-long is rejected", not (M.checkHostname(("x"):rep(25))))
end

do
  local cfg = { domain_id = 3, hostname = "wk-a", shared_secret = "0123456789abcdef" }
  local src = M.encodeConfig(cfg)
  local fn = load(src, "=cfg", "t")
  test("the config compiles", fn ~= nil)
  local t = fn()
  eq("domain round-trips", 3, t.domain_id)
  eq("hostname round-trips", "wk-a", t.hostname)
  eq("secret round-trips", "0123456789abcdef", t.shared_secret)
  test("the file warns that both must match the Manager",
    src:find("match the Manager", 1, true) ~= nil)
end

-- ============================================================
-- 3. rc.cfg surgery
-- ============================================================
print()
print("-- autostart --")

do
  local out, changed = M.addToRc("", "cluster-worker")
  test("empty rc gets an enabled list", changed)
  test("...naming the worker", out:find('"cluster%-worker"') ~= nil)

  out, changed = M.addToRc('enabled = { "foo" }\n', "cluster-worker")
  test("an existing list is extended", changed)
  test("...keeping what was there", out:find('"foo"', 1, true) ~= nil)
  test("...and adding ours", out:find('"cluster%-worker"') ~= nil)

  local already = 'enabled = { "cluster-worker" }\n'
  out, changed = M.addToRc(already, "cluster-worker")
  test("already-listed is left alone", not changed)
  eq("...byte for byte", already, out)

  -- Unrelated content must survive.
  out = M.addToRc('somethingelse = 1\n', "cluster-worker")
  test("unrelated rc content survives", out:find("somethingelse", 1, true) ~= nil)
end

-- ============================================================
-- 4. The flow
-- ============================================================
print()
print("-- flow --")

local function newCtx(opts)
  opts = opts or {}
  local c = { said = {}, files = {}, _answers = opts.answers or {} }
  c.probe = opts.probe
  c.say = function(t, k) c.said[#c.said + 1] = { text = t or "", kind = k } end
  c.ask = function(_, dflt)
    if #c._answers == 0 then return dflt end
    local a = table.remove(c._answers, 1)
    if a == "\0CANCEL" then return nil end
    if a == "\0DEFAULT" then return dflt end
    return a
  end
  c.confirm = function() return opts.autostart == true end
  c.readFile = function(p) return c.files[p] end
  c.writeFile = function(p, d) c.files[p] = d; return true end
  return c
end
local function said(c)
  local o = {}
  for _, s in ipairs(c.said) do o[#o + 1] = s.text end
  return table.concat(o, "\n")
end

-- A probe that reports a given environment table.
local function probeFor(env)
  return {
    hasModule = function(n)
      if n == "kernel.pkg" then return env.tosPkg == true end
      if n == "kernel.users" then return env.tosUsers == true end
      if n == "filesystem" then return env.ooFilesystem == true end
      if n == "shell" then return env.ooShell == true end
      if n == "term" then return env.ooTerm == true end
      return false
    end,
    hasGlobal = function(n) return n == "_TOS" and env.tosGlobal == true end,
    hasPath = function(p)
      if p == "/tos/kernel/init.lua" then return env.tosKernel == true end
      if p == "/lib/core/boot.lua" then return env.ooLibCore == true end
      return false
    end,
  }
end

do
  -- Run on TOS: refuse, explain, change nothing.
  local c = newCtx({ probe = probeFor(TOS) })
  local ok, osName = M.run(c)
  eq("refuses to run on TOS", false, ok)
  eq("...and reports which OS", "tos", osName)
  eq("nothing was written", nil, c.files[M.CFG_PATH])
  test("told to run cluster-setup instead",
    said(c):find("cluster-setup", 1, true) ~= nil)
end

do
  -- The happy path on OpenOS.
  local c = newCtx({ probe = probeFor(OPENOS), autostart = true,
    answers = { "3", "wk-a", "0123456789abcdef" } })
  test("completes on OpenOS", (M.run(c)))
  test("wrote the config", c.files[M.CFG_PATH] ~= nil)
  local cfg = load(c.files[M.CFG_PATH], "=c", "t")()
  eq("domain saved", 3, cfg.domain_id)
  eq("hostname saved", "wk-a", cfg.hostname)
  eq("secret saved", "0123456789abcdef", cfg.shared_secret)
  test("wrote the rc autostart", c.files[M.RC_PATH] ~= nil)
  -- The port is derived, not asked for, so it must be shown.
  test("shows the derived port", said(c):find("2004", 1, true) ~= nil)
  -- The operator has to go set the OTHER side; tell them exactly what.
  test("tells them what the Manager needs",
    said(c):find("worker_bridge_domain  = 3", 1, true) ~= nil)
  -- ...without echoing the secret back to the screen.
  test("does NOT echo the secret",
    said(c):find("0123456789abcdef", 1, true) == nil)
end

do
  -- Declining autostart must not touch rc.cfg.
  local c = newCtx({ probe = probeFor(OPENOS), autostart = false,
    answers = { "0", "wk-b", "0123456789abcdef" } })
  test("completes without autostart", (M.run(c)))
  eq("rc.cfg untouched", nil, c.files[M.RC_PATH])
end

do
  -- A short secret is re-asked, not written.
  local c = newCtx({ probe = probeFor(OPENOS),
    answers = { "0", "wk-c", "tooshort", "0123456789abcdef" } })
  test("recovers from a short secret", (M.run(c)))
  local cfg = load(c.files[M.CFG_PATH], "=c", "t")()
  eq("the GOOD secret was written", "0123456789abcdef", cfg.shared_secret)
  test("the operator was told why", said(c):find("HMAC", 1, true) ~= nil)
end

do
  -- Cancelling writes nothing.
  local c = newCtx({ probe = probeFor(OPENOS), answers = { "\0CANCEL" } })
  eq("cancelling aborts", false, (M.run(c)))
  eq("nothing written", nil, c.files[M.CFG_PATH])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***") end
return failed == 0
