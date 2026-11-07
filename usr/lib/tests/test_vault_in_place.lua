-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: vault in place never leaves half a file      ║
-- ║                                                                ║
-- ║  `vault encrypt-in-place` wrote the blob back with writeFile,  ║
-- ║  which opens with truncation. Encrypting grows a file by about ║
-- ║  130 bytes, so on a disk with less free than that the write    ║
-- ║  ran out of room part way: the plaintext was gone, the blob    ║
-- ║  was not whole, and the plaintext had lived only in the        ║
-- ║  command's memory. Found in the sweep for in-place writes      ║
-- ║  after kernel.backup lost files.                               ║
-- ║                                                                ║
-- ║  Now: room for a second copy -> atomic; room only once the old ║
-- ║  bytes are freed -> in place, which cannot run short; neither  ║
-- ║  -> refused with nothing changed. The fake disk below models   ║
-- ║  OpenComputers: truncate on open, a hard capacity.             ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_vault_in_place.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_vault_in_place.lua"
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

-- ── A disk with a capacity, truncating on open ───────────────────
local files, capacity, calls = {}, 0, {}
local function used()
  local n = 0
  for _, d in pairs(files) do n = n + #d end
  return n
end
local secfs = {
  readFile = function(p) return files[p] end,
  spaceFree = function() return capacity - used() end,
  writeFile = function(p, d)
    calls.writeFile = (calls.writeFile or 0) + 1
    files[p] = ""                        -- open("w") truncates at once
    local room = capacity - used()
    if #d > room then
      files[p] = d:sub(1, room)          -- what fitted
      return false, "not enough space"
    end
    files[p] = d
    return true
  end,
  writeFileAtomic = function(p, d)
    calls.atomic = (calls.atomic or 0) + 1
    if #d > capacity - used() then return false, "not enough space" end
    files[p] = d                         -- temp written whole, then renamed over
    return true
  end,
}
_G._TOS = { securefs = secfs }

local deps = {
  rp = function(p) return p end,
  openViewTab = function() end, openEditTab = function() end, refreshBrowser = function() end,
  canRead = function() return true end, canWrite = function() return true end,
  canAccess = function() return true end, rootOnly = function() return true end,
  adminOnly = function() return true end, makeProgramEnv = function() end,
  dialog = function() end, drawAll = function() end,
  promptInput = function() return nil end,
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

local out = {}
local function run(args)
  out, calls = {}, {}
  C.vault(args, function(t) out[#out + 1] = tostring(t) end)
  return table.concat(out, "\n")
end
local PASS = "correct horse battery staple"
local PLAIN = string.rep("SECRET PLANS line\n", 2000)   -- 36000 bytes

-- A disk with `spare` bytes free beside the plaintext.
local function disk(spare)
  files = { ["/d/plans.txt"] = PLAIN }
  capacity = #PLAIN + spare
end

print("=== plenty of room: written atomically ===")
do
  disk(200000)
  local said = run({ "encrypt-in-place", "/d/plans.txt", PASS })
  test("it says it encrypted", said:find("Encrypted in place", 1, true) ~= nil, said)
  test("through the atomic write", calls.atomic == 1 and not calls.writeFile)
  test("and the file decrypts to the plaintext", vault.decrypt(files["/d/plans.txt"], PASS) == PLAIN)
end

print("=== room only once the old bytes are freed: in place ===")
do
  disk(352)   -- the headless runner's floppy, filled: 352 B free
  local said = run({ "encrypt-in-place", "/d/plans.txt", PASS })
  test("it still encrypts", said:find("Encrypted in place", 1, true) ~= nil, said)
  test("in place, because a second copy would not fit", calls.writeFile == 1 and not calls.atomic)
  test("and the file decrypts to the plaintext", vault.decrypt(files["/d/plans.txt"], PASS) == PLAIN)
end

print("=== less room than the blob grows by: refused, untouched ===")
do
  disk(50)
  local said = run({ "encrypt-in-place", "/d/plans.txt", PASS })
  test("it is refused", said:find("Not enough room", 1, true) ~= nil, said)
  test("saying nothing was changed", said:find("Nothing was changed", 1, true) ~= nil, said)
  test("the file is still the plaintext", files["/d/plans.txt"] == PLAIN,
    #(files["/d/plans.txt"] or ""))
  test("and nothing was written", not calls.writeFile and not calls.atomic)
end

print("=== decrypting in place on a full disk works: it shrinks ===")
do
  disk(200000)
  run({ "encrypt-in-place", "/d/plans.txt", PASS })
  capacity = used()                       -- now completely full
  local said = run({ "decrypt-in-place", "/d/plans.txt", PASS })
  test("it decrypts", said:find("Decrypted in place", 1, true) ~= nil, said)
  test("back to the plaintext", files["/d/plans.txt"] == PLAIN)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
