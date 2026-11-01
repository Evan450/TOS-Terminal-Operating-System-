#!/usr/bin/env lua
-- Sign a built release, or check that it is signed.
--
--   python tos.py sign-release     asks for the passphrase, writes the signature
--   python tos.py verify-release   exit 0 only if TOS-Release is signed, and valid
--
-- Same key as the pack: same passphrase, same publisher label, same derivation
-- (kernel/pkgsign.lua). bootstrap.lua pins the public half, and this tool reads
-- it from there rather than keeping a second copy that could drift. A build
-- wipes TOS-Release, so a signature can never outlive the manifest it covers.

local function readAll(path)
  local h = io.open(path, "rb")
  if not h then return nil end
  local s = h:read("a")
  h:close()
  return s
end

local here = (arg and arg[0] or "build/release_sig.lua"):gsub("[^/\\]*$", "")
local DEV = (here == "" and "." or here:gsub("[/\\]+$", "")) .. "/.."
local RELEASE = DEV .. "/../TOS-Release"
local MANIFEST = RELEASE .. "/tos/system_manifest.lua"
local SIG = RELEASE .. "/tos/system_manifest.sig"

package.path = DEV .. "/tos/?.lua;" .. DEV .. "/tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end,
  freeMemory = function() return 1e9 end, totalMemory = function() return 1e9 end,
  beep = function() end, pullSignal = function() end }
package.loaded["component"] = { list = function() return function() end end,
  isAvailable = function() return false end, proxy = function() end }

local ed = require("kernel.ed25519")
local bootstrap = readAll(DEV .. "/bootstrap.lua")
local KEY = bootstrap and bootstrap:match('local RELEASE_KEY = "(%x+)"')
if not KEY then
  io.stderr:write("error: no RELEASE_KEY in bootstrap.lua\n")
  os.exit(1)
end

local function bin(hex)
  return (hex:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
end
local function hex(b)
  return (b:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local mode = arg and arg[1]
local manifest = readAll(MANIFEST)
if not manifest then
  io.stderr:write("error: no built release. Run: python tos.py build\n")
  os.exit(1)
end

if mode == "verify" then
  local raw = readAll(SIG)
  if not raw then
    print("TOS-Release is not signed.")
    os.exit(1)
  end
  local sig = assert(load(raw, "=signature", "t", {}))()
  if sig.key ~= KEY then
    print("TOS-Release is signed with a different key: " .. tostring(sig.key))
    os.exit(1)
  end
  if not ed.verify(manifest, bin(sig.sig), bin(KEY)) then
    print("TOS-Release's signature does not match its manifest. Sign it again.")
    os.exit(1)
  end
  print("TOS-Release is signed by " .. tostring(sig.signer) .. ".")
  os.exit(0)
elseif mode ~= "sign" then
  io.stderr:write("usage: lua build/release_sig.lua sign|verify\n")
  os.exit(2)
end

local pass = os.getenv("TOS_SIGNING_PASSPHRASE")
local label = os.getenv("TOS_SIGNING_NAME")
if not pass or pass == "" or not label or label == "" then
  io.stderr:write("error: run this through `python tos.py sign-release`, which asks.\n")
  os.exit(1)
end

local ps = require("kernel.pkgsign")
ps.init({ fs = {}, serialize = require("kernel.serialize") })
local seed, err = ps.seedFromPassphrase(pass, label)
if not seed then
  io.stderr:write("error: " .. tostring(err) .. "\n")
  os.exit(1)
end
local pub = ed.publickey(seed)
--! Refused, not warned past. A wrong passphrase derives a perfectly good key,
--! and signing with it would produce a release no bootstrap accepts.
if hex(pub) ~= KEY then
  io.stderr:write("error: that passphrase and label give a different key.\n"
    .. "       bootstrap.lua pins " .. KEY:sub(1, 16) .. "...\n"
    .. "       this one is       " .. hex(pub):sub(1, 16) .. "...\n"
    .. "       Nothing was signed.\n")
  os.exit(1)
end

local sig = ed.sign(manifest, seed, pub)
local body = string.format(
  'return {\n  ["key"] = %q,\n  ["covers"] = "tos/system_manifest.lua",\n'
  .. '  ["signer"] = %q,\n  ["sig"] = %q,\n  ["v"] = 1,\n}\n',
  KEY, ps.normalizeLabel(label), hex(sig))
local tmp = SIG .. ".tmp"
local h = assert(io.open(tmp, "wb"))
h:write(body)
h:close()
os.remove(SIG)
assert(os.rename(tmp, SIG))
print("Signed. Now: pwsh -File publish.ps1 -Push, from Working_Dir/tos-repo-push")
