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
--!      /etc/pkg-repos.cfg are AUTHORITIES, and there is no default repo.
--!      Revised for federated repos (docs/FEDERATED-REPOS.md): a package
--!      may NAME other repos, this machine learns of them (KNOWN_CFG),
--!      and a fetch may look in one for what no configured repo has. What
--!      it takes from there is held to pkg's floor -- signed by a key this
--!      machine trusts, or one the admin pins there and then; never
--!      unsigned; pkg trust discovered off turns it off. Hosts carry no
--!      trust; signatures carry all of it. An index still cannot send a
--!      fetch to another host: every file of a package comes from the
--!      repo its index came from.
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
local KNOWN_CFG  = "/var/pkg/known-repos.cfg"
local MAX_KNOWN  = 32
-- Repos nobody configured that ONE lookup may contact: the requirement's
-- hints, then the known store. A 192 KB machine must not discover the
-- size of its learned list by asking all of it.
local MAX_DISCOVERED = 8
local STAGE_ROOT = "/var/pkg/remote"

-- Bounds. Deliberately modest: these are Minecraft computers.
local MAX_INDEX_BYTES   = 128 * 1024
local MAX_FILE_BYTES    = 128 * 1024
local MAX_PKG_BYTES     = 512 * 1024
local MAX_FILES_PER_PKG = 64

-- The repo-hint rule is pkg's (it validates manifests). Until pkg hands
-- it over, NO hint passes: a store read without the rule reads as empty.
local validHint = function() return false end

function pkgremote.init(modules)
  modules = modules or {}
  log = modules.log
  if type(modules.validRepoHint) == "function" then validHint = modules.validRepoHint end
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

--! #SEC — a package name becomes a staging PATH below (and the staging
--! root is removed before every fetch), so it must be a name and nothing
--! else: the rule pkg.lua's validName applies to manifests -- alphanumerics
--! with inner dashes, 64 at most, no dots, no separators. A hand-typed
--! name was only the operator's own risk; a dependency name comes from a
--! REMOTE manifest, and "../../tos" there must not reach fs.remove.
--! (test_pkgremote_deps.lua)
local function validPkgName(n)
  if type(n) ~= "string" or n == "" or #n > 64 then return false end
  if #n == 1 then return n:match("^%w$") ~= nil end
  return n:match("^%w[%w%-]*%w$") ~= nil
