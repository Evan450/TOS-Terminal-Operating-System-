-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: commands say what actually happened          ║
-- ║                                                                ║
-- ║  From the 2026-10-31 command pass, where bad input read like   ║
-- ║  success: `du /nothere` answered 0B, `touch` on a directory    ║
-- ║  said Touched, `mv f /dir/nothere/f` built the missing         ║
-- ║  directory without a word (a disk's rename makes parents), and ║
-- ║  `compress` on a tiny file said "-113% smaller".               ║
-- ║                                                                ║
-- ║  Drives the REAL command table from shell/panels/commands/     ║
-- ║  core.lua against an in-memory filesystem. Its rename makes    ║
-- ║  parents, as OC's does.                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_command_honesty.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
                               freeMemory = function() return 1e6 end }
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }

local files, dirs
local function reset()
  files = { ["/tmp/a"] = "alpha\n", ["/tmp/tiny"] = "12345678" }
  dirs = { ["/"] = true, ["/tmp"] = true, ["/tmp/sub"] = true }
end
reset()

local F = {
  isDirectory = function(p) return dirs[p] == true end,
  exists = function(p) return files[p] ~= nil or dirs[p] == true end,
  size = function(p) return files[p] and #files[p] or 0 end,
  list = function(p)
    local out = {}
    local prefix = (p:gsub("/$", "")) .. "/"
    for k in pairs(files) do
      local rest = k:sub(1, #prefix) == prefix and k:sub(#prefix + 1)
      if rest and not rest:find("/", 1, true) then out[#out + 1] = rest end
    end
    return out
  end,
  join = function(a, b) return (a:gsub("/$", "")) .. "/" .. b end,
  readFile = function(p) return files[p] end,
  writeFile = function(p, d) files[p] = d; return true end,
  remove = function(p) files[p] = nil; return true end,
  rename = function(a, b)
    local parent = b:match("^(.*)/[^/]+$")
    if parent and parent ~= "" then dirs[parent] = true end
    files[b], files[a] = files[a], nil
    return true
  end,
}
local storedPack = {
  available = function() return true end,
  pack = function(data) return "HEADER___" .. data, "stored", #data, #data + 9 end,
}
local S = { F = F, T = setmetatable({}, { __index = function() return 0 end }),
            cwd = "/tmp", W = 80, H = 25,
            K = { getCompress = function() return storedPack end } }
local C = {}
require("shell.panels.commands.core")(C, S, {
  rp = function(p) return p:sub(1, 1) == "/" and p or ("/tmp/" .. p) end,
  canWrite = function() return true end,
  canRead = function() return true end,
  refreshBrowser = function() end,
})

local function run(cmd, ...)
  local out = {}
  C[cmd]({ ... }, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

print("=== du ===")
do
  local said = run("du", "/tmp/nothere")
  test("a path that is not there says so", said:find("No such file", 1, true) ~= nil, said)
  test("and no size is printed", not said:find("0B", 1, true), said)
  test("a real file still sizes", run("du", "/tmp/a"):find("total", 1, true) ~= nil)
  test("a real directory still sizes", run("du", "/tmp"):find("total", 1, true) ~= nil)
end

print("=== touch ===")
do
  local said = run("touch", "/tmp/sub")
  test("a directory is not touched", not said:find("Touched", 1, true), said)
  test("and it says what it is", said:find("Is a directory", 1, true) ~= nil, said)
  test("a file still is", run("touch", "/tmp/new"):find("Touched", 1, true) ~= nil)
end

print("=== mv ===")
do
  reset()
  local said = run("mv", "/tmp/a", "/tmp/nothere/deep/a")
  test("a missing parent is refused", said:find("No such directory", 1, true) ~= nil, said)
  test("the file stays where it was", files["/tmp/a"] == "alpha\n")
  test("no directory was built", dirs["/tmp/nothere/deep"] == nil and dirs["/tmp/nothere"] == nil)
  reset()
  said = run("mv", "/tmp/ghost", "/tmp/b")
  test("a missing source says so", said:find("No such file", 1, true) ~= nil, said)
  reset()
  run("mv", "/tmp/a", "/tmp/sub")
  test("moving onto a directory still moves into it", files["/tmp/sub/a"] == "alpha\n")
  reset()
  run("mv", "/tmp/a", "/tmp/b")
  test("a plain rename still works", files["/tmp/b"] == "alpha\n" and files["/tmp/a"] == nil)
end

print("=== compress ===")
do
  reset()
  local said = run("compress", "-k", "/tmp/tiny")
  test("a file that grew is not called smaller", not said:find("smaller:", 1, true) or
    said:find("no smaller", 1, true) ~= nil, said)
  test("there is no negative percentage", not said:find("-%d+%%"), said)
  test("it says no smaller", said:find("no smaller", 1, true) ~= nil, said)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
