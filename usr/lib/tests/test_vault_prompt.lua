-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `vault` asks for its passphrase              ║
-- ║                                                                ║
-- ║  Every vault subcommand took the passphrase as an argument, so  ║
-- ║  it stayed in the seat's command history -- `history` and the   ║
-- ║  up arrow showed it to whoever sat down next. Leave it off (or  ║
-- ║  give "-") and it is asked for, unechoed; encrypting asks       ║
-- ║  twice, since that SETS it. A typed one still works.            ║
-- ║                                                                ║
-- ║  Drives the REAL vault command (commands/core.lua) over the     ║
-- ║  real kernel.vault and kernel.crypto, with an in-memory         ║
-- ║  securefs and a scripted prompt.                                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_vault_prompt.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_vault_prompt.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["component"] = { list = function() return function() return nil end end,
                                proxy = function() return nil end }
local _t = 0
package.loaded["computer"] = { uptime = function() _t = _t + 0.013; return _t end,
  freeMemory = function() return 123456 end, totalMemory = function() return 999999 end }

local crypto = require("kernel.crypto")
crypto.init()
local vault = require("kernel.vault")

-- ── An in-memory filesystem behind securefs ─────────────────────────
local files = {}
_G._TOS = { securefs = {
  readFile = function(p) return files[p] end,
  writeFile = function(p, d) files[p] = d; return true end,
} }

-- ── The real command table ─────────────────────────────────────────
local asked, answers = 0, {}
local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end, refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end, rootOnly = function() return true end,
  adminOnly = function() return true end, makeProgramEnv = function() end,
  dialog = function() end, drawAll = function() end,
  promptInput = function(_, _, masked)
    asked = asked + 1
    if not masked then error("a passphrase prompt must be masked") end
    return table.remove(answers, 1)
  end,
}
local S = { K = {}, E = {}, P = {}, F = {}, D = {}, U = {}, SC = {}, NM = {}, st = {},
            T = setmetatable({}, { __index = function() return 0 end }), W = 80, H = 25,
            cmdHistory = {} }
local C = {}
local chunk
for _, p in ipairs({ base .. "../../../tos/shell/panels/commands/core.lua",
                     "tos/shell/panels/commands/core.lua" }) do
  chunk = loadfile(p); if chunk then break end
end
test("commands/core.lua loads", chunk ~= nil)
if not chunk then print("*** TESTS FAILED ***"); os.exit(1) end
chunk()(C, S, deps)
test("it registers `vault`", type(C.vault) == "function")

local out = {}
local function run(args, ans)
  out, asked, answers = {}, 0, ans or {}
  C.vault(args, function(t) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n")
end
local function said(needle) return table.concat(out, "\n"):find(needle, 1, true) ~= nil end

print("=== vault asks for its passphrase ===")
print()

files["/secret.txt"] = "the launch codes"
run({ "encrypt", "/secret.txt", "/secret.vlt" }, { "hunter2", "hunter2" })
test("encrypt with no passphrase asks for it", asked == 2, asked)
test("...twice, because this sets it", asked == 2 and files["/secret.vlt"] ~= nil)
test("...and the file is encrypted under what was typed",
  files["/secret.vlt"] and vault.decrypt(files["/secret.vlt"], "hunter2") == "the launch codes")
test("...with no history note: nothing was typed on the line", not said("command history"))

run({ "decrypt", "/secret.vlt", "/back.txt", "-" }, { "hunter2" })
test("decrypt with '-' asks once", asked == 1, asked)
test("...and decrypts", files["/back.txt"] == "the launch codes")

files["/other.vlt"] = nil
run({ "encrypt", "/secret.txt", "/other.vlt" }, { "hunter2", "hunter3" })
test("a mistyped confirmation changes nothing", files["/other.vlt"] == nil and said("did not match"))

run({ "encrypt", "/secret.txt", "/other.vlt" }, { "" })
test("an empty answer cancels", files["/other.vlt"] == nil and said("Cancelled"))

run({ "decrypt", "/secret.txt", "/x.txt" }, { "anything" })
test("decrypting something that is not a vault blob never asks", asked == 0 and said("not a TOS vault blob"))

run({ "encrypt", "/secret.txt", "/typed.vlt", "swordfish" })
test("a typed passphrase still works", files["/typed.vlt"] and vault.decrypt(files["/typed.vlt"], "swordfish") == "the launch codes")
test("...without asking", asked == 0)
test("...and says it stays in the history", said("command history"))

files["/inplace.txt"] = "keep this"
run({ "encrypt-in-place", "/inplace.txt" }, { "pw", "pw" })
test("encrypt-in-place asks twice", asked == 2 and vault.isEncrypted(files["/inplace.txt"]))
run({ "encrypt-in-place", "/inplace.txt" }, { "pw", "pw" })
test("...and refuses to double-encrypt before asking anything", asked == 0 and said("Already encrypted"))
run({ "decrypt-in-place", "/inplace.txt" }, { "pw" })
test("decrypt-in-place asks once and restores it", asked == 1 and files["/inplace.txt"] == "keep this")

-- `vault tape` hands the passphrase to the tape command in-process.
local handed
C.tape = function(args) handed = args end
run({ "tape", "encrypt" }, { "tapepw", "tapepw" })
test("vault tape encrypt asks twice and hands over what was typed",
  asked == 2 and handed and handed[1] == "encrypt" and handed[2] == "tapepw")

deps.promptInput = nil
local C2 = {}
chunk()(C2, S, deps)
out = {}
C2.vault({ "encrypt", "/secret.txt", "/nope.vlt" }, function(t) out[#out + 1] = tostring(t) end)
test("with no way to ask, it says so instead of guessing", files["/nope.vlt"] == nil and said("Cannot ask"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
