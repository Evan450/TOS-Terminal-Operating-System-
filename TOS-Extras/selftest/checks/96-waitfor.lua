-- net.waitFor from kernel context, on the real machine.
--
-- The first round's note answered the question 92-term was written to
-- ask: coroutine.isyieldable() is TRUE in kernel context on OpenComputers,
-- because the kernel runs inside machine.lua's coroutine. net.waitFor
-- used exactly that test to choose between yielding to the scheduler and
-- pumping listeners with event.pull. So from kernel context -- verifyPeer
-- inside the netfs, rshd and transfer request handlers, all of which run
-- as modem_message listeners -- it yielded to the HOST, which resumed the
-- kernel with the next queued signal: the reply it was waiting for, now
-- off the queue and never dispatched. The wait could only time out.
--
-- This is that shape with nothing but the kernel's own parts: a listener
-- for a private signal, the signal pushed, and net.waitFor called from
-- here, which is kernel context (the battery is not a process). Fixed,
-- the listener sees the signal within one pull. Unfixed, the host eats it
-- and this waits out its 2 s and fails.
--
-- The probe is a custom signal the kernel pushes, so nothing else acts on
-- it, and its listener is removed afterwards.
return function(t)
  local okN, net = pcall(require, "kernel.net")
  if not okN or type(net) ~= "table" or type(net.waitFor) ~= "function" then
    return t.skip("net.waitFor", "kernel.net unavailable")
  end
  local okE, event = pcall(require, "kernel.event")
  if not okE or type(event) ~= "table" or type(event.on) ~= "function"
     or type(event.off) ~= "function" then
    return t.skip("net.waitFor", "kernel.event unavailable")
  end

  local NAME = "selftest_waitfor_probe"
  local got = false
  local id = event.on(NAME, function() got = true end, "selftest")
  computer.pushSignal(NAME)
  local t0 = computer.uptime()
  local okW, r = pcall(net.waitFor, function() return got end, 2)
  local dt = computer.uptime() - t0
  event.off(NAME, id)

  t.ok(string.format("net.waitFor in kernel context lets a listener see what it waits for"
    .. " (returned %s after %.1f s%s)", tostring(r), dt,
    okW and "" or (", raised: " .. tostring(r))),
    okW and r == true and got)
end
