-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Remote package repositories                  ║
-- ║                                                            ║
-- ║  Fetching packages over an internet card, for repos laid   ║
-- ║  out the OPPM way: one `programs.cfg` index at the root,   ║
-- ║  sources underneath it.                                    ║
-- ║                                                            ║
-- ║  Loaded LAZILY by pkg — a machine that never fetches       ║
-- ║  anything never parses this file.                          ║
-- ╚══════════════════════════════════════════════════════════╝
--
-- THE SHAPE OF THIS, AND WHY:
--
-- Nothing here installs anything. It DOWNLOADS a remote repo into a local
-- staging directory laid out exactly like a repo on a floppy, and then the
-- ordinary `pkg.install` runs against that directory. Every guarantee the
-- local path already has — manifest validation, write-root confinement,
-- SHA-256 verification, conflict and file-ownership checks, dependency
-- resolution, the unverified-package gate — therefore applies to a remote
-- package without a second implementation that could drift from the first.
--
-- The alternative, threading HTTP through pkg.install, would have meant a
-- network-aware copy of the most security-sensitive loop in the system.
--
--! THREAT MODEL. This is the path by which EXECUTABLE CODE FROM OUTSIDE
--! THE WORLD reaches a TOS machine. Everything downloaded is hostile until
--! proven otherwise, and "proven otherwise" is not something this module
--! can do — it is what the operator does by choosing a repo and by having
--! to say --allow-unverified when an index ships no hashes.
--!
--! Four rules hold the line here:
--!   1. HOST ALLOWLIST. Only repos an admin has written into
--!      /etc/pkg-repos.cfg are fetched. There is no default repo, no
--!      discovery, and no way for an index to introduce another host —
--!      a fetch that would leave the configured origin is refused.
--!   2. PATHS FROM A STRANGER ARE NOT PATHS. Every source path in a
--!      remote index is vetted BEFORE it is used to build either a URL or
--!      a staging destination. This is the sharp edge: the index says
--!      where to write, and "master/../../../tos/kernel/fs.lua" would
--!      escape the staging directory into the live system if it were
--!      taken at face value. validateManifest checks this too, but that
--!      runs at INSTALL time — after these bytes have already hit the
--!      disk — so it cannot be the only check.
--!   3. BOUNDED. Files per package, bytes per file, bytes per package.
--!      A machine with 192 KB of RAM and a 2 MB disk cannot afford to
--!      discover a repo's size by running out.
--!   4. STAGING IS DISPOSABLE. Everything lands under /var/pkg/remote,
--!      which is package-owned space, and is cleared before each fetch so
--!      a previous failure cannot contribute files to the next install.

local fs        = require("kernel.fs")
local serialize = require("kernel.serialize")

local pkgremote = {}

local log = nil

local REPO_CFG   = "/etc/pkg-repos.cfg"
local STAGE_ROOT = "/var/pkg/remote"

-- Bounds. Deliberately modest: these are Minecraft computers.
local MAX_INDEX_BYTES   = 128 * 1024
local MAX_FILE_BYTES    = 128 * 1024
local MAX_PKG_BYTES     = 512 * 1024
local MAX_FILES_PER_PKG = 64

function pkgremote.init(modules)
  modules = modules or {}
  log = modules.log
end

local function inet()
  local ok, m = pcall(require, "kernel.internet")
  if ok then return m end
  return nil
end

-- ============================================================
-- Repository configuration
-- ============================================================
-- /etc/pkg-repos.cfg:
--   return {
--     { name = "myrepo", url = "https://example.com/oc/master" },
--   }
-- The URL is the directory the index sits in; `programs.cfg` is appended.
-- Writing this file is an admin act (it is under /etc, so securefs gates
-- it), and it IS the allowlist — there is no separate host list to keep in
-- step with it.

local function validRepoName(n)
  return type(n) == "string" and #n <= 32 and n:match("^[%w_%-]+$") ~= nil
end

--- Load configured repos. Returns an array of { name, url, host }.
--- A malformed entry is dropped rather than failing the whole file: one
--- bad line should not make every other repo unreachable.
function pkgremote.repos()
  local out = {}
  if not fs.exists(REPO_CFG) then return out end
  local data = fs.readFile(REPO_CFG)
  if not data then return out end
  local ok, raw = pcall(serialize.decode, data, { maxBytes = 16384 })
  if not ok or type(raw) ~= "table" then
    if log then log.warn("pkgremote", "Corrupt " .. REPO_CFG .. "; ignoring") end
    return out
  end
  local im = inet()
  for _, e in ipairs(raw) do
    if type(e) == "table" and validRepoName(e.name) and type(e.url) == "string" then
      local host = im and im.hostOf(e.url) or nil
      -- A repo whose URL does not parse as http/https is not usable and
      -- must not sit in the list looking configured.
      if host then
        out[#out + 1] = {
          name = e.name,
          url  = (e.url:gsub("/+$", "")),
          host = host,
          description = type(e.description) == "string" and e.description or nil,
        }
      elseif log then
        log.warn("pkgremote", "Repo '" .. tostring(e.name) .. "' has an unusable URL")
      end
    end
  end
  return out
