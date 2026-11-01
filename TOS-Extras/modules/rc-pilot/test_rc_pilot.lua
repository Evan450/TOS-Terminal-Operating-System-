-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: rc-pilot, host and robot, end to end         ║
-- ║                                                                ║
-- ║  The add-on had no test, and it did not work:                  ║
-- ║   * the host put 16 RAW random bytes in the nonce of a Lua-    ║
-- ║     literal frame the EEPROM parses with nonce="([^"]+)" -- one ║
-- ║     frame in sixteen carried a 0x22, the robot saw a shorter    ║
-- ║     nonce, the MAC failed, and the keystroke vanished;          ║
-- ║   * on a modem_message the host threw the payload away and     ║
-- ║     blocked on a second pullSignal() with no timeout;          ║
-- ║   * it resolved prefixes through net.listPeers, which does not ║
-- ║     exist;                                                     ║
-- ║   * the EEPROM was 6.9 KB with comments stripped, on a 4 KB    ║
-- ║     chip that `flash` refuses to overfill.                      ║
-- ║                                                                ║
-- ║  So this drives the REAL host module against the REAL EEPROM   ║
-- ║  source: frames the host sends are fed to the robot loop, and  ║
-- ║  the robot's actual robot.* calls are what is asserted. The    ║
-- ║  MAC the host computes with kernel.crypto has to satisfy the   ║
-- ║  EEPROM's own SHA-256/HMAC, which is the equivalence that       ║
-- ║  matters.                                                      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/rc-pilot/test_rc_pilot.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

local here = (arg and arg[0]) or "modules/rc-pilot/test_rc_pilot.lua"
local base = here:gsub("[^/\\]*$", "")
local ROOT = base .. "../../"                      -- TOS-Extras root
-- The kernel sits in ONE of two places and both are correct (run_tests.py
-- says the same about TOS-Extras itself): in the local monorepo TOS-Extras
-- is a SIBLING of TOS-Dev, so the kernel is ../TOS-Dev/tos/; on the
-- published dev branch TOS-Extras is nested INSIDE the source tree, so it
-- is ../tos/. Listing only the first meant this test passed here and failed
-- from a clean clone -- caught by an external reviewer, who had the clone.
package.path = ROOT .. "../TOS-Dev/tos/?.lua;" .. ROOT .. "../tos/?.lua;"
  .. "../TOS-Dev/tos/?.lua;../tos/?.lua;TOS-Dev/tos/?.lua;tos/?.lua;" .. package.path

local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end
local function firstOf(paths) for _, p in ipairs(paths) do if readFile(p) then return p end end end
local HOST   = firstOf({ base .. "init.lua", "modules/rc-pilot/init.lua" })
local EEPROM = firstOf({ ROOT .. "robot/eeprom-rc-pilot.lua", "robot/eeprom-rc-pilot.lua" })
local STRIP  = firstOf({ ROOT .. "../TOS-Dev/build/strip.lua", "../TOS-Dev/build/strip.lua" })
if not (HOST and EEPROM) then print("FAIL: sources not found"); print("*** TESTS FAILED ***"); os.exit(1) end

local SECRET = "a-shared-secret-of-decent-length"

print("=== rc-pilot host <-> EEPROM Tests ===")
print()

