-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: netfs open modes are a closed set             ║
-- ║                                                                ║
-- ║  The open mode comes off the wire. netfs searched it for w/a/+  ║
-- ║  and treated everything else as a read, then passed it to the   ║
-- ║  backend verbatim. TBFS (blockfs) opens every mode but "r"      ║
-- ║  writable and CREATES the file, so a peer allowed only to READ  ║
-- ║  an export could create files in it with mode "x"; a non-string ║
-- ║  mode raised in the handler (Sep 2026 pentest).                 ║
-- ║                                                                ║
-- ║  Drives the REAL netfs dispatcher over a filesystem with TBFS's ║
-- ║  open() semantics.                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_netfs_open_mode.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;" .. package.path
package.loaded["kernel.serialize"] = require("kernel.serialize")
local netfs = dofile("tos/kernel/netfs.lua")

-- TBFS open(): strip "b"; exactly "r" reads; anything else is writable
-- and creates the file if it is absent.
local files, dirs = { ["/srv/ro/hello.txt"] = "hi" }, { ["/"] = true, ["/srv"] = true, ["/srv/ro"] = true }
local F = {}
function F.normalize(p)
  if type(p) ~= "string" then return nil end
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then if #parts > 0 then table.remove(parts) end
    elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return "/" .. table.concat(parts, "/")
end
function F.exists(p) return files[p] ~= nil or dirs[p] == true end
function F.isDirectory(p) return dirs[p] == true end
function F.size(p) return files[p] and #files[p] or 0 end
function F.open(p, mode)
  mode = (mode or "r"):gsub("b", "")
  if mode == "r" then
    if not files[p] then return nil, "no such file" end
  else
    files[p] = files[p] or ""
    if mode == "w" then files[p] = "" end
  end
  return { read = function() return nil end, write = function() return true end,
           close = function() return true end, seek = function() return 0 end }
end

local PEER = "peer-aaaa"
netfs.init({ fs = F, computer = package.loaded["computer"],
  trust = { LEVEL = { TRUSTED = 3 }, getLevel = function(a) return a == PEER and 3 or 0 end } })
local exports, verr = netfs._validateExports({
  { name = "ro", path = "/srv/ro", mode = "ro", allow = { PEER } },
  { name = "rw", path = "/srv/ro", mode = "rw", allow = { PEER } },
})
assert(exports, "exports did not validate: " .. tostring(verr))
netfs.setExports(exports)

local function open(share, path, mode)
  local ok, res = pcall(netfs._dispatch, "open", { share = share, path = path, mode = mode }, PEER)
  return ok, res
end

print("=== netfs open modes ===")
print()
local ok, res = open("ro", "/made-by-peer.txt", "x")
test("mode 'x' on a read-only export is refused", ok and type(res) == "table" and res.err ~= nil)
test("...and created nothing", files["/srv/ro/made-by-peer.txt"] == nil)
ok, res = open("ro", "/hello.txt", 5)
test("a non-string mode is refused, not raised", ok and type(res) == "table" and res.err ~= nil)
ok, res = open("ro", "/hello.txt", "r")
test("'r' still opens on a read-only export", ok and type(res) == "table" and res.handle_id ~= nil)
ok, res = open("ro", "/hello.txt", "rb")
test("'rb' still opens on a read-only export", ok and type(res) == "table" and res.handle_id ~= nil)
ok, res = open("ro", "/hello.txt", "w")
test("'w' on a read-only export is still refused", ok and type(res) == "table" and res.err ~= nil)
ok, res = open("rw", "/new.txt", "w")
test("'w' on a read-write export still works", ok and type(res) == "table" and res.handle_id ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
