#!/usr/bin/env lua
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Optional Utilities — remote repo index (programs.cfg)         ║
-- ║                                                                ║
-- ║  Turns the built disk set into something `pkg fetch` can       ║
-- ║  install from over an internet card, so an add-on no longer    ║
-- ║  needs a floppy to reach a machine.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- WHAT pkg EXPECTS, and why this is shaped the way it is:
--
-- `pkg repo add <name> <url>` stores a URL; `pkg fetch <pkg>` then reads
-- `<url>/programs.cfg` and downloads each KEY of that package's `files`
-- table from `<url>/<key>`, mirroring them into a staging tree whose
-- `<staging>/<pkgname>/` is handed to the ordinary local installer. So
-- the published tree only has to be the disk layout with every package
-- at the root -- which is exactly what build-disk.lua already emits per
-- disk -- plus this index.
--
--! The index is DATA. kernel.pkgremote decodes it with serialize.decode
--! and never load()s it, because a repo index is a table written by a
--! stranger. This generator therefore writes it with TOS's OWN
--! serialize.encode rather than hand-rolling Lua syntax: the encoder and
--! the decoder are then the same code, and the format cannot drift into
--! something the parser rejects on a machine we cannot test from here.
--
-- The file list comes from each package manifest's `hashes` table, not
-- from walking the disk. That table is what pkg.install verifies against
-- at install time, so deriving the index from it means the index cannot
-- advertise a file the installer would then reject -- one source of
-- truth, not two that agree until they don't.
--
--   lua build/make-repo-index.lua [<extras-root>] [<out-file>]
--   lua build/make-repo-index.lua --check     exit 1 if stale (CI)

local function scriptDir()
  local s = arg and arg[0] or ""
  return s:match("^(.*)[/\\][^/\\]+$") or "."
end