-- ============================================================
-- Host side
-- ============================================================
local hostClock = 0                              -- the sandbox copies uptime once
local sent = {}                                  -- frames the host sent
local hostQueue = {}                             -- signals the host will pull
local hostOut = {}
local modemStub = {
  isWireless = function() return true end,
  open = function() return true end, close = function() return true end,
  send = function(to, port, data) sent[#sent + 1] = { to = to, port = port, data = data } end,
  broadcast = function(port, data) sent[#sent + 1] = { port = port, data = data, broadcast = true } end,
}
package.loaded["component"] = {
  list = function(t) local done = false
    return function() if not done and t == "modem" then done = true; return "modem-host" end end end,
  proxy = function() return modemStub end,
}
package.loaded["computer"] = {
  uptime = function() return hostClock end,
  freeMemory = function() return 200000 end, totalMemory = function() return 262144 end,
  address = function() return "host-computer" end,
  pullSignal = function()
    local s = table.remove(hostQueue, 1)
    if not s then error("host queue empty: the pilot did not exit on the quit key", 0) end
    return table.unpack(s, 1, s.n)
  end,
}
-- The host's crypto: what the package sandbox injects, backed by the real
-- kernel module so the MAC is the one a real seat would compute. Required
-- only now: kernel.crypto probes `component` for a data card at load.
local okC, kcrypto = pcall(require, "kernel.crypto")
if not okC then print("FAIL: kernel.crypto not loadable: " .. tostring(kcrypto)); print("*** TESTS FAILED ***"); os.exit(1) end
_G.crypto = { hmac = kcrypto.hmac, random = kcrypto.salt or kcrypto.random }
_G._TOS = { users = { currentSession = function() return nil end } }

local hostChunk = loadfile(HOST)
test("host module loads", hostChunk ~= nil)
local host = hostChunk()
local rc = host.commands.rc
local ROBOT = "0123456789abcdef-robot-address-0000"

local function key(char, code) return { n = 5, "key_down", "kb", char, code, "op" } end
local function o(s) hostOut[#hostOut + 1] = tostring(s) end

-- Usage and refusals.
rc({}, o)
test("no target: usage, nothing sent", #sent == 0 and hostOut[1]:find("Usage", 1, true))
hostOut = {}
rc({ "short" }, o)
test("a short target is refused with the full-address instruction",
  #sent == 0 and table.concat(hostOut, "\n"):find("full modem address", 1, true))
hostOut = {}
rc({ ROBOT }, o)                                 -- no secret anywhere
test("no secret: told how to give one, and not sent to a keychain rc cannot read",
  #sent == 0 and table.concat(hostOut, "\n"):find("--secret", 1, true) ~= nil
  and table.concat(hostOut, "\n"):find("keychain", 1, true) == nil)

-- A session: W, S, slot 3, ping, a pong reply, then the quit key.
hostOut = {}
hostQueue = {
  key(119, 17), key(115, 31), key(51, 4),
  key(112, 25),
  { n = 6, "modem_message", "modem-host", ROBOT, 7777, 3.0, '{magic="RCPILOT1",op="pong",arg=42}' },
  key(17, 16),                                   -- ^Q
}
rc({ ROBOT, "--secret", SECRET }, o)
eq("four frames sent (W, S, slot 3, ping)", 4, #sent)
test("--secret is called out as landing in history",
  table.concat(hostOut, "\n"):find("command history", 1, true) ~= nil)
test("the pong was read from the SAME signal and shown",
  table.concat(hostOut, "\n"):find("pong @ uptime=42", 1, true) ~= nil)
test("the pilot exited on the quit key", table.concat(hostOut, "\n"):find("exited", 1, true) ~= nil)
eq("frames go to the robot on port 7777", 7777, sent[1].port)
eq("...and to the right address", ROBOT, sent[1].to)
test("frame 1 is move:f", sent[1].data:find('op="move:f"', 1, true) ~= nil)
test("frame 3 carries the slot as arg", sent[3].data:find('op="select",arg=3,', 1, true) ~= nil)

-- The nonce must be safe inside a quoted Lua literal, EVERY time.
do
  local bad, n = 0, 0
  for _ = 1, 300 do
    sent = {}; hostOut = {}
    hostQueue = { key(119, 17), key(17, 16) }
    rc({ ROBOT, "--secret", SECRET }, o)
    local frame = sent[1].data
    -- The EEPROM's own extraction patterns, verbatim.
    local nonce = frame:match('nonce="([^"]+)"')
    local mac   = frame:match('mac="(%x+)"')
    local op    = frame:match('op="([^"]+)"')
    n = n + 1
    if not nonce or not nonce:match("^%x+$") or #nonce ~= 32 then bad = bad + 1 end
    if not mac or #mac ~= 64 or op ~= "move:f" then bad = bad + 1 end
  end
  eq("300 frames, every nonce 32 hex chars and every field extractable (bad count)", 0, bad)
end

-- ============================================================
-- Robot side: the real EEPROM, driven by the host's frames
-- ============================================================
local function makeRobot(secretOnChip)
  local R = { calls = {}, sentBack = {}, queue = {} }
  local function rec(name) return function(...) R.calls[#R.calls + 1] = name .. (select("#", ...) > 0 and ("(" .. tostring((...)) .. ")") or "") return true end end
  -- The real component: what machine.lua's proxy gives a bare EEPROM. The
  -- forward()/turnLeft() names are OpenOS's robot LIBRARY, which a chip does
  -- not have. This fake used to offer them, so these tests passed while every
  -- real robot sat still: the calls errored inside the chip's pcall.
  local SIDE = { [3] = "forward", [2] = "back", [1] = "up", [0] = "down" }
  local function front(name)
    return function(side)
      if side ~= 3 then error(name .. " is asked of the front") end
      R.calls[#R.calls + 1] = name
    end
  end
  local robot = {
    move = function(side) R.calls[#R.calls + 1] = SIDE[side] or error("bad side") end,
    turn = function(clockwise) R.calls[#R.calls + 1] = clockwise and "turnRight" or "turnLeft" end,
    use = front("use"), swing = front("swing"), place = front("place"), select = rec("select"),
  }
  local modem = { open = function() return true end,
    send = function(to, port, data) R.sentBack[#R.sentBack + 1] = { to = to, port = port, data = data } end }
  local eeprom = { getData = function() return secretOnChip end }
  local env = {
    component = {
      list = function(t) local done = false
        return function()
          if done then return nil end; done = true
          if t == "modem" then return "modem-robot" end
          if t == "robot" then return "robot-1" end
          if t == "eeprom" then return "eeprom-1" end
          return nil
        end end,
      proxy = function(a) return ({ ["modem-robot"] = modem, ["robot-1"] = robot, ["eeprom-1"] = eeprom })[a] end,
    },
    computer = {
      uptime = function() return 99 end, beep = function() end,
      pullSignal = function()
        local s = table.remove(R.queue, 1)
        if not s then error("halt", 0) end                 -- the loop never returns; this ends it
        return table.unpack(s, 1, s.n)
      end,
    },
    string = string, table = table, math = math, tonumber = tonumber, tostring = tostring,
    type = type, pcall = pcall, pairs = pairs, ipairs = ipairs, select = select, error = error,
  }
  function R.feed(frame, from)
    R.queue[#R.queue + 1] = { n = 6, "modem_message", "modem-robot", from or "host-1", 7777, 2.0, frame }
  end
  function R.run()
    local chunk, err = load(readFile(EEPROM), "=eeprom-rc-pilot", "t", env)
    if not chunk then return false, err end
    local ok, e = pcall(chunk)
    return (not ok and e == "halt"), e
  end
  return R
end

-- ============================================================
-- Through the real sandbox: rc hears its robot
-- ============================================================
-- Everything above hands the host a RAW pullSignal and a raw modem. A real
-- `rc` runs in the package sandbox, whose pullSignal drops every
-- modem_message except on a port the program opened through its gated proxy.
-- That is what made the pong invisible, so this goes through the real one:
-- the env's component and computer, and the rc-pilot package's capabilities.
do
  local okS, sandbox = pcall(require, "kernel.sandbox")
  test("the real sandbox loads", okS and type(sandbox) == "table"
    and type(sandbox.build) == "function")
  if okS and type(sandbox) == "table" and type(sandbox.build) == "function" then
    local hostComponent = package.loaded["component"]
    local hostComputer  = package.loaded["computer"]
    local realProxy, realList = hostComponent.proxy, hostComponent.list
    local card = { address = "modem-host", ports = {}, isWireless = modemStub.isWireless,
      send = modemStub.send, broadcast = modemStub.broadcast }
    function card.open(p) if card.ports[p] then return false end; card.ports[p] = true; return true end
    function card.isOpen(p) return card.ports[p] == true end
    function card.close(p) card.ports[p] = nil; return true end
    card.ports[42] = true                         -- the kernel is listening
    hostComponent.type = function() return "modem" end
    hostComponent.proxy = function() return card end
    hostComponent.list = function(t)
      local done = false
      return function()
        if not done and (not t or t == "modem") then done = true; return "modem-host", "modem" end
      end
    end

    local caps = {}
    for _, c in ipairs({ "fs.read", "fs.write", "component", "peripheral.modem", "crypto" }) do
      caps[c] = true
    end
    local env = sandbox.build({ caps = caps })
    -- Its require hands back the same views, as the sandbox's does.
    local chunk = loadfile(HOST, "t", setmetatable({
      component = env.component, computer = env.computer, crypto = _G.crypto,
      require = function(n)
        if n == "component" then return env.component end
        if n == "computer" then return env.computer end
        return require(n)
      end,
    }, { __index = _G }))
    local sandboxedRc = chunk().commands.rc

    sent = {}; hostOut = {}
    hostQueue = {
      key(112, 25),                                -- P: ping
      { n = 6, "modem_message", "modem-host", ROBOT, 42, 3.0, 'kernel traffic, op="pong",arg=1' },
      { n = 6, "modem_message", "modem-host", ROBOT, 7777, 3.0, '{magic="RCPILOT1",op="pong",arg=42}' },
      key(17, 16),                                 -- ^Q
    }
    rc = sandboxedRc
    rc({ ROBOT, "--secret", SECRET }, o)
    local text = table.concat(hostOut, "\n")
    test("through the real sandbox the ping still goes out", #sent == 1
      and sent[1].data:find('op="ping"', 1, true) ~= nil)
    test("...and the robot's pong reaches rc", text:find("pong @ uptime=42", 1, true) ~= nil, text)
    test("...and the kernel's port does not", text:find("pong @ uptime=1\n", 1, true) == nil
      and select(2, text:gsub("pong @", "")) == 1, text)
    test("the pilot still exits on the quit key", text:find("exited", 1, true) ~= nil)
    test("and it closed its port on the way out", card.ports[7777] == nil)
    test("leaving the kernel's alone", card.ports[42] == true)

    -- The address nobody could get: both real sides, frames passed by hand.
    local R = makeRobot(SECRET)
    local D = makeRobot(nil)
    sent = {}; hostOut = {}
    local answers = {}
    local realPull = hostComputer.pullSignal
    hostComputer.pullSignal = function()
      hostClock = hostClock + 0.5
      if #sent > 0 and not answers.asked then
        answers.asked = true
        R.feed(sent[1].data, "modem-host"); R.run()
        D.feed(sent[1].data, "modem-host"); D.run()
        for i, robot in ipairs({ R, D }) do
          local back = robot.sentBack[1]
          answers[#answers + 1] = { n = 6, "modem_message", "modem-host",
            "robot-address-" .. i, back and back.port, 2.0, back and back.data }
        end
        -- The same robot answering twice is one robot.
        answers[#answers + 1] = answers[1]
        answers[#answers + 1] = { n = 6, "modem_message", "modem-host", "x", 7777, 2.0, "noise" }
      end
      local s = table.remove(answers, 1)
      if s then return table.unpack(s, 1, s.n) end
      return nil
    end
    rc({ "scan" }, o)
    hostComputer.pullSignal = realPull
    text = table.concat(hostOut, "\n")
    test("`rc scan` asks everyone, unsigned", #sent == 1 and sent[1].broadcast
      and sent[1].data:find('op="who"', 1, true) ~= nil
      and sent[1].data:find("mac=", 1, true) == nil)
    test("a keyed robot is listed with its full address",
      text:find("robot-address-1  robot\n", 1, true) ~= nil
      or text:find("robot-address-1  robot$") ~= nil, text)
    test("a chip with no secret says so", text:find("robot-address-2  robot  (no secret", 1, true) ~= nil, text)
    test("each one once", select(2, text:gsub("robot%-address%-1", "")) == 1, text)
    test("the scan closes its port", card.ports[7777] == nil)

    card.ports[7777] = true                       -- someone else has it
    hostOut = {}
    hostComputer.pullSignal = function() hostClock = hostClock + 0.5; return nil end
    rc({ "scan" }, o)
    hostComputer.pullSignal = realPull
    text = table.concat(hostOut, "\n")
    test("a port someone else holds is said, not ignored",
      text:find("Cannot listen on port 7777", 1, true) ~= nil
      and text:find("in use", 1, true) ~= nil, text)
    card.ports[7777] = nil

    hostComponent.proxy, hostComponent.list, hostComponent.type = realProxy, realList, nil
    rc = host.commands.rc
  end
end

print()
print("-- the robot, running the real EEPROM --")
do
  -- Capture one frame of each kind from the host.
  sent = {}; hostOut = {}
  hostQueue = { key(119, 17), key(51, 4), key(112, 25), key(120, 45), key(17, 16) }
  rc({ ROBOT, "--secret", SECRET }, o)
  eq("host produced move, select, ping, swing", 4, #sent)

  local R = makeRobot(SECRET)
  R.feed(sent[1].data)                            -- move:f
  R.feed(sent[2].data)                            -- select 3
  R.feed(sent[3].data)                            -- ping
  R.feed(sent[4].data)                            -- swing
  R.feed(sent[1].data)                            -- REPLAY of move:f
  R.feed(sent[4].data:gsub('mac="%x', 'mac="0'))  -- tampered MAC
  R.feed(sent[4].data:gsub('RCPILOT1', 'RCPILOT9')) -- wrong magic
  R.feed('{magic="RCPILOT1",op="forward"}')       -- no mac at all
  R.feed(sent[1].data:gsub('op="move:f"', 'op="move:b"'))  -- op changed, MAC not
  local ran, why = R.run()
  test("the EEPROM ran its loop to the end of the queue (" .. tostring(why) .. ")", ran)
  -- Nine frames fed; three are legitimate robot calls (ping is answered,
  -- not dispatched), and the replay, the tampered MAC, the wrong magic,
  -- the MAC-less frame and the altered op must all do nothing.
  eq("exactly three calls reached the robot", 3, #R.calls)
  eq("1: forward", "forward", R.calls[1])
  eq("2: select(3)", "select(3)", R.calls[2])
  eq("3: swing", "swing", R.calls[3])
  eq("ping was answered with a pong to the sender", 1, #R.sentBack)
  test("the pong carries the uptime", R.sentBack[1].data:find('op="pong",arg=99', 1, true) ~= nil)
  eq("the pong went back to the host address", "host-1", R.sentBack[1].to)
end

-- Wait: the count above expects 3 robot calls (forward, select, swing) --
-- assert that precisely, since ping is not one.
do
  local R = makeRobot(SECRET)
  sent = {}; hostQueue = { key(119, 17), key(112, 25), key(17, 16) }
  rc({ ROBOT, "--secret", SECRET }, o)
  R.feed(sent[1].data); R.feed(sent[2].data)
  R.run()
  eq("move + ping = one robot call and one pong", 1, #R.calls)
  eq("...", 1, #R.sentBack)
end

-- No secret on the chip: fail closed.
do
  local R = makeRobot("")
  sent = {}; hostQueue = { key(119, 17), key(17, 16) }
  rc({ ROBOT, "--secret", SECRET }, o)
  R.feed(sent[1].data)
  R.run()
  eq("an unseeded robot moves for nobody", 0, #R.calls)
end

-- Wrong secret on the chip: fail closed.
do
  local R = makeRobot("some-other-secret-entirely")
  sent = {}; hostQueue = { key(119, 17), key(17, 16) }
  rc({ ROBOT, "--secret", SECRET }, o)
  R.feed(sent[1].data)
  R.run()
  eq("a robot with a different secret ignores the host", 0, #R.calls)
end

-- Every op the host can send is understood by the robot.
do
  local R = makeRobot(SECRET)
  sent = {}
  hostQueue = { key(115, 31), key(97, 30), key(100, 32), key(113, 16), key(101, 18),
                key(32, 57), key(0, 42), key(102, 33), key(98, 48), key(57, 10), key(17, 16) }
  rc({ ROBOT, "--secret", SECRET }, o)
  eq("ten frames for ten keys", 10, #sent)
  for _, f in ipairs(sent) do R.feed(f.data) end
  R.run()
  local seq = table.concat(R.calls, " ")
  eq("back / strafe-left / strafe-right / turns / up / down / use / place / select 9",
     "back turnLeft forward turnRight turnRight forward turnLeft turnLeft turnRight up down use place select(9)",
     seq)
end

-- ============================================================
-- Size: it has to fit the chip
-- ============================================================
print()
print("-- it fits the chip --")
do
  local src = readFile(EEPROM)
  -- What strip.lua --minify ships: no comments, no blank lines, no
  -- leading indentation. Run the real stripper when it is reachable;
  -- otherwise apply the same three rules here.
  local stripped
  if STRIP then
    local tmp = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"):gsub("\\", "/")
    local srcDir, dstDir = tmp .. "/rcp-src", tmp .. "/rcp-dst"
    os.execute('mkdir "' .. srcDir .. '" 2>nul >nul || mkdir -p "' .. srcDir .. '" 2>/dev/null')
    local f = io.open(srcDir .. "/eeprom-rc-pilot.lua", "wb"); if f then f:write(src); f:close() end
    os.execute('lua "' .. STRIP .. '" "' .. srcDir .. '" "' .. dstDir .. '" --minify >nul 2>&1 || lua "' .. STRIP .. '" "' .. srcDir .. '" "' .. dstDir .. '" --minify >/dev/null 2>&1')
    stripped = readFile(dstDir .. "/eeprom-rc-pilot.lua")
  end
  if not stripped then
    local out = {}
    for line in (src .. "\n"):gmatch("(.-)\n") do
      local l = line:gsub("^%s+", "")
      if l ~= "" and not l:match("^%-%-") then out[#out + 1] = l end
    end
    stripped = table.concat(out, "\n") .. "\n"
  end
  test(("stripped EEPROM fits a 4096-byte chip (%d bytes)"):format(#stripped), #stripped <= 4096)
  test("...and still parses", load(stripped, "=stripped", "t", {}) ~= nil)
end

_G.crypto, _G._TOS = nil, nil
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
