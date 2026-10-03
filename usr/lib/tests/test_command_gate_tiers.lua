-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a command's registry tier is its real tier   ║
-- ║                                                                ║
-- ║  Two checks guard a command. The executor refuses a seat below ║
-- ║  the REGISTRY tier before the command runs, and many command   ║
-- ║  bodies then call adminOnly/rootOnly themselves. When the two  ║
-- ║  disagree, the registry is what `help`, `why` and the MANUAL's  ║
-- ║  tier marks are built from -- so they promise one thing and the ║
-- ║  body does another. Found 2026-10-03: useradd, userdel and      ║
-- ║  usermod registered ADMIN but root-only in their bodies; log    ║
-- ║  and scp registered USER but admin-only. An admin was offered   ║
-- ║  useradd by `help` and refused by it.                           ║
-- ║                                                                ║
-- ║  For every command whose body OPENS with a tier gate, the        ║
-- ║  registry tier must name the same tier. Read from the source:   ║
-- ║  the registry table in commands.lua, the bodies in commands/.   ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_command_gate_tiers.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function read(p)
  local h = assert(io.open(p, "rb")); local s = h:read("*a"); h:close()
  return (s:gsub("\r\n", "\n"))
end

-- ── The registry: name = { ..., tier = N, ... } ─────────────────────
local registry = {}
for line in read("tos/shell/panels/commands.lua"):gmatch("[^\n]+") do
  local name, tier = line:match('^%s*%[?"?([%w%-_]+)"?%]?%s*=%s*{.-tier%s*=%s*(%d)')
  if name then registry[name] = tonumber(tier) end
end

-- ── The bodies: C.name = function(...) whose first lines gate ───────
local GATE = { rootOnly = 3, adminOnly = 2 }
local gated, checked = {}, 0
for _, file in ipairs({ "core", "admin", "extras" }) do
  local src = read("tos/shell/panels/commands/" .. file .. ".lua")
  for name, body in src:gmatch("\n%s*C%.([%w_]+)%s*=%s*function%s*%b()\n(.-)\n%s*end\n") do
    -- Only a gate in the opening lines counts: a gate deeper in is a
    -- per-subcommand check (`pkg trust add`), not the command's tier.
    local head = body:match("^([^\n]*\n?[^\n]*\n?[^\n]*)") or ""
    local which = head:match("if not (rootOnly)%(o%)") or head:match("if not (adminOnly)%(o%)")
    if which then
      gated[#gated + 1] = { name = name, gate = GATE[which], file = file }
    end
  end
end

print("=== a command's registry tier is its real tier ===")
print()

test("the registry was read", next(registry) ~= nil)
test("gated commands were found", #gated >= 20, #gated)
for _, g in ipairs(gated) do
  checked = checked + 1
  local reg = registry[g.name]
  test(string.format("%s (%s.lua): registry tier matches its %s gate",
      g.name, g.file, g.gate == 3 and "root" or "admin"),
    reg == g.gate, "registry says " .. tostring(reg))
end

-- The five that disagreed, named, so the fix cannot quietly regress.
for name, want in pairs({ useradd = 3, userdel = 3, usermod = 3, log = 2, scp = 2 }) do
  test(name .. " is registered at tier " .. want, registry[name] == want, registry[name])
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
