-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: launcher.readTapeMenu                     ║
-- ║                                                            ║
-- ║  The launcher reads the operator's personal menu off a     ║
-- ║  tape-authenticator keycard. This builds a real card image ║
-- ║  (via the package's own buildImage) with a vault-encrypted ║
-- ║  menu and checks the launcher reads it back — proving the  ║
-- ║  two sides agree on the wire format.                       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_launcher_tape.lua

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

-- tape-authenticator requires component/computer at load.
package.loaded["component"] = { list = function() return function() return nil end end,
                                proxy = function() return nil end }
package.loaded["computer"] = { uptime = function() return 0 end, pullSignal = function() end }

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local L = require("shell.launcher")

local here = (arg and arg[0]) or "usr/lib/tests/test_launcher_tape.lua"
local base = here:gsub("[^/\\]*$", "")
local tape
for _, p in ipairs({
    base .. "../../../../TOS-Extras/modules/tape-authenticator/init.lua",
    "../TOS-Extras/modules/tape-authenticator/init.lua",
    "TOS-Extras/modules/tape-authenticator/init.lua" }) do
  local chunk = loadfile(p); if chunk then tape = chunk(); break end
end
if not L.readTapeMenu or not (tape and tape._format) then
  print("FAIL: launcher.readTapeMenu or tape _format missing")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local F = tape._format

-- Mock vault: opaque marker + passphrase-gated decrypt (good enough to prove
-- the launcher routes through vault correctly).
local MARK = "VBLOB1:"
local vault = {
  encrypt = function(plain) return MARK .. plain end,
  isEncrypted = function(s) return type(s) == "string" and s:sub(1, #MARK) == MARK end,
  decrypt = function(blob, pass)
    if pass ~= "right" then return nil, "wrong passphrase" end
    if blob:sub(1, #MARK) ~= MARK then return nil, "not a blob" end
    return blob:sub(#MARK + 1)
  end,
}

local body = F.makeBody("OP-1", 1)
local MAC  = string.rep("a", 64)
local menuBlob = vault.encrypt("Reactor status|doctor\nDisks|df")
local image    = F.buildImage(body, MAC, "", menuBlob)

print("=== launcher.readTapeMenu Tests ===")
print()

local menu, err = L.readTapeMenu(image, "right", vault)
test("reads a menu", "table", type(menu))
test("menu title", "Tape toolbox", menu and menu.title)
test("two items", 2, menu and #menu.items)
test("item 1 label", "Reactor status", menu and menu.items[1].label)
test("item 1 runs doctor", "doctor", menu and menu.items[1].run)
test("item 2 runs df", "df", menu and menu.items[2].run)

-- A card with a log but NO menu region.
local imgLogOnly = F.buildImage(body, MAC, vault.encrypt("a log line"), nil)
local m2, e2 = L.readTapeMenu(imgLogOnly, "right", vault)
test("no menu region -> nil", nil, m2)
test("no menu region -> explains", true, type(e2) == "string" and e2:find("menu") ~= nil)

-- Wrong passphrase is rejected by vault.decrypt.
local m3, e3 = L.readTapeMenu(image, "wrong", vault)
test("wrong passphrase -> nil", nil, m3)
test("wrong passphrase -> decrypt error", true,
  type(e3) == "string" and e3:find("decrypt") ~= nil)

-- Non-keycard data.
local m4, e4 = L.readTapeMenu("not a keycard at all....................", "right", vault)
test("non-keycard -> nil", nil, m4)

-- ── Streaming reader (the Tape-Menu OOM fix) ───────────────────────
-- readTapeMenuFromDrive must parse the SAME image straight off a drive,
-- reading only header + menu bytes and seeking over label/MAC/log. The
-- fake drive records how many bytes were actually read so the test can
-- prove the whole-tape read is gone.
local function fakeDrive(image, tapeSize)
  local pos, bytesRead = 0, 0
  return {
    getSize = function() return tapeSize end,
    stop    = function() end,
    seek    = function(n)
      local target = math.max(0, math.min(tapeSize, pos + n))
      local moved = target - pos; pos = target; return moved
    end,
    read    = function(n)
      n = math.min(n or 1, tapeSize - pos)
      if n <= 0 then return "" end
      -- Past the image, a real tape returns zero-filled media.
      local chunk = image:sub(pos + 1, pos + n)
      chunk = chunk .. string.rep("\0", n - #chunk)
      pos = pos + n; bytesRead = bytesRead + n
      return chunk
    end,
    _stats  = function() return bytesRead end,
  }
end

-- Give the card a fat personal log so "streamed" is measurable: the reader
-- must SKIP it, not load it.
local bigLog  = vault.encrypt(string.rep("log line\n", 2000))     -- ~18 KB
local imgBig  = F.buildImage(body, MAC, bigLog, menuBlob)
local TAPE_SZ = 4 * 1024 * 1024                                   -- stock 4 MB tape

local d1 = fakeDrive(imgBig, TAPE_SZ)
local m5, e5 = L.readTapeMenuFromDrive(d1, "right", vault)
test("streamed: reads the menu", "table", type(m5))
test("streamed: two items", 2, m5 and #m5.items)
test("streamed: item 1 runs doctor", "doctor", m5 and m5.items[1].run)
test("streamed: skips the log + never loads the tape (< 4 KB read)",
  true, d1._stats() < 4096)

local d2 = fakeDrive(imgBig, TAPE_SZ)
local m6, e6 = L.readTapeMenuFromDrive(d2, "wrong", vault)
test("streamed: wrong passphrase -> nil", nil, m6)

local d3 = fakeDrive("garbage tape contents.......................", 64)
local m7, e7 = L.readTapeMenuFromDrive(d3, "right", vault)
test("streamed: non-keycard -> nil", nil, m7)

-- Hostile/corrupt menu length must be refused, not allocated.
local hostile = F.buildImage(body, MAC, "", nil)
  .. string.char(0xFF, 0xFF, 0xFF, 0x7F)   -- menuLen = ~2 GB
local d4 = fakeDrive(hostile, TAPE_SZ)
local m8, e8 = L.readTapeMenuFromDrive(d4, "right", vault)
test("streamed: implausible menuLen refused", nil, m8)
test("streamed: implausible menuLen explains", true,
  type(e8) == "string" and e8:find("implausible") ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
