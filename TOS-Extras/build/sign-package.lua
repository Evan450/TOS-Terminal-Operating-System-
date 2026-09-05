#!/usr/bin/env lua
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Sign one package (or print the key that would sign it)        ║
-- ║                                                                ║
-- ║  build-disk.lua --sign signs the whole assembled pack, which    ║
-- ║  is what a RELEASE wants. A package author working on one       ║
-- ║  add-on wants to sign that one, in place, without assembling    ║
-- ║  floppies first -- and wants to print their public key before   ║
-- ║  they have anything to sign with it.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
--
--! The signature format is defined in exactly ONE place: kernel/pkgsign.lua.
--! This drives that module over a filesystem shim, exactly as build-disk.lua
--! does, rather than writing the record itself -- a package signed here, a
--! package signed by `pkg sign` on a booted machine, and a pack signed by
--! the disk builder must all be the same bytes, and the only way to
--! guarantee that is to have one implementation.
--
--   TOS_SIGNING_PASSPHRASE=... lua build/sign-package.lua modules/mything
--   TOS_SIGNING_PASSPHRASE=... lua build/sign-package.lua --all
--   TOS_SIGNING_PASSPHRASE=... lua build/sign-package.lua --key
--
--! The passphrase comes from the environment and never from a flag. It is
--! not "a password for the key" -- the key is DERIVED from it, so it IS
--! the private key, and argv reaches shell history, `ps` output and CI logs.

local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]+$") or "."
local extrasRoot = scriptDir .. "/.."

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function writeAll(p, d)
  local h = io.open(p, "wb"); if not h then return false, "open failed: " .. p end
  h:write(d); h:close(); return true
end
local function exists(p) local h = io.open(p, "rb"); if h then h:close(); return true end return false end

--! Both tree shapes: TOS-Dev as a SIBLING (the monorepo) and the OS tree
--! one level up (the published dev branch, where TOS-Extras is nested).
--! Same ladder as build-disk.lua; getting it wrong here means signing is
--! unavailable to exactly the contributors it exists for.
local function loadKernelModule(rel)
  for _, cand in ipairs({
      extrasRoot .. "/../TOS-Dev/tos/kernel/" .. rel,
      extrasRoot .. "/../tos/kernel/" .. rel,
      scriptDir  .. "/../../TOS-Dev/tos/kernel/" .. rel,
      scriptDir  .. "/../../tos/kernel/" .. rel,
      "TOS-Dev/tos/kernel/" .. rel,
      "../tos/kernel/" .. rel }) do
    local chunk = loadfile(cand)
    if chunk then local ok, m = pcall(chunk); if ok then return m end end
  end
end

