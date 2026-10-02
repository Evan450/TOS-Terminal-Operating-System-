-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: every directory TOS runs code from is        ║
-- ║  protected, so an ADMIN cannot plant code there               ║
-- ║                                                                ║
-- ║  The protected set (securefs REMOVE_PROTECTED) stops even an   ║
-- ║  ADMIN writing /tos, /usr/lib, /usr/bin: code there runs as    ║
-- ║  the kernel, or as whoever types a command, root included.     ║
-- ║  Two code roots were missing, both OpenOS's, and both searched ║
-- ║  AHEAD of the TOS root they shadow:                            ║
-- ║    /lib  init.lua's require (before /usr/lib, in kernel _G).   ║
-- ║          The shell requires `mouse` at every start, so an      ║
-- ║          ADMIN writing /lib/mouse.lua ran as the kernel.       ║
-- ║    /bin  the shell's first trusted bin dir (before /usr/bin):  ║
-- ║          /bin/ssh.lua ran for root's `ssh`, with root's fs.     ║
-- ║                                                                ║
-- ║  The roots are READ FROM SOURCE -- init.lua's searchPaths and  ║
-- ║  helpers.lua's SYSTEM_BIN_DIRS -- so a code root added later   ║
-- ║  fails here until it is protected too.                         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_code_roots_protected.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_code_roots_protected.lua"
local base = here:gsub("[^/\\]*$", "")
local function readAll(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local h = io.open(p, "rb")
    if h then local s = h:read("*a"); h:close(); return s end
  end
end

print("=== code roots are protected ===")
print()

-- ── The roots, from the files that define them ─────────────────────
local initSrc    = readAll("init.lua")
local helpersSrc = readAll("tos/shell/panels/helpers.lua")
test("init.lua readable", initSrc ~= nil)
test("shell/panels/helpers.lua readable", helpersSrc ~= nil)
if not (initSrc and helpersSrc) then
  print(); print(string.format("Results: %d passed, %d failed", passed, failed))
  print("*** TESTS FAILED ***"); return false
end

local roots, seen = {}, {}
local function addRoot(dir, from)
  if dir and dir ~= "" and not seen[dir] then
    seen[dir] = true; roots[#roots + 1] = { dir = dir, from = from }
  end
end
local sp = initSrc:match("local searchPaths = (%b{})")
test("init.lua searchPaths found", sp ~= nil)
for pat in (sp or ""):gmatch('"([^"]+)"') do
  addRoot(pat:match("^(.-)/%?"), "require")          -- "/lib/?.lua" -> "/lib"
end
local bins = helpersSrc:match("M%.SYSTEM_BIN_DIRS%s*=%s*(%b{})")
test("helpers.lua SYSTEM_BIN_DIRS found", bins ~= nil)
for dir in (bins or ""):gmatch('"([^"]+)"') do addRoot(dir, "bin") end

test("the roots include /lib and /bin (else this proves nothing)",
  seen["/lib"] and seen["/bin"])
test("...and more than those two (" .. #roots .. " roots)", #roots > 2)

-- ── The REAL guard, through the REAL ACL ───────────────────────────
package.path = "tos/?.lua;" .. base .. "../../../tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end, freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
package.loaded["kernel.process"] = { currentSession = function() return nil end,
                                     yieldCooperative = function() end }

local written = {}
local kfs = require("kernel.fs")
local users = require("kernel.users")
users.init({ fs = { normalize = kfs.normalize, exists = function() return false end,
  readFile = function() return nil end, writeFile = function() return true end,
  makeDirectory = function() return true end },
  crypto = { init = function() end, hasHardware = function() return false end,
    salt = function(n) return string.rep("s", n or 16) end,
    hashPassword = function(pw, s) return "h:" .. pw .. s end } })
local securefs = require("kernel.securefs")
-- A recording fs under securefs: anything that reaches it was allowed.
securefs.init({ users = users, log = nil, fs = setmetatable({
  writeFile = function(p, c) written[p] = c; return true end,
}, { __index = kfs }) })

local T = users.TIER
local admin = { user = "adam", tier = T.ADMIN, home = "/home/adam" }
local root  = { user = "root", tier = T.ROOT,  home = "/root" }

for _, r in ipairs(roots) do
  local target = r.dir .. "/planted.lua"
  test(r.dir .. " (" .. r.from .. " root) is protected",
    securefs._isProtectedTarget(target, admin) ~= nil)
  -- And a case-folded spelling, which OC's disk resolves to the same
  -- file on a Windows or macOS host.
  test("..." .. r.dir:upper() .. " too",
    securefs._isProtectedTarget(r.dir:upper() .. "/planted.lua", admin) ~= nil)
end

-- End to end, the two plants that mattered.
for _, p in ipairs({ "/lib/mouse.lua", "/bin/ssh.lua" }) do
  written[p] = nil
  local ok, err = securefs.writeFile(p, "-- planted", admin)
  test("an ADMIN cannot write " .. p, not ok and written[p] == nil)
  test("...and is told it is a protected path",
    type(err) == "string" and err:find("protected system path", 1, true) ~= nil)
end

-- Root still can, once it stands the guard down for its own session:
-- the protected set is defence in depth, not a wall for the owner.
test("root arms the override", securefs.setOperatorOverride(root, true) == true)
local okR = securefs.writeFile("/lib/mouse.lua", "-- root's own", root)
test("...and may then write /lib", okR == true and written["/lib/mouse.lua"] == "-- root's own")
securefs.setOperatorOverride(root, false)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
