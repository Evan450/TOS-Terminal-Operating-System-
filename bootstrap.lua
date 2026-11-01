-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔══════════════════════════════════════╗
-- ║  TOS Network Bootstrap               ║
-- ║  Terminal Operating System           ║
-- ║  Fetch a release, hand off to setup  ║
-- ╚══════════════════════════════════════╝
-- For a bare OpenOS machine that has neither a TOS install disk nor any
-- TOS files yet, but DOES have an Internet Card. This pulls the same file
-- set an install disk carries (bios.lua, install.lua, and every file
-- /tos/system_manifest.lua declares) from GitHub over
-- raw.githubusercontent.com, stages it in a scratch directory, and then
-- hands off to the downloaded install.lua exactly as if that directory
-- were a mounted floppy — every safety check install.lua already has
-- (FORCE-WIPE confirmation, BIOS fingerprint + typed confirm, post-copy
-- size verification) runs completely unchanged.
--
-- Run from OpenOS:
--   # bootstrap.lua                          (uses the built-in repo)
--   # bootstrap.lua <owner>/<repo>            (install from a fork)
--   # bootstrap.lua <owner>/<repo> <branch>
--   # bootstrap.lua <owner>/<repo> <branch> <subdir>
--   # bootstrap.lua --help                    (usage, in game)
--
-- Which drive TOS ends up on is install.lua's question, asked after the
-- download: the boot drive is only the default.
--
-- Requires an Internet Card. No card, no physical disk yet either? Craft
-- one (tier 1 is enough) or borrow one temporarily — nothing else here
-- substitutes for it, on purpose (see the internet-access note below).

local component = require("component")
local computer = require("computer")
local term = require("term")

-- Try to load OpenOS's filesystem library. Staging files needs it; the
-- internet fetch below deliberately does NOT depend on OpenOS's own
-- `internet` library (require("internet")) being intact — it talks to
-- component.internet directly, the same low-level approach TOS's own
-- kernel.internet module uses once installed, so a damaged or missing
-- OpenOS internet.lua can't take this path down with it.
local fs = nil
pcall(function() fs = require("filesystem") end)

-- ============================================================
-- Helpers — same vocabulary as install.lua, so the two scripts read as
-- one continuous flow when this hands off to it.
-- ============================================================

local gpu = component.gpu

local function color(fg)
  if gpu and gpu.setForeground then
    pcall(gpu.setForeground, fg)
  end
end

local function ok(msg)
  color(0x00FF00); print("  + " .. msg); color(0xFFFFFF)
end

local function warn(msg)
  color(0xFFFF00); print("  ! " .. msg); color(0xFFFFFF)
end

local function fail(msg)
  color(0xFF0000); print("  X " .. msg); color(0xFFFFFF)
end

local function ask(question, options, default)
  color(0xFFFF00)
  io.write(question)
  if options then
    color(0xAAAAAA)
    io.write(" [" .. table.concat(options, "/") .. "]")
  end
  if default then
    color(0x888888)
    io.write(" (default: " .. default .. ")")
  end
  color(0xFFFFFF)
  io.write(": ")
  local answer
  if term and term.read then
    local okT, result = pcall(term.read)
    if okT then
      answer = result
      if answer then answer = answer:gsub("\n$", "") end
    end
  else
    answer = io.read()
  end
  if not answer or answer == "" then return default end
  return answer
end

local function confirm(question)
  local answer = ask(question, {"y", "n"}, "y")
  return answer and (answer:lower() == "y" or answer:lower() == "yes")
end

local function pause(seconds)
  -- Best-effort — a build without os.sleep just retries immediately
  -- rather than failing the whole run over a missing convenience.
  if os.sleep then pcall(os.sleep, seconds) end
end

local BOOTSTRAP_VERSION = "1.0.0"

local LOGO_MARK = {
  "████████  ████████  ████████",
  "   ██     ██    ██  ██      ",
  "   ██     ██    ██  ████████",
  "   ██     ██    ██        ██",
  "   ██     ████████  ████████",
}

local function header()
  color(0x00AAFF)
  for _, ln in ipairs(LOGO_MARK) do print("   " .. ln) end
  color(0xFFFFFF); print()
  color(0x00FF66); print("   Strata Systems LLC"); color(0xFFFFFF)
  color(0xAAAAAA)
  print("   Terminal Operating System — Network Bootstrap v" .. BOOTSTRAP_VERSION)
  color(0xFFFFFF)
  print()
end

-- ============================================================
-- Repository configuration
-- ============================================================
-- Overridable by CLI arg so a fork, a mirror, or a different branch/
-- layout doesn't need a code change — only the built-in defaults live
-- here.
local DEFAULT_OWNER = "Evan450"
local DEFAULT_REPO  = "TOS-Terminal-Operating-System-"

-- Branches tried in order until one serves a real manifest — covers
-- both the "main" and older "master" default-branch conventions without
-- the operator needing to know which this repo uses.
local BRANCH_CANDIDATES = { "main", "master" }

--! THE ROOT OF TRUST: this file, which is short enough to read before it runs.
--! The publisher's Ed25519 public key is pinned here, and so are the digests
--! of the code that checks a signature, so neither comes from the server the
--! download does. Compare RELEASE_KEY with the key in the README of the
--! repository's optional-utilities branch, which is the same one.
local RELEASE_KEY = "dcdafa5342333048be0ad519911a6bd1ecffefcffde73879a4e246fc20d7fd8b"
--! Filled in by build/strip.lua: a digest for each verifier file, over the
--! bytes this release ships. Still this string in the source tree, which is
--! how a copy that did not come from a build knows it cannot vouch for anything.
local VERIFIER_PINS = "@VERIFIER_PINS@"

