-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `backup snapshot` works on OpenComputers'    ║
-- ║  clock                                                         ║
-- ║                                                                ║
-- ║  On the headless machine `backup snapshot /etc /tmp/etc.bak`   ║
-- ║  died: "backup.lua:25: number (local 'n') has no integer       ║
-- ║  representation". OC's os.time() is GAME time, a float that is ║
-- ║  usually fractional, and the header's packU32 did bitwise ops  ║
-- ║  on it. So every snapshot failed whenever the clock was not on ║
-- ║  a whole second -- and kernel.backup had no test at all.       ║
-- ║  Drives the real module over an in-memory securefs.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_backup_snapshot.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local sha = dofile("tos/kernel/sha256.lua")

-- A tree: path -> content, or true for a directory.
local tree = { ["/"] = true, ["/etc"] = true, ["/etc/a.cfg"] = "alpha\n",
               ["/etc/sub"] = true, ["/etc/sub/b.cfg"] = "beta beta\n" }
local function norm(p) p = ("/" .. tostring(p)):gsub("//+", "/"); if #p > 1 then p = p:gsub("/$", "") end return p end
local securefs = {
  normalize = norm,
  exists = function(p) return tree[norm(p)] ~= nil end,
  isDirectory = function(p) return tree[norm(p)] == true end,
  size = function(p) local v = tree[norm(p)]; return type(v) == "string" and #v or 0 end,
  readFile = function(p) local v = tree[norm(p)]; return type(v) == "string" and v or nil end,
  writeFile = function(p, d) tree[norm(p)] = d; return true end,
  makeDirectory = function(p) tree[norm(p)] = true; return true end,
  list = function(p)
    local base, out = norm(p), {}
    for k, v in pairs(tree) do
      local parent, name = k:match("^(.*)/([^/]+)$")
      if name and norm(parent == "" and "/" or parent) == base then
        out[#out + 1] = name .. (v == true and "/" or "")
      end
    end
    table.sort(out)
    return out
  end,
}

local realTime = os.time
os.time = function() return 23940.56 end   -- OC: game time, fractional

local backup = dofile("tos/kernel/backup.lua")
backup.init({ securefs = securefs, fs = securefs, log = nil,
  crypto = { hash = function(d) return sha.hex(d) end, ctEquals = function(a, b) return a == b end } })
local SESSION = { user = "root", tier = 3 }

print("=== backup snapshot on OpenComputers' clock ===")
print()

local ok, info = backup.snapshot("/etc", "/tmp/etc.bak", { session = SESSION })
test("a snapshot taken at a fractional game time succeeds", ok == true, info)
test("...and wrote the backup", type(tree["/tmp/etc.bak"]) == "string")

local ins, iErr = backup.inspect("/tmp/etc.bak", { session = SESSION })
test("inspect reads it back", type(ins) == "table", iErr)
test("...with the time rounded down to a whole second", ins and ins.created == 23940, ins and ins.created)

local okR, rErr = backup.restore("/tmp/etc.bak", { session = SESSION, destRoot = "/restored" })
test("restore puts the tree back", okR == true and tree["/restored/a.cfg"] == "alpha\n"
  and tree["/restored/sub/b.cfg"] == "beta beta\n", rErr)

os.time = realTime
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
