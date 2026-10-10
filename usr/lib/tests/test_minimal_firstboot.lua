-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a low-memory first boot still sets root's    ║
-- ║  password                                                      ║
-- ║                                                                ║
-- ║  Under 32 KB free at the login step, TOS uses a minimal login  ║
-- ║  that asks for "root password". On a FRESH install that is the ║
-- ║  default, "root", which the screen never said -- and typing it ║
-- ║  gave the restricted first-boot token (GUEST tier, password    ║
-- ║  change only), so the operator landed in a shell that could do  ║
-- ║  nothing. Seen on a T1 machine at 1,280 KB with an internet    ║
-- ║  card, on the headless machine (2026-10-09).                   ║
-- ║                                                                ║
-- ║  minimalFirstBoot is LIFTED from tos/kernel/init.lua and run   ║
-- ║  against a fake 50-column screen and a fake user module.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_minimal_firstboot.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local src = assert(io.open("tos/kernel/init.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local body = src:match("(local function minimalFirstBoot.-end)%s*%-%-%[%[/TEST%-EXTRACT%-FB%]%]")
test("found minimalFirstBoot in tos/kernel/init.lua", body ~= nil)
if not body then print("*** TESTS FAILED ***"); os.exit(1) end
local minimalFirstBoot = assert(load(body .. "\nreturn minimalFirstBoot", "=minimalFirstBoot", "t"))()

-- The call site: minimal login asks it first.
test("minimalAuth runs it before asking for the root password",
  (src:find("minimalFirstBoot(display, usersmod, computer.pullSignal, W, T)", 1, true) or math.huge)
  < (src:find('"Low memory mode. Enter root password."', 1, true) or 0))

local W = 50
local T = setmetatable({}, { __index = function(_, k) return k end })
local lines
local d = {
  set = function(x, y, text) lines[#lines + 1] = { x = x, y = y, text = text } end,
  fill = function() end,
}

local function keys(...)
  local q = {}
  for _, word in ipairs({ ... }) do
    for c in word:gmatch(".") do q[#q + 1] = { "key_down", "kb", c:byte(), 0 } end
    q[#q + 1] = { "key_down", "kb", 13, 28 }
  end
  -- Keys go to the input polls (0.5 s); the pauses after a message (1 s,
  -- 1.5 s) time out empty, as they do when nobody types. Running dry is an
  -- error, not a hang.
  return function(t)
    if t ~= 0.5 then return nil end
    local s = table.remove(q, 1)
    if s then return table.unpack(s) end
    error("the prompt asked for more keys than the test typed", 0)
  end, q
end

print("=== a low-memory first boot ===")
print()

do
  lines = {}
  local calls = {}
  local users = {
    getUser = function(n) return n == "root" and { firstBoot = true } or nil end,
    login = function(u, p) calls[#calls + 1] = "login " .. u .. "/" .. p; return "TOKEN" end,
    changePassword = function(a, u, old, new)
      calls[#calls + 1] = table.concat({ "change", a, u, old, new }, " "); return true end,
    promoteAfterFirstBoot = function(t) calls[#calls + 1] = "promote " .. t; return true end,
  }
  local pull = keys("abc", "abc", "secret1", "secret2", "secret1", "secret1")
  local tok = minimalFirstBoot(d, users, pull, W, T)
  local all = {}
  for _, l in ipairs(lines) do all[#all + 1] = l.text end
  local text = table.concat(all, " | ")
  test("it says this is a first boot and asks for root's new password",
    text:find("First boot", 1, true) ~= nil and text:find("set a password for root", 1, true) ~= nil, text)
  test("a short password is refused", text:find("6+ characters", 1, true) ~= nil)
  test("a mismatch is refused", text:find("don't match", 1, true) ~= nil)
  test("the default is replaced from the default",
    calls[1] == "login root/root" and calls[2] == "change root root root secret1", table.concat(calls, "; "))
  test("...and the session promoted out of first-boot", calls[3] == "promote TOKEN")
  test("it hands back the token to start TOS with", tok == "TOKEN")
  test("it never echoes a password", text:find("secret", 1, true) == nil)
  local widest = 0
  for _, l in ipairs(lines) do widest = math.max(widest, l.x + #l.text - 1) end
  test("every line fits a 50-column Tier 1 screen", widest <= W, widest)
end

do
  lines = {}
  local users = { getUser = function() return { firstBoot = false } end }
  test("a machine that is NOT on its first boot is left to the normal prompt",
    minimalFirstBoot(d, users, function() error("should not read keys") end, W, T) == nil and #lines == 0)
end

do
  lines = {}
  local calls = 0
  local users = {
    getUser = function() return { firstBoot = true } end,
    login = function() return "T" end,
    changePassword = function() calls = calls + 1
      if calls == 1 then return false, "disk is read-only" end; return true end,
    promoteAfterFirstBoot = function() return true end,
  }
  local tok = minimalFirstBoot(d, users, keys("goodpass", "goodpass", "goodpass", "goodpass"), W, T)
  local all = {}
  for _, l in ipairs(lines) do all[#all + 1] = l.text end
  test("a failed change says why and asks again",
    table.concat(all, " "):find("disk is read-only", 1, true) ~= nil and tok == "T")
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