-- Subdirectory inside the repo that holds the install-disk root
-- (install.lua + bios.lua + tos/ + etc/ + usr/ + init.lua). "" means the
-- repo root IS that root. Tried in order — a repo layout guess that's
-- wrong is a "not found, try the next one" instead of a hard failure.
local SUBDIR_CANDIDATES = { "", "TOS-Release" }

--! A CLI-supplied owner/repo/branch/subdir becomes part of an HTTPS URL
--! below. Restricting the charset here isn't a security boundary against
--! a hostile operator (they could just as easily hand-edit the URL), but
--! it does stop a typo or stray whitespace from building a malformed or
--! surprising request — the same spirit as kernel.internet's URL vetting,
--! kept local because this script runs before that module is reachable.
local function safeToken(s)
  return type(s) == "string" and s ~= "" and not s:find("[%c]")
    and s:match("^[%w%.%-_/]+$") ~= nil
end

-- ============================================================
-- Internet access (raw component — see the note above on why this
-- doesn't go through OpenOS's own `internet` library)
-- ============================================================

local function internetCard()
  local addr = component.list("internet")()
  if not addr then return nil end
  local okP, p = pcall(component.proxy, addr)
  if not okP then return nil end
  return p
end

-- Sized for OpenComputers, not a desktop: a Tier 1 machine has 192 KB of
-- RAM total, and a response held as a Lua string is real RAM. The cap
-- exists to stop a hostile or broken server streaming until the machine
-- dies, not to police our own files.
--
--! IT WAS 96 KB, AND THE RELEASE GREW PAST IT. core.lua reached 99,048
--! bytes -- 744 over -- so every network install silently skipped the
--! file holding most of the shell's commands. The machine booted, and
--! then `Failed to load category 'core'` meant half the commands did not
--! exist. admin.lua at 97,660 was still squeaking under, so this was one
--! ordinary edit away from happening again on a different file.
--!
--! A constant that "the largest file is well under" is a tripwire, not a
--! limit, unless something checks. test_install_bootstrap.lua now
--! measures the real release against this number and fails when the
--! headroom runs out.
local MAX_FILE_BYTES    = 256 * 1024
local REQUEST_TIMEOUT   = 20   -- seconds of no progress before giving up
local DOWNLOAD_RETRIES  = 3
local PROBE_RETRIES     = 2

