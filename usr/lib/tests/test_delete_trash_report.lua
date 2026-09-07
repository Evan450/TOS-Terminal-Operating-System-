-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a delete says where the file went             ║
-- ║                                                                ║
-- ║  Operator report, real emulator: "the trash seems to be broken  ║
-- ║  (or, if something's too large to put into the trash, it        ║
-- ║  doesn't say so)." Both halves were true, in different files.   ║
-- ║                                                                ║
-- ║  `rm` asked the trash to take the file and, when it refused --  ║
-- ║  "file too large for trash (N > M)" is one of its answers --    ║
-- ║  captured the reason into a local it never read, fell through   ║
-- ║  to a HARD delete, and printed "Removed: x". A file the         ║
-- ║  operator expected to be recoverable was gone, and the sentence ║
-- ║  explaining why had been computed and thrown away.              ║
-- ║                                                                ║
-- ║  The file browser's F8 never used the trash AT ALL -- it called ║
-- ║  fs.remove directly, under a dialog that said "This cannot be   ║
-- ║  undone", which was true only because of the bypass. Delete     ║
-- ║  from the browser, look in the trash, find nothing.             ║
-- ║                                                                ║
-- ║  Falling through is still right for a session that HAS no trash ║
-- ║  (a guest): their delete IS the irreversible thing they asked   ║
-- ║  for. It is wrong when the trash exists and refused.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_delete_trash_report.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_delete_trash_report.lua"
local base = here:gsub("[^/\\]*$", "")
local function readFile(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("a"); f:close(); return s
end
local function firstOf(paths)
  for _, p in ipairs(paths) do local s = readFile(p); if s then return s, p end end
end

local coreSrc = firstOf({ base .. "../../../tos/shell/panels/commands/core.lua",
                          "tos/shell/panels/commands/core.lua" })
local fbSrc   = firstOf({ base .. "../../../tos/shell/panels/filebrowser.lua",
                          "tos/shell/panels/filebrowser.lua" })
local trashSrc = firstOf({ base .. "../../../tos/kernel/trash.lua",
                           "tos/kernel/trash.lua" })
if not (coreSrc and fbSrc and trashSrc) then
  print("FAIL: could not read the delete paths")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); os.exit(1)
end

print("=== a delete says where the file went ===")
print()

-- ── The trash really does refuse an oversized file ────────────────
-- Drive the real module: if this stops returning a reason, the callers
-- below have nothing to report and this whole test is theatre.
print("-- kernel.trash refuses, with a reason --")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 1 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local BIG = 8 * 1024 * 1024        -- past the 4 MB default cap
local sizes = { ["/home/u/big.bin"] = BIG, ["/home/u/small.txt"] = 10 }
local dirs = { ["/home/u"] = true, ["/home/u/.trash"] = true }
local securefsStub = {
  normalize = function(p) return p end,
  -- Only paths that really are there. An `exists` that says yes to
  -- anything under the home directory makes trash.put's collision loop
  -- ("append ~N until a free slot") spin forever.
  exists = function(p) return sizes[p] ~= nil or dirs[p] == true end,
  isDirectory = function(p) return dirs[p] == true end,
  size = function(p) return sizes[p] or 0 end,
  list = function() return {} end,
  makeDirectory = function() return true end,
  rename = function(from, to) sizes[to] = sizes[from]; sizes[from] = nil; return true end,
  copy = function() return true end,
  remove = function(p) sizes[p] = nil; return true end,
  writeFile = function() return true end,
  readFile = function() return nil end,
}
package.loaded["kernel.securefs"] = securefsStub
package.loaded["kernel.serialize"] = { encode = function() return "{}" end,
                                       decode = function() return {} end }
package.loaded["kernel.users"] = { currentSession = function() return { user = "u" } end }

local okT, trash = pcall(require, "kernel.trash")
test("kernel.trash loads", okT and type(trash) == "table")
if okT and trash and trash.init then
  pcall(trash.init, { securefs = securefsStub, users = package.loaded["kernel.users"],
                      serialize = package.loaded["kernel.serialize"] })
end
if okT and trash and trash.put then
  local ok1, why = trash.put("/home/u/big.bin", { user = "u", home = "/home/u" })
  test("an oversized file is refused", ok1 == false)
  test("...and the reason names the size limit (" .. tostring(why) .. ")",
    type(why) == "string" and why:find("too large", 1, true) ~= nil)
end

-- ── `rm` must not throw that reason away ──────────────────────────
print()
print("-- rm reports it --")
local rmBody = coreSrc:match("C%.rm = function.-\n  end\n") or coreSrc
test("rm still captures the trash's reason", rmBody:find("local ok2, err2", 1, true) ~= nil)
test("...and now PRINTS it", rmBody:find('o("Not trashed: "', 1, true) ~= nil)
test("...and stops instead of hard-deleting behind the operator's back",
  rmBody:find("It is still there", 1, true) ~= nil)
test("...naming --hard as the way to force it",
  rmBody:find("--hard ", 1, true) ~= nil)
test("a session with NO trash still falls through (a guest's rm is final)",
  rmBody:find('why:find("no trash"', 1, true) ~= nil
  and rmBody:find("deleting " , 1, true) ~= nil)
test("the success message still points at restore",
  rmBody:find("use 'restore' to undo", 1, true) ~= nil)

-- ── F8 in the browser goes through the same door ──────────────────
print()
print("-- the file browser uses the trash too --")
local delBody = fbSrc:match("function M%.doDelete.-\nend\n") or fbSrc
test("it asks the trash first", delBody:find("trashMod.put", 1, true) ~= nil)
test("...and says the file is recoverable when it is",
  delBody:find("trash restore", 1, true) ~= nil)
test("...and only claims 'cannot be undone' when there is no trash",
  delBody:find('or "This cannot be undone."', 1, true) ~= nil)
test("system paths still bypass the trash, as rm does",
  delBody:find('path:match("^/tos")', 1, true) ~= nil)
test("a refusal leaves the file alone rather than hard-deleting it",
  delBody:find("Not trashed: ", 1, true) ~= nil
  and delBody:find("still there", 1, true) ~= nil)
test("a hard delete still surfaces fs.remove's own failure",
  delBody:find("Delete failed: ", 1, true) ~= nil)

-- ── The two paths agree ───────────────────────────────────────────
print()
print("-- the two delete paths agree --")
local function skipSet(body)
  local s = {}
  for p in body:gmatch('match%("%^(/%w+)"%)') do s[p] = true end
  return s
end
local rmSkip, fbSkip = skipSet(rmBody), skipSet(delBody)
local same = true
for k in pairs(rmSkip) do if not fbSkip[k] then same = false end end
for k in pairs(fbSkip) do if not rmSkip[k] then same = false end end
local names = {}
for k in pairs(rmSkip) do names[#names + 1] = k end
table.sort(names)
test("both skip the same system roots (" .. table.concat(names, " ") .. ")", same)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
