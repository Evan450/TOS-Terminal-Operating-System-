-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a manifest is parsed and verified from the   ║
-- ║  SAME bytes (pentest, Sep 2026)                                ║
-- ║                                                                ║
-- ║  pkg.install parsed package.lua, then pkgsign re-read the file ║
-- ║  to check its signature. Storage that answers each read afresh ║
-- ║  could serve the parser its own manifest (its files, its       ║
-- ║  hashes) and the verifier a trusted publisher's signed one:    ║
-- ║  the package installed as "trusted", with `pkg trust require   ║
-- ║  on`, and every per-file hash matched because the hashes were  ║
-- ║  the attacker's. The fake disk below is that storage; pkg and  ║
-- ║  pkgsign are both the real modules.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_pkg_manifest_read_once.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_pkg_manifest_read_once.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p); if chunk then return chunk() end
  end
  error("cannot find " .. rel)
end

package.loaded["kernel.sha512"] = loadMod("sha512.lua")
local sha256 = loadMod("sha256.lua")
package.loaded["kernel.sha256"] = sha256
local ed = loadMod("ed25519.lua")
package.loaded["kernel.ed25519"] = ed
local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
package.loaded["kernel.pkgsign"] = loadMod("pkgsign.lua")
package.loaded["kernel.crypto"] = {
  hash = function(s) return sha256.hex(s) end,
  ctEquals = function(a, b) return a == b end,
}

local function hex(b) return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local SEED = string.rep("S", 32)
local PUB  = hex(ed.publickey(SEED))

local DIR  = "/mnt/net/demo"
local MPATH = DIR .. "/package.lua"
local GOOD, EVIL = "return 'the publisher's code'", "return 'somebody else's code'"

local function manifestFor(body)
  return serialize.encode({ name = "demo", version = "1.0.0", kind = "command",
    files = { "/usr/lib/demo.lua" }, hashes = { ["/usr/lib/demo.lua"] = sha256.hex(body) } })
end
local SIGNED = manifestFor(GOOD)     -- what the publisher signed
local FORGED = manifestFor(EVIL)     -- what the far end wants installed
local SIG = serialize.encode({ v = 1, alg = "ed25519", key = PUB,
  sig = hex(ed.sign(SIGNED, SEED, ed.publickey(SEED))), covers = "package.lua" })

--- A disk whose package.lua answers odd reads with FORGED and even reads
--- with SIGNED, the way a remote store that chooses per request would.
local function newFS(flip, fileBody)
  local files, dirs = {}, { ["/"] = true }
  local reads = 0
  local F
  F = {
    _files = files,
    normalize = function(p) return (tostring(p):gsub("//+", "/")) end,
    join = function(a, b) return tostring(a):gsub("/$", "") .. "/" .. tostring(b) end,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    makeDirectory = function(p) dirs[p] = true; return true end,
    readFile = function(p)
      if p == MPATH and flip then
        reads = reads + 1
        return (reads % 2 == 1) and FORGED or SIGNED
      end
      return files[p]
    end,
    writeFile = function(p, c)
      local acc = ""
      for seg in tostring(p):gmatch("[^/]+") do
        acc = acc .. "/" .. seg
        if acc ~= p then dirs[acc] = true end
      end
      files[p] = c; return true
    end,
    remove = function(p) files[p] = nil; return true end,
    list = function() return {} end,
  }
  F.writeFile(MPATH, SIGNED)
  F.writeFile(DIR .. "/package.sig", SIG)
  F.writeFile(DIR .. "/usr/lib/demo.lua", fileBody)
  F.writeFile("/etc/pkg_trust.cfg", serialize.encode({ requireSignature = true,
    keys = { publisher = PUB } }))
  return F
end

local ADMIN = { user = "root", tier = 3 }
local usersMock = { currentSession = function() return ADMIN end,
  TIER = { GUEST = 0, USER = 1, ADMIN = 2, ROOT = 3 } }

local function newPkg(fs)
  package.loaded["kernel.pkg"] = nil
  local ps = package.loaded["kernel.pkgsign"]
  ps.init({ fs = fs, serialize = serialize }); ps.reloadTrust()
  local pkg = loadMod("pkg.lua")
  pkg.init({ fs = fs, log = nil, users = usersMock })
  return pkg
end

print("=== manifest read-once Tests ===")

do  -- control: the honest disk installs, and as TRUSTED
  local fs = newFS(false, GOOD)
  local pkg = newPkg(fs)
  local ok, err = pkg.install(DIR, { session = ADMIN })
  test("control: the publisher's own package installs (" .. tostring(err) .. ")", ok)
  test("control: recorded as trusted", pkg.info("demo") and pkg.info("demo")._sigState == "trusted")
end

do  -- the attack
  local fs = newFS(true, EVIL)
  local pkg = newPkg(fs)
  local ok = pkg.install(DIR, { session = ADMIN })
  test("a manifest that differs between reads is NOT installed", not ok)
  test("  ...the forged file never reached the disk", fs._files["/usr/lib/demo.lua"] == nil)
  test("  ...and nothing is registered", pkg.info("demo") == nil)
end

do  -- `pkg verify-sig` must describe the manifest it actually parsed
  local fs = newFS(true, EVIL)
  local pkg = newPkg(fs)
  local v, m = pkg.checkSignature(DIR)
  local parsedHash = m and m.hashes and m.hashes["/usr/lib/demo.lua"]
  test("verify-sig never calls the parsed (forged) manifest trusted",
    not (v and v.state == "trusted" and parsedHash == sha256.hex(EVIL)))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