--- GET url -> body, err, status. Retries transient failures; a clean
--- non-200 (404, etc.) returns immediately since retrying won't change
--- "the file isn't there".
--! `onWait` is called while the request is in flight so a caller can
--! show that something is still happening. A probe that prints
--! "probing main ... " and then goes silent for ten seconds is
--! indistinguishable from one that has hung, and the operator's only
--! options are to guess or to reboot.
local function httpGet(card, url, retries, onWait)
  retries = retries or DOWNLOAD_RETRIES
  local function tick() if onWait then pcall(onWait) end end
  for attempt = 1, retries do
    local okReq, handle, reason = pcall(card.request, url, nil,
      { ["user-agent"] = "TOS-Bootstrap/" .. BOOTSTRAP_VERSION })
    if okReq and handle then
      local parts, total, status = {}, 0, nil
      local failed, failReason = false, nil
      local deadline = computer.uptime() + REQUEST_TIMEOUT
      while true do
        local okRead, chunk, readErr = pcall(handle.read)
        if not okRead then failed = true; failReason = tostring(chunk); break end
        if handle.response and not status then
          local okR, code = pcall(handle.response)
          if okR and code then status = code end
        end
        if chunk == nil then
          if readErr then failed = true; failReason = tostring(readErr) end
          break
        end
        if #chunk > 0 then
          total = total + #chunk
          if total > MAX_FILE_BYTES then
            failed = true
            failReason = "response exceeds " .. MAX_FILE_BYTES .. " bytes"
            break
          end
          parts[#parts + 1] = chunk
          deadline = computer.uptime() + REQUEST_TIMEOUT
        else
          tick()
          pause(0)
        end
        if computer.uptime() > deadline then
          failed = true; failReason = "timed out after " .. REQUEST_TIMEOUT .. "s"
          break
        end
      end
      pcall(function() handle.close() end)
      if not failed then
        if status and status ~= 200 then
          return nil, "HTTP " .. tostring(status), status
        end
        return table.concat(parts), nil, status
      end
      if attempt < retries then pause(1) end
    else
      if attempt < retries then pause(1) end
    end
  end
  return nil, "request failed after " .. retries .. " attempt(s)"
end

local function rawUrl(owner, repo, branch, subdir, path)
  local prefix = (subdir ~= "" and ("/" .. subdir) or "")
  return string.format("https://raw.githubusercontent.com/%s/%s/%s%s%s",
    owner, repo, branch, prefix, path)
end

-- ============================================================
-- Manifest parsing — identical contract to install.lua's loadManifest:
-- text-only load() with an empty environment, never executed with
-- ambient globals. kernel.serialize is not reachable from bare OpenOS
-- (the TOS kernel's require() search paths don't exist yet), so unlike
-- install.lua's disk-mode path this never even attempts that branch —
-- it goes straight to the same safe fallback install.lua would land on
-- anyway in this exact scenario.
-- ============================================================

local function parseManifest(source)
  if #source > 256 * 1024 then
    return nil, "manifest exceeds 256 KB sanity cap"
  end
  local fn, err = load(source, "=manifest", "t", {})
  if not fn then return nil, "manifest parse error: " .. tostring(err) end
  local ok2, result = pcall(fn)
  if not ok2 then return nil, "manifest run error: " .. tostring(result) end
  if type(result) ~= "table" then return nil, "manifest did not return a table" end
  return result
end

-- ============================================================
-- Arguments
-- ============================================================
--! "-h" and "--help" used to be read as an owner/repo, rejected as
--! malformed, and then the script carried on to ask whether to download --
--! so the obvious thing to type in game, with no wiki to hand, produced a
--! warning about a repository nobody named. Anything that starts with "-" is
--! an option, never a repository: help is answered, anything else is refused.
local function classifyArgs(args)   --[[TEST-EXTRACT]]
  local out = { positional = {} }
  for _, a in ipairs(args) do
    if a == "-h" or a == "--help" or a == "-?" or a == "/?" then
      out.help = true
    elseif a == "--allow-unsigned" then
      out.allowUnsigned = true
    elseif type(a) == "string" and a:sub(1, 1) == "-" then
      out.unknown = out.unknown or a
    else
      out.positional[#out.positional + 1] = a
    end
  end
  return out
end                                 --[[/TEST-EXTRACT]]

-- Kept to 50 columns so a Tier 1 screen shows it unwrapped.
local function printHelp()
  print("Downloads TOS over the internet and installs it.")
  print()
  print("Usage:")
  print("  bootstrap.lua [owner/repo [branch [subdir]]]")
  print("  bootstrap.lua --help")
  print()
  print("With no arguments it uses the official repo")
  print("(" .. DEFAULT_OWNER .. "/" .. DEFAULT_REPO .. ").")
  print("A fork or another branch can be named instead.")
  print()
  print("You need:")
  print("  - an Internet Card in this computer")
  print("  - about 1.4 MB free for the download (it picks")
  print("    the drive with the most room)")
  print()
  print("It checks every file against the release's")
  print("digests, then runs the installer. The installer")
  print("asks which drive TOS goes on (the boot drive is")
  print("only the default), asks a few setup questions,")
  print("and offers to flash the TOS BIOS. Nothing is")
  print("installed until you confirm.")
  print()
  print("Run it by its full path, e.g. /bootstrap.lua.")
end

-- ============================================================
-- Main
-- ============================================================

local parsed = classifyArgs({...})

term.clear()
header()

if parsed.help or parsed.unknown then
  if parsed.unknown and not parsed.help then
    fail("Unknown option: " .. tostring(parsed.unknown))
    print()
  end
  printHelp()
  return
end

if not fs then
  fail("OpenOS filesystem library unavailable — cannot stage a download.")
  warn("Run this from OpenOS, not a bare Lua interpreter.")
  return
end

local card = internetCard()
if not card then
  fail("No Internet Card found on this computer.")
  warn("Craft one (Tier 1 is enough) and place it in this computer or")
  warn("server, or install from a physical disk with install.lua instead.")
  return
end
ok("Internet Card found")
print()

-- CLI overrides: bootstrap.lua [owner/repo] [branch] [subdir]
local cliArgs = parsed.positional
local owner, repoName = DEFAULT_OWNER, DEFAULT_REPO
if cliArgs[1] then
  local o, r = cliArgs[1]:match("^([^/]+)/(.+)$")
  if o and r and safeToken(o) and safeToken(r) then
    owner, repoName = o, r
  else
    warn("Ignoring malformed owner/repo argument: " .. tostring(cliArgs[1]))
  end
end
local branches = BRANCH_CANDIDATES
if cliArgs[2] then
  if safeToken(cliArgs[2]) then branches = { cliArgs[2] }
  else warn("Ignoring malformed branch argument: " .. tostring(cliArgs[2])) end
end
local subdirs = SUBDIR_CANDIDATES
if cliArgs[3] ~= nil then
  if cliArgs[3] == "" or safeToken(cliArgs[3]) then subdirs = { cliArgs[3] }
  else warn("Ignoring malformed subdir argument: " .. tostring(cliArgs[3])) end
end

ok("Repository: " .. owner .. "/" .. repoName)
print()

if not confirm("Download TOS from the internet and run the installer?") then
  print("Cancelled.")
  return
end
print()

-- ── Locate a reachable (branch, subdir) combo ─────────────────────
color(0x00AAFF); print("--- Locating release files ---"); color(0xFFFFFF)
local baseBranch, baseSubdir, manifestSrc
for _, branch in ipairs(branches) do
  for _, subdir in ipairs(subdirs) do
    local label = branch .. (subdir ~= "" and ("/" .. subdir) or "")
    io.write("  probing " .. label .. " ")
    --! A dot every third of a second while the request is in flight, so
    --! a slow probe LOOKS slow instead of looking hung. Throttled rather
    --! than one-per-read: the read loop spins far faster than a person
    --! can read, and a wall of dots is its own kind of noise.
    --!
    --! Capped so an unreachable host cannot push the label off an
    --! 80-column line -- at 20 s of REQUEST_TIMEOUT this would otherwise
    --! print ~60 dots and wrap.
    local dots = 0
    local lastDot = computer.uptime()
    local function tickDot()
      local now = computer.uptime()
      if now - lastDot >= 0.3 and dots < 40 then
        lastDot = now
        dots = dots + 1
        io.write(".")
      end
    end
    local url = rawUrl(owner, repoName, branch, subdir, "/tos/system_manifest.lua")
    local body, err = httpGet(card, url, PROBE_RETRIES, tickDot)
    io.write(" ")
    if body and #body > 0 then
      color(0x00FF00); print("found"); color(0xFFFFFF)
      baseBranch, baseSubdir, manifestSrc = branch, subdir, body
      break
    else
      color(0xAAAAAA); print("not there (" .. tostring(err) .. ")"); color(0xFFFFFF)
    end
  end
  if manifestSrc then break end
end
print()

if not manifestSrc then
  --! A repo can be reachable, current, and still unusable: if its files
  --! were uploaded WITHOUT their directory structure (everything dumped
  --! at the root), the manifest is there but every path it declares —
  --! /tos/kernel/init.lua and the rest — resolves to nothing. Worse, a
  --! flat layout is lossy in a way no download logic can undo: TOS ships
  --! six different init.lua files (kernel, net, shell, panels, compat,
  --! and the root boot loader) plus two event.lua and two internet.lua,
  --! and a flat repo can hold exactly one of each. Detect that shape and
  --! say so, rather than leaving an operator staring at four 404s.
  local flat = httpGet(card, rawUrl(owner, repoName, branches[1], "",
    "/system_manifest.lua"), PROBE_RETRIES)
  if flat and #flat > 0 then
    fail("This repo has a FLAT layout — no directory structure.")
    warn("system_manifest.lua is at the root, but the files it declares")
    warn("(/tos/kernel/init.lua and the rest) have no directories to live")
    warn("in. That cannot be installed from, and it cannot be repaired by")
    warn("downloading harder: TOS ships six separate init.lua files, and a")
    warn("flat repo can only hold one of them.")
    warn("Fix: push the release tree WITH its directories (tos/, etc/,")
    warn("usr/) to the repo, then re-run this script.")
    return
  end
  fail("Could not find a TOS release under " .. owner .. "/" .. repoName ..
    " on any of: " .. table.concat(branches, ", "))
  warn("If this is a fork or the layout changed, point at it directly:")
  warn("  bootstrap.lua " .. owner .. "/" .. repoName .. " <branch> <subdir>")
  return
end

local manifest, mErr = parseManifest(manifestSrc)
if not manifest then
  fail("Cannot parse the downloaded manifest: " .. tostring(mErr))
  return
end
ok("Using " .. owner .. "/" .. repoName .. "@" .. baseBranch ..
  (baseSubdir ~= "" and ("/" .. baseSubdir) or "") ..
  " (" .. #manifest .. " files declared)")
print()

-- ============================================================
-- Download integrity
-- ============================================================
--! WHAT THIS PROVES, as a chain with one end here. This file holds the
--! publisher's key and a hasher of its own. The hasher checks the verifier
--! files against digests pinned in this file, the verifier checks the
--! publisher's signature over the manifest, and the manifest holds a SHA-256
--! for every file. So a release is what the publisher signed, whoever serves
--! it. A hostile server can stop an install. It cannot change one.
--!
--! The hasher used to be a download, checked against the manifest it was about
--! to be used on, which proved nothing against a hostile server and said so.

--- SHA-256, as hex. Lives in this file so that it is not a download.
local function sha256hex(msg)                  --[[TEST-EXTRACT]]
  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }
  local M = 0xFFFFFFFF
  local function rr(x, n) return ((x >> n) | (x << (32 - n))) & M end
  local len = #msg
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. string.pack(">I8", len * 8)
  local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
  local w = {}
  for p = 1, #msg, 64 do
    for i = 0, 15 do w[i + 1] = string.unpack(">I4", msg, p + i * 4) end
    for i = 17, 64 do
      local x, y = w[i - 15], w[i - 2]
      w[i] = (w[i - 16] + (rr(x, 7) ~ rr(x, 18) ~ (x >> 3)) + w[i - 7]
        + (rr(y, 17) ~ rr(y, 19) ~ (y >> 10))) & M
    end
    local a, b, c, d, e, f, g, t = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 1, 64 do
      local t1 = (t + (rr(e, 6) ~ rr(e, 11) ~ rr(e, 25)) + ((e & f) ~ (~e & g)) + K[i] + w[i]) & M
      local t2 = ((rr(a, 2) ~ rr(a, 13) ~ rr(a, 22)) + ((a & b) ~ (a & c) ~ (b & c))) & M
      t, g, f, e, d, c, b, a = g, f, e, (d + t1) & M, c, b, a, (t1 + t2) & M
    end
    h[1], h[2], h[3], h[4] = (h[1] + a) & M, (h[2] + b) & M, (h[3] + c) & M, (h[4] + d) & M
    h[5], h[6], h[7], h[8] = (h[5] + e) & M, (h[6] + f) & M, (h[7] + g) & M, (h[8] + t) & M
  end
  return (string.format("%08x%08x%08x%08x%08x%08x%08x%08x", table.unpack(h)))
end                                            --[[/TEST-EXTRACT]]

local hashes = {}
for _, entry in ipairs(manifest) do
  if type(entry) == "table" and type(entry.path) == "string"
     and type(entry.hash) == "string" and #entry.hash == 64 then
    hashes[entry.path] = entry.hash:lower()
  end
end

--! What the verifier runs in. Pure computation over strings: no load, no os,
--! io or filesystem, no component or computer. The files were checked against
--! pinned digests before they get here, and they still get no more than this.
local VERIFIER_ENV = {
  string = string, table = table, math = math,
  tonumber = tonumber, tostring = tostring, type = type,
  select = select, ipairs = ipairs, pairs = pairs, pcall = pcall,
  error = error, assert = assert, setmetatable = setmetatable,
}

--- Is this manifest what the publisher signed? True, or nil and why. `get`
--- fetches a path of the release; everything else comes from this file.
--! `yield` is not a nicety. Ed25519 in pure Lua takes seconds on a real
--! machine, and curve25519field stays alive by asking kernel.process to yield.
--! There is no kernel.process on OpenOS, so without this it asks nobody, and
--! OC kills a machine that goes 5 seconds without yielding.
local function verifyRelease(manifestSrc, get, key, pins, env, hash, yield)   --[[TEST-EXTRACT]]
  if type(pins) ~= "table" then
    return nil, "this copy of bootstrap.lua is not from a release build"
  end
  local raw = get("/tos/system_manifest.sig")
  if not raw then return nil, "the release has no signature" end
  local fn = load(raw, "=signature", "t", {})
  local okS, sig = false, nil
  if fn then okS, sig = pcall(fn) end
  if not okS or type(sig) ~= "table" or type(sig.sig) ~= "string" then
    return nil, "its signature cannot be read"
  end
  if sig.key ~= key then return nil, "it is signed with a different key" end

  local mods = { ["kernel.process"] = { yieldCooperative = yield or function() end } }
  local venv = { require = function(name)
    return mods[name] or error("verifier wants " .. tostring(name))
  end }
  for k, v in pairs(env) do venv[k] = v end
  for _, m in ipairs({ { "kernel.sha512", "/tos/kernel/sha512.lua" },
                       { "kernel.curve25519field", "/tos/kernel/curve25519field.lua" },
                       { "kernel.ed25519", "/tos/kernel/ed25519.lua" } }) do
    local body = get(m[2])
    if not body then return nil, "could not fetch " .. m[2] end
    if hash(body) ~= pins[m[2]] then
      return nil, m[2] .. " is not the file this bootstrap was built with"
    end
    local chunk = load(body, "=" .. m[2], "t", venv)
    local okM, mod = false, nil
    if chunk then okM, mod = pcall(chunk) end
    if not okM or type(mod) ~= "table" then return nil, "the verifier did not load" end
    mods[m[1]] = mod
  end

  local function bin(hex)
    return (hex:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end))
  end
  local okV, good = pcall(mods["kernel.ed25519"].verify, manifestSrc, bin(sig.sig), bin(key))
  if okV and good then return true end
  return nil, "its signature does not match its manifest"
end                                            --[[/TEST-EXTRACT]]

do
  local official = owner == DEFAULT_OWNER and repoName == DEFAULT_REPO and baseBranch == "main"
  io.write("  checking the publisher's signature... ")
  local signed, why = verifyRelease(manifestSrc, function(path)
    return httpGet(card, rawUrl(owner, repoName, baseBranch, baseSubdir, path))
  end, RELEASE_KEY, VERIFIER_PINS, VERIFIER_ENV, sha256hex,
    function() computer.pullSignal(0) end)
  if signed then
    color(0x00FF00); print("valid"); color(0xFFFFFF)
    ok("This release is the one the publisher signed.")
  elseif official and not parsed.allowUnsigned then
    color(0xFF0000); print("REFUSED"); color(0xFFFFFF)
    fail("This release cannot be trusted: " .. tostring(why) .. ".")
    fail("Nothing was downloaded or installed. Try again later: a release")
    fail("is signed by hand. --allow-unsigned goes ahead anyway, and then")
    fail("nothing vouches for what this machine runs.")
    return
  else
    color(0xFFFF00); print("none"); color(0xFFFFFF)
    warn("Not the publisher's signed release: " .. tostring(why) .. ".")
    warn("Nothing vouches for this code but the place it came from.")
  end
  print()
end

local sha256, verifyOn = { hex = sha256hex }, next(hashes) ~= nil
if verifyOn then
  local declared = 0
  for _ in pairs(hashes) do declared = declared + 1 end
  ok(declared .. " of " .. #manifest .. " files carry a digest and will be verified")
  print()
else
  warn("This release ships no digests, so downloads cannot be verified.")
  print()
end

-- ── Staging directory, chosen by FREE SPACE ────────────────────────
--! /tmp used to be picked unconditionally. On a real machine that is a
--! tmpfs of a few hundred KB, and the release is ~1.2 MB across 152
--! files -- so it filled, and every remaining write failed with "cannot
--! open staging file for write". The operator saw 142 identical errors
--! and no mention of space, which is the least useful way to say "the
--! disk is full".
--!
--! So: consider the candidates, ask each how much room it actually has,
--! and take the roomiest. /tmp still wins when it is big enough, because
--! staging in RAM leaves nothing behind on a failed install.
local function freeSpace(path)
  local okP, proxy = pcall(fs.get, path)
  if not okP or not proxy then return nil end
  local okT, total = pcall(proxy.spaceTotal)
  local okU, used  = pcall(proxy.spaceUsed)
  if not (okT and okU) or type(total) ~= "number" or type(used) ~= "number" then
    return nil
  end
  --! An unmanaged or read-only mount can report a total of 0; treat that
  --! as "unusable" rather than as "0 bytes free but maybe fine".
  if total <= 0 then return nil end
  return total - used
end

local function kb(n) return string.format("%.0f KB", n / 1024) end

--! REMOVE A TREE, LEAVES FIRST. OpenComputers' filesystem component does
--! not recurse: the disk-backed one compiles down to Java's File.delete(),
--! which refuses a non-empty directory, and OpenOS's filesystem.remove
--! hands the path straight to it (its own `rm` implements -r itself, in
--! the shell). So `fs.remove(stagingDir)` on a staging tree full of files
--! has always returned false.
--!
--! Operator report, real emulator: the bootstrap "doesn't clean up after
--! itself". It believed it did -- the cleanup below is written, and its
--! comment explains why reclaiming ~1.2 MB matters on a 4 MB boot drive
--! -- but the call could not work, so every install left a second full
--! copy of the release behind, and the stale-directory sweep at the top
--! of a retry could not clear it either.
local function removeTree(path)
  if not fs.exists(path) then return true end
  if fs.isDirectory(path) then
    local names = {}
    -- OpenOS's fs.list returns an iterator; a plain table is also
    -- tolerated so this does not depend on which one you get.
    local okL, it = pcall(fs.list, path)
    if okL and it then
      if type(it) == "function" then
        for name in it do names[#names + 1] = name end
      elseif type(it) == "table" then
        for _, name in ipairs(it) do names[#names + 1] = name end
      end
    end
    for _, name in ipairs(names) do
      local child = path .. "/" .. tostring(name):gsub("/$", "")
      removeTree(child)
    end
  end
  local okR = pcall(fs.remove, path)
  return okR and not fs.exists(path)
end

--! Roughly what the payload needs. Not read from the manifest, which
--! declares no sizes -- it is a floor for WARNING only, never a refusal,
--! so an unusual layout that knows better is not blocked by our guess.
local NEED_BYTES = 1400 * 1024

local stagingDir, stagingFree
do
  local candidates = {}
  if fs.isDirectory("/tmp")  then candidates[#candidates + 1] = { "/tmp/tos-netinstall",  "/tmp"  } end
  if fs.isDirectory("/home") then candidates[#candidates + 1] = { "/home/tos-netinstall", "/home" } end
  candidates[#candidates + 1] = { "/tos-netinstall-tmp", "/" }

  local best, bestFree
  for _, c in ipairs(candidates) do
    local free = freeSpace(c[2])
    if free and (not bestFree or free > bestFree) then best, bestFree = c[1], free end
  end

  --! Every candidate refused to report. Fall back to the old behaviour
  --! rather than refusing to install: not knowing the free space is not
  --! the same as knowing there is none.
  stagingDir  = best or ((fs.isDirectory("/tmp") and "/tmp/tos-netinstall") or "/tos-netinstall-tmp")
  stagingFree = bestFree

  if stagingFree then
    ok("Staging in " .. stagingDir .. " (" .. kb(stagingFree) .. " free)")
    if stagingFree < NEED_BYTES then
      warn("That is under the ~" .. kb(NEED_BYTES) .. " the release needs.")
      warn("The download will likely run out of space partway through.")
      warn("Free some room, or install from a disk instead. Continuing.")
    end
  end
end
if fs.exists(stagingDir) then
  warn("Removing a stale staging directory from a previous run: " .. stagingDir)
  removeTree(stagingDir)
end
if not fs.makeDirectory(stagingDir) then
  fail("Cannot create staging directory: " .. stagingDir)
  return
end

-- ── Build the file list: every manifest entry, plus install.lua and
--    bios.lua, which live at the disk root and are not part of the
--    running-system manifest (mirrors what the `deploy` command puts
--    on a physical install disk — see extras.lua's deploy command). ──
local fileList, seen = {}, {}
for _, entry in ipairs(manifest) do
  if type(entry) == "table" and type(entry.path) == "string" and not seen[entry.path] then
    seen[entry.path] = true
    fileList[#fileList + 1] = entry.path
  end
end
if not seen["/install.lua"] then fileList[#fileList + 1] = "/install.lua" end
if not seen["/bios.lua"] then fileList[#fileList + 1] = "/bios.lua" end

-- ── Download ─────────────────────────────────────────────────────
color(0x00AAFF)
print("--- Downloading " .. #fileList .. " files ---")
color(0xFFFFFF)
local copied, failed = 0, 0
local failedPaths = {}
local outOfSpace = false
for i, path in ipairs(fileList) do
  local dir = path:match("^(.+)/[^/]+$")
  if dir then
    local acc = ""
    for seg in dir:gmatch("[^/]+") do
      acc = acc .. "/" .. seg
      if not fs.isDirectory(stagingDir .. acc) then fs.makeDirectory(stagingDir .. acc) end
    end
  end
  local url = rawUrl(owner, repoName, baseBranch, baseSubdir, path)
  local body, err = httpGet(card, url)
  if body then
    --! Verify BEFORE writing. A file that fails its digest never reaches
    --! the staging tree, so a later retry cannot find a bad copy sitting
    --! there and a partial install cannot be completed by accident.
    local want = verifyOn and hashes[path] or nil
    if want and sha256.hex(body) ~= want then
      failed = failed + 1
      failedPaths[#failedPaths + 1] = path .. ": DIGEST MISMATCH (corrupt or tampered)"
      body = nil
    end
  end
  if body then
    local f = io.open(stagingDir .. path, "w")
    if f then
      f:write(body); f:close()
      copied = copied + 1
    else
      failed = failed + 1
      --! A write that fails because the filesystem is FULL will fail for
      --! every remaining file too, so stop and say so once. Grinding on
      --! produced 142 identical "cannot open staging file for write"
      --! lines that never mentioned space -- the operator was left to
      --! infer the cause from the volume of the noise.
      local freeNow = freeSpace(stagingDir)
      if freeNow and freeNow < 4096 then
        outOfSpace = true
        failedPaths[#failedPaths + 1] = path .. ": OUT OF SPACE (" .. kb(freeNow) .. " free)"
        break
      end
      failedPaths[#failedPaths + 1] = path .. ": cannot open staging file for write"
    end
  elseif err == nil then
    -- Already counted as a digest failure above; nothing more to say.
  else
    -- bios.lua is not on every install disk either; a 404 for it
    -- specifically is not a failure, just "this release has none".
    if path == "/bios.lua" then
      -- silently skip
    else
      failed = failed + 1
      failedPaths[#failedPaths + 1] = path .. ": " .. tostring(err)
    end
  end
  if i % 10 == 0 or i == #fileList then
    io.write(string.format("\r  %d/%d files (%d failed)   ", i, #fileList, failed))
  end
end
print()
print()

--! Out of space is a different failure from "some downloads went wrong",
--! and the remedy is different too, so it gets its own exit rather than
--! being buried in a list of paths.
if outOfSpace then
  fail("Ran out of space in " .. stagingDir .. " after " .. copied .. " file(s).")
  print()
  warn("The release needs roughly " .. kb(NEED_BYTES) .. " of scratch space, and")
  warn("this filesystem does not have it. Nothing was written outside")
  warn(stagingDir .. ", and the target disk was never touched.")
  print()
  warn("Options, in the order worth trying:")
  warn("  - Install from a floppy or install disk: no scratch space needed.")
  warn("  - Free space on a larger drive; bootstrap stages wherever there")
  warn("    is the most room, so it will pick it up automatically.")
  warn("  - On a machine with only a small tmpfs, an installed HDD with")
  warn("    free space is enough -- it does not have to be the target.")
  removeTree(stagingDir)
  return
end

if failed == 0 then
  ok("Downloaded " .. copied .. " files")
else
  fail(failed .. " file(s) failed to download:")
  for i = 1, math.min(5, #failedPaths) do warn("  " .. failedPaths[i]) end
  if #failedPaths > 5 then warn("  (+" .. (#failedPaths - 5) .. " more)") end
end
print()

--! ANY missing file refuses the install, not just a mismatched digest.
--!
--! This used to reason that "install.lua's own copy+verify pass will
--! catch whatever is missing". It does not stop anything: a file the
--! manifest marks `critical = false` is copied if present and shrugged
--! at if absent, so the install completed and the machine booted with
--! core.lua -- most of the shell's commands -- simply not there. The
--! operator found out later, from `verify`, that a file was gone.
--!
--! An incomplete install is not a lesser kind of success. The whole
--! reason to hand install.lua a staging tree is that it is a COMPLETE
--! copy of the release; if it is not, the thing being installed is not
--! the release, and only the person running it can decide to accept
--! that. So it stops, names what is missing, and leaves the choice with
--! them instead of quietly shipping a crippled system.
do
  local absent = {}
  for _, msg in ipairs(failedPaths) do
    if not msg:find("DIGEST MISMATCH", 1, true) then absent[#absent + 1] = msg end
  end
  if #absent > 0 then
    fail(#absent .. " file(s) never made it into the staging tree:")
    for i = 1, math.min(8, #absent) do warn("  " .. absent[i]) end
    if #absent > 8 then warn("  (+" .. (#absent - 8) .. " more)") end
    print()
    fail("Refusing to install an incomplete release.")
    warn("Installing anyway would produce a machine that boots and is")
    warn("quietly missing pieces -- that is how a release once shipped")
    warn("without the file holding most of the shell's commands.")
    print()
    warn("Retry: these are usually transient. If the same file fails")
    warn("every time, the release is broken; install from a disk and")
    warn("report which file.")
    removeTree(stagingDir)
    return
  end
end

--! A digest mismatch is a different claim from a missing file: the
--! repository served bytes it does not agree with. Reported separately
--! because the remedy differs -- a retry fixes a dropped download, and
--! does not fix a server disagreeing with its own manifest.
do
  local tampered = {}
  for _, msg in ipairs(failedPaths) do
    if msg:find("DIGEST MISMATCH", 1, true) then tampered[#tampered + 1] = msg end
  end
  if #tampered > 0 then
    fail(#tampered .. " file(s) did not match the digest the manifest declares:")
    for i = 1, math.min(8, #tampered) do warn("  " .. tampered[i]) end
    if #tampered > 8 then warn("  (+" .. (#tampered - 8) .. " more)") end
    print()
    fail("Refusing to install. Nothing was written outside " .. stagingDir .. ".")
    --! The likeliest cause by far is a release published minutes ago, not
    --! an attack, and saying so first stops an operator hunting one.
    --! GitHub caches branch URLs, so a fetch during a release can pick up
    --! the NEW manifest and files still cached from the OLD one. Every
    --! digest then mismatches for an entirely boring reason. Said before
    --! the tampering wording, because a scary message people learn to
    --! ignore is worse than no message.
    warn("Most likely: a release was published in the last few minutes and")
    warn("the download caught it half-updated — the host serves cached files")
    warn("for a while after a push. Wait five minutes and retry; that fixes")
    warn("this on its own, and no wait is needed for a disk install.")
    print()
    warn("If it repeats after that, treat it as real: a mangling proxy or a")
    warn("truncated transfer looks the same as tampering from here, and so")
    warn("does a release that is not what it claims. Install from a disk.")
    return
  end
end

-- install.lua is the one file bootstrap cannot proceed without — every
-- other manifest entry's fate is install.lua's own copy+verify problem
-- (it re-checks sizes against this staging directory exactly as it
-- would against a physical disk), same as a floppy that lost a sector.
local installPath = stagingDir .. "/install.lua"
local installStaged = fs.exists(installPath) and (fs.size(installPath) or 0) > 0
if not installStaged then
  fail("install.lua did not download successfully — nothing to hand off to.")
  warn("Retry, or point at the release directly if the layout is nonstandard:")
  warn("  bootstrap.lua " .. owner .. "/" .. repoName .. " " .. baseBranch ..
    (baseSubdir ~= "" and (" " .. baseSubdir) or " \"\""))
  return
end

-- ── Hand off to the downloaded install.lua ──────────────────────────
-- Loaded and called directly (not via shell.execute) so this doesn't
-- depend on any particular shell implementation being present or on
-- OpenOS's os.getenv("_") convention for locating the invoking script.
-- The staging directory is passed as install.lua's first argument,
-- which its own findInstallDisk() takes as an explicit source override
-- — the same door a scripted/unattended install would use, and more
-- reliable here than path inference since this script's directory has
-- no fixed relationship to where the release got staged.
color(0x00AAFF); print("--- Handing off to install.lua ---"); color(0xFFFFFF)
ok("Staged at " .. stagingDir)
print()

local chunk, lerr = loadfile(installPath)
if not chunk then
  fail("Downloaded install.lua does not parse: " .. tostring(lerr))
  warn("The file may have been corrupted in transit — try again.")
  return
end

local hok, herr = pcall(chunk, stagingDir)
if not hok then
  fail("install.lua exited with an error: " .. tostring(herr))
  warn("You can retry it directly:")
  warn("  " .. installPath .. " " .. stagingDir)
  warn("Leaving the staging tree in place so a retry needs no re-download.")
  return
end

--! Reclaim the staging tree once it has served its purpose.
--!
--! It is a second full copy of the release -- ~1.2 MB, and on a machine
--! whose tmpfs was too small it lands on a real disk. A 4 MB boot drive
--! carrying OpenOS plus TOS plus an abandoned copy of TOS was left with
--! 550 KB free after an install, which is most of the way to the next
--! failure. It is kept on FAILURE, where a retry can reuse it; on
--! success there is nothing left to want from it.
do
  local freed = stagingFree and freeSpace(stagingDir)
  if removeTree(stagingDir) then
    local after = freeSpace("/")
    if after and freed then
      ok("Removed the staging copy (" .. kb(after) .. " free now)")
    else
      ok("Removed the staging copy from " .. stagingDir)
    end
  else
    warn("Could not remove the staging copy at " .. stagingDir .. ".")
    warn("It is a full second copy of the release; delete it to reclaim")
    warn("the space: rm -r " .. stagingDir)
  end
end

--! ...AND THE SCRIPT ITSELF, which is the other half of "it doesn't clean
--! up after itself". This is downloaded to the filesystem ROOT (the
--! documented one-liner saves it to /bootstrap.lua, and it has to be an
--! absolute path because the root is not on OpenOS's PATH). It is dead
--! weight the moment the install succeeds: the machine reboots into TOS,
--! and a second install would re-download it in one line anyway.
--!
--! Only on SUCCESS, only the file we were actually run from, and only
--! when that is a plain file at the root -- never a guess. Removing the
--! running script is safe: it was read into memory before it ran.
--! ...and "at the root" now MEANS at the root. The comment above has said
--! so since this was written; the code only prepended a slash to a relative
--! name and then removed whatever `arg[0]` pointed at, anywhere on the disk.
--! Nothing hit it while the documented install was `wget -f … /bootstrap.lua`,
--! because that always is at the root -- but the OPPM package installs this
--! file to /usr/bin, where `oppm` keeps an ownership record. Deleting a file
--! out from under a package manager leaves it certain it installed something
--! that is no longer there, and `oppm uninstall` then fails on a machine
--! whose install actually succeeded. A managed copy is not ours to remove.
-- Pure, and named, so the decision can be tested without running an
-- installer: test_install_bootstrap.lua lifts THIS function out of this
-- file and calls it, rather than grepping for the guard and hoping.
local function selfPathToReclaim(a0)   --[[TEST-EXTRACT]]
  if type(a0) ~= "string" or a0 == "" then return nil end
  local p = a0
  if p:sub(1, 1) ~= "/" then p = "/" .. p end
  if p:find("/", 2, true) then return nil end   -- not at the root: someone else's
  return p
end                                    --[[/TEST-EXTRACT]]

do
  local self = selfPathToReclaim((arg and arg[0]) or nil)
  if self and fs.exists(self) and not fs.isDirectory(self) then
    if pcall(fs.remove, self) and not fs.exists(self) then
      ok("Removed " .. self .. " (re-download it with the same one-liner)")
    else
      warn("Could not remove " .. self .. "; delete it when convenient.")
    end
  end
end
