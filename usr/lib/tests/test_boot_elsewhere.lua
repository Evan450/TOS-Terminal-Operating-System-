-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a broken install is not a boot loop          ║
-- ║                                                                ║
-- ║  The EEPROM boots its saved disk without asking. A disk whose  ║
-- ║  /init.lua runs but whose system files are missing was booted, ║
-- ║  refused ("MISSING n FILES"), rebooted on a key, and booted     ║
-- ║  again -- forever, short of moving the disk to another machine. ║
-- ║  That screen now offers B: pick another bootable disk and the   ║
-- ║  EEPROM is pointed at it, as the BIOS's own "Save it? Y" does.  ║
-- ║                                                                ║
-- ║  bootElsewhere is LIFTED from /init.lua (a top-level chunk that ║
-- ║  boots when run) and driven with fake disks and fake keys.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_boot_elsewhere.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local src = assert(io.open("init.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local body = src:match("(local function bootElsewhere.-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
test("bootElsewhere lifts out of init.lua", body ~= nil)
local bootElsewhere = body and assert(load(body .. "\nreturn bootElsewhere", "=bootElsewhere", "t"))()

-- ── A machine ──────────────────────────────────────────────────────
local BROKEN, TMP, OPENOS, TBFS, BLANK, TAPE, FLAKY =
  "b40k-0000", "7777-tmp0", "0pen-0s00", "7bf5-dr1v", "b1a7-dr1v", "7a9e-dr1v", "f1a6-0000"
local devices
local function machine(extra)
  devices = {
    [BROKEN] = { kind = "filesystem", files = { ["/init.lua"] = true }, label = "TOS" },
    [TMP]    = { kind = "filesystem", files = {}, label = "tmpfs" },
    [BLANK]  = { kind = "drive", sector1 = string.rep("\0", 512) },
    [TAPE]   = { kind = "tape_drive" },
  }
  for k, v in pairs(extra or {}) do devices[k] = v end
end
local comp = {
  list = function(kind, exact)
    local out = {}
    for a, d in pairs(devices) do
      if (exact and d.kind == kind) or (not exact and d.kind:find(kind, 1, true)) then
        out[#out + 1] = a
      end
    end
    table.sort(out)
    local i = 0
    return function() i = i + 1; return out[i] end
  end,
  proxy = function(a)
    local d = devices[a]
    if not d then error("no such component") end
    local px = { getLabel = function() return d.label end }
    if d.kind == "filesystem" then
      px.exists = function(p)
        if d.raises then error("disk removed") end
        return d.files[p] == true
      end
    elseif d.kind == "drive" then
      px.readSector = function() return d.sector1 end
    end
    return px
  end,
}
local SKIP = { [BROKEN] = true, [TMP] = true }

-- Keys: a list of signals (a bare number is a key's char), and an
-- optional hook run before signal i is delivered. The run fails loudly
-- if it asks for a key the test did not press.
local function run(signals, setBoot, before)
  local said, i = {}, 0
  local function pull()
    i = i + 1
    if before then before(i) end
    local s = signals[i]
    if s == nil then error("asked for a key the test did not press") end
    if type(s) ~= "table" then s = { "key_down", "kbd", s, 0 } end
    return table.unpack(s)
  end
  local ok, r = pcall(bootElsewhere, comp, SKIP, function(t) said[#said + 1] = t end, pull, setBoot)
  return ok, r, said, i
end
local function saidAny(said, needle)
  for _, l in ipairs(said) do if l:find(needle, 1, true) then return true end end
  return false
end
local B, b, ONE, TWO, X = 66, 98, 49, 50, 120

print("=== a broken install is not a boot loop ===")
print()

if bootElsewhere then
  local set
  local function setBoot(a) set = a end

  machine({ [OPENOS] = { kind = "filesystem", files = { ["/init.lua"] = true }, label = "OpenOS" } })
  set = nil
  local ok, r, said = run({ X }, setBoot)
  test("any other key reboots, as before", ok and r == nil and set == nil)
  test("...and the screen says B is the way out", saidAny(said, "B: boot another disk"))

  set = nil
  ok, r = run({ { "component_added", "x", "filesystem" }, { "touch", "s", 1, 1 }, X }, setBoot)
  test("signals that are not keys do nothing", ok and r == nil and set == nil)

  set = nil
  ok, r, said = run({ B, ONE }, setBoot)
  test("B lists the other bootable disk, and its number picks it",
    ok and r == OPENOS and set == OPENOS)
  test("...naming it", saidAny(said, " 1) " .. OPENOS:sub(1, 8) .. " OpenOS"))
  test("...never the disk that just failed, nor the tmpfs",
    not saidAny(said, BROKEN:sub(1, 8)) and not saidAny(said, TMP:sub(1, 8)))
  test("...and says what it did", saidAny(said, "Boot disk set to " .. OPENOS:sub(1, 8)))

  set = nil
  ok, r = run({ b, TWO }, setBoot)
  test("lower-case b works; a number past the list reboots instead", ok and r == nil and set == nil)

  -- A raw TBFS drive is bootable too; a blank drive and a tape drive are not.
  machine({ [TBFS] = { kind = "drive", sector1 = "TBFS\1" .. string.rep("\0", 507), label = "raw" } })
  set = nil
  ok, r, said = run({ B, ONE }, setBoot)
  test("a raw drive with a TBFS superblock is offered", ok and r == TBFS and set == TBFS)
  test("...a blank drive is not", not saidAny(said, BLANK:sub(1, 8)))
  test("...nor a tape drive", not saidAny(said, TAPE:sub(1, 8)))

  -- Nothing else to boot: say so, and let a disk be inserted.
  machine()
  set = nil
  ok, r, said = run({ B, B, ONE }, setBoot, function(i)
    -- The operator reads "no other disk", inserts the installer, presses B.
    if i == 2 then
      devices[OPENOS] = { kind = "filesystem", files = { ["/init.lua"] = true }, label = "Installer" }
    end
  end)
  test("with no other disk it says so", saidAny(said, "No other bootable disk"))
  test("...and a disk inserted then is found by pressing B again",
    ok and r == OPENOS and set == OPENOS)

  -- A disk pulled mid-scan must not take the screen down with it.
  machine({ [FLAKY] = { kind = "filesystem", files = {}, raises = true },
            [OPENOS] = { kind = "filesystem", files = { ["/init.lua"] = true }, label = "OpenOS" } })
  set = nil
  ok, r = run({ B, ONE }, setBoot)
  test("a disk that errors while scanned is skipped", ok and r == OPENOS)

  -- Without setBootAddress there is nothing to offer.
  ok, r, said = run({ B }, nil)
  test("no setBootAddress: plain reboot prompt, no B", ok and r == nil
    and saidAny(said, "Press any key to reboot") and not saidAny(said, "B:"))
end

-- The missing-files screen is where it is used, with the real setter.
do
  local block = src:match("if #missingFiles > 0 then(.-)\nend\n")
  test("the missing-files screen offers it, with computer.setBootAddress",
    block ~= nil and block:find("pcall(bootElsewhere", 1, true) ~= nil
    and block:find("computer.setBootAddress", 1, true) ~= nil)
  test("...skipping the disk that failed and the tmpfs",
    block ~= nil and block:find("skip[bootFS.address] = true", 1, true) ~= nil
    and block:find("computer.tmpAddress()", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
