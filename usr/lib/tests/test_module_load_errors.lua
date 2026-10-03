-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a module that cannot load says why           ║
-- ║                                                                ║
-- ║  On the smallest machine TOS runs on (1024 KB, measured on the ║
-- ║  headless OpenComputers machine), every `pkg` command printed  ║
-- ║  "pkg module unavailable" and nothing else. The reason, thrown ║
-- ║  away by the command, was the boot loader's:                   ║
-- ║    Syntax error in 'kernel.pkg' (/tos/kernel/pkg.lua):         ║
-- ║    not enough memory                                           ║
-- ║  -- itself wrong, since a compile that runs out of memory is   ║
-- ║  not a syntax error. Eight other commands dropped the reason   ║
-- ║  the same way.                                                 ║
-- ║                                                                ║
-- ║  Checks the loader's wording (lifted from init.lua), the       ║
-- ║  shell's one-line reason, and the real `pkg` command when      ║
-- ║  kernel.pkg will not load.                                     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_module_load_errors.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local function readSrc(path)
  local h = assert(io.open(path, "rb"))
  local s = h:read("*a"); h:close()
  return (s:gsub("\r\n", "\n"))
end

print("=== a module that cannot load says why ===")

-- ── The boot loader's words ───────────────────────────────────────
print("-- the loader (init.lua) --")
do
  local src = readSrc("init.lua")
  local body = src:match("(local function loadErrorText.-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
  test("found loadErrorText in init.lua", body ~= nil)
  if body then
    local f = load(body .. "\nreturn loadErrorText", "=loadErrorText", "t", { tostring = tostring })()
    local oom = f("kernel.pkg", "/tos/kernel/pkg.lua", "not enough memory", "compile")
    test("a compile that ran out of memory says so", oom:find("Out of memory loading 'kernel.pkg'", 1, true) ~= nil, oom)
    test("...and is not called a syntax error", not oom:find("Syntax error", 1, true), oom)
    local syn = f("kernel.x", "/tos/kernel/x.lua", "[string]:3: unexpected symbol", "compile")
    test("a real syntax error is still a syntax error",
      syn == "Syntax error in 'kernel.x' (/tos/kernel/x.lua): [string]:3: unexpected symbol", syn)
    local rd = f("kernel.x", "/tos/kernel/x.lua", "disk unplugged", "read")
    test("a read failure is a read error", rd:find("^Read error in 'kernel.x'") ~= nil, rd)
  end
end

-- ── The shell's one line ──────────────────────────────────────────
print("-- the shell's reason --")
package.loaded["computer"] = {
  uptime = function() return 10 end,
  totalMemory = function() return 1024 * 1024 end,
  freeMemory = function() return 200 * 1024 end,
}
package.loaded["component"] = { list = function() return function() end end, proxy = function() end }
local okH, helpers = pcall(require, "shell.panels.helpers")
test("the shell helpers load", okH, helpers)
if okH then
  test("helpers.loadFailure exists", type(helpers.loadFailure) == "function")
  if type(helpers.loadFailure) == "function" then
    local a = helpers.loadFailure("pkg", "Out of memory loading 'kernel.pkg' (/tos/kernel/pkg.lua): too little free RAM to compile it")
    test("out of memory reads as out of memory", a == "pkg cannot load: not enough free memory on this machine.", a)
    local b = helpers.loadFailure("srm", "Syntax error in 'kernel.srm' (/tos/kernel/srm.lua): x")
    test("anything else keeps its reason", b == "srm module unavailable: Syntax error in 'kernel.srm' (/tos/kernel/srm.lua): x", b)
    test("no reason at all still makes a sentence",
      helpers.loadFailure("cron", nil) == "cron module unavailable: unknown error")
  end
end

-- ── The real `pkg` command, when kernel.pkg will not load ─────────
print("-- pkg on a machine it does not fit --")
do
  package.loaded["kernel.pkg"] = nil
  package.preload["kernel.pkg"] = function()
    error("Out of memory loading 'kernel.pkg' (/tos/kernel/pkg.lua): too little free RAM to compile it", 0)
  end
  local S = { T = setmetatable({}, { __index = function(_, k) return k end }), F = {} }
  local deps = {
    rp = function(p) return p end,
    rootOnly = function() return true end, adminOnly = function() return true end,
    promptInput = function() return nil end,
    confirm = function() return false end, confirmTyped = function() return false end,
  }
  local C = {}
  local okR, err = pcall(function() assert(loadfile("tos/shell/panels/commands/admin.lua"))()(C, S, deps) end)
  test("admin.lua registers", okR, err)
  if okR and C.pkg then
    local out = {}
    C.pkg({ "list" }, function(line) out[#out + 1] = tostring(line) end)
    local text = table.concat(out, "\n")
    test("pkg says it does not fit, not just 'unavailable'",
      text:find("pkg cannot load: not enough free memory", 1, true) ~= nil, text)
    test("...and how much memory it needs, against what this machine has",
      text:find("needs 1280 KB of RAM; this machine has 1024 KB", 1, true) ~= nil, text)
  end
  package.preload["kernel.pkg"] = nil
end

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
