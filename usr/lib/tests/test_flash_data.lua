-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `flash --data` writes the chip's data field  ║
-- ║                                                                ║
-- ║  rc-pilot's robot program reads its shared secret from the     ║
-- ║  EEPROM's DATA field, and a chip with none ignores every frame ║
-- ║  without a sound. Nothing on TOS could write that field:       ║
-- ║  `flash` wrote only the code, `component eeprom setData` is    ║
-- ║  refused because `flash` is the one EEPROM write path, and the ║
-- ║  sandbox hides the EEPROM from every program, the root `lua`   ║
-- ║  prompt included. So following rc's own instructions burned a  ║
-- ║  chip that could never move a robot.                           ║
-- ║                                                                ║
-- ║  Drives the REAL `flash` from admin.lua against a fake EEPROM: ║
-- ║  the secret lands in the data field, is asked twice and never  ║
-- ║  shown, a mismatch or a cancel writes nothing at all, and a    ║
-- ║  BIOS is refused --data (the TOS BIOS keeps its boot address   ║
-- ║  and the manifest anchor there).                               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_flash_data.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

-- A component method on real OpenComputers is a callable table.
local callback = { __call = function(self, ...) return self.fn(...) end }
local function method(fn) return setmetatable({ fn = fn }, callback) end

local chip
local function newChip()
  chip = { code = "old code", data = "old data", sets = 0, dataSets = 0, failData = false }
  return {
    address = "e1", type = "eeprom",
    getSize = method(function() return 4096 end),
    getDataSize = method(function() return 256 end),
    getLabel = method(function() return "EEPROM" end),
    set = method(function(c) chip.code = c; chip.sets = chip.sets + 1 end),
    setData = method(function(d)
      if chip.failData then error("not enough space") end
      chip.data = d; chip.dataSets = chip.dataSets + 1
    end),
    getData = method(function() return chip.data end),
  }
end
local proxy = newChip()

package.loaded["computer"] = {
  uptime = function() return 10 end,
  getBootAddress = function() return "boot-disk-address" end,
  pullSignal = function() return nil end,
}
package.loaded["component"] = {
  list = function(kind)
    local done = false
    return function()
      if kind == "eeprom" and not done then done = true; return "e1", "eeprom" end
    end
  end,
  proxy = function() return proxy end,
}
package.loaded["shell.panels.helpers"] = {
  fmtSz = function(n) return tostring(n) end,
  expandBuf = function(_, buf) return buf end,
}
package.loaded["kernel.crypto"] = { hash = function() return string.rep("a", 64) end }

local ROBOT = "local m = component.list('modem')() return m"     -- not a BIOS
local BIOS = "local b = computer.getBootAddress() return b"      -- a BIOS
local files = { ["/robot.lua"] = ROBOT, ["/bios.lua"] = BIOS }

local answers, asked, typedWords, boxes = {}, {}, {}, {}
local S = {
  T = setmetatable({}, { __index = function(_, k) return k end }),
  F = {
    size = function(p) return files[p] and #files[p] or nil end,
    readFile = function(p)
      if files[p] then return files[p] end
      return nil, "no such file"
    end,
  },
}
local deps = {
  rp = function(p) return p end,
  rootOnly = function() return true end,
  adminOnly = function() return true end,
  promptInput = function(msg, maxLen, masked)
    asked[#asked + 1] = { msg = msg, maxLen = maxLen, masked = masked }
    return table.remove(answers, 1)
  end,
  -- The typed-word gates: answer with the word, as an operator would.
  confirmTyped = function(msg, word)
    boxes[#boxes + 1] = msg
    typedWords[#typedWords + 1] = word
    return true
  end,
  confirm = function() return true end,
  pullSignal = function() return nil end,
}

local C = {}
local register = assert(loadfile("tos/shell/panels/commands/admin.lua"))()
register(C, S, deps)
test("the real flash command is registered", type(C.flash) == "function")

local out
local function run(args, typed)
  proxy = newChip()
  answers, asked, typedWords, boxes = {}, {}, {}, {}
  for i, a in ipairs(typed or {}) do answers[i] = a end
  out = {}
  C.flash(args, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

local SECRET = "a-shared-secret-of-decent-length"

print("flash --data")

local text = run({ "/robot.lua", "--data" }, { SECRET, SECRET })
test("the code is written", chip.code == ROBOT, chip.code)
test("the data field holds what was typed", chip.data == SECRET, chip.data)
test("it was asked for twice", #asked == 2, #asked)
test("both times masked", asked[1] and asked[1].masked == true and asked[2] and asked[2].masked == true)
test("asked with the chip's data size as the limit", asked[1] and asked[1].maxLen == 256,
  asked[1] and asked[1].maxLen)
test("the secret never appears in the output", not text:find(SECRET, 1, true))
test("the output says the data field was set", text:find("Data field set", 1, true) ~= nil, text)
test("a non-BIOS chip is told to go back out of this computer",
  text:find("put this computer's own EEPROM back", 1, true) ~= nil)
test("the not-a-BIOS box says a robot chip is expected",
  boxes[1] ~= nil and boxes[1]:find("robot or a drone", 1, true) ~= nil)
test("the typed-word gates are still both there", typedWords[1] == "force" and typedWords[2] == "flash",
  table.concat(typedWords, ","))

run({ "--data", "/robot.lua" }, { SECRET, SECRET })
test("--data may come before the file", chip.code == ROBOT and chip.data == SECRET)

run({ "/robot.lua", "--data" }, { SECRET, SECRET .. "x" })
test("a mismatch writes neither the code nor the data",
  chip.sets == 0 and chip.dataSets == 0 and chip.code == "old code" and chip.data == "old data")

run({ "/robot.lua", "--data" }, {})        -- the prompt was cancelled
test("a cancelled prompt writes nothing", chip.sets == 0 and chip.dataSets == 0)

text = run({ "/bios.lua", "--data" }, { SECRET, SECRET })
test("a BIOS is refused --data", text:find("Refusing --data", 1, true) ~= nil, text)
test("...before anything is asked or written", #asked == 0 and chip.sets == 0 and chip.dataSets == 0)

run({ "/bios.lua" })
test("a BIOS without --data flashes as before", chip.code == BIOS and chip.data == "old data")

run({ "/robot.lua" })
test("without --data the data field is left alone", chip.code == ROBOT and chip.data == "old data"
  and chip.dataSets == 0)

proxy = nil
do
  proxy = newChip()
  chip.failData = true
  answers, asked, typedWords, boxes = { SECRET, SECRET }, {}, {}, {}
  out = {}
  -- run() would build a fresh chip; drive this one by hand.
  local failing = proxy
  local saved = package.loaded["component"].proxy
  package.loaded["component"].proxy = function() return failing end
  C.flash({ "/robot.lua", "--data" }, function(line) out[#out + 1] = tostring(line) end)
  package.loaded["component"].proxy = saved
  text = table.concat(out, "\n")
  test("a data write that fails is reported, not claimed",
    text:find("data field was NOT", 1, true) ~= nil and not text:find("Data field set", 1, true), text)
end

text = run({})
test("the usage names --data", text:find("--data", 1, true) ~= nil, text)

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
