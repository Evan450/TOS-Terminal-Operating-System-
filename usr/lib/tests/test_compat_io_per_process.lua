-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: io's default streams belong to one process      ║
-- ║                                                                    ║
-- ║  AUDIT 5 / external review H-05. compat/io.lua kept defaultInput   ║
-- ║  and defaultOutput as module upvalues. sandbox.lua's               ║
-- ║  isolatedModule() gives each sandbox its own module TABLE but      ║
-- ║  hands out the ORIGINAL closures, so the upvalues behind them      ║
-- ║  were one pair for the whole machine: a program calling            ║
-- ║  io.output(f) redirected EVERY other program's io.write into its   ║
-- ║  own file, io.input(f) fed them its bytes, and safeClose closed    ║
-- ║  whatever the previous holder had open.                            ║
-- ║                                                                    ║
-- ║  The isolation fix stopped monkey-patching; it never addressed     ║
-- ║  shared STATE, which is why this needed its own pin. Records are   ║
-- ║  keyed on the process TABLE, not the pid -- pids are reused after  ║
-- ║  a reap (#SEC M-11) and a weak key dies with the process.          ║
-- ║                                                                    ║
-- ║  Drives the REAL compat.io against a stand-in kernel.process so    ║
-- ║  "which process is running" can be moved between assertions.       ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_compat_io_per_process.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;" .. package.path

-- A switchable "current process", standing in for the scheduler.
local procA, procB = { pid = 1, name = "A" }, { pid = 2, name = "B" }
local current = nil
package.loaded["kernel.process"] = { current = function() return current end }

package.loaded["computer"] = { uptime = function() return 0 end,
                               pullSignal = function() end }
package.loaded["component"] = { list = function() return function() end end,
                                isAvailable = function() return false end }
local written = {}
package.loaded["kernel.display"] = {
  getSize = function() return 80, 25 end,
  set = function(_, _, s) written[#written + 1] = s end,
  fill = function() end, getGpu = function() return nil end,
}

local io2 = require("compat.io")

-- A stream we can tell apart from the terminal.
local function sink(tag)
  local s = { tag = tag, buf = {}, closed = false }
  function s:write(d) self.buf[#self.buf + 1] = d; return self end
  function s:close() self.closed = true end
  function s:read() return "line-from-" .. self.tag .. "\n" end
  function s:flush() return self end
  return s
end

print("=== io's default streams are per process ===")
print()

local aSink, bSink = sink("A"), sink("B")

current = procA
io2.output(aSink)
test("A's io.output() reports A's sink", io2.output() == aSink)

current = procB
test("B still sees the terminal, not A's sink", io2.output() ~= aSink)
io2.write("B's private output")
test("B's io.write did NOT land in A's sink", #aSink.buf == 0)

io2.output(bSink)
io2.write("B's private output")
test("B's io.write lands in B's own sink",
  #bSink.buf == 1 and bSink.buf[1] == "B's private output")

current = procA
test("A's redirection survived B's (still A's sink)", io2.output() == aSink)
io2.write("A's private output")
test("A's write went to A only",
  #aSink.buf == 1 and aSink.buf[1] == "A's private output" and #bSink.buf == 1)

-- Input side: the same separation, and no cross-feeding.
--! Never call io.read() while the default input is the TERMINAL one here.
--! That path is term.read(), which waits for a keystroke: inside a process
--! it yields to the scheduler (AUDIT 5, H-04, fixed), and outside one --
--! as here -- it waits on the machine, and this file's computer stub never
--! delivers a key. Both processes get an explicit stream first, which is
--! what we are testing anyway. (term.read itself: test_compat_term_seat.lua)
current = procA
io2.input(aSink)
current = procB
test("B's io.input is not A's stream", io2.input() ~= aSink)
io2.input(bSink)
test("B's io.read reads B's own stream, not A's",
  io2.read() == "line-from-B\n")
current = procA
test("A's input is still A's after B set its own", io2.input() == aSink)

-- safeClose must not reach across processes.
current = procA
io2.output(sink("A2"))
test("replacing A's output closed A's OWN previous stream", aSink.closed == true)
test("...and left B's stream open", bSink.closed == false)

-- No process context at all (kernel code, boot, the rest of this suite):
-- the old shared behaviour, so nothing that ran before this change breaks.
current = nil
local kSink = sink("kernel")
io2.output(kSink)
test("with no process, io.output still works", io2.output() == kSink)
current = nil
test("...and is stable across calls", io2.output() == kSink)

-- The record must not survive its process: a reused pid is a different
-- program (#SEC M-11), and the table key is what makes that safe.
local recycled = { pid = 1, name = "C (reused pid)" }
current = recycled
test("a NEW process reusing pid 1 does not inherit A's redirection",
  io2.output() ~= aSink)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
