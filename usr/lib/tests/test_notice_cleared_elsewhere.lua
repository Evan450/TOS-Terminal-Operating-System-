-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a notice answered on one seat closes on all  ║
-- ║                                                                ║
-- ║  kernel.notify's contract: every seat raises each notice, and  ║
-- ║  the first answer settles it for everyone. Each seat's shell   ║
-- ║  shows it in its own blocking dialog -- and nothing told the   ║
-- ║  others when it was settled. On the headless machine with two  ║
-- ║  seats, OK on seat 1 cleared seat 1; seat 2 still showed the   ║
-- ║  box, until someone answered it a second time (2026-10-10).    ║
-- ║                                                                ║
-- ║  dialogs.dialog now takes closeIf, polled each time the box    ║
-- ║  wakes; the notice raiser closes on "settled". Driven here     ║
-- ║  with the real dialog loop and the real kernel.notify.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_notice_cleared_elsewhere.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_notice_cleared_elsewhere.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadSrc(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local f = io.open(p, "rb")
    if f then local s = f:read("*a"); f:close(); return s end
  end
end

local clock = 100
package.loaded.computer = { uptime = function() return clock end }
local dialogs = assert(load(assert(loadSrc("tos/shell/panels/dialogs.lua")), "=dialogs"))()
local nf = assert(load(assert(loadSrc("tos/kernel/notify.lua")), "=notify"))()

local function newSeat()
  local D = {}
  function D.set() end
  function D.fill() end
  return { D = D, W = 80, H = 25, T = setmetatable({}, { __index = function() return 0 end }) }
end

-- A dialog in a coroutine, as a shell runs it. step(...) wakes it with a
-- signal (or with nothing, an idle tick); done/result say how it ended.
local function openBox(opts)
  local box = { done = false }
  local co = coroutine.create(function() return dialogs.dialog(newSeat(), opts) end)
  local function settle(ok, res)
    assert(ok, res)
    if coroutine.status(co) == "dead" then box.done, box.result = true, res end
  end
  settle(coroutine.resume(co))
  function box.step(...) if not box.done then settle(coroutine.resume(co, ...)) end end
  return box
end
local ENTER = { "key_down", "kb", 13, 28 }

print("=== closeIf ===")
print()

do
  local answered = false
  local box = openBox({ message = "hello", buttons = { "OK" },
                        closeIf = function() return answered end })
  box.step(); box.step()
  test("a box waits while nothing has happened", not box.done)
  answered = true
  box.step()
  test("...and closes on its next wake once closeIf says so", box.done)
  test("...with no answer of its own", box.result == nil)
end

do
  local answered = false
  local box = openBox({ message = "hello", buttons = { "OK" },
                        closeIf = function() return answered end })
  answered = true
  box.step(table.unpack(ENTER))
  test("a key arriving as it closes is not taken as an answer",
    box.done and box.result == nil)
end

do
  local box = openBox({ message = "hello", buttons = { "OK" } })
  box.step(); box.step()
  test("without closeIf a box still waits for its own answer", not box.done)
  box.step(table.unpack(ENTER))
  test("...and Enter answers it", box.done and box.result == 1)
end

print()
print("=== one notice, two seats ===")
print()

do
  nf._reset()
  local id = assert(nf.post({ message = "Both seats", from = "notify/root" }))
  -- What the notice raiser in shell/panels/events.lua does on each seat.
  local function raise()
    return openBox({ message = "Both seats", buttons = { "OK", "Later" },
                     closeIf = function() return nf.result(id) ~= nil end })
  end
  local seat1, seat2 = raise(), raise()
  seat1.step(); seat2.step()
  test("both seats show it", not seat1.done and not seat2.done)

  seat1.step("key_down", "kb", 0, 205)   -- Right: focus "Later"
  seat1.step(table.unpack(ENTER))
  test("seat 1 answers Later", seat1.done and seat1.result == 2)
  nf.settle(id, seat1.result)

  seat2.step()
  test("seat 2's box closes on its next wake", seat2.done)
  test("...without answering again", seat2.result == nil)
  test("the notice keeps seat 1's answer", nf.result(id) == 2)
  test("...and is gone from the queue", nf.depth() == 0)
end

do
  -- Expiry is not an answer: a box nobody has read yet stays up.
  nf._reset()
  local id = assert(nf.post({ message = "Unread", from = "notify/root", ttl = 10 }))
  local box = openBox({ message = "Unread", buttons = { "OK" },
                        closeIf = function() return nf.result(id) ~= nil end })
  clock = clock + 60
  nf.sweep()
  box.step()
  test("a notice that expires while its box is up does not close the box", not box.done)
end

print()
print("=== the shell wires it ===")
print()

local ev = loadSrc("tos/shell/panels/events.lua") or ""
test("the notice raiser closes its box when the notice is settled",
  ev:find("closeIf = function() return nf.result(notice.id) ~= nil end", 1, true) ~= nil)
test("...and does not settle it a second time",
  ev:find("if not (okD and pick == nil) then nf.settle(notice.id, okD and pick or 1) end", 1, true) ~= nil)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
