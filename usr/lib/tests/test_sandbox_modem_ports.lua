-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a sandboxed program and its modem ports      ║
-- ║                                                                ║
-- ║  A program holding peripheral.modem got the raw card. It could ║
-- ║  open any port, and close() with no argument shut every port   ║
-- ║  there was, the kernel's included, taking the machine off the  ║
-- ║  network. It still could not hear a thing: pullSignal dropped  ║
-- ║  every modem_message, so `rc` never heard its robot.           ║
-- ║                                                                ║
-- ║  Now it hears the ports IT opened and only those, the kernel's ║
-- ║  are refused at open(), and so are the daemons' unless the     ║
-- ║  caller is an rc.d service. Ports go with the env, so a        ║
-- ║  service's survive the shell that started it, and a program's  ║
-- ║  close when its process dies. Real sandbox, real scheduler,    ║
-- ║  and a fake card that records what the hardware was told.      ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_modem_ports.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_sandbox_modem_ports.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;TOS-Dev/tos/?.lua;"
  .. base .. "../../../tos/?/init.lua;tos/?/init.lua;TOS-Dev/tos/?/init.lua;" .. package.path

-- The card. `open` is the hardware: true when newly opened, false if it was.
local ADDR, OTHER = "modem-aaaa", "modem-bbbb"
local cards = {}
local function newCard(addr)
  local c = { address = addr, type = "modem", ports = {} }
  function c.open(p) if c.ports[p] then return false end; c.ports[p] = true; return true end
  function c.isOpen(p) return c.ports[p] == true end
  function c.close(p)
    if p == nil then
      local any = next(c.ports) ~= nil
      c.ports = {}
      return any
    end
    if not c.ports[p] then return false end
    c.ports[p] = nil
    return true
  end
  function c.send() return true end
  function c.isWireless() return true end
  cards[addr] = c
  return c
end
newCard(ADDR); newCard(OTHER)

local queue = {}
package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 4e6 end,
  totalMemory = function() return 8e6 end, beep = function() end,
  pushSignal = function() end, address = function() return "pc" end,
  pullSignal = function() return table.unpack(table.remove(queue, 1) or {}) end,
}
package.loaded["component"] = {
  list = function(filter)
    local names, i = { ADDR, OTHER }, 0
    return function()
      i = i + 1
      if names[i] and (not filter or filter == "modem") then return names[i], "modem" end
    end
  end,
  type = function(a) return cards[a] and "modem" or nil end,
  slot = function() return 0 end,
  proxy = function(a) return cards[a] end,
  get = function(a) return a end,
  isAvailable = function() return true end,
  getPrimary = function() return cards[ADDR] end,
  invoke = function(a, m, ...) return cards[a][m](...) end,
}

local kernelPorts = { [42] = true }
_G._TOS = { net = { kernelPorts = function() return kernelPorts end } }

local sandbox = require("kernel.sandbox")
local proc = require("kernel.process")

local CAPS = { component = true, ["peripheral.modem"] = true }
local function envFor(opts)
  opts = opts or {}
  opts.caps = CAPS
  return sandbox.build(opts)
end
local function reset()
  for _, c in pairs(cards) do c.ports = {} end
  cards[ADDR].ports[42] = true                 -- the kernel is listening
end

print("=== what a program may open ===")
print()
do
  reset()
  local env = envFor()
  local m = env.component.proxy(ADDR)
  test("an ordinary port opens", m.open(7777) == true and cards[ADDR].ports[7777])

  local ok, why = m.open(42)
  test("the kernel's port is refused", ok == nil and tostring(why):find("kernel", 1, true) ~= nil, why)
  test("a fraction does not get past that", m.open(42.5) == nil)
  test("nor does a string", m.open("42") == nil and cards[ADDR].ports["42"] == nil)

  kernelPorts = { [5000] = true }
  test("the kernel's port is asked for, not assumed",
    m.open(5000) == nil and m.open(43) == true)
  kernelPorts = { [42] = true }

  for _, p in ipairs({ 2001, 2004, 2100, 2101, 2200 }) do
    ok, why = m.open(p)
    test(p .. " is a daemon's, even with nothing listening", ok == nil
      and not cards[ADDR].ports[p] and tostring(why):find("belongs to", 1, true) ~= nil, why)
  end

  reset()
  local other = envFor().component.proxy(ADDR)
  m = envFor().component.proxy(ADDR)
  test("one program opens a port", m.open(7777) == true)
  ok, why = other.open(7777)
  test("a second is told it is taken", ok == nil and tostring(why):find("in use", 1, true) ~= nil, why)
  test("and cannot shut it", other.close(7777) == nil and cards[ADDR].ports[7777])
  test("the owner asking again is just `already open`", m.open(7777) == false)
