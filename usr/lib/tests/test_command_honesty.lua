-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: commands say what actually happened          ║
-- ║                                                                ║
-- ║  From the 2026-10-31 command pass, where bad input read like   ║
-- ║  success: `du /nothere` answered 0B, `touch` on a directory    ║
-- ║  said Touched, `mv f /dir/nothere/f` built the missing         ║
-- ║  directory without a word (a disk's rename makes parents), and ║
-- ║  `compress` on a tiny file said "-113% smaller". And `find`    ║
-- ║  was wrong twice: the form the manual gives searched the       ║
-- ║  pattern as a path, and every result ended /0 because gsub's   ║
-- ║  count became a path segment, so no directory was entered.     ║
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
    for k in pairs(dirs) do
      local rest = k:sub(1, #prefix) == prefix and k:sub(#prefix + 1)
      if rest and rest ~= "" and not rest:find("/", 1, true) then out[#out + 1] = rest .. "/" end
    end
    return out
  end,
  -- Takes every argument, as fs.join does: that is what the bug needed.
  join = function(...)
    local parts = { ... }
    parts[1] = parts[1]:gsub("/$", "")
    return table.concat(parts, "/")
  end,
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
            U = { canAccessAs = function() return true end },
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

print("=== find ===")
do
  reset()
  dirs["/tmp/sub/deep"] = true
  files["/tmp/sub/deep/notes.md"] = "x"
  files["/tmp/sub/other.txt"] = "y"
  local said = run("find", "/tmp", "notes")
  test("the form the manual gives searches the path", said:find("Searching /tmp ", 1, true) ~= nil, said)
  test("it goes down into directories", said:find("/tmp/sub/deep/notes.md", 1, true) ~= nil, said)
  test("no result grows a count", not said:find("/0", 1, true), said)
  test("what does not match stays out", not said:find("other.txt", 1, true), said)
  said = run("find", "/tmp", "-name", "notes")
  test("-name still works", said:find("/tmp/sub/deep/notes.md", 1, true) ~= nil, said)
  said = run("find", "/tmp/sub")
  test("one word that is a directory is the path", said:find("Searching /tmp/sub ", 1, true) ~= nil, said)
  test("and lists what is under it", said:find("other.txt", 1, true) ~= nil, said)
  said = run("find", "notes")
  test("one word that is not is the pattern", said:find("Searching / ", 1, true) ~= nil, said)
  test("and finds it from the top", said:find("/tmp/sub/deep/notes.md", 1, true) ~= nil, said)
  test("a directory shows as one", run("find", "/tmp", "deep"):find("/tmp/sub/deep/", 1, true) ~= nil)
end

print("=== nothing else hands join a gsub count ===")
do
  local listing = io.popen(package.config:sub(1, 1) == "\\"
    and 'dir /s /b tos\\*.lua 2>nul' or "find tos -name '*.lua' 2>/dev/null")
  local bad, seen = {}, 0
  for line in listing:lines() do
    local rel = line:gsub("\\", "/"):match("(tos/.*)$")
    local h = rel and io.open(rel:gsub("%s+$", ""), "rb")
    if h then
      seen = seen + 1
      local text = h:read("a"); h:close()
      for call in text:gmatch("[%w_%.]*[Jj]oin%b()") do
        -- A last argument that is a bare x:gsub(...) passes its count on.
        if call:match(",%s*[%w_%.%[%]]+:gsub%b()%)$") then bad[#bad + 1] = rel .. ": " .. call end
      end
    end
  end
  listing:close()
  test("the scan read the kernel and the shell", seen > 100, seen)
  test("no join takes gsub's count as a path segment", #bad == 0, bad[1])
end

print("=== cp and grep take the flags a hand types ===")
do
  reset()
  dirs["/tmp/d"] = true
  F.copy = function(a, b) files[b] = files[a] or ""; return true end
  local said = run("cp", "-r", "/tmp/a", "/tmp/b")
  test("cp -r is not a file name", files["/tmp/b"] == "alpha\n", said)
  local real = package.loaded["shell.panels.helpers"]
  local keep = real.eachLine
  real.eachLine = function(_, p, fn)
    for line in (files[p] .. "\n"):gmatch("(.-)\n") do if line ~= "" then fn(line) end end
    return true
  end
  files["/tmp/g"] = "Alpha\nbeta\n"
  said = run("grep", "-i", "ALPHA", "/tmp/g")
  test("grep -i folds case", said:find("Alpha", 1, true) ~= nil, said)
  test("and is not read as the pattern", not said:find("Cannot read", 1, true), said)
  said = run("grep", "ALPHA", "/tmp/g")
  test("plain grep still does not", said:find("No matches", 1, true) ~= nil, said)
  files["/tmp/h"] = "gamma Alpha\n"
  said = run("grep", "Alpha", "/tmp/g", "/tmp/h")
  test("grep reads every file it is given", said:find("/tmp/h:1: gamma Alpha", 1, true) ~= nil, said)
  test("and says which file each hit is in", said:find("/tmp/g:1: Alpha", 1, true) ~= nil, said)
  test("and counts them all", said:find("2 match(es)", 1, true) ~= nil, said)
  real.eachLine = keep
end

print("=== $NAME ===")
do
  local h = assert(io.open("tos/shell/panels/executor.lua", "rb"))
  local src = h:read("a"):gsub("\r\n", "\n"); h:close()
  local from = src:find("local function expandVars", 1, true)
  local to = src:find("\nend\n", from, true)
  local expand = assert(load(src:sub(from, to + 4) .. "\nreturn expandVars", "=expand", "t",
    { tostring = tostring, table = table }))()
  local vars = { HOME = "/root", A_1 = "x" }
  local function x(s) return expand(s, function(n) return vars[n] end) end
  test("a set name expands", x("echo $HOME") == "echo /root", x("echo $HOME"))
  test("in braces too", x("echo ${HOME}/bin") == "echo /root/bin", x("echo ${HOME}/bin"))
  test("next to text it stops at the name", x("echo $HOME.") == "echo /root.", x("echo $HOME."))
  test("digits and underscores count", x("$A_1") == "x")
  test("inside double quotes it expands", x('echo "$HOME"') == 'echo "/root"')
  test("inside single quotes it does not", x("echo '$HOME'") == "echo '$HOME'", x("echo '$HOME'"))
  test("a name not set stays as typed", x("echo $NOPE") == "echo $NOPE")
  test("a bare dollar stays", x("echo costs $5 and $") == "echo costs $5 and $")
  test("no dollar is the same string", x("ls /tmp") == "ls /tmp")
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
