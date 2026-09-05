-- ╔══════════════════════════════════════════════════════╗
-- ║  Test: tape-authenticator (keycard + encrypted log)    ║
-- ║                                                        ║
-- ║  Loads the module inside a faithful fake of the pkg     ║
-- ║  sandbox (crypto/vault capability globals, an in-       ║
-- ║  memory tape drive, kernel.* requires raise) and walks   ║
-- ║  the full lifecycle: init → verify → log add/list/      ║
-- ║  remove/passwd/clear → tamper detection → legacy v1.     ║
-- ╚══════════════════════════════════════════════════════╝
-- Run: lua modules/tape-authenticator/test_tape_auth.lua  (from TOS-Extras root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "modules/tape-authenticator/test_tape_auth.lua"
local base = here:gsub("[^/\\]*$", "")

-- ── Stub crypto (deterministic 64-hex "HMAC") ────────────────
local function hex64(s)
  local h1, h2 = 5381, 52711
  for i = 1, #s do
    local b = s:byte(i)
    h1 = (h1 * 33 + b) % 4294967296
    h2 = (h2 * 31 + b) % 4294967296
  end
  return (string.format("%08x%08x", h1, h2)):rep(4)
end
local SECRET = string.rep("\7", 32)
local adminMode = true
local cryptoStub = {
  hash = hex64,
  hmac = function(k, m) return hex64(k .. "\0" .. m) end,
  ctEquals = function(a, b) return a == b end,
  random = function(n) return string.rep("r", n or 32) end,
  secret = function()
    if adminMode then return SECRET end
    return nil, "crypto.secret requires an admin session"
  end,
}

-- ── Stub vault (reversible, passphrase-checked) ──────────────
local VMAGIC = "VSTUB1\0"
local vaultStub = {
  encrypt = function(plain, pass)
    return VMAGIC .. string.char(#pass) .. pass .. plain, { algo = "stub" }
  end,
  decrypt = function(blob, pass)
    if blob:sub(1, #VMAGIC) ~= VMAGIC then return nil, "not a vault blob" end
    local plen = blob:byte(#VMAGIC + 1)
    local stored = blob:sub(#VMAGIC + 2, #VMAGIC + 1 + plen)
    if stored ~= pass then return nil, "MAC mismatch (wrong passphrase?)" end
    return blob:sub(#VMAGIC + 2 + plen), { algo = "stub" }
  end,
  isEncrypted = function(s) return s:sub(1, #VMAGIC) == VMAGIC end,
}

-- ── Stub tape drive over an in-memory buffer ─────────────────
local function makeDrive(size)
  local d = { data = string.rep("\0", size), pos = 0, size = size }
  function d.isReady() return true end
  function d.getSize() return d.size end
  function d.stop() end
  function d.seek(n)
    local np = math.max(0, math.min(d.size, d.pos + n))
    local moved = np - d.pos; d.pos = np; return moved
  end
  function d.read(n)
    local chunk = d.data:sub(d.pos + 1, math.min(d.size, d.pos + n))
    d.pos = d.pos + #chunk
    return chunk
  end
  function d.write(s)
    s = s:sub(1, math.max(0, d.size - d.pos))
    d.data = d.data:sub(1, d.pos) .. s .. d.data:sub(d.pos + #s + 1)
    d.pos = d.pos + #s
    return true
  end
  return d
end

-- ── Fake sandbox environment ─────────────────────────────────
local drive = makeDrive(4096)
local t = 0
local computerStub = {
  uptime = function() t = t + 1; return t end,
  pullSignal = function() return nil end,
}
local componentStub = {
  list = function(ctype)
    local done = false
    return function()
      if done or ctype ~= "tape_drive" then return nil end
      done = true; return "tape-addr", "tape_drive"
    end
  end,
  proxy = function() return drive end,
}
local function sandboxRequire(name)
  if name == "component" then return componentStub end
  if name == "computer" then return computerStub end
  if type(name) == "string" and name:sub(1, 7) == "kernel." then
    error("sandbox: cannot require kernel module '" .. name .. "'", 2)
  end
  error("sandbox: module '" .. tostring(name) .. "' is not on the allowed list", 2)
end
local env = {
  assert = assert, error = error, pcall = pcall, xpcall = xpcall,
  type = type, tostring = tostring, tonumber = tonumber,
  pairs = pairs, ipairs = ipairs, next = next, select = select,
  math = math, string = string, table = table,
  require = sandboxRequire,
  crypto = cryptoStub, vault = vaultStub,
}
env._G = env

local out = {}
local o = function(text) out[#out + 1] = tostring(text) end
local function outHas(needle)
  for _, l in ipairs(out) do if l:find(needle, 1, true) then return true end end
  return false
end
local function reset() out = {} end

-- ── Load the module ──────────────────────────────────────────
local src
for _, p in ipairs({ base .. "init.lua", "modules/tape-authenticator/init.lua" }) do
  local f = io.open(p, "r")
  if f then src = f:read("*a"); f:close(); break end
end
local chunk, lerr = load(src or "", "=pkg:tape-authenticator", "t", env)
if not chunk then
  print("FAIL: load error: " .. tostring(lerr))
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local okRun, mod = pcall(chunk)

print("=== tape-authenticator Tests ===")
print()
test("entry loads under sandbox env", true, okRun and type(mod) == "table")
local cmd = mod and mod.commands and mod.commands["tape-auth"]
test("commands map uses the proper name->fn shape", "function", type(cmd))
if type(cmd) ~= "function" then
  print("Results: " .. passed .. " passed, " .. (failed + 1) .. " failed")
  print("*** TESTS FAILED ***"); return false
end

-- ── help / blank tape ────────────────────────────────────────
reset(); cmd({}, o)
test("no args -> help", true, outHas("Tape Authenticator"))
reset(); cmd({ "verify" }, o)
test("blank tape -> bad magic", true, outHas("bad magic"))

-- ── Admin gate on minting ────────────────────────────────────
adminMode = false
reset(); cmd({ "init", "Operator-7" }, o)
test("non-admin cannot init", true, outHas("admin"))
adminMode = true

-- ── init + verify + info ─────────────────────────────────────
reset(); cmd({ "init", "Operator-7" }, o)
test("init succeeds", true, outHas("Keycard initialized"))
reset(); cmd({ "verify" }, o)
test("verify VALID", true, outHas("VALID: label=Operator-7"))
reset(); cmd({ "info" }, o)
test("info shows label without secret", true, outHas("Operator-7"))
test("info reports empty log", true, outHas("log: empty"))

-- verify needs the admin-gated secret
adminMode = false
reset(); cmd({ "verify" }, o)
test("non-admin cannot verify", true, outHas("admin"))
adminMode = true

-- ── Personal log lifecycle (no admin needed) ─────────────────
adminMode = false
reset(); cmd({ "log", "add", "hunter2", "first", "shift", "done" }, o)
test("log add #1 (non-admin ok)", true, outHas("Logged entry #1"))
reset(); cmd({ "log", "add", "hunter2", "reactor", "refueled" }, o)
test("log add #2", true, outHas("Logged entry #2"))
reset(); cmd({ "log", "list", "hunter2" }, o)
test("list shows both entries", true,
  outHas("first shift done") and outHas("reactor refueled"))
test("list shows count", true, outHas("(2 entries)"))

reset(); cmd({ "log", "list", "wrongpass" }, o)
test("wrong passphrase refused", true, outHas("Cannot decrypt log"))

reset(); cmd({ "log", "remove", "hunter2", "1" }, o)
test("remove entry 1", true, outHas("Removed:") and outHas("first shift done"))
reset(); cmd({ "log", "list", "hunter2" }, o)
test("one entry remains", true, outHas("(1 entries)") and outHas("reactor refueled"))

-- Identity survives log edits.
adminMode = true
reset(); cmd({ "verify" }, o)
test("verify still VALID after log edits", true, outHas("VALID: label=Operator-7"))
reset(); cmd({ "info" }, o)
test("info reports encrypted log bytes", true, outHas("(encrypted)"))

-- init refuses to nuke a card that has a log
reset(); cmd({ "init", "Imposter" }, o)
test("init refuses over an existing log", true, outHas("WITH a personal log"))

-- passphrase change
adminMode = false
reset(); cmd({ "log", "passwd", "hunter2", "correct-horse" }, o)
test("log passwd", true, outHas("passphrase changed"))
reset(); cmd({ "log", "list", "correct-horse" }, o)
test("new passphrase works", true, outHas("reactor refueled"))
reset(); cmd({ "log", "list", "hunter2" }, o)
test("old passphrase dead", true, outHas("Cannot decrypt log"))

-- clear
reset(); cmd({ "log", "clear", "correct-horse" }, o)
test("log clear", true, outHas("Log cleared"))
reset(); cmd({ "log", "list", "correct-horse" }, o)
test("cleared log lists empty", true, outHas("Log is empty"))

-- ── Tamper detection ─────────────────────────────────────────
adminMode = true
do
  -- Flip one byte inside the label region of the identity block.
  local pos = 7 + 4 + 2 + 1  -- first label byte (1-indexed)
  local orig = drive.data
  drive.data = orig:sub(1, pos - 1)
    .. string.char((orig:byte(pos) + 1) % 256) .. orig:sub(pos + 1)
  reset(); cmd({ "verify" }, o)
  test("tampered label -> INVALID", true, outHas("INVALID"))
  drive.data = orig
  reset(); cmd({ "verify" }, o)
  test("restored tape -> VALID again", true, outHas("VALID"))
end

-- ── Legacy TAUTH1 card verifies read-only ────────────────────
do
  local function p16(n) return string.char(n & 0xFF, (n >> 8) & 0xFF) end
  local function p32(n)
    return string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
  end
  local body = "TAUTH1\0" .. p32(99) .. p16(3) .. "old"
  local image = body .. cryptoStub.hmac(SECRET, body)
  drive.data = image .. string.rep("\0", drive.size - #image)
  reset(); cmd({ "verify" }, o)
  test("TAUTH1 card verifies", true, outHas("VALID: label=old"))
  test("...flagged as legacy", true, outHas("legacy"))
  reset(); cmd({ "log", "add", "pw", "note" }, o)
  test("log on TAUTH1 -> upgrade hint", true, outHas("re-run `tape-auth init`"))
end

-- ── OOM guard: reads STREAM only the card, not the whole tape ─
-- The old readWholeTape() slurped getSize() bytes into one Lua string, which
-- OOMs a real 4 MB+ tape even on tier-3.5 RAM. readCard must touch only the
-- few-KB keycard region near the front. Prove it by counting bytes served.
do
  local big = makeDrive(1024 * 1024)        -- 1 MB tape
  local served = 0
  local rawRead = big.read
  big.read = function(n) local c = rawRead(n); served = served + #c; return c end
  drive = big                               -- component.proxy returns this now
  adminMode = true
  reset(); cmd({ "init", "BigKey" }, o)
  test("init on a 1MB tape succeeds", true, outHas("Keycard initialized"))
  served = 0
  reset(); cmd({ "verify" }, o)
  test("verify on 1MB tape is VALID", true, outHas("VALID: label=BigKey"))
  test("verify streamed only the card (<4KB of a 1MB tape)", true, served < 4096)
  -- info on an admin session now authenticates inline (no "run verify" nag).
  served = 0
  reset(); cmd({ "info" }, o)
  test("info authenticates inline for admin (VALID)", true, outHas("VALID"))
  test("info does NOT nag to run verify when admin", false, outHas("Run `tape-auth verify`"))
  test("info also streamed only the card", true, served < 4096)
end

-- ── Personal menu: separator + first-add passphrase adoption ──
-- #FIX (emulator round 7). The shipped usage text said
--     tape-auth menu add <pass> <Label> | <command>
-- but the TOS shell parses an unquoted "|" as a PIPE, so it split the
-- line before this package saw it: the operator typed
--     tape-auth menu add 111111 test | doctor
-- and `doctor` ran on the computer instead. "--" is the separator now.
adminMode = false
do
  reset(); cmd({ "menu", "add", "tapepw", "Diagnostics", "--", "doctor" }, o)
  test("menu add with the -- separator", true, outHas("Added menu item #1"))
  reset(); cmd({ "menu", "list", "tapepw" }, o)
  test("the item stored the label", true, outHas("Diagnostics"))
  test("the item stored the command", true, outHas("doctor"))

  -- A quoted "|" survives the shell and must still work, so nobody who
  -- learned the old form is stranded.
  reset(); cmd({ "menu", "add", "tapepw", "Power", "|", "status" }, o)
  test("a quoted | still works", true, outHas("Added menu item #2"))

  -- THE REPORTED SYMPTOM: the shell ate everything after the "|", so the
  -- package is handed a bare label. It must explain that, not just
  -- reprint usage.
  reset(); cmd({ "menu", "add", "tapepw", "test" }, o)
  test("a separator-less add is refused", false, outHas("Added menu item"))
  test("...and names the shell pipe as the cause", true, outHas("shell PIPE"))
  test("...and shows the working form", true, outHas("--"))
end

-- The FIRST add on a fresh tape silently SET the passphrase, which reads
-- as "it already knew my password" (the operator reused their login
-- password and concluded tape-auth had read it). It says so now.
do
  drive = makeDrive(4096)
  adminMode = true                      -- minting a card is an admin action
  reset(); cmd({ "init", "Keycard" }, o)
  adminMode = false                     -- everything below is operator-tier
  reset(); cmd({ "menu", "add", "111111", "First", "--", "doctor" }, o)
  test("first add succeeds", true, outHas("Added menu item #1"))
  test("first add WARNS that it just set the passphrase", true,
    outHas("now") and outHas("passphrase"))
  test("...and says not to reuse the login password", true,
    outHas("login password"))

  -- Second add is no longer 'fresh', so no warning — and a wrong
  -- passphrase is now genuinely refused.
  reset(); cmd({ "menu", "add", "111111", "Second", "--", "log" }, o)
  test("second add does not repeat the warning", false, outHas("login password"))
  reset(); cmd({ "menu", "add", "wrongpw", "Third", "--", "log" }, o)
  test("a wrong passphrase is refused once the menu exists", true,
    outHas("Cannot decrypt menu"))

  -- And the passphrase can be changed without wiping the menu.
  reset(); cmd({ "menu", "passwd", "111111", "betterpw" }, o)
  test("menu passwd changes it", true, outHas("Menu passphrase changed"))
  reset(); cmd({ "menu", "list", "betterpw" }, o)
  test("the items survived the change", true, outHas("First") and outHas("Second"))
  reset(); cmd({ "menu", "list", "111111" }, o)
  test("the old passphrase no longer opens it", true, outHas("Cannot decrypt menu"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
