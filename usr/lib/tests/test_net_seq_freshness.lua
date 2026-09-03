-- ╔══════════════════════════════════════════════════════╗
-- ║  Regression Test: Net Replay Freshness (H-3)         ║
-- ║  Per-peer monotonic sequence + per-boot epoch:        ║
-- ║  reject non-increasing; accept genuine reboots;       ║
-- ║  reject replays from retired epochs.                  ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_net_seq_freshness.lua

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

-- net/init.lua requires component/computer at load time; preload stubs.
package.loaded["component"] = { list = function() return function() return nil end end }
package.loaded["computer"]  = { uptime = function() return 0 end }

local here = (arg and arg[0]) or "usr/lib/tests/test_net_seq_freshness.lua"
local base = here:gsub("[^/\\]*$", "")
local net
for _, p in ipairs({ base .. "../../../tos/kernel/net/init.lua",
    "tos/kernel/net/init.lua", "TOS-Dev/tos/kernel/net/init.lua" }) do
  local chunk = loadfile(p)
  if chunk then net = chunk(); break end
end
if not net or not net._seqCheck then
  print("FAIL: could not load net/init.lua / _seqCheck missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

local seqCheck = net._seqCheck
-- accepted(holder, peer, epoch, seq) -> true if accepted
local function accepted(holder, peer, epoch, seq)
  local ok = seqCheck(holder, peer, epoch, seq)
  return ok == true
end

print("=== Net Replay Freshness Tests ===")
print()

local H = {}
local PEER = "peerAddr"

-- Increasing sequence within an epoch is accepted.
test("epoch A seq 1 accepted", true,  accepted(H, PEER, "A", 1))
test("epoch A seq 2 accepted", true,  accepted(H, PEER, "A", 2))
test("epoch A seq 3 accepted", true,  accepted(H, PEER, "A", 3))

-- Replays / non-increasing within the epoch are rejected.
test("epoch A replay seq 2 rejected", false, accepted(H, PEER, "A", 2))
test("epoch A seq 3 (==max) rejected", false, accepted(H, PEER, "A", 3))
test("epoch A seq 1 (old) rejected",  false, accepted(H, PEER, "A", 1))

-- A genuine reboot (new epoch, counter restarts at 1) is accepted.
test("epoch B seq 1 accepted (reboot)", true, accepted(H, PEER, "B", 1))

-- A replay carrying the now-retired epoch A is rejected, even though its
-- seq (5) is higher than B's current max — this is the aged-out-nonce
-- replay the old code allowed.
test("retired epoch A seq 5 rejected", false, accepted(H, PEER, "A", 5))

-- Continue advancing in epoch B.
test("epoch B seq 1 replay rejected", false, accepted(H, PEER, "B", 1))
test("epoch B seq 2 accepted", true, accepted(H, PEER, "B", 2))

-- Legacy packet (no epoch/seq) defers to the nonce window (accepted here).
test("legacy (nil epoch) deferred/accepted", true, accepted(H, PEER, nil, nil))

-- Distinct peers are tracked independently.
test("different peer epoch A seq 1 accepted", true, accepted(H, "other", "A", 1))

-- Many retired epochs: after the bounded retire set overflows, a very old
-- epoch may be re-accepted, but the CURRENT-epoch monotonic guarantee and
-- recent-epoch rejection still hold. Walk several reboots and confirm the
-- current epoch always rejects a stale seq.
local H2, P2 = {}, "p2"
for i = 1, 12 do
  accepted(H2, P2, "E" .. i, 1)   -- 12 reboots, each starts at seq 1
end
test("current epoch rejects stale after many reboots", false,
  accepted(H2, P2, "E12", 1))
test("current epoch accepts advance after many reboots", true,
  accepted(H2, P2, "E12", 2))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print("*** TESTS FAILED ***")
  return false
else
  print("All tests passed.")
  return true
end
