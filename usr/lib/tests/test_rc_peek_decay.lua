-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: rc.lua's two narrow things                    ║
-- ║                                                                ║
-- ║  1. THE PEEK. rc reads a service's caps, restart flag and       ║
-- ║     restart budget from its SOURCE (it never runs a script at   ║
-- ║     root to ask). It matched raw text, so a comment that said   ║
-- ║     `restart = true` made a service restart, a comment that     ║
-- ║     sketched a caps table stood in for the real one, and only   ║
-- ║     QUOTED cap names counted: cluster-storaged's                ║
-- ║     `{ ["fs.read"] = true, ["fs.write"] = true, net = true }`   ║
-- ║     gave the daemon no network.                                 ║
-- ║  2. THE BUDGET. restartCount never decayed, so a service that   ║
-- ║     crashed once a week ran out of restarts eventually and      ║
-- ║     stayed down for good.                                       ║
-- ║                                                                ║
-- ║  Drives the REAL kernel/rc.lua (sandbox stubbed, as             ║
-- ║  test_rc_disabled does) with a clock the test controls.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rc_peek_decay.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local clock = 0
package.loaded["computer"] = { uptime = function() return clock end }
local sharedEnv = {}
package.loaded["kernel.sandbox"] = { build = function() return sharedEnv end }
package.loaded["kernel.users"]   = { kernelSession = function() return {} end }
_G._TOS = { bootSession = {} }

local function makeFs(files)
  return {
    exists = function(p)
      if files[p] ~= nil then return true end
      local prefix = p:sub(-1) == "/" and p or (p .. "/")
      for k in pairs(files) do if k:sub(1, #prefix) == prefix then return true end end
      return false
    end,
    makeDirectory = function() return true end,
    list = function(dir)
      local out, prefix = {}, dir:sub(-1) == "/" and dir or (dir .. "/")
      for p in pairs(files) do
        local rest = p:sub(#prefix + 1)
        if p:sub(1, #prefix) == prefix and not rest:find("/") then out[#out + 1] = rest end
      end
      table.sort(out)
      return out
    end,
    readFile  = function(p) return files[p] end,
    writeFile = function(p, d) files[p] = d; return true end,
    remove    = function(p) files[p] = nil; return true end,
  }
end

-- Boot rc over one rc.d script; return the listed entry for it.
local function boot(src)
  package.loaded["kernel.rc"] = nil
  local rc = require("kernel.rc")
  rc.init({ fs = makeFs({ ["/etc/rc.d/svc.lua"] = src }) })
  rc.runAll()
  for _, s in ipairs(rc.list()) do if s.name == "svc" then return s, rc end end
  return nil, rc
end
local BODY = "start = function() end, stop = function() end"

print("=== rc.lua: the peek and the restart budget ===")
print()

print("-- the peek reads caps in every literal form --")
local s = boot('return { caps = { ["fs.read"] = true, ["fs.write"] = true, net = true }, ' .. BODY .. ' }')
test("a bare `net = true` key is read (cluster-storaged's form)", s and s.caps and s.caps.net == true)
test("...beside the quoted keys", s and s.caps and s.caps["fs.read"] and s.caps["fs.write"])
s = boot('return { caps = { "fs.read", "load" }, ' .. BODY .. ' }')
test("an array of names still reads", s and s.caps and s.caps.load and s.caps["fs.read"])
s = boot('local x = 1\nreturn { caps = { "net", extra = x }, ' .. BODY .. ' }')
test("a table that is not a literal falls back to the quoted names",
  s and s.caps and s.caps.net and not s.caps.extra)
s = boot('return { caps = { "net", "legacy" }, ' .. BODY .. ' }')
test("a cap services may not have is still not granted", s and s.caps and s.caps.net
  and not s.caps.legacy)
s = boot('return { ' .. BODY .. ' }')
test("no caps means rc's defaults", s and s.caps and s.caps.net and s.caps.component
  and s.caps["fs.read"])

print()
print("-- the peek ignores comments --")
s = boot('-- old: caps = { "load" }\nreturn { caps = { "net" }, ' .. BODY .. ' }')
test("a commented-out caps table is not the one read", s and s.caps and s.caps.net
  and not s.caps.load)
s = boot('--[[ caps = { "load" } ]]\nreturn { caps = { "net" }, ' .. BODY .. ' }')
test("...nor one in a block comment", s and s.caps and s.caps.net and not s.caps.load)
s = boot('-- set restart = true to keep it up\nreturn { restart = false, ' .. BODY .. ' }')
test("a comment mentioning restart = true does not make it restart", s and s.restart == false)
s = boot('return { restart = true, ' .. BODY .. ' }')
test("a real restart = true still does", s and s.restart == true)
s = boot('return { caps = { "net" }, note = "-- not a comment", ' .. BODY .. ' }')
test("-- inside a string is not a comment", s and s.caps and s.caps.net)

print()
print("-- the restart budget comes back --")
local crashes = 0
local CRASHY = 'return { restart = true, maxRestart = 2, start = function() STARTS = (STARTS or 0) + 1 end, '
  .. 'stop = function() end }'
sharedEnv.STARTS = nil
clock = 0
local _, rc = boot(CRASHY)
local function crash() rc.stop("svc"); crashes = crashes + 1 end
local function entry() for _, e in ipairs(rc.list()) do if e.name == "svc" then return e end end end
test("booted once", sharedEnv.STARTS == 1)
-- A crash loop: three crashes within a minute.
clock = 10; crash(); rc.supervise()
clock = 20; crash(); rc.supervise()
test("two quick restarts are given", sharedEnv.STARTS == 3 and entry().running)
clock = 30; crash(); rc.supervise()
test("a third within the minute is refused (a loop)", sharedEnv.STARTS == 3
  and not entry().running)
-- The operator starts it; that resets the budget.
rc.start("svc")
test("an operator's start resets the count", entry().restartCount == 0 and entry().running)
-- Now it stays up a long while, and crashes once.
clock = 30 + 700
crash(); rc.supervise()
test("after a long healthy run a crash is restarted", entry().running)
clock = clock + 700; crash(); rc.supervise()
clock = clock + 700; crash(); rc.supervise()
test("...and so is the next, a long while later -- the budget decays",
  entry().running and entry().restartCount <= 1)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