end

print()
print("=== what a program may close ===")
print()
do
  reset()
  local m = envFor().component.proxy(ADDR)
  m.open(7777); m.open(7778)
  test("closing the kernel's port is refused", m.close(42) == nil and cards[ADDR].ports[42])
  test("close() shuts mine", m.close() == true
    and not cards[ADDR].ports[7777] and not cards[ADDR].ports[7778])
  test("and leaves the kernel on the network", cards[ADDR].ports[42] == true)
end

print()
print("=== no way round the proxy ===")
print()
do
  reset()
  local env = envFor()
  local c = env.component
  local ok, why = c.invoke(ADDR, "open", 42)
  test("invoke(open) meets the same rule", ok == nil, why)
  test("invoke(close) with no port leaves the kernel's",
    (c.invoke(ADDR, "close") or true) and cards[ADDR].ports[42])
  test("getPrimary hands out the gate", c.getPrimary("modem").open(42) == nil)
  test("component.modem does too", c.modem.open(42) == nil)
  c.invoke(ADDR, "open", 7777)
  test("and a port opened by invoke is mine", c.proxy(ADDR).close(7777) == true)
end

print()
print("=== who hears what ===")
print()
do
  reset()
  local pull = sandbox._safePullSignal
  queue = { { "modem_message", ADDR, "robot", 7777, 5, "nobody opened this" } }
  test("nothing open, nothing heard", pull(0.1) == nil)

  local m = envFor().component.proxy(ADDR)
  m.open(7777)
  queue = { { "modem_message", ADDR, "robot", 7777, 5, "pong" } }
  local sig = table.pack(pull(0.1))
  test("a port I opened is heard, payload and all", sig[1] == "modem_message" and sig[6] == "pong")
  queue = { { "modem_message", ADDR, "peer", 42, 5, "kernel traffic" },
            { "modem_message", ADDR, "peer", 2101, 5, "cluster traffic" },
            { "modem_message", OTHER, "peer", 7777, 5, "another card" },
            { "key_down", "kb", 65, 30 } }
  test("the kernel's, a daemon's and another card's are not",
    pull(0.1) == "key_down")
  m.close(7777)
  queue = { { "modem_message", ADDR, "robot", 7777, 5, "too late" } }
  test("closed again, gone again", pull(0.1) == nil)
end

print()
print("=== a port follows its owner ===")
print()
do
  reset()
  local started, heard = false, nil
  local env = envFor()
  local pid = proc.spawn("rc", function()
    env.component.proxy(ADDR).open(7777)
    started = true
    heard = table.pack(sandbox._safePullSignal(5))
  end)
  proc.tick(nil)
  test("the program opened its port", started and cards[ADDR].ports[7777], pid)
  local p = proc.get(pid)
  test("and its process knows it", p and p.modemPorts ~= nil)

  proc.tick({ "modem_message", ADDR, "peer", 42, 5, "kernel traffic", n = 6 })
  test("the scheduler's copy of a kernel packet is dropped", heard == nil)
  proc.tick({ "modem_message", ADDR, "robot", 7777, 5, "pong", n = 6 })
  test("its own arrives through the real scheduler", heard and heard[6] == "pong",
    heard and heard[1])

  proc.tick(nil)
  test("it died, and the card was told", not cards[ADDR].ports[7777])
  test("the kernel's port is untouched", cards[ADDR].ports[42] == true)

  reset()
  local svc = envFor({ service = true })
  test("a service may open a daemon's port", svc.component.proxy(ADDR).open(2101) == true)
  test("but still not the kernel's", svc.component.proxy(ADDR).open(42) == nil)
  local ran = false
  local spid = proc.spawn("shell", function()
    svc.component.proxy(ADDR).open(2100)
    ran = true
  end)
  proc.tick(nil); proc.tick(nil)
  test("`service start` ran in a process that has since gone",
    ran and (proc.get(spid) == nil or proc.get(spid).state ~= nil))
  test("and the service keeps its port", cards[ADDR].ports[2100] == true)
  test("its stop(), from anywhere, can still close it",
    svc.component.proxy(ADDR).close(2100) == true)
end

_G._TOS = nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