end

local function saveRepos(list)
  local clean = {}
  for _, r in ipairs(list) do
    clean[#clean + 1] = { name = r.name, url = r.url, description = r.description }
  end
  return fs.writeFileAtomic and fs.writeFileAtomic(REPO_CFG, serialize.encode(clean))
    or fs.writeFile(REPO_CFG, serialize.encode(clean))
end

--- Add (or replace) a repo. The caller is responsible for the admin gate —
--- pkg's `repo` verb does it, in the same place it gates install.
function pkgremote.addRepo(name, url, description)
  if not validRepoName(name) then
    return false, "invalid repo name (letters, digits, _ and - only)"
  end
  local im = inet()
  if not im then return false, "internet module unavailable" end
  local ok, err = im.parseUrl(url)
  if not ok then return false, err end
  local list = pkgremote.repos()
  local replaced = false
  for _, r in ipairs(list) do
    if r.name == name then
      r.url, r.description, replaced = (url:gsub("/+$", "")), description, true
    end
  end
  if not replaced then
    list[#list + 1] = { name = name, url = (url:gsub("/+$", "")), description = description }
  end
  local okW = saveRepos(list)
  if not okW then return false, "could not write " .. REPO_CFG end
  if log then log.info("pkgremote", "Repo '" .. name .. "' -> " .. url) end
  return true
end

function pkgremote.removeRepo(name)
  local list, out, found = pkgremote.repos(), {}, false
  for _, r in ipairs(list) do
    if r.name == name then found = true else out[#out + 1] = r end
  end
  if not found then return false, "no such repo: " .. tostring(name) end
  if not saveRepos(out) then return false, "could not write " .. REPO_CFG end
  return true
end

-- ============================================================
-- Path vetting  (#SEC — see rule 2 in the header)
-- ============================================================
--! A source path out of a remote index is used for two things: appended to
--! the repo URL, and appended to the staging directory. Both are injection
--! sites. Refused: absolute paths, any "." or ".." segment, backslashes,
--! control characters, a scheme (so an index cannot redirect the fetch to
--! another host), a protocol-relative "//" prefix, and query/fragment
--! punctuation that would make the URL mean something else.
local function safeRepoPath(p)
  if type(p) ~= "string" or p == "" then return nil end
  if #p > 256 then return nil end
  if p:find("[%c]") then return nil end
  if p:find("\\", 1, true) then return nil end
  if p:sub(1, 1) == "/" then return nil end
  if p:find("://", 1, true) then return nil end
  if p:find("?", 1, true) or p:find("#", 1, true) then return nil end
  if p:find("@", 1, true) then return nil end
  for seg in p:gmatch("[^/]+") do
    if seg == "." or seg == ".." then return nil end
  end
  -- Collapse any doubled slashes so the joined URL and the joined path
  -- agree on the segment count.
  return (p:gsub("/+", "/"))
end

-- ============================================================
-- Index fetch
-- ============================================================
local indexCache = {}   -- repoName -> { at = uptime, index = table }

--- Fetch and parse a repo's programs.cfg. Cached for the session so a
--- multi-package install doesn't re-download the index per package.
--- Returns index, err.
function pkgremote.index(repo, opts)
  opts = opts or {}
  local im = inet()
  if not im then return nil, "internet module unavailable" end
  if not opts.refresh and indexCache[repo.name] then
    return indexCache[repo.name].index
  end
  local url = repo.url .. "/programs.cfg"
  local body, err = im.get(url, { maxBytes = MAX_INDEX_BYTES })
  if not body then
    return nil, "could not fetch " .. url .. ": " .. tostring(err)
  end
  --! The index is DATA, and is decoded by kernel.serialize with a byte
  --! bound — never `load()`ed. A repo index is a table written by a
  --! stranger; running it as Lua would be handing them the machine before
  --! they had even shipped a package.
  local ok, raw = pcall(serialize.decode, body, { maxBytes = MAX_INDEX_BYTES })
  if not ok or type(raw) ~= "table" then
    return nil, "repo '" .. repo.name .. "' returned an index that is not a table"
  end
  indexCache[repo.name] = { index = raw }
  return raw
end

function pkgremote.clearCache() indexCache = {} end

--- Every package available across the configured repos.
--- Returns an array of { name, repo, description, version, files }.
function pkgremote.search(opts)
  local out = {}
  for _, repo in ipairs(pkgremote.repos()) do
    local idx, err = pkgremote.index(repo, opts)
    if idx then
      for name, entry in pairs(idx) do
        if type(name) == "string" and type(entry) == "table" and not entry.hidden then
          out[#out + 1] = {
            name        = name,
            repo        = repo.name,
            description = entry.description or entry.note,
            version     = entry.version,
          }
        end
      end
    elseif log then
      log.warn("pkgremote", tostring(err))
    end
  end
  table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  return out
end

-- ============================================================
-- Fetch a package into staging
-- ============================================================
--- Download `name` from the configured repos into a local staging tree
--- laid out like a repo directory, and return the PACKAGE DIRECTORY inside
--- it for pkg.install to consume.
---
--- Returns pkgDir, err.
function pkgremote.fetch(name, opts)
  opts = opts or {}
  local im = inet()
  if not im then return nil, "internet module unavailable" end
  if not im.available() then
    local st = im.status()
    return nil, st.reason or "internet is not available"
  end
  local repos = pkgremote.repos()
  if #repos == 0 then
    return nil, "no remote repositories configured (see 'pkg repo add')"
  end

  local repo, entry
  for _, r in ipairs(repos) do
    local idx = pkgremote.index(r, opts)
    if idx and type(idx[name]) == "table" then
      repo, entry = r, idx[name]
      break
    end
  end
  if not entry then
    return nil, "package '" .. tostring(name) .. "' is not in any configured repo"
  end
  if type(entry.files) ~= "table" then
    return nil, "package '" .. name .. "' declares no files"
  end

  -- Staging tree: <STAGE_ROOT>/<repo>/  holds programs.cfg + the sources,
  -- and <STAGE_ROOT>/<repo>/<name>/ is the package directory whose PARENT
  -- the manifest reader looks in for the index. Cleared per fetch.
  local root   = fs.join(STAGE_ROOT, repo.name)
  local pkgDir = fs.join(root, name)
  pcall(fs.remove, root)
  if not fs.makeDirectory(root) or not fs.makeDirectory(pkgDir) then
    return nil, "could not create staging directory " .. pkgDir
  end

  -- Write a ONE-PACKAGE index next to the sources. Deliberately not the
  -- whole remote index: the manifest reader would happily read any entry
  -- in it, and staging should contain only what this fetch is for.
  local okIdx = fs.writeFile(fs.join(root, "programs.cfg"),
    serialize.encode({ [name] = entry }))
  if not okIdx then return nil, "could not stage the package index" end

  local count, total = 0, 0
  for src in pairs(entry.files) do
    local rel = safeRepoPath(src:gsub("^:", ""))   -- ':' = OPPM dir copy
    if src:sub(1, 1) == ":" then
      return nil, "package '" .. name ..
        "' uses an OPPM directory-copy entry (" .. tostring(src) ..
        "); TOS installs a declared file list"
    end
    if not rel then
      -- #SEC — the index tried to name a path that is not a path.
      if log then
        log.warn("pkgremote", "Refused unsafe source path from repo '"
          .. repo.name .. "': " .. tostring(src))
      end
      return nil, "package '" .. name .. "' declares an unsafe file path: " .. tostring(src)
    end
    count = count + 1
    if count > MAX_FILES_PER_PKG then
      return nil, "package '" .. name .. "' exceeds the " .. MAX_FILES_PER_PKG
        .. "-file limit"
    end

    local url  = repo.url .. "/" .. rel
    local dest = fs.join(root, rel)
    local parent = dest:match("^(.*)/[^/]+$")
    if parent and parent ~= "" then fs.makeDirectory(parent) end

    local okD, dErr, meta = im.download(url, dest, { maxBytes = MAX_FILE_BYTES })
    if not okD then
      pcall(fs.remove, root)
      return nil, "downloading " .. rel .. ": " .. tostring(dErr)
    end
    total = total + ((meta and meta.bytes) or 0)
    if total > MAX_PKG_BYTES then
      pcall(fs.remove, root)
      return nil, "package '" .. name .. "' exceeds the "
        .. math.floor(MAX_PKG_BYTES / 1024) .. " KB total limit"
    end
  end

  if count == 0 then
    pcall(fs.remove, root)
    return nil, "package '" .. name .. "' listed no installable files"
  end
  if log then
    log.info("pkgremote", string.format("Fetched %s from %s (%d files, %d bytes)",
      name, repo.name, count, total))
  end
  return pkgDir, nil, { repo = repo.name, files = count, bytes = total }
end

--- Drop the staging tree. Called after an install so downloaded sources do
--- not sit on a small disk forever.
function pkgremote.cleanup(pkgDir)
  if type(pkgDir) ~= "string" then return end
  local root = pkgDir:match("^(" .. STAGE_ROOT:gsub("%-", "%%-") .. "/[^/]+)")
  if root then pcall(fs.remove, root) end
end

pkgremote.STAGE_ROOT = STAGE_ROOT
pkgremote.REPO_CFG   = REPO_CFG
-- Exposed for tests: the path vetting is the sharpest edge in this file.
pkgremote._safeRepoPath = safeRepoPath

return pkgremote
