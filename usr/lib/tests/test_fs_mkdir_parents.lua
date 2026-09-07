-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.fs.makeDirectory creates the parents  ║
-- ║                                                                ║
-- ║  Nothing below this function does. OpenComputers' managed      ║
-- ║  filesystem is single-level -- the disk-backed component calls  ║
-- ║  Java's File.mkdir(), not mkdirs(), and the in-memory one       ║
-- ║  resolves the parent and fails when it is absent -- and OpenOS  ║
-- ║  hands the path straight down (its own `mkdir` has no -p).      ║
-- ║                                                                ║
-- ║  TOS believed otherwise in writing: pkg.init()'s comment said   ║
-- ║  "the OC proxy creates parents recursively, so a single call    ║
-- ║  covers /var, /var/pkg, /var/pkg/installed" and then made that  ║
-- ║  call. On a fresh managed disk it failed at /var/pkg and only   ║
-- ║  logged a warning, so a first install had no package store.     ║
-- ║  backup.lua had hand-rolled the segment loop; TBFS had grown    ║
-- ║  its own recursion. Two backends, two behaviours, and portable  ║
-- ║  code that worked on a raw drive and broke on a managed one.    ║
-- ║                                                                ║
-- ║  The guarantee lives in the kernel layer now, so this test      ║
-- ║  drives a deliberately SINGLE-LEVEL proxy: it fails any         ║
-- ║  makeDirectory whose parent is missing, exactly as the real     ║
-- ║  component does.                                                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_fs_mkdir_parents.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_fs_mkdir_parents.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path

package.loaded["component"] = {
  list = function() return function() return nil end end,
  proxy = function() return nil end, invoke = function() return nil end,
}
package.loaded["computer"] = { uptime = function() return 0 end, getBootAddress = function() return "boot" end }

-- ── A proxy with OpenComputers' real semantics ───────────────────
-- makeDirectory("a/b") when "a" is missing returns FALSE. That is the
-- whole point of the fixture; a permissive fake would pass either way.
local function newProxy()
  local dirs, files = { ["/"] = true }, {}
  local P = { address = "single-level", calls = {} }
  local function norm(p)
    p = "/" .. tostring(p or ""):gsub("^/+", "")
    return (p:gsub("//+", "/"):gsub("(.)/$", "%1"))
  end
  function P.exists(p) p = norm(p); return dirs[p] == true or files[p] ~= nil end
  function P.isDirectory(p) return dirs[norm(p)] == true end
  function P.list(p) return {} end
  function P.getLabel() return "test" end
  function P.spaceTotal() return 1000 end
  function P.spaceUsed() return 0 end
  function P.makeDirectory(p)
    p = norm(p)
    P.calls[#P.calls + 1] = p
    if dirs[p] or files[p] then return false end          -- already there
    local parent = p:match("^(.*)/[^/]+$")
    if parent == "" then parent = "/" end
    if not dirs[parent] then return false end             -- SINGLE LEVEL
    dirs[p] = true
    return true
  end
  function P.open() return nil end
  function P.remove(p) dirs[norm(p)] = nil; files[norm(p)] = nil; return true end
  P._dirs, P._files = dirs, files
  return P
end

local fs = require("kernel.fs")
local proxy = newProxy()
if fs.init then pcall(fs.init, proxy) end

print("=== fs.makeDirectory creates parents Tests ===")
print()

-- ── The fixture is honest about being single-level ───────────────
print("-- the proxy really is single-level --")
test("the proxy refuses a nested path outright", false, proxy.makeDirectory("/a/b/c"))
test("...and made nothing", false, proxy.isDirectory("/a"))

-- ── One call, whole chain ────────────────────────────────────────
print()
print("-- one call makes the whole chain --")
proxy.calls = {}
test("a three-deep path is created", true, fs.makeDirectory("/var/pkg/installed"))
test("the top level exists", true, fs.isDirectory("/var"))
test("the middle exists", true, fs.isDirectory("/var/pkg"))
test("the leaf exists", true, fs.isDirectory("/var/pkg/installed"))
test("it asked the proxy shallowest-first, one level at a time", "/var,/var/pkg,/var/pkg/installed",
  table.concat(proxy.calls, ","))

-- ── The return contract callers rely on is unchanged ─────────────
print()
print("-- the return value still means what it meant --")
test("creating something new is true", true, fs.makeDirectory("/var/log"))
test("creating it again is false", false, fs.makeDirectory("/var/log"))
test("...with a reason", "already exists", select(2, fs.makeDirectory("/var/log")))
test("a partially-existing chain still reports true for the new leaf",
  true, fs.makeDirectory("/var/log/old"))

-- ── A file in the way is not a parent ────────────────────────────
print()
print("-- a file in the way --")
proxy._files["/var/afile"] = "x"
test("refuses to treat a file as a directory", false, fs.makeDirectory("/var/afile/sub"))
test("...and says which level", "not a directory: /var/afile",
  select(2, fs.makeDirectory("/var/afile/sub")))
test("...and created nothing below it", false, fs.exists("/var/afile/sub"))

-- ── A refusing backend is reported, not swallowed ────────────────
print()
print("-- a backend that refuses --")
local realMk = proxy.makeDirectory
proxy.makeDirectory = function(p)
  if tostring(p):find("readonly") then return false end
  return realMk(p)
end
local ok, why = fs.makeDirectory("/var/readonly/deep")
test("a refused level fails the call", false, ok)
test("...naming the level", true, tostring(why):find("/var/readonly", 1, true) ~= nil)
proxy.makeDirectory = realMk

-- ── Edge cases ───────────────────────────────────────────────────
print()
print("-- edges --")
test("root is not created", false, fs.makeDirectory("/"))
test("a tainted path fails closed", false, fs.makeDirectory("/var/\0evil"))
test("trailing slashes are the same directory", true, fs.makeDirectory("/deep/one/two/"))
test("...and it exists without the slash", true, fs.isDirectory("/deep/one/two"))
test("dot segments normalize away", false, fs.makeDirectory("/deep/one/./two"))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
