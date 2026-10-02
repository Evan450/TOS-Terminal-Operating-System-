-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: cat, mkdir and touch take every path given    ║
-- ║                                                                ║
-- ║  All three read args[1] and ignored the rest, as rm did before  ║
-- ║  test_rm_targets.lua. `touch a b c` made a and said "Touched:   ║
-- ║  a"; `mkdir x y` made x; `cat a b` printed a alone. And         ║
-- ║  `mkdir -p dir` made a directory literally named "-p".          ║
-- ║                                                                ║
-- ║  Each path now runs the checks the single path always did,      ║
-- ║  independently: a refusal on one says so and the rest go on.    ║
-- ║                                                                ║
-- ║  Drives the REAL command table from shell/panels/commands/      ║
-- ║  core.lua against an in-memory filesystem.                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_multi_path_cmds.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_multi_path_cmds.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = "tos/?.lua;tos/?/init.lua;" .. base .. "../../../tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;" .. package.path
local freeMem = 1e6
package.loaded["computer"] = { uptime = function() return 0 end,
                               freeMemory = function() return freeMem end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local files, dirs
local function reset()
  files = { ["/tmp/a"] = "alpha\n", ["/tmp/b"] = "beta\n" }
  dirs  = { ["/"] = true, ["/tmp"] = true }
end
reset()

-- A path the caller may not write: canWrite refuses it, saying so, the
-- way the shell's real gate does.
local readOnly = { ["/tmp/locked"] = true, ["/tmp/ro"] = true }

local F = {
  isDirectory = function(p) return dirs[p] == true end,
  exists = function(p) return files[p] ~= nil or dirs[p] == true end,
  makeDirectory = function(p)
    if dirs[p] then return false end
    dirs[p] = true
    return true
  end,
  writeFile = function(p, d) files[p] = d; return true end,
  open = function(p)
    local data = files[p]
    if not data then return nil, "no such file: " .. p end
    local pos = 1
    return {
      read = function(_, n)
        if pos > #data then return nil end
        local c = data:sub(pos, pos + n - 1); pos = pos + n; return c
      end,
      close = function() end,
    }
  end,
}
local S = { F = F, T = setmetatable({}, { __index = function() return 0 end }),
            cwd = "/tmp", K = {}, W = 80, H = 25 }
local C = {}
local refreshes = 0
require("shell.panels.commands.core")(C, S, {
  rp = function(p) return p:sub(1, 1) == "/" and p or ("/tmp/" .. p) end,
  canWrite = function(p, o)
    if readOnly[p] then o("Permission denied: " .. p); return false end
    return true
  end,
  canRead = function(p, o)
    if readOnly[p] then o("Permission denied: " .. p); return false end
    return true
  end,
  refreshBrowser = function() refreshes = refreshes + 1 end,
})

local function run(cmd, ...)
  local out = {}
  C[cmd]({ ... }, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

print("=== cat, mkdir and touch take every path ===")
print()

-- touch
reset()
local said = run("touch", "x", "y", "z")
test("touch x y z creates x", files["/tmp/x"] == "")
test("...and y", files["/tmp/y"] == "")
test("...and z", files["/tmp/z"] == "")
test("...and reports each", said:find("Touched: y", 1, true) and said:find("Touched: z", 1, true))

reset()
said = run("touch", "x", "locked", "z")
test("a refused path is not created", files["/tmp/locked"] == nil)
test("...and the refusal is shown", said:find("Permission denied: /tmp/locked", 1, true) ~= nil)
test("...while the paths around it are", files["/tmp/x"] == "" and files["/tmp/z"] == "")

reset()
run("touch", "a")
test("touch leaves an existing file's contents alone", files["/tmp/a"] == "alpha\n")
test("touch with no path prints usage", run("touch"):find("Usage: touch", 1, true) ~= nil)

-- mkdir
reset()
said = run("mkdir", "d1", "d2")
test("mkdir d1 d2 creates d1", dirs["/tmp/d1"] == true)
test("...and d2", dirs["/tmp/d2"] == true)
test("...and reports each", said:find("Created: d1", 1, true) and said:find("Created: d2", 1, true))

reset()
said = run("mkdir", "d1", "ro/sub", "d2")
test("a refused mkdir does not stop the next", dirs["/tmp/d1"] and dirs["/tmp/d2"])
test("...and says why", said:find("Permission denied: /tmp/ro", 1, true) ~= nil)

reset()
run("mkdir", "-p", "deep")
test("mkdir -p does not make a directory called -p", dirs["/tmp/-p"] == nil)
test("...and makes the one asked for", dirs["/tmp/deep"] == true)

reset()
said = run("mkdir", "tmp2", "/tmp")
test("an existing directory is named as such", said:find("Already exists: /tmp", 1, true) ~= nil)
said = run("mkdir", "-p", "/tmp")
test("...and -p makes it a quiet success", said == "")
test("mkdir with no path prints usage", run("mkdir"):find("Usage: mkdir", 1, true) ~= nil)
test("mkdir -p alone prints usage", run("mkdir", "-p"):find("Usage: mkdir", 1, true) ~= nil)

-- cat
reset()
said = run("cat", "a", "b")
test("cat a b prints a", said:find("alpha", 1, true) ~= nil)
test("...and b, in order", said:find("beta", 1, true) ~= nil
  and said:find("alpha", 1, true) < said:find("beta", 1, true))

reset()
said = run("cat", "a", "missing", "b")
test("a missing file is named", said:find("Cannot read: missing", 1, true) ~= nil)
test("...and the files around it still print", said:find("alpha", 1, true) and said:find("beta", 1, true))

-- Memory running short stops the whole command, not just the one file:
-- starting the next file is exactly what the floor exists to prevent.
reset()
freeMem = 0
said = run("cat", "a", "b")
freeMem = 1e6
test("low memory stops cat with the note", said:find("memory is low", 1, true) ~= nil)
test("...and does not start the next file", said:find("beta", 1, true) == nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
