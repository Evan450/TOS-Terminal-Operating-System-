-- The other "am I in a process?" callers, from kernel context, on the real
-- machine.
--
-- 96-waitfor covers net.waitFor. Four more places asked
-- coroutine.isyieldable() the same question, and on OpenComputers that is
-- TRUE in kernel context (the kernel runs inside machine.lua's coroutine),
-- so from here each of them yielded to the HOST:
--   * an empty pipe read waited for a signal, dropped it, found the pipe
--     still empty, and waited again -- forever;
--   * proc.yield and proc.sleep were resumed by the next signal, which
--     nothing dispatched;
--   * the sandbox's safe pullSignal had no ceiling and ignored its timeout
--     until some signal came along.
-- They ask proc.inProcess() now. The battery is not a process, so this is
-- exactly the context that was wrong.
--
-- Each probe is bounded: pushed signals are private names, the sleep is
-- 0.3 s, and a pipe read that hung would stall the battery, which the RUN
-- line written before every check names. safePullSignal is only reachable
-- through a sandbox, so it is checked through the env sandbox.build makes.
return function(t)
  local okP, proc = pcall(require, "kernel.process")
  if not okP or type(proc) ~= "table" or type(proc.inProcess) ~= "function" then
    return t.skip("inprocess callers", "kernel.process unavailable")
  end
  t.note("kernel context: isyieldable=" .. tostring(coroutine.isyieldable and coroutine.isyieldable())
    .. " inProcess=" .. tostring(proc.inProcess()))

  -- 1. An empty pipe answers nil at once.
  local okPi, pipe = pcall(require, "kernel.pipe")
  if okPi and type(pipe) == "table" and type(pipe.create) == "function" then
    local r = pipe.create()
    local t0 = computer.uptime()
    local okR, v = pcall(r.read, r)
    t.ok(string.format("an empty pipe read in kernel context returns nil (%.2f s)",
      computer.uptime() - t0), okR and v == nil and computer.uptime() - t0 < 1)
  else
    t.skip("pipe read", "kernel.pipe unavailable")
  end

  -- 2. proc.sleep takes the time asked, and a signal arriving meanwhile
  --    reaches its listener rather than vanishing into the host.
  local okE, event = pcall(require, "kernel.event")
  if okE and type(event) == "table" and type(event.on) == "function" then
    local NAME = "selftest_inprocess_probe"
    local got = false
    local id = event.on(NAME, function() got = true end, "selftest")
    computer.pushSignal(NAME)
    local t0 = computer.uptime()
    local okS, err = pcall(proc.sleep, 0.3)
    local dt = computer.uptime() - t0
    event.off(NAME, id)
    t.ok(string.format("proc.sleep(0.3) in kernel context takes about 0.3 s (%.2f s%s)",
      dt, okS and "" or (", raised: " .. tostring(err))), okS and dt >= 0.25 and dt < 2)
    t.ok("...and the signal pushed during it reached its listener", got)
  else
    t.skip("proc.sleep", "kernel.event unavailable")
  end

  -- 3. proc.yield returns at once.
  local t0 = computer.uptime()
  local okY = pcall(proc.yield)
  t.ok(string.format("proc.yield in kernel context returns at once (%.2f s)",
    computer.uptime() - t0), okY and computer.uptime() - t0 < 1)

  -- 4. A sandbox's pullSignal honours its timeout with nothing queued.
  local okB, sandbox = pcall(require, "kernel.sandbox")
  if okB and type(sandbox) == "table" and type(sandbox.build) == "function" then
    -- The safe computer table comes with the component cap.
    local okEnv, env = pcall(sandbox.build, { caps = { component = true } })
    local pull = okEnv and type(env) == "table" and env.computer and env.computer.pullSignal
    if type(pull) == "function" then
      local t1 = computer.uptime()
      local okQ = pcall(pull, 0.2)
      local dq = computer.uptime() - t1
      t.ok(string.format("a sandbox pullSignal(0.2) in kernel context returns on time (%.2f s)", dq),
        okQ and dq < 2)
    else
      t.skip("sandbox pullSignal", "sandbox env has no computer.pullSignal")
    end
  else
    t.skip("sandbox pullSignal", "kernel.sandbox unavailable")
  end
end
