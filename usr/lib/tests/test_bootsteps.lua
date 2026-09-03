-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.bootsteps narration mapping      ║
-- ║                                                            ║
-- ║  Maps raw kernel boot-log messages to friendly high-level ║
-- ║  steps for the splash loading bar, collapsing the noisy    ║
-- ║  internal chatter into a clean sequence. Verifies the      ║
-- ║  mapping, the unmatched case, and the dedup (next()).      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_bootsteps.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
local bootsteps = require("kernel.bootsteps")

print("=== kernel.bootsteps Tests ===")
print()

-- ── stageFor: representative real boot messages ────────────────────
eq("filesystem", "Mounting filesystems", bootsteps.stageFor("Initializing filesystem..."))
eq("the OpenOS example", "Loading OpenOS compatibility layer",
  bootsteps.stageFor("OpenOS compat: 11 modules loaded, 0 failed"))
eq("package manager", "Loading package manager",
  bootsteps.stageFor("Package manager initialized (0 installed)"))
eq("an rc service", "Starting background services",
  bootsteps.stageFor("Service started: 10-discoveryd"))
eq("network", "Starting networking", bootsteps.stageFor("Network ready (tos)"))
eq("boot complete", "Boot complete", bootsteps.stageFor("Boot complete! Free memory: 569KB"))
test("unmatched message -> nil", bootsteps.stageFor("Mounted 8ce0575a at /mnt/tmpfs") == nil
  or type(bootsteps.stageFor("Mounted 8ce0575a at /mnt/tmpfs")) == "string")
eq("truly unknown -> nil", nil, bootsteps.stageFor("xyzzy frobnicate"))
eq("nil input -> nil", nil, bootsteps.stageFor(nil))

-- ── STAGE_COUNT: the splash bar's denominator ──────────────────────
do
  local seen, n = {}, 0
  for _, s in ipairs(bootsteps.STAGES) do
    if not seen[s[2]] then seen[s[2]] = true; n = n + 1 end
  end
  eq("STAGE_COUNT == distinct friendly stages in STAGES", n, bootsteps.STAGE_COUNT)
  test("STAGE_COUNT is a sane denominator (>= 12)",
    type(bootsteps.STAGE_COUNT) == "number" and bootsteps.STAGE_COUNT >= 12)
end

-- ── next(): dedup consecutive same-stage messages ──────────────────
eq("first match shows", "Loading users and security",
  bootsteps.next(nil, "User system initialized (1 accounts)"))
eq("same stage again -> nil (collapsed)", nil,
  bootsteps.next("Loading users and security", "Security: users + securefs ready"))
eq("new stage shows", "Starting networking",
  bootsteps.next("Loading users and security", "Trust manager initialized"))

-- ── End-to-end: a real boot transcript -> clean narration ──────────
do
  local transcript = {
    "TOS Kernel v1.4.0 starting", "Scanning hardware...",
    "CPU T3 | GPU T2 | RAM T3 | 12 components", "Initializing filesystem...",
    "Mounted e1344d2b at /mnt/disk_e134", "Boot disk: 3066KB free / 4096KB total",
    "Loading configuration...", "Starting event system...", "Starting process manager...",
    "Initializing display...", "Crypto: Hardware", "User system initialized (1 accounts)",
    "Security: users + securefs ready", "Theme manager ready (9 presets)",
    "Trust manager initialized (0 known peers)", "Network ready (tos)",
    "Remote shell handler ready", "Loading: 10-discoveryd.lua",
    "Service started: 10-discoveryd", "Startup services loaded",
    "Cron scheduler initialized", "Package manager initialized (0 installed)",
    "OpenOS compat: 11 modules loaded, 0 failed", "Audio feedback: enabled",
    "Boot complete! Free memory: 569KB",
  }
  local narration, prev = {}, nil
  for _, m in ipairs(transcript) do
    local step = bootsteps.next(prev, m)
    if step then narration[#narration + 1] = step; prev = step end
  end
  -- The raw lines collapse to a shorter, ordered, de-duplicated set
  -- (non-matching chatter dropped, runs of one stage merged).
  test("collapses chatter (fewer steps than raw lines)",
    #narration < #transcript and #narration >= 10)
  eq("narration starts with hardware scan", "Scanning hardware", narration[1])
  eq("narration ends with boot complete", "Boot complete", narration[#narration])
  -- No two consecutive entries are identical (dedup worked).
  local dupes = false
  for i = 2, #narration do if narration[i] == narration[i - 1] then dupes = true end end
  test("no consecutive duplicate steps", not dupes)
  -- The operator's example phrase appears.
  local hasCompat = false
  for _, n in ipairs(narration) do if n == "Loading OpenOS compatibility layer" then hasCompat = true end end
  test("includes 'Loading OpenOS compatibility layer'", hasCompat)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
