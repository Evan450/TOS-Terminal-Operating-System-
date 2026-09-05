-- ╔══════════════════════════════════════════════════════════╗
-- ║  Test: tape — bounded archive/vault reads + V2 magic      ║
-- ║                                                            ║
-- ║  Covers the two defects fixed alongside this file:         ║
-- ║   1. `tape decrypt` rejected every tape `tape encrypt`     ║
-- ║      had just written, because tapeFormatGuess() matched   ║
-- ║      only TVAULT1 while kernel.vault writes TVAULT2.       ║
-- ║   2. readWholeTape() slurped getSize() bytes into one Lua  ║
-- ║      string — the same OOM pattern launcher.lua's streamed ║
-- ║      reader exists to avoid. Reads are now bounded by the  ║
-- ║      archive's real length / the vault header's ctLen.     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua modules/tape/test_tape_vault.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, expected, actual)
  if expected == actual then
    passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. "  (expected " .. tostring(expected)
      .. ", got " .. tostring(actual) .. ")")
  end
end

local here = (arg and arg[0]) or "modules/tape/test_tape_vault.lua"
local base = here:gsub("[^/\\]*$", "")

-- ── Sandbox stubs ────────────────────────────────────────────
-- The module is normally loaded by the pkg sandbox, which supplies
-- `component`/`computer` via require and `fs` as a securefs proxy.
local componentStub = {
  list  = function() return function() return nil end end,
  proxy = function() return nil end,
}
local computerStub = {
  pullSignal = function() end,
  -- 0 makes memBudget() fall back to "unbounded", which is what we want
  -- for most cases; individual tests override it to exercise the guard.
  freeMemory = function() return 0 end,
}

local realRequire = require
local function stubRequire(name)
  if name == "component" then return componentStub end
  if name == "computer"  then return computerStub  end
  error("require blocked in sandbox: " .. tostring(name), 0)
end

_G.fs = { exists = function() return false end }

-- ── Fake tape drive ──────────────────────────────────────────
-- `size` is the PHYSICAL cartridge length (a stock tape is 4 MB); `img` is
-- the data actually written at the start. Everything past `img` reads as
-- NUL padding, exactly like a real tape. bytesRead is the whole point of
-- this fixture: it proves we never pull the padding into RAM.
local function fakeDrive(img, size)
  size = size or (4 * 1024 * 1024)
  local d = { bytesRead = 0, seeks = 0 }
  local pos = 0
  function d.getSize() return size end
  function d.isReady() return true end
  function d.stop() end
  function d.seek(n)
    local want = pos + n
    if want < 0 then want = 0 elseif want > size then want = size end
    local moved = want - pos
    pos = want
    d.seeks = d.seeks + 1
    return moved
  end
  function d.read(n)
    if n == nil then n = 1 end
    if pos >= size then return "" end
    local avail = math.min(n, size - pos)
    local out
    if pos >= #img then
      out = string.rep("\0", avail)                     -- past the data: padding
    else
      out = img:sub(pos + 1, pos + avail)
      if #out < avail then out = out .. string.rep("\0", avail - #out) end
    end
    pos = pos + avail
    d.bytesRead = d.bytesRead + #out
    return out
  end
  return d
end

-- ── Fixture builders ─────────────────────────────────────────
local A_MAGIC, EOA = "TOS\x01", "TOS\x00"

local function enc16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function enc32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
                     math.floor(n / 256) % 256, n % 256)
end

