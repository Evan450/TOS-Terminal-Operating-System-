-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel/strip.lua, and those who must heed it ║
-- ║                                                                ║
-- ║  SELF-STRIPPING (TODO, the operator's 2026-08-11 decision).    ║
-- ║  Groups come from the manifest's tags; a strip refuses the     ║
-- ║  floor, an unknown group, a second strip, and a group SRM      ║
-- ║  holds no copies of (unless --no-copy says so); the record is  ║
-- ║  written before a file goes; restore brings files back from    ║
-- ║  SRM's store or, with --online, through the online repair, and ║
-- ║  unmarks the group only when every file is here. The online    ║
-- ║  repair and srm scan, driven for real, treat a stripped file   ║
-- ║  as removed on purpose.                                        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_strip.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha = dofile("tos/kernel/sha256.lua")

-- ── A fake disk ───────────────────────────────────────────────
local F = { _f = {}, atomic = 0 }
local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
function F.exists(p) for k in pairs(F._f) do if under(p, k) then return true end end return false end
function F.readFile(p) return F._f[p] end
function F.writeFile(p, d) F._f[p] = d; return true end
function F.writeFileAtomic(p, d) F.atomic = F.atomic + 1; F._f[p] = d; return true end
function F.remove(p) for k in pairs(F._f) do if under(p, k) then F._f[k] = nil end end return true end
function F.size(p) return F._f[p] and #F._f[p] or 0 end
function F.isDirectory(p) return F.exists(p) and F._f[p] == nil end
package.loaded["kernel.fs"] = F
_G._TOS = { fs = F }

local BODY = { ["/tos/kernel/net/init.lua"] = "-- net", ["/usr/man/net.man"] = "NET",
               ["/tos/kernel/jbod.lua"] = "-- jbod", ["/tos/kernel/init.lua"] = "-- kernel" }
local MANIFEST = {
  { path = "/tos/kernel/init.lua", critical = true, floor = true, hash = sha.hex(BODY["/tos/kernel/init.lua"]) },
  { path = "/tos/kernel/net/init.lua", critical = false, group = "network", hash = sha.hex(BODY["/tos/kernel/net/init.lua"]) },
  { path = "/usr/man/net.man", critical = false, group = "network", hash = sha.hex(BODY["/usr/man/net.man"]) },
  { path = "/tos/kernel/jbod.lua", critical = false, group = "jbod", hash = sha.hex(BODY["/tos/kernel/jbod.lua"]) },
}
package.loaded["system_manifest"] = MANIFEST

-- SRM's index and store, as strip and restore read them.
local stored = {}
package.loaded["kernel.srm"] = {
  loadIndex = function()
    local files = {}
    for p in pairs(stored) do files[p] = { stored = true } end
    return { files = files }
  end,
  restore = function(_, opts)
    for _, p in ipairs(opts.paths or {}) do if stored[p] then F._f[p] = BODY[p] end end
    return { findings = { { text = "restored from store", sev = "ok" } } }
  end,
}
local netCall
package.loaded["kernel.netrepair"] = {
  run = function(deps, opts)
    netCall = { deps = deps, opts = opts }
    for _, e in ipairs(deps.manifest or {}) do F._f[e.path] = BODY[e.path] end
    return { lines = { { text = "fetched", sev = "ok" } } }
  end,
}

local function fresh()
  F._f = {}
  for p, b in pairs(BODY) do F._f[p] = b end
  stored, netCall, F.atomic = {}, nil, 0
  package.loaded["kernel.strip"] = nil
  local s = dofile("tos/kernel/strip.lua")
  package.loaded["kernel.strip"] = s
  return s
end

print("=== groups come from the manifest ===")
local strip = fresh()
local g = strip.groups()
test("network has its two files", g.network and #g.network == 2)
test("jbod has one", g.jbod and #g.jbod == 1)
local rows = strip.list()
test("list shows both, here", #rows == 2 and rows[1].name == "jbod" and rows[2].present == 2)

print("=== what a strip refuses ===")
local ok, why = strip.strip(nil, "nosuch")
test("an unknown group", ok == false and why:find("no feature group", 1, true), why)
ok, why = strip.strip(nil, "network")
test("a group SRM holds no copies of", ok == false and why:find("--no-copy", 1, true)
  and why:find("--from <mount>", 1, true), why)
test("...and nothing was removed", F._f["/tos/kernel/net/init.lua"] ~= nil)
MANIFEST[#MANIFEST + 1] = { path = "/tos/kernel/init.lua", floor = true, group = "bad" }
strip = fresh()
ok, why = strip.strip(nil, "bad", { noCopy = true })
test("a group holding a floor file", ok == false and why:find("floor", 1, true), why)
test("...and the kernel is still here", F._f["/tos/kernel/init.lua"] ~= nil)
table.remove(MANIFEST)

print("=== a strip with SRM's copies ===")
strip = fresh()
stored["/tos/kernel/net/init.lua"], stored["/usr/man/net.man"] = true, true
local rep
ok, rep = strip.strip(nil, "network")
test("it strips", ok == true, rep)
test("both files are gone", F._f["/tos/kernel/net/init.lua"] == nil and F._f["/usr/man/net.man"] == nil)
test("the other group is untouched", F._f["/tos/kernel/jbod.lua"] ~= nil)
test("it says how much", rep and rep.removed == 2 and rep.freed > 0, rep and rep.freed)
test("the record was written atomically", F.atomic >= 1 and F._f["/etc/stripped.cfg"] ~= nil)
test("isStripped knows", (strip.isStripped("/usr/man/net.man")) == true)
test("and only for what was stripped", (strip.isStripped("/tos/kernel/jbod.lua")) == false)
ok, why = strip.strip(nil, "network")
test("a second strip is refused", ok == false and why:find("already stripped", 1, true), why)
test("list shows it stripped", (function()
  for _, r in ipairs(strip.list()) do if r.name == "network" then return r.stripped end end
end)())

print("=== restore from SRM's store ===")
ok, rep = strip.restore(nil, "network")
test("it restores", ok == true, rep and rep.missing and table.concat(rep.missing, ","))
test("the files are back", F._f["/tos/kernel/net/init.lua"] == "-- net")
test("with what SRM said", rep and rep.lines and rep.lines[1] and rep.lines[1].text == "restored from store")
strip.reset()
test("and the group is unmarked", (strip.isStripped("/usr/man/net.man")) == false)

print("=== --no-copy, then a restore with nothing to restore from ===")
strip = fresh()
ok = strip.strip(nil, "jbod", { noCopy = true })
test("--no-copy strips without copies", ok == true and F._f["/tos/kernel/jbod.lua"] == nil)
ok, rep = strip.restore(nil, "jbod")
test("restore without --online cannot bring it back", ok == false and rep.missing[1] == "/tos/kernel/jbod.lua")
strip.reset()
test("so the group stays marked", (strip.isStripped("/tos/kernel/jbod.lua")) == true)
ok, rep = strip.restore(nil, "jbod", { online = true })
test("--online brings it back", ok == true and F._f["/tos/kernel/jbod.lua"] == "-- jbod")
test("through the online repair, given only the group's entries",
  netCall and #netCall.deps.manifest == 1 and netCall.deps.manifest[1].path == "/tos/kernel/jbod.lua")
test("with the strip check off for exactly that call", netCall and netCall.deps.stripAware == false)
test("and --apply", netCall and netCall.opts.apply == true)

print("=== restore --from a TOS disk, checked against the digest ===")
do
  strip = fresh()
  package.loaded["kernel.crypto"] = { hash = function(d) return sha.hex(d) end }
  strip.strip(nil, "network", { noCopy = true })
  test("setup: network stripped", F._f["/tos/kernel/net/init.lua"] == nil)
  -- A disk with the right net/init.lua and a WRONG net.man.
  F._f["/mnt/install/tos/kernel/net/init.lua"] = "-- net"
  F._f["/mnt/install/usr/man/net.man"] = "NOT THE RELEASE'S"
  local ok3, rep3 = strip.restore(nil, "network", { from = "/mnt/install" })
  test("the right file is copied back", F._f["/tos/kernel/net/init.lua"] == "-- net")
  test("the wrong one is refused, not written", F._f["/usr/man/net.man"] == nil)
  local said = false
  for _, l in ipairs(rep3 and rep3.lines or {}) do
    if tostring(l.text):find("NOT the release's bytes", 1, true) then said = true end
  end
  test("saying so", said)
  test("so the group is still stripped", ok3 == false)
  F._f["/mnt/install/usr/man/net.man"] = "NET"
  ok3 = strip.restore(nil, "network", { from = "/mnt/install" })
  test("with the right disk it comes back whole", ok3 == true and F._f["/usr/man/net.man"] == "NET")
  package.loaded["kernel.crypto"] = nil
end

print("=== an emptied directory goes with its files ===")
do
  strip = fresh()
  F.list = function(p)
    local out, seen = {}, {}
    for k in pairs(F._f) do
      if k:sub(1, #p + 1) == p .. "/" then
        local head = k:sub(#p + 2):match("^([^/]+)")
        if head and not seen[head] then seen[head] = true; out[#out + 1] = head end
      end
    end
    return out
  end
  F._f["/tos/kernel/net"] = nil
  local removedDir = false
  local realRemove = F.remove
  F.remove = function(p) if p == "/tos/kernel/net" then removedDir = true end return realRemove(p) end
  -- OC keeps an emptied directory; this fake only implies them, so model it.
  local realExists = F.exists
  F.exists = function(p) if p == "/tos/kernel/net" and not removedDir then return true end return realExists(p) end
  strip.strip(nil, "network", { noCopy = true })
  F.remove, F.list, F.exists = realRemove, nil, realExists
  test("/tos/kernel/net is removed once empty", removedDir)
end

print("=== the real online repair leaves a stripped file alone ===")
do
  strip = fresh()
  strip.strip(nil, "jbod", { noCopy = true })
  package.loaded["kernel.netrepair"] = nil
  local nr = dofile("tos/kernel/netrepair.lua")
  local crypto = { hash = function(d) return sha.hex(d) end }
  local damaged, skipped = nr.damaged({ fs = F, crypto = crypto, manifest = MANIFEST })
  local inDamaged = false
  for _, d in ipairs(damaged) do if d.path == "/tos/kernel/jbod.lua" then inDamaged = true end end
  local why2
  for _, s in ipairs(skipped) do if s.path == "/tos/kernel/jbod.lua" then why2 = s.why end end
  test("it is not damage to repair", not inDamaged)
  test("it is skipped, saying why", why2 and why2:find("stripped on purpose", 1, true), why2)
  damaged = nr.damaged({ fs = F, crypto = crypto, manifest = MANIFEST, stripAware = false })
  inDamaged = false
  for _, d in ipairs(damaged) do if d.path == "/tos/kernel/jbod.lua" then inDamaged = true end end
  test("unless restore asks for it (stripAware = false)", inDamaged)
end

print("=== the real srm scan does not call it missing ===")
do
  local okS, srm = pcall(dofile, "tos/kernel/srm.lua")
  test("srm.lua loads", okS and type(srm) == "table", srm)
  if okS and type(srm) == "table" then
    -- A baseline that knew jbod.lua, which is now stripped.
    F._f[srm.INDEX] = serialize.encode({ version = srm.VERSION, files = {
      ["/tos/kernel/jbod.lua"] = { hash = sha.hex("-- jbod"), size = 7 } } })
    local rep2 = srm.scan({ fs = F, serialize = serialize,
      crypto = { hash = function(d) return sha.hex(d) end } }, { checkStore = false })
    test("not missing", #rep2.missing == 0, #rep2.missing)
    local said = false
    for _, l in ipairs(rep2.findings or {}) do
      if tostring(l.text):find("STRIPPED", 1, true) then said = true end
    end
    test("reported as stripped", said)
  end
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
