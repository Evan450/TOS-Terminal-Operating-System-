-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Relay Anti-Amplification (H-18)    ║
-- ║  cluster.relayHandle dedup + per-peer rate limit     ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_relay_amplification.lua
--      (or `run /usr/lib/tests/test_relay_amplification.lua` inside TOS)
--
-- cluster.lua uses only lazy pcall(require, ...) internally, so it loads
-- standalone; crypto/computer requires fail gracefully and the module
-- falls back to raw-byte dedup keys and os.clock() timing.

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- cluster.lua relocated out of the base kernel into the optional cluster
-- package (TOS-Extras); load it from there.
local here = (arg and arg[0]) or "usr/lib/tests/test_relay_amplification.lua"
local base = here:gsub("[^/\\]*$", "")
local CL = "TOS-Extras/cluster/manager-skeleton/usr/lib/cluster/protocol.lua"
local candidates = {
  base .. "../../../../" .. CL,
  CL,
  "../" .. CL,
}
local cluster
for _, p in ipairs(candidates) do
  local chunk = loadfile(p)
  if chunk then cluster = chunk(); break end
end
if not cluster then
  print("FAIL: could not load cluster.lua")
  print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***")
  return false
end

local SELF = "selfAddr"
local function env(inner, opts)
  opts = opts or {}
  return {
    dest  = opts.dest or "destAddr",
    path  = opts.path or {},
    ttl   = opts.ttl or 3,
    inner = inner,
  }
end

print("=== Relay Anti-Amplification Tests ===")
print()

-- Malformed input
test("non-table envelope -> malformed",
  "malformed", cluster.relayHandle("nope", SELF).reason)

-- Loop detection still works (path contains self)
cluster._resetRelayState()
test("self in path -> loop",
  "loop", cluster.relayHandle(env("p", { path = { "a", SELF, "b" } }), SELF).reason)

-- TTL exhaustion still works
cluster._resetRelayState()
test("ttl 0 -> ttl_exceeded",
  "ttl_exceeded", cluster.relayHandle(env("p", { ttl = 0 }), SELF).reason)

-- Destination delivery bypasses dedup (delivering twice is fine)
cluster._resetRelayState()
local d1 = cluster.relayHandle(env("dpay", { dest = SELF }), SELF)
local d2 = cluster.relayHandle(env("dpay", { dest = SELF }), SELF)
test("dest==self first -> deliver", "deliver", d1.action)
test("dest==self repeat -> deliver (not deduped)", "deliver", d2.action)

-- Dedup: same inner payload forwarded twice within the window is dropped
cluster._resetRelayState()
local f1 = cluster.relayHandle(env("dup-payload"), SELF, nil, "peerA")
local f2 = cluster.relayHandle(env("dup-payload"), SELF, nil, "peerA")
test("first forward -> forward", "forward", f1.action)
test("duplicate inner -> duplicate", "duplicate", cluster.relayHandle and f2.reason)

-- Distinct payloads from the same peer up to the cap all forward,
-- then the next is rate_limited.
cluster._resetRelayState()
local MAX = cluster.TIMING.RELAY_RATE_MAX
local allForwarded = true
for i = 1, MAX do
  local r = cluster.relayHandle(env("rate-" .. i), SELF, nil, "peerB")
  if r.action ~= "forward" then allForwarded = false end
end
test("forwards up to RELAY_RATE_MAX all succeed", true, allForwarded)
local over = cluster.relayHandle(env("rate-over"), SELF, nil, "peerB")
test("forward past cap -> rate_limited", "rate_limited", over.reason)

-- A different peer has an independent budget.
local otherPeer = cluster.relayHandle(env("rate-other"), SELF, nil, "peerC")
test("different peer not rate_limited", "forward", otherPeer.action)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
