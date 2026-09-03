-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: kernel.srm (System Repair & Maintenance)    ║
-- ║                                                                ║
-- ║  1. The BIOS channel — parse/strip a parked SRM fault code     ║
-- ║     WITHOUT disturbing the boot address or the TOS1 anchor     ║
-- ║     that share the EEPROM data field.                          ║
-- ║  2. Baseline capture (hashes-only and with content copies).    ║
-- ║  3. Scan detects drift, deletion and store rot — and stays     ║
-- ║     quiet on a clean system.                                   ║
-- ║  4. Restore puts files back from the store, REFUSES a source   ║
-- ║     whose hash doesn't match, and never truncates the target.  ║
-- ║  5. Repair composes the kernel.repair fixer pass.              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_srm.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  if expected == actual then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

-- ── Module loading (works from the repo root or from the test dir) ──
local here = (arg and arg[0]) or "usr/lib/tests/test_srm.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadMod(rel)
  for _, p in ipairs({ base .. "../../../tos/kernel/" .. rel,
      "tos/kernel/" .. rel, "TOS-Dev/tos/kernel/" .. rel }) do
    local chunk = loadfile(p)
    if chunk then return chunk() end
  end
end

local serialize = loadMod("serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha256 = loadMod("sha256.lua")
package.loaded["kernel.sha256"] = sha256
-- crypto.lua reaches for machine globals at load time; SRM only needs a
-- hash, so inject a real SHA-256 rather than dragging the whole module in.
local crypto = { hash = function(s) return sha256.hex(s) end }
package.loaded["kernel.crypto"] = crypto

local repairMod = loadMod("repair.lua")
package.loaded["kernel.repair"] = repairMod

local srm = loadMod("srm.lua")
if not (srm and serialize and sha256 and repairMod) then
  print("FAIL: could not load srm/serialize/sha256/repair")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

print("=== kernel.srm Tests ===")
print()

-- ============================================================
-- 1. The BIOS channel
-- ============================================================
print("-- SRM Basic fault codes (the EEPROM channel) --")

local ADDR   = "fsss-1111-2222"
local ANCHOR = "TOS1:" .. string.rep("a", 64)

eq("no code in a bare boot address", nil, srm.parseFault(ADDR))
eq("code parsed after the anchor", "K4",
  srm.parseFault(ADDR .. "\n" .. ANCHOR .. "\nSRM:K4"))
eq("code parsed with no anchor present", "D2", srm.parseFault(ADDR .. "\nSRM:D2"))
eq("code parsed when it is the only line", "I6", srm.parseFault("SRM:I6"))
-- A boot address is 36 hex-and-dashes; nothing in it may ever be read as a
-- code, and a code must be at a line start (never mid-field).
eq("SRM: mid-line is NOT a code", nil, srm.parseFault(ADDR .. "xSRM:K4"))
eq("empty data is not a code", nil, srm.parseFault(""))
eq("non-string is not a code", nil, srm.parseFault(nil))

-- Stripping must be surgical: losing line 1 would leave the machine
-- prompting "Boot drive changed" on every single power-on.
local full = ADDR .. "\n" .. ANCHOR .. "\nSRM:K4"
eq("strip keeps the boot address AND the anchor", ADDR .. "\n" .. ANCHOR,
  srm.stripFault(full))
eq("strip is a no-op when there is no code", ADDR .. "\n" .. ANCHOR,
  srm.stripFault(ADDR .. "\n" .. ANCHOR))
eq("strip handles a code-only field", "", srm.stripFault("SRM:I5"))
eq("boot address survives a strip",
  ADDR, srm.stripFault(full):match("^[^\n]*"))
eq("anchor survives a strip (kernel's own matcher still finds it)",
  string.rep("a", 64), srm.stripFault(full):match("\nTOS1:(%x+)"))

-- Every code SRM Basic can park must have an explanation, and the digit
-- must equal the beep count bios.lua emits (see the F() loop there).
do
  local n = 0
  for code, why in pairs(srm.BASIC_CODES) do
    n = n + 1
    if type(why) ~= "string" or why == "" then
      test("code " .. code .. " has an explanation", false)
    end
    local digit = tonumber(code:sub(2, 2))
    if not digit or digit < 1 or digit > 9 then
      test("code " .. code .. " ends in a beep-countable digit", false)
    end
  end
  test("BASIC_CODES is populated (" .. n .. " codes)", n >= 6)
end

-- Round-trip through a fake EEPROM proxy.
do
  local data = ADDR .. "\n" .. ANCHOR .. "\nSRM:B3"
  local ep = {
    getData = function() return data end,
    setData = function(v) data = v; return true end,
  }
  local deps = { eeprom = ep }
  local f = srm.readFault(deps)
  eq("readFault returns the code", "B3", f and f.code)
  test("readFault explains the code", f and f.why and f.why:find("blob") ~= nil)
  eq("clearFault succeeds", true, (srm.clearFault(deps)))
  eq("clearFault removed the code", nil, srm.parseFault(data))
  eq("clearFault preserved the boot address", ADDR, data:match("^[^\n]*"))
  eq("clearFault is idempotent", true, (srm.clearFault(deps)))
  -- An unknown code (older TOS, newer BIOS) must still be reported.
  data = ADDR .. "\nSRM:Z9"
  local f2 = srm.readFault(deps)
  eq("unknown code still surfaces", "Z9", f2 and f2.code)
  test("unknown code says so", f2 and f2.why:find("unrecognised") ~= nil)
end

eq("readFault with no EEPROM is nil, not an error", nil, srm.readFault({ eeprom = false }))

-- ============================================================
-- In-memory filesystem, shaped like kernel.fs
-- ============================================================
local function fakeFS()
  local files, dirs = {}, { ["/"] = true }
  local F
  local function parentsOf(p)
    local acc = ""
    for seg in p:gmatch("[^/]+") do
      acc = acc .. "/" .. seg
      if acc ~= p then dirs[acc] = true end
    end
  end
  F = {
    _files = files,
    exists = function(p) return files[p] ~= nil or dirs[p] == true end,
    isDirectory = function(p) return dirs[p] == true end,
    size = function(p) return files[p] and #files[p] or nil end,
    readFile = function(p)
      if files[p] == nil then return nil, "File not found: " .. p end
      return files[p]
    end,
    writeFile = function(p, c) parentsOf(p); files[p] = c; return true end,
    remove = function(p) files[p] = nil; return true end,
    rename = function(a, b) files[b] = files[a]; files[a] = nil; return true end,
    makeDirectory = function(p) parentsOf(p); dirs[p] = true; return true end,
    list = function(p)
      local out = {}
      for k in pairs(files) do
        local rest = k:match("^" .. p:gsub("%p", "%%%1") .. "/([^/]+)$")
        if rest then out[#out + 1] = rest end
      end
      table.sort(out)
      return out
    end,
  }
  -- Real atomic semantics: temp then rename, so the test exercises the
  -- same code path the live kernel does.
  F.writeFileAtomic = function(p, c)
    local tmp = p .. ".tos-tmp"
    F.writeFile(tmp, c)
    F.remove(p)
    return F.rename(tmp, p)
  end
  return F
end

local CRIT = { "/init.lua", "/tos/kernel/init.lua", "/tos/kernel/fs.lua" }
local function seeded()
  local fs = fakeFS()
  fs.writeFile("/init.lua",            "-- boot loader\nreturn 1\n")
  fs.writeFile("/tos/kernel/init.lua", "-- kernel\nreturn 2\n")
  fs.writeFile("/tos/kernel/fs.lua",   "-- fs\nreturn 3\n")
  return fs, { fs = fs, serialize = serialize, crypto = crypto, eeprom = false }
end

-- ============================================================
-- 2. Baseline capture
-- ============================================================
print()
print("-- baseline --")

do
  local fs, deps = seeded()
  local ok, sum = srm.baseline(deps, { paths = CRIT })
  eq("hashes-only baseline succeeds", true, ok)
  eq("hashed every file", 3, sum.hashed)
  eq("stored nothing (hashes only)", 0, sum.stored)
  test("index file written", fs.exists(srm.INDEX))

  local idx = srm.loadIndex(deps)
  test("index reloads", idx ~= nil)
  eq("index records content=false", false, idx.content)
  eq("index hash matches a fresh hash of the file",
    sha256.hex(fs._files["/init.lua"]), idx.files["/init.lua"].hash)
  eq("index records the size", #fs._files["/init.lua"], idx.files["/init.lua"].size)
  eq("nothing was copied into the store", false, idx.files["/init.lua"].stored)
end

do
  local fs, deps = seeded()
  local ok, sum = srm.baseline(deps, { paths = CRIT, content = true })
  eq("content baseline succeeds", true, ok)
  eq("stored every file", 3, sum.stored)
  test("store mirrors the real path",
    fs.exists("/var/srm/store/tos/kernel/init.lua"))
  eq("stored bytes are identical to the original",
    fs._files["/tos/kernel/init.lua"],
    fs._files["/var/srm/store/tos/kernel/init.lua"])
  local u = srm.storeUsage(deps)
  eq("storeUsage counts the copies", 3, u.files)
  test("storeUsage counts bytes", u.bytes == sum.bytes and u.bytes > 0)
end

do
  -- A file over the store cap is still hashed (drift is detectable) but
  -- not copied — and that must be reported, not silently dropped.
  local fs, deps = seeded()
  fs.writeFile("/tos/kernel/init.lua", string.rep("x", srm.MAX_STORE_BYTES + 1))
  local ok, sum = srm.baseline(deps, { paths = CRIT, content = true })
  eq("oversized file still baselines", true, ok)
  eq("oversized file is hashed", 3, sum.hashed)
  eq("oversized file is not stored", 2, sum.stored)
  eq("oversized file is counted as skipped", 1, sum.skipped)
  local idx = srm.loadIndex(deps)
  eq("oversized file has a hash", true, type(idx.files["/tos/kernel/init.lua"].hash) == "string")
  eq("oversized file is marked unstored", false, idx.files["/tos/kernel/init.lua"].stored)
end

do
  -- Re-baselining must not orphan the previous store: copies the new
  -- baseline doesn't claim occupy disk that storeUsage would never count
  -- and scan would never check again.
  local fs, deps = seeded()
  srm.baseline(deps, { paths = CRIT, content = true })
  test("store populated before re-baseline",
    fs.exists("/var/srm/store/tos/kernel/fs.lua"))

  local ok, sum = srm.baseline(deps, { paths = { "/init.lua" }, content = true })
  eq("narrower re-baseline succeeds", true, ok)
  eq("dropped files' copies were pruned", 2, sum.pruned)
  eq("pruned copy is gone from disk", false,
    fs.exists("/var/srm/store/tos/kernel/fs.lua"))
  test("kept copy survives", fs.exists("/var/srm/store/init.lua"))
  eq("storeUsage matches what is actually on disk", 1, srm.storeUsage(deps).files)

  -- Dropping to hashes-only must clear the store too, or the index would
  -- claim nothing is stored while the disk still held every copy.
  srm.baseline(deps, { paths = CRIT, content = true })
  local ok2, sum2 = srm.baseline(deps, { paths = CRIT })
  eq("hashes-only re-baseline prunes the whole store", 3, sum2.pruned)
  eq("nothing left in the store", false, fs.exists("/var/srm/store/init.lua"))
  eq("storeUsage agrees", 0, srm.storeUsage(deps).files)
end

do
  -- A missing file at capture time is reported, not silently baselined.
  local fs, deps = seeded()
  fs.remove("/tos/kernel/fs.lua")
  local ok, sum = srm.baseline(deps, { paths = CRIT })
  eq("baseline succeeds with a file absent", true, ok)
  eq("absent file reported", 1, #sum.missing)
  eq("absent file named", "/tos/kernel/fs.lua", sum.missing[1])
  eq("only the present files were hashed", 2, sum.hashed)
end

-- ============================================================
-- 3. Scan
-- ============================================================
print()
print("-- scan --")

do
  -- A partial baseline is deliberately NOT "clean": critical files it
  -- doesn't cover are files SRM cannot protect, and saying so is the point.
  local _, deps = seeded()
  srm.baseline(deps, { paths = CRIT, content = true })
  local rep = srm.scan(deps)
  eq("partial baseline: no errors", 0, rep.counts.err)
  eq("partial baseline: no drift", 0, #rep.drift)
  eq("partial baseline: warns about the files it misses", "warn", srm.worst(rep))
end

do
  -- The genuinely clean case: a baseline covering the WHOLE critical set,
  -- resolved by the module itself (which also exercises criticalPaths'
  -- fallback layer — no pkg manifest, no critical.bak on this fake disk).
  local fs = fakeFS()
  local deps = { fs = fs, serialize = serialize, crypto = crypto, eeprom = false }
  local crit, source = srm.criticalPaths(deps)
  eq("criticalPaths falls back when no on-disk list exists",
    "built-in fallback", source)
  test("fallback critical set is non-trivial", #crit >= 8)
  for i, p in ipairs(crit) do fs.writeFile(p, "-- file " .. i .. "\nreturn " .. i .. "\n") end

  srm.baseline(deps, { content = true })     -- no paths: uses the critical set
  local rep = srm.scan(deps)
  eq("clean system reports no errors", 0, rep.counts.err)
  eq("clean system finds no drift", 0, #rep.drift)
  eq("clean system finds nothing missing", 0, #rep.missing)
  eq("clean system leaves nothing unbaselined", 0, #rep.unbaselined)
  eq("clean system is 'ok' overall", "ok", srm.worst(rep))
end

do
  local fs, deps = seeded()
  srm.baseline(deps, { paths = CRIT, content = true })
  fs.writeFile("/tos/kernel/init.lua", "-- kernel\nreturn 2 -- TAMPERED\n")
  local rep = srm.scan(deps)
  eq("tampered file detected as drift", 1, #rep.drift)
  eq("drift names the file", "/tos/kernel/init.lua", rep.drift[1])
  test("drift is an error, not a warning", rep.counts.err >= 1)
  local sawChanged = false
  for _, f in ipairs(rep.findings) do
    if f.text:find("CHANGED", 1, true) and f.text:find("init.lua", 1, true) then sawChanged = true end
  end
  test("report says CHANGED for the drifted file", sawChanged)
end

do
  local fs, deps = seeded()
  srm.baseline(deps, { paths = CRIT })
  fs.remove("/tos/kernel/fs.lua")
  local rep = srm.scan(deps)
  eq("deleted file detected", 1, #rep.missing)
  eq("deleted file named", "/tos/kernel/fs.lua", rep.missing[1])
  eq("deleted file is not also counted as drift", 0, #rep.drift)
end

do
  -- Store rot: the repair SOURCE is bad. That has to surface, because an
  -- operator who trusts it would restore corruption over a good file.
  local fs, deps = seeded()
  srm.baseline(deps, { paths = CRIT, content = true })
  fs.writeFile("/var/srm/store/tos/kernel/fs.lua", "-- rotted copy\n")
  local rep = srm.scan(deps)
  eq("rot does not show up as system drift", 0, #rep.drift)
  local sawRot = false
  for _, f in ipairs(rep.findings) do
    if f.text:find("store copy is corrupt", 1, true) then sawRot = true end
  end
  test("corrupt store copy is reported", sawRot)
  test("corrupt store copy is a warning", rep.counts.warn >= 1)
end

do
  -- A critical file added by an upgrade after the baseline was captured.
  local fs, deps = seeded()
  srm.baseline(deps, { paths = { "/init.lua" } })
  local rep = srm.scan(deps)
  local sawNew = false
  for _, f in ipairs(rep.findings) do
    if f.text:find("not in baseline", 1, true) then sawNew = true end
  end
  test("files outside the baseline are flagged", sawNew)
  test("unbaselined list is populated", #rep.unbaselined > 0)
end

do
  local _, deps = seeded()
  local rep = srm.scan(deps)
  test("no baseline at all is a warning, not a crash", rep.counts.warn >= 1)
end

-- ============================================================
-- 4. Restore
-- ============================================================
print()
print("-- restore --")

do
  local fs, deps = seeded()
  local good = fs._files["/tos/kernel/init.lua"]
  srm.baseline(deps, { paths = CRIT, content = true })
  fs.writeFile("/tos/kernel/init.lua", "-- TAMPERED\n")
  local rep = srm.restore(deps)
  eq("restored one file", 1, rep.fixed)
  eq("file is byte-identical to the baseline", good, fs._files["/tos/kernel/init.lua"])
  eq("no errors restoring from the store", 0, rep.counts.err)
  eq("system is clean afterwards", 0, #srm.scan(deps).drift)
  -- The atomic write must not leave its temp behind.
  eq("no temp file left in the tree", nil, fs._files["/tos/kernel/init.lua.tos-tmp"])
end

do
  local fs, deps = seeded()
  local good = fs._files["/tos/kernel/fs.lua"]
  srm.baseline(deps, { paths = CRIT, content = true })
  fs.remove("/tos/kernel/fs.lua")
  local rep = srm.restore(deps)
  eq("deleted file is restored", 1, rep.fixed)
  eq("deleted file comes back intact", good, fs._files["/tos/kernel/fs.lua"])
end

do
  -- #SEC — the whole point of the store: a source that does not match the
  -- baseline hash must be REFUSED, not written over a system file.
  local fs, deps = seeded()
  srm.baseline(deps, { paths = CRIT, content = true })
  local tampered = "-- TAMPERED\n"
  fs.writeFile("/tos/kernel/init.lua", tampered)
  fs.writeFile("/var/srm/store/tos/kernel/init.lua", "-- ALSO TAMPERED\n")
  local rep = srm.restore(deps)
  eq("nothing was restored from a bad source", 0, rep.fixed)
  eq("the live file was left alone", tampered, fs._files["/tos/kernel/init.lua"])
  local sawReject = false
  for _, f in ipairs(rep.findings) do
    if f.text:find("rejected", 1, true) then sawReject = true end
  end
  test("the bad source is explicitly rejected", sawReject)
  test("failing to repair is an error", rep.counts.err >= 1)
end

do
  -- External source (an install floppy). Verified against the baseline
  -- exactly like the local store is.
  local fs, deps = seeded()
  local good = fs._files["/tos/kernel/init.lua"]
  srm.baseline(deps, { paths = CRIT })          -- hashes only: no local store
  fs.writeFile("/tos/kernel/init.lua", "-- TAMPERED\n")
  fs.writeFile("/mnt/floppy/tos/kernel/init.lua", good)
  local rep = srm.restore(deps, { source = "/mnt/floppy" })
  eq("restored from the external source", 1, rep.fixed)
  eq("restored bytes are correct", good, fs._files["/tos/kernel/init.lua"])

  -- ...and a floppy carrying a DIFFERENT build is refused.
  local fs2, deps2 = seeded()
  srm.baseline(deps2, { paths = CRIT })
  fs2.writeFile("/tos/kernel/init.lua", "-- TAMPERED\n")
  fs2.writeFile("/mnt/floppy/tos/kernel/init.lua", "-- a different build\n")
  local rep2 = srm.restore(deps2, { source = "/mnt/floppy" })
  eq("mismatched external source restores nothing", 0, rep2.fixed)
end

do
  -- Hashes-only baseline with no --source: SRM must say why it can't help
  -- rather than failing obscurely.
  local fs, deps = seeded()
  srm.baseline(deps, { paths = CRIT })
  fs.writeFile("/tos/kernel/init.lua", "-- TAMPERED\n")
  local rep = srm.restore(deps)
  eq("nothing restored without a source", 0, rep.fixed)
  local sawAdvice = false
  for _, f in ipairs(rep.findings) do
    if f.text:find("--source", 1, true) then sawAdvice = true end
  end
  test("report tells the operator to pass --source", sawAdvice)
end

do
  -- No baseline at all: refuse to write anything unless told explicitly.
  local fs, deps = seeded()
  local orig = fs._files["/tos/kernel/init.lua"]
  local rep = srm.restore(deps, { paths = { "/tos/kernel/init.lua" },
                                  source = "/mnt/floppy" })
  eq("no baseline: nothing restored", 0, rep.fixed)
  eq("no baseline: live file untouched", orig, fs._files["/tos/kernel/init.lua"])
  test("no baseline: refusal is an error", rep.counts.err >= 1)

  fs.writeFile("/mnt/floppy/tos/kernel/init.lua", "-- from the floppy\n")
  local rep2 = srm.restore(deps, { paths = { "/tos/kernel/init.lua" },
                                   source = "/mnt/floppy", unverified = true })
  eq("--unverified allows the restore", 1, rep2.fixed)
  eq("--unverified wrote the floppy's copy",
    "-- from the floppy\n", fs._files["/tos/kernel/init.lua"])
  local sawWarn = false
  for _, f in ipairs(rep2.findings) do
    if f.text:find("UNVERIFIED", 1, true) then sawWarn = true end
  end
  test("--unverified restore is labelled UNVERIFIED", sawWarn)
end

do
  local _, deps = seeded()
  srm.baseline(deps, { paths = CRIT, content = true })
  local rep = srm.restore(deps)
  eq("clean system: nothing to restore", 0, rep.fixed)
  eq("clean system: no errors", 0, rep.counts.err)
end

-- ============================================================
-- 5. Repair composes the fixer pass
-- ============================================================
print()
print("-- repair --")

do
  local fs, deps = seeded()
  -- An orphaned atomic temp is exactly what kernel.repair sweeps.
  fs.writeFile("/etc/leftover.tos-tmp", "junk")
  local rep = srm.repair(deps)
  test("repair produced findings", #rep.findings > 0)
  eq("orphaned temp was swept", nil, fs._files["/etc/leftover.tos-tmp"])
  test("repair counted a fix", rep.fixed >= 1)
  eq("repair alone is not an error", 0, rep.counts.err)
end

do
  -- repair --restore composes both stages in one pass.
  local fs, deps = seeded()
  local good = fs._files["/tos/kernel/init.lua"]
  srm.baseline(deps, { paths = CRIT, content = true })
  fs.writeFile("/tos/kernel/init.lua", "-- TAMPERED\n")
  fs.writeFile("/etc/leftover.tos-tmp", "junk")
  local rep = srm.repair(deps, { restore = true })
  eq("temp swept AND file restored", good, fs._files["/tos/kernel/init.lua"])
  eq("no leftover temp", nil, fs._files["/etc/leftover.tos-tmp"])
  test("both stages counted", rep.fixed >= 2)
end

-- ============================================================
-- 6. Status
-- ============================================================
print()
print("-- status --")

do
  local fs = fakeFS()
  local data = ADDR .. "\nSRM:K4"
  local ep = { getData = function() return data end,
               setData = function(v) data = v; return true end }
  local deps = { fs = fs, serialize = serialize, crypto = crypto, eeprom = ep }

  local rep = srm.status(deps)
  test("status surfaces the parked fault", rep.counts.err >= 1)
  eq("status does NOT clear the fault by default", "K4", srm.parseFault(data))
  local sawWhy = false
  for _, f in ipairs(rep.findings) do
    if f.text:find("kernel was missing", 1, true) then sawWhy = true end
  end
  test("status explains the fault in English", sawWhy)

  local rep2 = srm.status(deps, { clearFault = true })
  test("status --clear reports the fault once more", rep2.counts.err >= 1)
  eq("status --clear consumed it", nil, srm.parseFault(data))

  local rep3 = srm.status(deps)
  eq("a clean POST is reported as ok", 0, rep3.counts.err)
end

-- ============================================================
-- 7. Argument grammar
-- ============================================================
print()
print("-- argument grammar --")

do
  local verb, flags, paths = srm.parseArgs({})
  eq("no args defaults to status", "status", verb)
  eq("no args: no paths", 0, #paths)

  verb, flags = srm.parseArgs({ "SCAN" })
  eq("verb is case-insensitive", "scan", verb)

  verb, flags = srm.parseArgs({ "repair", "--restore" })
  eq("bare flag is boolean true", true, flags.restore)
  eq("verb survives a following flag", "repair", verb)

  verb, flags = srm.parseArgs({ "restore", "--source=/mnt/x" })
  eq("--flag=value carries the value", "/mnt/x", flags.source)

  verb, flags = srm.parseArgs({ "restore", "--source", "/mnt/x" })
  eq("--flag value (space form) carries the value", "/mnt/x", flags.source)

  -- The regression this grammar exists for: the mount point must never be
  -- mistaken for a file to restore, whatever order it is written in.
  verb, flags, paths = srm.parseArgs({ "restore", "/tos/kernel/fs.lua", "--source", "/mnt/x" })
  eq("path-then-source: source captured", "/mnt/x", flags.source)
  eq("path-then-source: exactly one path", 1, #paths)
  eq("path-then-source: the path is the file, not the mount",
    "/tos/kernel/fs.lua", paths[1])

  verb, flags, paths = srm.parseArgs({ "restore", "--source", "/mnt/x", "/tos/kernel/fs.lua" })
  eq("source-then-path: source captured", "/mnt/x", flags.source)
  eq("source-then-path: exactly one path", 1, #paths)
  eq("source-then-path: the path is the file", "/tos/kernel/fs.lua", paths[1])

  -- A dangling --source must be reportable, not silently swallowed.
  verb, flags = srm.parseArgs({ "restore", "--source" })
  eq("dangling --source stays boolean (caller reports it)", true, flags.source)
  verb, flags = srm.parseArgs({ "restore", "--source", "--unverified" })
  eq("--source followed by a flag does not eat it", true, flags.source)
  eq("...and the following flag is still parsed", true, flags.unverified)

  verb, flags, paths = srm.parseArgs({ "baseline", "--full" })
  eq("baseline --full", true, flags.full)
  eq("baseline --full: no stray paths", 0, #paths)
end

-- ============================================================
-- 8. Shell wiring
-- ============================================================
-- Source-level checks, in the style test_bios.lua uses for the BIOS: a
-- registry entry with no matching assignment (or vice versa) shows up as
-- "unknown command" at runtime, which is not a failure mode worth
-- discovering in the emulator.
print()
print("-- shell wiring --")

do
  local function readUp(rel)
    for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
      local h = io.open(p, "r")
      if h then local s = h:read("a"); h:close(); return s end
    end
  end
  local regSrc = readUp("tos/shell/panels/commands.lua")
  local admSrc = readUp("tos/shell/panels/commands/admin.lua")
  test("commands.lua readable", regSrc ~= nil)
  test("admin.lua readable", admSrc ~= nil)

  if regSrc and admSrc then
    local M = load(regSrc, "=commands.lua", "t")()
    local entry = M.entry("srm")
    test("srm is in the command registry", entry ~= nil)
    eq("srm is an admin-category command", "admin", entry and entry.category)
    -- Tier 1, not 2: status/scan/health are read-only and a user should be
    -- able to ask why the machine is unhappy. The WRITING subcommands
    -- self-gate in-body, which is the next assertion.
    eq("srm is tier 1 (read-only surface is open)", 1, entry and entry.tier)
    test("srm has help text", type(entry and entry.help) == "string"
      and #entry.help > 0)
    local names = {}
    for _, n in ipairs(M.commandNames()) do names[n] = true end
    test("srm is dispatchable by name", names.srm == true)

    test("admin.lua actually assigns C.srm", admSrc:find("C.srm = function", 1, true) ~= nil)
    -- Every subcommand the usage text advertises must exist in the body.
    for _, verb in ipairs({ "status", "scan", "health", "verify",
                            "repair", "baseline", "restore", "full" }) do
      test("srm handles '" .. verb .. "'",
        admSrc:find('sub == "' .. verb .. '"', 1, true) ~= nil)
    end
    -- #SEC — the three subcommands that write must be admin-gated. Extract
    -- the C.srm body and check each mutating branch is followed by the gate.
    local body = admSrc:match("C%.srm = function.-\n  end\n")
    test("C.srm body located", body ~= nil)
    if body then
      for _, verb in ipairs({ "baseline", "repair", "restore" }) do
        local branch = body:match('sub == "' .. verb .. '" then(.-)\n    elseif')
          or body:match('sub == "' .. verb .. '" then(.-)\n    else')
        test("srm " .. verb .. " is admin-gated",
          branch ~= nil and branch:find("adminOnly(o)", 1, true) ~= nil)
      end
      for _, verb in ipairs({ "scan", "status" }) do
        local branch = body:match('sub == "' .. verb .. '" then(.-)\n    elseif')
        test("srm " .. verb .. " is NOT gated (read-only)",
          branch ~= nil and branch:find("adminOnly", 1, true) == nil)
      end
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***") end
return failed == 0
