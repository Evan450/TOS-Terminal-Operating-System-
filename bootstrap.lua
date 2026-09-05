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
-- RAM total, and a response held as a Lua string is real RAM. The
-- largest individual TOS source file is well under this.
local MAX_FILE_BYTES    = 96 * 1024
local REQUEST_TIMEOUT   = 20   -- seconds of no progress before giving up
local DOWNLOAD_RETRIES  = 3
local PROBE_RETRIES     = 2

--- GET url -> body, err, status. Retries transient failures; a clean
--- non-200 (404, etc.) returns immediately since retrying won't change
--- "the file isn't there".
local function httpGet(card, url, retries)
  retries = retries or DOWNLOAD_RETRIES
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
-- Main
-- ============================================================

term.clear()
header()

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
local cliArgs = {...}
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

if not confirm("Download TOS from the internet and install it here?") then
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
    io.write("  probing " .. label .. " ... ")
    local url = rawUrl(owner, repoName, branch, subdir, "/tos/system_manifest.lua")
    local body, err = httpGet(card, url, PROBE_RETRIES)
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
--! WHAT THIS DOES AND DOES NOT PROVE. The release manifest carries a
--! SHA-256 for every file it lists, so once the manifest is in hand every
--! subsequent download can be checked against it. That turns a truncated
--! transfer, a proxy that mangles line endings, or a file swapped in
--! flight into a loud refusal instead of a machine that boots something
--! subtly wrong.
--!
--! It does NOT prove the release is genuine. The manifest and the files
--! come from the same place over the same connection: whoever can rewrite
--! one can rewrite the other. Verifying downloads against it means "these
--! are the bytes that repository is serving", not "these are the bytes
--! Strata published". Closing that gap needs a signature checked against
--! a key pinned HERE, in this file, rather than fetched alongside the
--! thing it vouches for -- tracked, not done.
--!
--! Bootstrapping the hasher is the ordering problem: sha256.lua is itself
--! one of the downloads. It is fetched first and checked against its own
--! manifest entry, which catches corruption but is obviously circular
--! against a hostile server. Stated plainly rather than dressed up.
local hashes = {}
for _, entry in ipairs(manifest) do
  if type(entry) == "table" and type(entry.path) == "string"
     and type(entry.hash) == "string" and #entry.hash == 64 then
    hashes[entry.path] = entry.hash:lower()
  end
end

local sha256, verifyOn = nil, false
do
  local declared = 0
  for _ in pairs(hashes) do declared = declared + 1 end
  if declared == 0 then
    warn("This release ships no digests — downloads cannot be verified.")
    warn("Older releases predate them; the install will still work, but a")
    warn("corrupted transfer will not be caught here.")
    print()
  else
    io.write("  fetching the hasher ... ")
    local SHA_PATH = "/tos/kernel/sha256.lua"
    local body = httpGet(card, rawUrl(owner, repoName, baseBranch, baseSubdir, SHA_PATH))
    if not body then
      color(0xFFFF00); print("unavailable"); color(0xFFFFFF)
      warn("Could not fetch " .. SHA_PATH .. "; downloads will NOT be verified.")
      print()
    else
      local chunk = load(body, "=sha256", "t", {})
      local okS, mod = false, nil
      if chunk then okS, mod = pcall(chunk) end
      if okS and type(mod) == "table" and mod.hex then
        -- Circular by construction; see the note above.
        if hashes[SHA_PATH] and mod.hex(body) ~= hashes[SHA_PATH] then
          color(0xFF0000); print("CORRUPT"); color(0xFFFFFF)
          fail("sha256.lua does not match its own manifest entry.")
          fail("Refusing to install from a repository that is inconsistent")
          fail("with itself. Retry; if it persists, the release is broken.")
          return
        end
        sha256, verifyOn = mod, true
        color(0x00FF00); print("ok"); color(0xFFFFFF)
        ok(declared .. " of " .. #manifest .. " files carry a digest and will be verified")
        print()
      else
        color(0xFFFF00); print("unusable"); color(0xFFFFFF)
        warn("sha256.lua did not load; downloads will NOT be verified.")
        print()
      end
    end
  end
end

-- ── Staging directory, with a fallback if /tmp isn't there ─────────
-- /tmp is OpenOS's normal tmpfs mount and is present on any install
-- that boots to a shell at all, but a stripped-down or custom image
-- might not have it — fall back to a root-level scratch dir instead
-- of failing outright.
local stagingDir = (fs.isDirectory("/tmp") and "/tmp/tos-netinstall")
  or "/tos-netinstall-tmp"
if fs.exists(stagingDir) then
  warn("Removing a stale staging directory from a previous run: " .. stagingDir)
  pcall(fs.remove, stagingDir)
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

if failed == 0 then
  ok("Downloaded " .. copied .. " files")
else
  fail(failed .. " file(s) failed to download:")
  for i = 1, math.min(5, #failedPaths) do warn("  " .. failedPaths[i]) end
  if #failedPaths > 5 then warn("  (+" .. (#failedPaths - 5) .. " more)") end
end
print()

--! A digest mismatch is not a flaky network. Ordinary download failures
--! are worth retrying and install.lua's own copy+verify pass will catch
--! whatever is missing; a file that arrived intact and hashed WRONG is a
--! different claim — the repository served bytes it does not agree with.
--! Refuse the whole install rather than hand a partly-suspect tree to the
--! installer, and say which files, because "some of it was wrong" is not
--! something an operator can act on.
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
end
