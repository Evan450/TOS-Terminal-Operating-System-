-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: bios.lua (the 4 KiB EEPROM)                 ║
-- ║                                                                ║
-- ║  1. Compiles (text mode) and fits the EEPROM after the release ║
-- ║     strip (build/strip.lua --minify) — the byte budget.        ║
-- ║  2. Boots END-TO-END from a fake TBFS raw drive: superblock    ║
-- ║     parse, contiguous boot-region read, blob load + run, the   ║
-- ║     _TBFS_BOOT_DRIVE handoff, and the /init.lua chain.         ║
-- ║  3. Boots the managed-FS path (stored address, POST, fn(fs)).  ║
-- ║  4. Fallback approval (#SEC H1): Shift+Enter one-time boot vs  ║
-- ║     Y EEPROM commit vs timeout halt.                           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_bios.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- Resolve repo-relative paths whether run from TOS-Dev or usr/lib/tests.
local function readAll(path)
  local h = io.open(path, "rb")
  if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, prefix in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(prefix .. rel)
    if s then return s, prefix .. rel end
  end
  return nil
end

print("=== bios.lua (EEPROM) Tests ===")
print()

local biosSrc = findUp("bios.lua")
test("bios.lua readable", biosSrc ~= nil)
if not biosSrc then print(); print("*** TESTS FAILED ***"); return false end

-- ── 1. Compile + byte budget ───────────────────────────────────────
test("bios.lua compiles (text mode)", (load(biosSrc, "=bios.lua", "t")) ~= nil)

local stripSrc, stripPath = findUp("build/strip.lua")
test("build/strip.lua readable", stripSrc ~= nil)
if stripSrc then
  -- load() doesn't skip shebang lines (loadfile does) — drop it manually.
  stripSrc = stripSrc:gsub("^#[^\n]*", "")
  local stripM = assert(load(stripSrc, "=strip.lua", "t"))()
  local stripped = stripM.strip(biosSrc, { minify = true })
  test("stripped BIOS still compiles", (load(stripped, "=bios.min", "t")) ~= nil)
  test("stripped BIOS fits 4096-byte EEPROM (" .. #stripped .. " bytes)",
    #stripped <= 4096)
  -- Leave a little headroom for future one-line fixes.
  test("stripped BIOS leaves >= 128 bytes headroom (" .. (4096 - #stripped) .. " free)",
    #stripped <= 4096 - 128)
end

-- ── 1b. Lua architecture probe (5.3 AND 5.4 boot; 5.2 halts) ──────
-- The probe must stay a PARSER-FEATURE probe — load("return 1<<1") —
-- not a _VERSION/getArchitecture() compare: the 5.4 architecture parses
-- 5.3 syntax and must keep booting. Pin the probe source in BOTH boot
-- files, and prove the probe expression itself accepts this (5.3+)
-- interpreter while a 5.2-style parser failure would take the halt
-- branch.
do
  test("BIOS uses the parser-feature probe (5.4-compatible)",
    biosSrc:find('load("return 1<<1")', 1, true) ~= nil)
  test("BIOS does not version-compare the architecture",
    biosSrc:find("_VERSION", 1, true) == nil
    and biosSrc:find("getArchitecture", 1, true) == nil)
  local initSrc = findUp("init.lua")
  test("init.lua readable", initSrc ~= nil)
  if initSrc then
    test("init.lua uses the same parser-feature probe",
      initSrc:find('load("return 1<<1")', 1, true) ~= nil)
    test("init.lua does not version-compare the architecture",
      initSrc:find("getArchitecture", 1, true) == nil)
  end
  test("probe passes on a 5.3+ interpreter (this one)",
    load("return 1<<1") ~= nil)
end

-- ── Shared stubs ───────────────────────────────────────────────────
-- The real blockfs driver (for formatting the fake drive + the blob).
local blockfs
do
  local src = findUp("TOS-Extras/modules/blockfs/usr/lib/blockfs.lua")
  test("blockfs.lua readable (TOS-Extras)", src ~= nil)
  if not src then print(); print("*** TESTS FAILED ***"); return false end
  blockfs = assert(load(src, "=blockfs.lua", "t"))()
  blockfs._SRC = src
end

local function fakeDrive(sectorSize, sectors)
  local store = {}
  return {
    address = "drive-1111-2222",
    getSectorSize = function() return sectorSize end,
    getCapacity   = function() return sectorSize * sectors end,
    getPlatterCount = function() return 1 end,
    readSector    = function(n) return store[n] or string.rep("\0", sectorSize) end,
    writeSector   = function(n, d)
      if #d < sectorSize then d = d .. string.rep("\0", sectorSize - #d)
      elseif #d > sectorSize then d = d:sub(1, sectorSize) end
      store[n] = d
    end,
  }
end

-- A minimal managed-FS proxy (enough for the BIOS's managed path).
local function fakeManagedFS(files)
  local handles, nh = {}, 1
  return {
    address = "fsss-3333-4444",
    exists = function(p) return files[p] ~= nil end,
    getLabel = function() return "fakehd" end,
    open = function(p, m)
      if not files[p] then return nil end
      local h = nh; nh = nh + 1
      handles[h] = { data = files[p], pos = 1 }
      return h
    end,
    read = function(h, n)
      local st = handles[h]; if not st then return nil end
      if st.pos > #st.data then return nil end
      local chunk = st.data:sub(st.pos, st.pos + n - 1)
      st.pos = st.pos + n
      return chunk
    end,
    close = function(h) handles[h] = nil end,
  }
end

-- Build the stubbed OC environment and run the BIOS inside it. The stubs
-- are installed as REAL globals (and restored after): the BIOS loads the
-- boot blob with load(..., "t") and no env, so the blob's chunk sees _G —
-- a wrapper env on the BIOS chunk alone would not reach it.
--   opts.eepromData   what getData returns (stored boot address)
--   opts.components   { [addr] = { type = ..., proxy = ... } }
--   opts.signals      queued pullSignal returns, in order:
--                       table  → unpacked as the signal tuple
--                       string → returned as a bare event name
--                       number → clock jump: advance uptime, return nil
--                     Exhausting the queue raises (loud, not a hang).
-- Returns ok, err, log { setData = {...}, shutdowns = n, data = <live field> }
local function runBios(opts)
  local log = { setData = {}, shutdowns = 0, beeps = 0, tones = {} }
  local comps = opts.components or {}
  comps["eeee-0000"] = { type = "eeprom", proxy = {} }
  local signals = opts.signals or {}
  local sigIdx = 0
  local clock = 0
  -- The data field is STATEFUL: SRM Basic reads it, edits one line and
  -- writes it back, so a stub that always returned the original value would
  -- hide whether the boot address and the manifest anchor actually survive.
  local eepromData = opts.eepromData

  local component = {
    list = function(t)
      local addrs = {}
      for a, c in pairs(comps) do
        if c.type == t then addrs[#addrs + 1] = a end
      end
      table.sort(addrs)
      local i = 0
      return function() i = i + 1; return addrs[i] end
    end,
    type = function(a) return comps[a] and comps[a].type end,
    proxy = function(a)
      if comps[a] then return comps[a].proxy end
      error("no such component")
    end,
    invoke = function(a, m, ...)
      if m == "getData" then return eepromData end
      if m == "setData" then
        eepromData = (...)
        log.setData[#log.setData + 1] = (...)
        log.data = eepromData
        return true
      end
      error("invoke " .. tostring(m))
    end,
  }
  local computer = {
    uptime = function() clock = clock + 0.05; return clock end,
    -- Record the TONE, not just the count: SRM Basic beeps its fault code
    -- (one long 400 Hz, then <digit> short 900 Hz) so a screenless box is
    -- still diagnosable, and that contract needs pinning.
    beep = function(f) log.beeps = log.beeps + 1; log.tones[#log.tones + 1] = f or 0 end,
    pullSignal = function()
      sigIdx = sigIdx + 1
      local s = signals[sigIdx]
      if s == nil then error("TEST: signal queue underflow", 0) end
      if type(s) == "number" then clock = clock + s; return nil end
      if type(s) == "table" then return table.unpack(s) end
      return s
    end,
    shutdown = function()
      log.shutdowns = log.shutdowns + 1
      error("SHUTDOWN-SENTINEL", 0)
    end,
  }

  -- Fresh globals the BIOS (and the boot chain) touches.
  _G._BIOS_CY, _G._BIOS_DEPTH, _G._BIOS_ONETIME = nil, nil, nil
  _G._TBFS_BOOT_DRIVE, _G._TOS_UNMANAGED_ROOT = nil, nil
  _G._TEST_BOOTED = nil

  local savedComponent, savedComputer = _G.component, _G.computer
  _G.component, _G.computer = component, computer
  local fn = assert(load(biosSrc, "=bios.lua", "t"))
  local ok, err = pcall(fn)
  _G.component, _G.computer = savedComponent, savedComputer
  return ok, err, log
end

-- ── 2. TBFS raw-drive boot, end to end ─────────────────────────────
local drive = fakeDrive(512, 2048)          -- 1 MB raw volume
do
  local nowT = 0
  local nowfn = function() nowT = nowT + 1; return nowT end
  local blob = blockfs.bootBlob(blockfs._SRC)
  assert(blockfs.format(drive, { label = "tosboot", now = nowfn,
    bootBytes = #blob + 4096 }))
  local root = assert(blockfs.mount(drive, { now = nowfn }))
  local h = root.open("/init.lua", "w")
  root.write(h, "_G._TEST_BOOTED = 'TBFS-VIA-BIOS'")
  root.close(h)
  root.unmount()
  assert(blockfs.writeBoot(drive, blob))
end

do
  -- Stored boot address points at the raw drive: boots with NO prompt.
  local ok, err, log = runBios({
    eepromData = "drive-1111-2222",
    components = { ["drive-1111-2222"] = { type = "drive", proxy = drive } },
    signals = { "key_down" },   -- for the post-boot K() halt
  })
  test("TBFS boot: BIOS ran to the halt sentinel",
    not ok and tostring(err):find("SHUTDOWN%-SENTINEL") ~= nil)
  eq("TBFS boot: /init.lua actually ran", "TBFS-VIA-BIOS", _G._TEST_BOOTED)
  test("TBFS boot: unmanaged root exposed to init",
    _G._TOS_UNMANAGED_ROOT ~= nil and _G._TOS_UNMANAGED_ROOT.isDirectory
    and _G._TOS_UNMANAGED_ROOT.exists("/init.lua"))
  eq("TBFS boot: root proxy carries the drive address",
    "drive-1111-2222", _G._TOS_UNMANAGED_ROOT and _G._TOS_UNMANAGED_ROOT.address)
  eq("TBFS boot: handoff global cleaned up", nil, _G._TBFS_BOOT_DRIVE)
  eq("TBFS boot: EEPROM data untouched", 0, #log.setData)
  eq("TBFS boot: POST OK beeped once", 1, log.beeps)
  eq("TBFS boot: not flagged one-time", false, _G._BIOS_ONETIME)
end

-- ── 3. Managed-FS boot via stored address ──────────────────────────
do
  local mfs = fakeManagedFS({
    ["/init.lua"] = "_G._TEST_BOOTED = 'MANAGED-' .. tostring((...) ~= nil)",
    ["/tos/kernel/init.lua"] = "-- present",
  })
  local ok, err, log = runBios({
    eepromData = "fsss-3333-4444",
    components = { ["fsss-3333-4444"] = { type = "filesystem", proxy = mfs } },
  })
  test("managed boot: BIOS ran init.lua without error", ok, err)
  eq("managed boot: init ran AND received the boot FS arg",
    "MANAGED-true", _G._TEST_BOOTED)
  eq("managed boot: EEPROM data untouched", 0, #log.setData)
  -- #FIX (round 7) — the POST-OK beep lived ONLY on the TBFS branch, so
  -- the path almost every machine takes shipped silent. A 5150 beeped;
  -- so does this. Pinned on BOTH branches so neither can lose it again.
  eq("managed boot: POST OK beeped once", 1, log.beeps)
end

-- ── 4. Fallback approval (#SEC H1) — raw drive discovered by scan ──
do
  -- Shift+Enter: one-time boot, EEPROM NOT written.
  local ok, err, log = runBios({
    eepromData = "",
    components = { ["drive-1111-2222"] = { type = "drive", proxy = drive } },
    signals = {
      { "key_down", "kb", 0, 42 },    -- Shift down
      { "key_down", "kb", 13, 28 },   -- Enter (Shift held)
      "key_down",                     -- post-boot K() halt
    },
  })
  test("one-time: reached the halt sentinel",
    not ok and tostring(err):find("SHUTDOWN%-SENTINEL") ~= nil)
  eq("one-time: booted the TBFS volume", "TBFS-VIA-BIOS", _G._TEST_BOOTED)
  eq("one-time: _BIOS_ONETIME flagged", true, _G._BIOS_ONETIME)
  eq("one-time: EEPROM NOT rewritten", 0, #log.setData)
end

do
  -- 'Y': commit the EEPROM, then boot.
  local ok, err, log = runBios({
    eepromData = "",
    components = { ["drive-1111-2222"] = { type = "drive", proxy = drive } },
    signals = {
      { "key_down", "kb", 121, 21 },  -- 'y'
      "key_down",                     -- post-boot K() halt
    },
  })
  test("commit: reached the halt sentinel",
    not ok and tostring(err):find("SHUTDOWN%-SENTINEL") ~= nil)
  eq("commit: booted the TBFS volume", "TBFS-VIA-BIOS", _G._TEST_BOOTED)
  eq("commit: EEPROM rewritten once", 1, #log.setData)
  eq("commit: rewritten to the drive address", "drive-1111-2222", log.setData[1])
  eq("commit: not flagged one-time", false, _G._BIOS_ONETIME)
end

do
  -- No approval (30s timeout elapses): halt, no boot, no write.
  local ok, err, log = runBios({
    eepromData = "",
    components = { ["drive-1111-2222"] = { type = "drive", proxy = drive } },
    signals = {
      31,           -- clock jump past the 30s approval deadline
      "key_down",   -- the K() halt keypress
    },
  })
  test("timeout: halted at the sentinel",
    not ok and tostring(err):find("SHUTDOWN%-SENTINEL") ~= nil)
  eq("timeout: nothing booted", nil, _G._TEST_BOOTED)
  eq("timeout: EEPROM NOT rewritten", 0, #log.setData)
end

-- ── 5. SRM Basic — POST faults are named, parked and beeped ────────
-- The EEPROM half of System Repair & Maintenance. Its whole reason to exist
-- is that these faults happen BEFORE anything on disk runs, so the code has
-- to survive in the one place that works on a machine whose disk is the
-- problem. What must hold on every fault path:
--   * the right code is parked, on its own line
--   * the boot address (line 1) and the TOS1 manifest anchor (line 2) are
--     untouched — clobbering line 1 would make the machine prompt "Boot
--     drive changed" on every power-on afterwards
--   * the beep pattern matches the code's digit
--   * the machine halts
local ANCHOR_LINE = "TOS1:" .. string.rep("b", 64)

local function faultCase(name, code, opts)
  opts.signals = opts.signals or { "key_down" }
  local ok, err, log = runBios(opts)
  test(name .. ": halted", not ok and tostring(err):find("SHUTDOWN%-SENTINEL") ~= nil)
  eq(name .. ": parked exactly one code", 1, #log.setData)
  local parked = log.data or ""
  eq(name .. ": code is " .. code, code, parked:match("\nSRM:(%S+)") or parked:match("^SRM:(%S+)"))
  -- Beep pattern: one long 400 Hz marker, then <digit> short 900 Hz.
  local digit = tonumber(code:sub(2, 2))
  eq(name .. ": beeped " .. (digit + 1) .. " time(s)", digit + 1, log.beeps)
  eq(name .. ": first tone is the 400 Hz fault marker", 400, log.tones[1])
  local shorts = 0
  for i = 2, #log.tones do if log.tones[i] == 900 then shorts = shorts + 1 end end
  eq(name .. ": " .. digit .. " short beep(s) = the code digit", digit, shorts)
  return log
end

do
  -- D2 — nothing bootable attached at all.
  local log = faultCase("no boot device", "D2", {
    eepromData = "", components = {},
  })
  eq("no boot device: nothing booted", nil, _G._TEST_BOOTED)
end

do
  -- K4 — the disk boots but the kernel isn't on it.
  local mfs = fakeManagedFS({ ["/init.lua"] = "_G._TEST_BOOTED = 'NOPE'" })
  local log = faultCase("kernel missing", "K4", {
    eepromData = "fsss-3333-4444\n" .. ANCHOR_LINE,
    components = { ["fsss-3333-4444"] = { type = "filesystem", proxy = mfs } },
  })
  eq("kernel missing: init did NOT run", nil, _G._TEST_BOOTED)
  eq("kernel missing: boot address preserved", "fsss-3333-4444", log.data:match("^[^\n]*"))
  eq("kernel missing: manifest anchor preserved",
    string.rep("b", 64), log.data:match("\nTOS1:(%x+)"))
end

do
  -- I6 — /init.lua is present but won't compile (a truncated write).
  local mfs = fakeManagedFS({
    ["/init.lua"] = "this is not valid lua ((((",
    ["/tos/kernel/init.lua"] = "-- present",
  })
  local log = faultCase("init syntax", "I6", {
    eepromData = "fsss-3333-4444\n" .. ANCHOR_LINE,
    components = { ["fsss-3333-4444"] = { type = "filesystem", proxy = mfs } },
  })
  eq("init syntax: boot address preserved", "fsss-3333-4444", log.data:match("^[^\n]*"))
  eq("init syntax: anchor preserved", string.rep("b", 64), log.data:match("\nTOS1:(%x+)"))
end

do
  -- I5 — /init.lua exists (so it was selected) but cannot be opened.
  local base = fakeManagedFS({
    ["/init.lua"] = "-- unreadable",
    ["/tos/kernel/init.lua"] = "-- present",
  })
  base.open = function() return nil end
  faultCase("init unreadable", "I5", {
    eepromData = "fsss-3333-4444",
    components = { ["fsss-3333-4444"] = { type = "filesystem", proxy = base } },
  })
end

do
  -- B3 — a TBFS raw drive whose boot region holds something uncompilable.
  local bad = fakeDrive(512, 2048)
  local nowT = 0
  local nowfn = function() nowT = nowT + 1; return nowT end
  assert(blockfs.format(bad, { label = "badboot", now = nowfn, bootBytes = 4096 }))
  assert(blockfs.writeBoot(bad, "((( not lua at all"))
  faultCase("bad boot blob", "B3", {
    eepromData = "drive-1111-2222",
    components = { ["drive-1111-2222"] = { type = "drive", proxy = bad } },
  })
end

do
  -- A previously-parked code must be REPLACED, not appended to, or a box
  -- with a history of faults would accumulate lines until the 256-byte
  -- field overflowed and took the boot address with it.
  local log = faultCase("stale code replaced", "D2", {
    eepromData = "\n" .. ANCHOR_LINE .. "\nSRM:K4",
    components = {},
  })
  local n = 0
  for _ in log.data:gmatch("SRM:") do n = n + 1 end
  eq("stale code replaced: exactly one SRM line", 1, n)
  eq("stale code replaced: anchor still intact",
    string.rep("b", 64), log.data:match("\nTOS1:(%x+)"))
  test("stale code replaced: field stayed inside the 256-byte EEPROM",
    #log.data <= 256)
end

do
  -- A SUCCESSFUL boot must never write the data field. (A machine that
  -- re-flashed its EEPROM on every power-on would be a nasty surprise.)
  local mfs = fakeManagedFS({
    ["/init.lua"] = "_G._TEST_BOOTED = 'CLEAN'",
    ["/tos/kernel/init.lua"] = "-- present",
  })
  local ok, err, log = runBios({
    eepromData = "fsss-3333-4444\n" .. ANCHOR_LINE,
    components = { ["fsss-3333-4444"] = { type = "filesystem", proxy = mfs } },
  })
  test("clean boot: no error", ok, err)
  eq("clean boot: init ran", "CLEAN", _G._TEST_BOOTED)
  eq("clean boot: EEPROM never written", 0, #log.setData)
  eq("clean boot: POST-OK beep only", 1, log.beeps)
end

do
  -- Operator declining a fallback boot is a CHOICE, not a fault: parking a
  -- code for it would make `srm status` cry wolf on the next boot.
  local ok, err, log = runBios({
    eepromData = "",
    components = { ["drive-1111-2222"] = { type = "drive", proxy = drive } },
    signals = {
      { "key_down", "kb", 110, 49 },   -- 'n' — anything but Y/Shift+Enter
      "key_down",                      -- the K() halt keypress
    },
  })
  test("boot cancelled: halted",
    not ok and tostring(err):find("SHUTDOWN%-SENTINEL") ~= nil)
  eq("boot cancelled: no fault code parked", 0, #log.setData)
end

-- Every code the BIOS can park must be explained by the kernel half.
do
  local srmSrc = findUp("tos/kernel/srm.lua")
  test("kernel/srm.lua readable", srmSrc ~= nil)
  if srmSrc then
    local srm = assert(load(srmSrc, "=srm.lua", "t"))()
    for code in biosSrc:gmatch('F%("(%u%d)"') do
      test("srm explains BIOS code " .. code,
        type(srm.BASIC_CODES[code]) == "string")
    end
    -- ...and nothing is explained that the BIOS can no longer emit.
    for code in pairs(srm.BASIC_CODES) do
      test("BIOS still emits documented code " .. code,
        biosSrc:find('F("' .. code .. '"', 1, true) ~= nil)
    end
  end
end

-- Cleanup the globals the boots left behind.
_G._BIOS_CY, _G._BIOS_DEPTH, _G._BIOS_ONETIME = nil, nil, nil
_G._TBFS_BOOT_DRIVE, _G._TOS_UNMANAGED_ROOT, _G._TEST_BOOTED = nil, nil, nil

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed == 0 then print("*** ALL TESTS PASSED ***")
else print("*** TESTS FAILED ***") end
return failed == 0