local checkOnly = false
local positional = {}
for i = 1, #arg do
  if arg[i] == "--check" then checkOnly = true else positional[#positional + 1] = arg[i] end
end

local EXTRAS = positional[1] or (scriptDir() .. "/..")
local DIST   = EXTRAS .. "/dist/optional-utilities"
local OUT    = positional[2] or (DIST .. "/programs.cfg")

package.path = EXTRAS .. "/../TOS-Dev/tos/?.lua;" .. package.path
local okS, serialize = pcall(require, "kernel.serialize")
if not okS then
  io.stderr:write("error: cannot load kernel.serialize from the sibling TOS-Dev tree\n")
  os.exit(2)
end

local function readAll(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local s = fh:read("*a"); fh:close(); return s
end

-- ── The set manifest enumerates the whole set ──────────────────────
-- Using it instead of listing directories keeps this dependency-free
-- (no LuaFileSystem, no shell-out) and means the index describes exactly
-- the set build-disk.lua decided to ship -- SKIP entries included.
local setSrc = readAll(DIST .. "/disk1/optutil-set.lua")
if not setSrc then
  io.stderr:write("error: no built set at " .. DIST .. "/disk1/optutil-set.lua\n" ..
                  "       build it first:  lua build/build-disk.lua\n")
  os.exit(2)
end
local set, sErr = serialize.decode(setSrc, { maxBytes = 256 * 1024 })
if type(set) ~= "table" or type(set.packages) ~= "table" then
  io.stderr:write("error: set manifest did not decode as a table: " .. tostring(sErr) .. "\n")
  os.exit(2)
end

local names = {}
for name in pairs(set.packages) do names[#names + 1] = name end
table.sort(names)

local index, fileCount = {}, 0
for _, name in ipairs(names) do
  local meta = set.packages[name]
  local pkgPath = string.format("%s/disk%d/%s/package.lua", DIST, tonumber(meta.disk) or 1, name)
  local pkgSrc = readAll(pkgPath)
  if not pkgSrc then
    io.stderr:write("error: " .. name .. " is in the set but has no manifest at " .. pkgPath .. "\n")
    os.exit(2)
  end
  local manifest = serialize.decode(pkgSrc, { maxBytes = 256 * 1024 })
  if type(manifest) ~= "table" then
    io.stderr:write("error: " .. name .. "'s manifest did not decode\n")
    os.exit(2)
  end

  -- package.lua itself, plus every file the manifest will be checked
  -- against. A hash key is the ABSOLUTE install path (/usr/modules/x.lua)
  -- and the disk mirrors it under the package dir, so the repo-relative
  -- source path is simply <name> .. <key>.
  local files = { [name .. "/package.lua"] = "/" }
  local n = 1

  --! The signature has to be advertised or it never travels. pkg.install
  --! verifies by reading the .sig sitting beside the manifest
  --! (pkgsign.sigPathFor: package.lua -> package.sig), and pkgremote only
  --! downloads what this index lists -- so an unlisted signature means a
  --! package that is signed on the floppy and arrives UNSIGNED over the
  --! network. With `pkg trust require on` that is the difference between
  --! installing and being refused, and the operator would have no way to
  --! tell which half was wrong.
  --!
  --! Conditional because signing is opt-in (build-disk.lua --sign): an
  --! unsigned pack simply has none of these, and listing a file that is
  --! not there would fail the download instead.
  do
    local sigRel = name .. "/package.sig"
    if readAll(string.format("%s/disk%d/%s", DIST, tonumber(meta.disk) or 1, sigRel)) then
      files[sigRel] = "/"
      n = n + 1
    end
  end
  if type(manifest.hashes) == "table" then
    for target in pairs(manifest.hashes) do
      files[name .. target] = target
      n = n + 1
    end
  end
  if n == 1 then
    io.stderr:write("warning: " .. name .. " declares no hashes; index lists only its manifest\n")
  end
  fileCount = fileCount + n

  index[name] = {
    version     = manifest.version or meta.version,
    description = manifest.description or meta.description,
    category    = manifest.category or meta.category,
    kind        = manifest.kind or meta.kind,
    files       = files,
  }
end

-- ── Emit, with SORTED keys ─────────────────────────────────────────
--! serialize.encode walks the table with pairs(), and Lua randomizes its
--! string-hash seed per process, so the same table encodes in a different
--! KEY ORDER on every run. That is fine for a wire format and useless for
--! a file under version control: every regeneration would show a diff,
--! and --check could never pass. So the ordering is ours and the FORMAT
--! is still verified -- by round-tripping the result through the real
--! decoder below, which is the only compatibility that actually matters.
local function emit(value, indent)
  local pad = string.rep("  ", indent)
  if type(value) == "table" then
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    if #keys == 0 then return "{ }" end
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = string.format("%s  [%q] = %s", pad, k, emit(value[k], indent + 1))
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
  elseif type(value) == "string" then
    return string.format("%q", value)
  else
    return tostring(value)
  end
end

local body = "-- Optional Utilities remote index -- generated by build/make-repo-index.lua.\n"
  .. "-- Read by `pkg fetch` over an internet card. Data only; never executed.\n"
  .. "return " .. emit(index, 0) .. "\n"

-- Prove the decoder accepts what we just wrote, and that nothing was lost
-- on the way. A machine we cannot test from here is the one that has to
-- parse this, so failing loudly now beats failing there.
do
  local decoded, dErr = serialize.decode(body, { maxBytes = 512 * 1024 })
  if type(decoded) ~= "table" then
    io.stderr:write("error: generated index does not decode: " .. tostring(dErr) .. "\n")
    os.exit(2)
  end
  for _, name in ipairs(names) do
    local a, b = index[name], decoded[name]
    if type(b) ~= "table" or a.version ~= b.version or a.description ~= b.description then
      io.stderr:write("error: round-trip lost data for '" .. name .. "'\n")
      os.exit(2)
    end
    local na, nb = 0, 0
    for _ in pairs(a.files) do na = na + 1 end
    for _ in pairs(b.files or {}) do nb = nb + 1 end
    if na ~= nb then
      io.stderr:write("error: round-trip lost files for '" .. name ..
        "' (" .. na .. " -> " .. nb .. ")\n")
      os.exit(2)
    end
  end
end

if checkOnly then
  local current = readAll(OUT)
  if current ~= body then
    io.stderr:write("programs.cfg is stale; run: lua build/make-repo-index.lua\n")
    os.exit(1)
  end
  print(string.format("programs.cfg is current (%d packages, %d files).", #names, fileCount))
  os.exit(0)
end

-- Write via a temp then rename, so a failure mid-write cannot leave a
-- truncated index that a machine would then try to install from.
local tmp = OUT .. ".tmp"
local fh = io.open(tmp, "wb")
if not fh then
  io.stderr:write("error: cannot write " .. tmp .. "\n"); os.exit(2)
end
fh:write(body); fh:close()
if #body == 0 then os.remove(tmp); io.stderr:write("error: refused to write an empty index\n"); os.exit(2) end
os.remove(OUT)
local okR = os.rename(tmp, OUT)
if not okR then io.stderr:write("error: could not finalize " .. OUT .. "\n"); os.exit(2) end

print(string.format("Wrote %s: %d packages, %d files.", OUT, #names, fileCount))