-- ── Arguments ──────────────────────────────────────────────────────
local wantKeyOnly, wantAll, dirs = false, false, {}
for i = 1, #(arg or {}) do
  local a = arg[i]
  if a == "--key" then wantKeyOnly = true
  elseif a == "--all" then wantAll = true
  elseif a:sub(1, 2) == "--" then
    io.stderr:write("unknown option: " .. a .. "\n"); os.exit(2)
  else dirs[#dirs + 1] = a end
end

local pass = os.getenv("TOS_SIGNING_PASSPHRASE")
if not pass or pass == "" then
  io.stderr:write(
    "error: set TOS_SIGNING_PASSPHRASE.\n" ..
    "       Deliberately not a flag: argv lands in shell history, in `ps`\n" ..
    "       output and in CI logs, and this passphrase IS the private key --\n" ..
    "       the key is derived from it, not stored.\n")
  os.exit(1)
end

-- ── Wire up the real signer ────────────────────────────────────────
--! ORDER MATTERS. ed25519.lua does `require("kernel.sha512")` at load
--! time (RFC 8032 needs SHA-512), so the hashers have to be in
--! package.loaded BEFORE it is loaded, not after. Loading all four first
--! and registering them afterwards leaves ed25519 the only one that
--! silently fails to load -- and the error then reads as "no crypto
--! modules found", pointing at the search path instead of the ordering.
local sha256 = loadKernelModule("sha256.lua")
local sha512 = loadKernelModule("sha512.lua")
local serial = loadKernelModule("serialize.lua")
if sha256 then package.loaded["kernel.sha256"] = sha256 end
if sha512 then package.loaded["kernel.sha512"] = sha512 end
local ed = loadKernelModule("ed25519.lua")
if not (sha256 and sha512 and ed and serial) then
  io.stderr:write("error: could not load the kernel crypto modules from the TOS tree.\n" ..
                  "       Run this from inside TOS-Extras, with the OS tree beside\n" ..
                  "       it (../TOS-Dev/) or above it (../tos/).\n")
  io.stderr:write(string.format("       sha256=%s sha512=%s ed25519=%s serialize=%s\n",
    tostring(sha256 ~= nil), tostring(sha512 ~= nil),
    tostring(ed ~= nil), tostring(serial ~= nil)))
  os.exit(1)
end
package.loaded["kernel.ed25519"] = ed
local ps = loadKernelModule("pkgsign.lua")
if not ps then io.stderr:write("error: kernel/pkgsign.lua not found.\n"); os.exit(1) end
ps.init({ fs = { exists = exists, readFile = readAll, writeFile = writeAll },
          serialize = serial })

local seed, sErr = ps.seedFromPassphrase(pass)
if not seed then io.stderr:write("error: " .. tostring(sErr) .. "\n"); os.exit(1) end
local pubHex = ps.binToHex(ed.publickey(seed))

print("Public key : " .. pubHex)
print("Fingerprint: " .. ps.fingerprint(pubHex))
print("Recipients trust it with:  pkg trust add <name> " .. pubHex)

if wantKeyOnly then os.exit(0) end

-- ── Which packages ─────────────────────────────────────────────────
if wantAll then
  --! Discover the same way build-disk does -- a package is a directory
  --! with a package.lua under one of the discovery roots -- so "--all"
  --! cannot come to mean a different set than the one that ships.
  local roots = { "modules", "cluster", "rbmk" }
  local sep = package.config:sub(1, 1)
  for _, root in ipairs(roots) do
    local cmd = (sep == "\\")
      and ('dir /b /s "' .. (extrasRoot .. "/" .. root):gsub("/", "\\") .. '\\package.lua" 2>nul')
      or  ('find "' .. extrasRoot .. "/" .. root .. '" -name package.lua 2>/dev/null')
    local pipe = io.popen(cmd)
    if pipe then
      for line in pipe:lines() do
        line = line:gsub("\\", "/"):gsub("%s+$", "")
        if line ~= "" and not line:find("/dist/") then
          dirs[#dirs + 1] = line:gsub("/package%.lua$", "")
        end
      end
      pipe:close()
    end
  end
end

if #dirs == 0 then
  io.stderr:write("\nNothing to sign. Give a package directory, or --all.\n")
  os.exit(2)
end

print()
local signed, failed = 0, 0
for _, d in ipairs(dirs) do
  d = d:gsub("[/\\]+$", "")
  local manifest = d .. "/package.lua"
  if not exists(manifest) then
    io.stderr:write("  SKIP " .. d .. " (no package.lua)\n")
    failed = failed + 1
  else
    local okS, sigPathOrErr = ps.signManifest(manifest, seed,
      { signer = os.getenv("TOS_SIGNING_NAME") })
    if okS then
      print("  signed " .. manifest)
      signed = signed + 1
    else
      io.stderr:write("  FAIL   " .. manifest .. ": " .. tostring(sigPathOrErr) .. "\n")
      failed = failed + 1
    end
  end
end

print()
print(string.format("Signed %d package(s)%s.", signed,
  failed > 0 and (", " .. failed .. " failed") or ""))
--! Signing the SOURCE tree is not the same as shipping a signed pack: the
--! disk builder copies manifests into dist/, so say so rather than let
--! someone assume the published pack inherited this.
if signed > 0 and not wantAll then
  print("Rebuild the pack to carry these into dist/:  lua build/build-disk.lua --sign")
end
os.exit(failed > 0 and 1 or 0)