--- One-file TOS archive: header + data + end-of-archive marker.
local function buildArchive(path, data)
  return A_MAGIC
    .. string.char(1)            -- version
    .. string.char(0)            -- flags (0 = file)
    .. enc16(#path) .. path
    .. enc32(#data)
    .. enc32(0)                  -- checksum (unused by the reader under test)
    .. data
    .. EOA
end

--- Vault blob with the real wire layout (kernel/vault.lua): 114-byte header
--- with a LITTLE-endian ctLen at offset 47, then ctLen bytes of ciphertext.
local function buildVault(magic, ct)
  local n = #ct
  local le32 = string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
  local header = magic                       -- 8  magic
    .. "aes\0"                               -- 4  algo
    .. string.char(0, 0)                     -- 2  rounds
    .. string.rep("s", 16)                   -- 16 salt
    .. string.rep("i", 16)                   -- 16 iv
    .. le32                                  -- 4  ctLen
    .. string.rep("m", 64)                   -- 64 mac
  assert(#header == 114, "fixture header must be 114 bytes, got " .. #header)
  return header .. ct
end

-- ── Load the module under the stubs ──────────────────────────
local chunk = assert(loadfile(base .. "init.lua"))
local env = setmetatable({ require = stubRequire }, { __index = _G })
if setfenv then setfenv(chunk, env) else
  chunk = assert(load(string.dump(chunk), "tape", "b", env))
end
local mod = chunk()

print("tape: bounded reads + vault magic")

-- ── 1. Vault magic: both wire versions ───────────────────────
-- The regression that broke encrypt→decrypt round-tripping.
local ctV2 = string.rep("C", 300)
local d = fakeDrive(buildVault("TVAULT2\0", ctV2))
local blob, err = mod.readVaultBlobFromDrive(d)
test("V2 blob is recognised (the encrypt→decrypt regression)", 114 + #ctV2, blob and #blob or err)

d = fakeDrive(buildVault("TVAULT1\0", string.rep("C", 300)))
blob = mod.readVaultBlobFromDrive(d)
test("V1 blob still recognised (backward compat)", 114 + 300, blob and #blob or -1)

d = fakeDrive("NOTAVAULT" .. string.rep("x", 500))
blob, err = mod.readVaultBlobFromDrive(d)
test("non-vault tape rejected", true, blob == nil and err:find("not encrypted") ~= nil)

-- ── 2. Vault reads are bounded by ctLen, not tape size ───────
d = fakeDrive(buildVault("TVAULT2\0", ctV2), 4 * 1024 * 1024)
blob = mod.readVaultBlobFromDrive(d)
test("vault read returns exactly header+ctLen", 414, blob and #blob or -1)
test("vault read never touches the 4MB of padding", true, d.bytesRead <= 1024)

-- A corrupt/hostile ctLen must be refused, not trusted into an allocation.
local huge = buildVault("TVAULT2\0", "short")
huge = huge:sub(1, 46) .. string.char(0xFF, 0xFF, 0xFF, 0x7F) .. huge:sub(51)
d = fakeDrive(huge, 4096)
blob, err = mod.readVaultBlobFromDrive(d)
test("implausible ctLen refused", true, blob == nil and err:find("truncated or") ~= nil)

-- ── 3. Archive reads are bounded by the archive, not the tape ─
local payload = string.rep("D", 2000)
local archive = buildArchive("/etc/hosts", payload)
d = fakeDrive(archive, 4 * 1024 * 1024)
local data, aerr = mod.readArchiveFromDrive(d)
test("archive read returns exactly the archive", #archive, data and #data or aerr)
test("archive read ends with the EOA marker", EOA, data and data:sub(-4) or "?")
-- The old readWholeTape pulled all 4 MB here; scanArchive walks structurally
-- and skips file data with seek, so the real figure is far below the tape size.
test("archive read never pulls the 4MB cartridge", true, d.bytesRead < 64 * 1024)

d = fakeDrive("", 4 * 1024 * 1024)
data, aerr = mod.readArchiveFromDrive(d)
test("blank tape reports no archive", true, data == nil and aerr:find("No TOS data archive") ~= nil)

-- ── 4. Memory guard refuses rather than OOMs ─────────────────
-- A machine with very little free RAM must decline the read with a clear
-- message instead of building the string and dying.
computerStub.freeMemory = function() return 300 end   -- budget = 100 bytes
d = fakeDrive(buildVault("TVAULT2\0", ctV2))
blob, err = mod.readVaultBlobFromDrive(d)
test("vault read declines when RAM is short", true, blob == nil and err:find("RAM") ~= nil)

d = fakeDrive(archive, 4 * 1024 * 1024)
data, aerr = mod.readArchiveFromDrive(d)
test("archive read declines when RAM is short", true, data == nil and aerr:find("RAM") ~= nil)
computerStub.freeMemory = function() return 0 end

-- ── Summary ──────────────────────────────────────────────────
-- The harness classifies on these exact markers (run_tests.py
-- PASS_MARKERS / FAIL_MARKER) — don't reword them.
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