end
pkgremote.validPkgName = validPkgName

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
-- Known repos (federated repos slice 2)
-- ============================================================
--! /var/pkg/known-repos.cfg:
--!   return { { url = "https://host/path", from = { "mail-client" } }, ... }
--! What installed packages said about where they, and what they require,
--! can be found. KNOWN is not CONFIGURED: this file is not the allowlist
--! (REPO_CFG is, and only an admin writes it), it is written as a side
--! effect of installing, and a repo in it is trusted with nothing. It is
--! kept apart from REPO_CFG so that no install can ever add to the
--! allowlist. Bounded (MAX_KNOWN, the newest kept): growth follows what the
--! operator installs. Every entry reads back through the same URL rule a
--! manifest was held to; one that fails is dropped, not trusted.
--! (test_pkg_known_repos.lua)
local function readKnown()
  local out = {}
  if not fs.exists(KNOWN_CFG) then return out end
  local data = fs.readFile(KNOWN_CFG)
  if not data then return out end
  local ok, raw = pcall(serialize.decode, data, { maxBytes = 16384 })
  if not ok or type(raw) ~= "table" then
    if log then log.warn("pkgremote", "Corrupt " .. KNOWN_CFG .. "; ignoring") end
    return out
  end
  for _, e in ipairs(raw) do
    if type(e) == "table" and validHint(e.url) then
      local from = {}
      for _, f in ipairs(type(e.from) == "table" and e.from or {}) do
        if validPkgName(f) then from[#from + 1] = f end
      end
      out[#out + 1] = { url = (e.url:gsub("/+$", "")), from = from }
    end
  end
  while #out > MAX_KNOWN do table.remove(out, 1) end
  return out
end

local function saveKnown(list)
  local clean = {}
  for _, e in ipairs(list) do clean[#clean + 1] = { url = e.url, from = e.from } end
  local body = serialize.encode(clean)
  if fs.writeFileAtomic then return fs.writeFileAtomic(KNOWN_CFG, body) end
  return fs.writeFile(KNOWN_CFG, body)
end

--- Learned repos, oldest first: { {url=, from={pkg,...}}, ... }
function pkgremote.known() return readKnown() end

--- Record the repos `from` (a package name) names. A configured repo is
--- not recorded -- it is already more than known -- and a URL that is
--- already known gains `from`. Returns how many were new.
function pkgremote.learn(urls, from)
  if type(urls) ~= "table" then return 0 end
  local list = readKnown()
  local configured = {}
  for _, r in ipairs(pkgremote.repos()) do configured[r.url] = true end
  local added = 0
  for _, u in ipairs(urls) do
    if validHint(u) then
      local url = (u:gsub("/+$", ""))
      if not configured[url] then
        local hit
        for _, e in ipairs(list) do if e.url == url then hit = e; break end end
        if not hit then
          hit = { url = url, from = {} }
          list[#list + 1] = hit
          added = added + 1
        end
        if validPkgName(from) then
          local has = false
          for _, f in ipairs(hit.from) do if f == from then has = true end end
          if not has and #hit.from < 8 then hit.from[#hit.from + 1] = from end
        end
      end
    end
  end
  while #list > MAX_KNOWN do table.remove(list, 1) end
  local ok = saveKnown(list)
  if not ok then return 0, "could not write " .. KNOWN_CFG end
  if added > 0 and log then
    log.info("pkgremote", ("Learned %d repo(s) from '%s' (known, not trusted)"):format(
      added, tostring(from)))
  end
  return added
end

--- Forget learned repos: "all", the number `pkg repo list` shows, or a URL.
function pkgremote.forget(which)
  local list = readKnown()
  if which == "all" then
    if not saveKnown({}) then return false, "could not write " .. KNOWN_CFG end
    return true, #list
  end
  local idx = tonumber(which)
  if not idx then
    local url = type(which) == "string" and (which:gsub("/+$", "")) or nil
    for i, e in ipairs(list) do if e.url == url then idx = i end end
  end
  if not idx or not list[idx] then
    return false, "no known repo " .. tostring(which) .. " (see 'pkg repo list')"
  end
  table.remove(list, idx)
  if not saveKnown(list) then return false, "could not write " .. KNOWN_CFG end
  return true, 1
end

--- A repo object for a URL nobody configured. Its name keys the session's
--- index cache and the staging directory, so it is derived from the URL:
--- a configured repo's name is the admin's word, and nobody chose this
--- one. nil when the URL breaks the rule or cannot be named.
local function discoveredRepo(url)
  if not validHint(url) then return nil end
  url = (url:gsub("/+$", ""))
  local okC, crypto = pcall(require, "kernel.crypto")
  local im = inet()
  if not okC or type(crypto) ~= "table" or type(crypto.hash) ~= "function" or not im then
    return nil
  end
  local host = im.hostOf and im.hostOf(url)
  local h = tostring(crypto.hash(url) or "")
  if not host or not h:match("^%x+$") or #h < 12 then return nil end
  return { name = "k" .. h:sub(1, 12), url = url, host = host, discovered = true }
end

--- The repos nobody configured that a lookup may try, in order: the
--- hints it was given, then the known store. Configured URLs and repeats
--- are skipped; at most MAX_DISCOVERED.
local function discoveredCandidates(repos, hints)
  local configured, seen, out = {}, {}, {}
  for _, r in ipairs(repos) do configured[r.url] = true end
  local function consider(u)
    if #out >= MAX_DISCOVERED or type(u) ~= "string" then return end
    local url = (u:gsub("/+$", ""))
    if configured[url] or seen[url] then return end
    seen[url] = true
    local r = discoveredRepo(url)
    if r then out[#out + 1] = r end
  end
  for _, u in ipairs(type(hints) == "table" and hints or {}) do consider(u) end
  for _, k in ipairs(readKnown()) do consider(k.url) end
  return out
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
local sigCache = {}     -- repoName -> the programs.sig body, or false (none)

--! #SEC / #MEM (pentest, Sep 2026) — the byte bound was the only one. A
--! 128 KB index of "{{},{},...}" built 805 KB of tables before the decoder's
--! per-table entry cap stopped it, and "{{{}},...}" 1.5 MB: whoever runs a
--! configured repo could take down every machine that ran `pkg search`
--! against it. The budget stops either at 64 KB of heap; the largest real
--! index (Optional Utilities', 8.6 KB) is charged 26 KB of it.
--! (test_untrusted_index_budget.lua)
local MAX_INDEX_COST = 64 * 1024

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
  local ok, raw = pcall(serialize.decode, body, { maxBytes = MAX_INDEX_BYTES,
    maxCost = MAX_INDEX_COST, maxKeys = 1024 })
  if not ok or type(raw) ~= "table" then
    return nil, "repo '" .. repo.name .. "' returned an index that is not a table"
  end
  indexCache[repo.name] = { index = raw }
  return raw
end

function pkgremote.clearCache() indexCache = {}; sigCache = {} end

--! pkgsign's own bound on a .sig: a real one is about 300 bytes.
local MAX_SIG_BYTES = 4096

--- Does this repo sign its index? Returns the programs.sig body, false
--- (it does not), or nil + err when there was no answer to go on.
--! Absent and broken are different verdicts (pkgsign: a signature that
--! will not parse is evidence, and is refused), so what counts as "the
--! repo has no signature" is decided here, narrowly:
--!   * the server said so: any 4xx;
--!   * it sent something that is not a signature at all -- a body that
--!     does not decode as a table, or more bytes than a signature can be.
--!     An OpenComputers card without handle.response() cannot report a
--!     404, so a host's error page arrives as the body; staging that would
--!     refuse every package from every unsigned repo.
--! A body that IS a table is the repo's signature, and pkgsign judges it.
--! No answer at all (a timeout, a 5xx, a dropped transfer) is not "none":
--! guessing "none" records a signed package as unsigned, which is the bug
--! this exists to fix. The fetch is refused and the next one asks again,
--! as it already is when any of the package's own files fails to arrive.
local function indexSignature(im, repo, opts)
  if not opts.refresh and sigCache[repo.name] ~= nil then return sigCache[repo.name] end
  local body, err, meta = im.get(repo.url .. "/programs.sig", { maxBytes = MAX_SIG_BYTES })
  local answer
  if type(body) == "string" then
    local okD, rec = pcall(serialize.decode, body, { maxBytes = MAX_SIG_BYTES })
    answer = (okD and type(rec) == "table") and body or false
  else
    meta = type(meta) == "table" and meta or {}
    local status = tonumber(meta.status) or tonumber(tostring(err):match("^HTTP (%d%d%d)"))
    if (status and status >= 400 and status < 500) or (meta.bytes or 0) > MAX_SIG_BYTES then
      answer = false
    else
      return nil, "could not ask repo '" .. repo.name .. "' whether it signs its index: "
        .. tostring(err) .. "  [E-501 ERR_NET_NO_ANSWER]"
    end
  end
  sigCache[repo.name] = answer
  return answer
end

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
  if not validPkgName(name) then
    return nil, "not a package name: " .. tostring(name):sub(1, 64)
      .. "  [E-602 ERR_PKG_BAD_NAME]"
  end
  local im = inet()
  if not im then return nil, "internet module unavailable" end
  if not im.available() then
    local st = im.status()
    return nil, st.reason or "internet is not available"
  end
  local repos = pkgremote.repos()
  --! Repos nobody configured are read only when the caller says what the
  --! floor allows (opts.discoveredPolicy, from pkg trust discovered) and
  --! it is not "off". pkg.installRemote holds whatever comes from one to
  --! that floor; this module only finds it. (test_pkg_discovered.lua)
  local discovery = opts.discoveredPolicy ~= nil and opts.discoveredPolicy ~= "off"
  local others = discovery and discoveredCandidates(repos, opts.hints) or {}
  if #repos == 0 and #others == 0 then
    return nil, "no remote repositories configured (see 'pkg repo add')"
  end

  local repo, entry
  local unusable = {}   -- repos whose index could not be read, and why
  for _, r in ipairs(repos) do
    local idx, iErr = pkgremote.index(r, opts)
    if idx and type(idx[name]) == "table" then
      repo, entry = r, idx[name]
      break
    elseif not idx then
      unusable[#unusable + 1] = tostring(iErr)
    end
  end
  -- Only for what no configured repo has: a configured repo always wins.
  if not entry then
    for _, r in ipairs(others) do
      local idx, iErr = pkgremote.index(r, opts)
      if idx and type(idx[name]) == "table" then
        repo, entry = r, idx[name]
        break
      elseif not idx then
        unusable[#unusable + 1] = tostring(iErr)
      end
    end
  end
  --! A repo may sign its WHOLE index: programs.sig beside programs.cfg,
  --! covering the index's raw bytes. Staging a re-encoded one-entry index
  --! (below) threw that signature away, so a package from a publisher the
  --! machine trusts was recorded as `unsigned`. When the repo serves a
  --! signature, the index is fetched again at that moment -- so the bytes
  --! and the signature are a pair -- and this package's entry is taken
  --! from THOSE bytes, the ones the signature covers. A repo with no
  --! signature costs one request per session and is staged as before.
  --! (test_pkgremote_signed_index.lua)
  local signedIndex, sigBody
  if entry then
    local sig, sErr = indexSignature(im, repo, opts)
    if sig == nil then return nil, sErr end
    if sig then
      local fresh, fErr = im.get(repo.url .. "/programs.cfg", { maxBytes = MAX_INDEX_BYTES })
      local okD, freshIdx = false, nil
      if type(fresh) == "string" then
        okD, freshIdx = pcall(serialize.decode, fresh, { maxBytes = MAX_INDEX_BYTES,
          maxCost = MAX_INDEX_COST, maxKeys = 1024 })
      end
      --! The session's cached copy may predate the signature, so this read
      --! is the only copy the signature can cover. Without it, refuse.
      if not (okD and type(freshIdx) == "table") then
        return nil, "repo '" .. repo.name .. "' signs its index, and re-reading it failed: "
          .. tostring(fErr or "it did not decode")
      end
      if type(freshIdx[name]) ~= "table" then
        return nil, "package '" .. tostring(name) .. "' is no longer in repo '"
          .. repo.name .. "''s signed index"
      end
      signedIndex, sigBody, entry = fresh, sig, freshIdx[name]
    end
  end
  if not entry then
    --! A repo whose index would not load used to vanish from the answer:
    --! "not in any configured repo" when the truth was "that repo's index
    --! is broken". Say both. (test_pkgremote_malformed.lua)
    local why = "package '" .. tostring(name) .. "' is not in any configured repo"
      .. (#others > 0 and (", nor in the " .. #others .. " other repo(s) it was pointed to") or "")
    if #unusable > 0 then why = why .. " (" .. table.concat(unusable, "; ") .. ")" end
    return nil, why .. "  [E-601 ERR_PKG_NOT_FOUND]"
  end
  if type(entry.files) ~= "table" then
    return nil, "package '" .. name .. "' declares no files"
  end
  --! #SEC — the entry is a stranger's data, and every key is used as a
  --! string below. A `files` table written as an array ({ "a.lua" })
  --! has number keys, and `src:gsub` on one THREW out of `pkg fetch`
  --! instead of refusing. Check the whole shape before anything is staged
  --! or downloaded: OPPM's files map is source path -> destination dir,
  --! both strings. (test_pkgremote_malformed.lua)
  for src, dest in pairs(entry.files) do
    if type(src) ~= "string" or type(dest) ~= "string" then
      return nil, "package '" .. name .. "' in repo '" .. repo.name
        .. "' has a malformed file list (expected { [\"source/path\"] = \"/dest/dir\" }, got "
        .. type(src) .. " -> " .. type(dest) .. ")"
    end
  end

  -- Staging tree: <STAGE_ROOT>/<repo>.<name>/ holds programs.cfg + the
  -- sources, and .../<name>/ is the package directory whose PARENT the
  -- manifest reader looks in for the index. Cleared per fetch.
  --! One root PER PACKAGE, not per repo: `pkg fetch` stages a package's
  --! dependencies while the package itself is still staged, and a
  --! per-repo root was wiped by the next fetch from the same repo. "." is
  --! legal in neither a repo name nor a package name, so no two collide.
  local root   = fs.join(STAGE_ROOT, repo.name .. "." .. name)
  local pkgDir = fs.join(root, name)
  pcall(fs.remove, root)
  if not fs.makeDirectory(root) or not fs.makeDirectory(pkgDir) then
    return nil, "could not create staging directory " .. pkgDir
  end
  --! Every refusal from here on leaves staging empty. Two of them (an
  --! OPPM directory copy, an unsafe path) returned with the staged index
  --! still on disk.
  local function fail(msg)
    pcall(fs.remove, root)
    return nil, msg
  end

  -- Write a ONE-PACKAGE index next to the sources: staging should contain
  -- only what this fetch is for. A SIGNED index goes whole, because the
  -- signature covers its exact bytes and a one-entry copy is different
  -- bytes. That stays within the rule: the manifest reader takes the entry
  -- named by the package directory, raw[name], and pkg.install reads that
  -- one directory and resolves nothing else from staging.
  local okIdx
  if signedIndex then
    okIdx = fs.writeFile(fs.join(root, "programs.cfg"), signedIndex)
      and fs.writeFile(fs.join(root, "programs.sig"), sigBody)
  else
    okIdx = fs.writeFile(fs.join(root, "programs.cfg"),
      serialize.encode({ [name] = entry }))
  end
  if not okIdx then return fail("could not stage the package index") end

  local count, total = 0, 0
  for src in pairs(entry.files) do
    local rel = safeRepoPath(src:gsub("^:", ""))   -- ':' = OPPM dir copy
    if src:sub(1, 1) == ":" then
      return fail("package '" .. name ..
        "' uses an OPPM directory-copy entry (" .. tostring(src) ..
        "); TOS installs a declared file list")
    end
    if not rel then
      -- #SEC — the index tried to name a path that is not a path.
      if log then
        log.warn("pkgremote", "Refused unsafe source path from repo '"
          .. repo.name .. "': " .. tostring(src))
      end
      return fail("package '" .. name .. "' declares an unsafe file path: " .. tostring(src))
    end
    count = count + 1
    if count > MAX_FILES_PER_PKG then
      return fail("package '" .. name .. "' exceeds the " .. MAX_FILES_PER_PKG
        .. "-file limit")
    end

    local url  = repo.url .. "/" .. rel
    local dest = fs.join(root, rel)
    local parent = dest:match("^(.*)/[^/]+$")
    if parent and parent ~= "" then fs.makeDirectory(parent) end

    local okD, dErr, meta = im.download(url, dest, { maxBytes = MAX_FILE_BYTES })
    if not okD then
      return fail("downloading " .. rel .. ": " .. tostring(dErr))
    end
    total = total + ((meta and meta.bytes) or 0)
    if total > MAX_PKG_BYTES then
      return fail("package '" .. name .. "' exceeds the "
        .. math.floor(MAX_PKG_BYTES / 1024) .. " KB total limit")
    end
  end

  if count == 0 then
    return fail("package '" .. name .. "' listed no installable files")
  end
  if log then
    log.info("pkgremote", string.format("Fetched %s from %s (%d files, %d bytes)",
      name, repo.name, count, total))
  end
  return pkgDir, nil, { repo = repo.name, url = repo.url, files = count, bytes = total,
                        discovered = repo.discovered and repo.url or nil }
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
pkgremote.KNOWN_CFG  = KNOWN_CFG
pkgremote.MAX_KNOWN  = MAX_KNOWN
-- Exposed for tests: the path vetting is the sharpest edge in this file.
pkgremote._safeRepoPath = safeRepoPath

return pkgremote
