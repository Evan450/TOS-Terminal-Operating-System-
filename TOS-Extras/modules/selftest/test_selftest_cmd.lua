-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: the `selftest` command and the kernel's battery agree    ║
-- ║                                                                ║
-- ║  The command and the runner are two sides of one contract: the  ║
-- ║  command WRITES /etc/selftest.on and the kernel READS it; the   ║
-- ║  command LISTS checks and the kernel RUNS them; the kernel      ║
-- ║  WRITES /var/selftest.log and the command READS it. Each side   ║
-- ║  testing itself against a fixture of its own is how the add-ons ║
-- ║  in this tree have broken before, so every check here drives    ║
-- ║  the REAL kernel/selftest.lua against the REAL command over one ║
-- ║  in-memory disk.                                                ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/selftest/test_selftest_cmd.lua   (from TOS-Extras)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "modules/selftest/test_selftest_cmd.lua"
local base = here:gsub("[^/\\]*$", "")
local function loadFirst(paths)
  for _, p in ipairs(paths) do
    local chunk = loadfile(p)
    if chunk then return chunk end
  end
  error("none of: " .. table.concat(paths, ", "))
end

-- ── One disk, with the securefs rule for the marker ────────────────
-- users.lua ROOT_WRITE_PATHS: only root writes /etc/selftest.on.
local files, dirs, mounts = {}, {}, {}
local asRoot = true
local function under(p, d) return p:sub(1, #d + 1) == d .. "/" end
local F = {}
function F.exists(p)
  if files[p] or dirs[p] then return true end
  for k in pairs(files) do if under(k, p) then return true end end
  return false
end
function F.isDirectory(p) return dirs[p] == true or (F.exists(p) and not files[p]) end
function F.readFile(p) return files[p] end
function F.writeFile(p, d)
  if p == "/etc/selftest.on" and not asRoot then
    return false, "Permission denied: /etc/selftest.on (root only)  [E-401 ERR_PERM_DENIED]"
  end
  files[p] = d; return true
end
function F.appendFile(p, d) files[p] = (files[p] or "") .. d; return true end
function F.remove(p)
  if p == "/etc/selftest.on" and not asRoot then return false, "Permission denied (root only)" end
  files[p] = nil; return true
end
function F.list(p)
  local out, seen = {}, {}
  for k in pairs(files) do
    if under(k, p) then
      local head = k:sub(#p + 2):match("^([^/]+)")
      if head and not seen[head] then seen[head] = true; out[#out + 1] = head end
    end
  end
  table.sort(out)
  return out
end
function F.mounts()
  local out = { { mountPoint = "/" } }
  for _, m in ipairs(mounts) do out[#out + 1] = { mountPoint = m } end
  return out
end

-- ── The real kernel runner ─────────────────────────────────────────
local selftest = loadFirst({ base .. "../../../TOS-Dev/tos/kernel/selftest.lua",
  "../TOS-Dev/tos/kernel/selftest.lua", "TOS-Dev/tos/kernel/selftest.lua" })()
local clock = 0
local comp = { uptime = function() clock = clock + 0.1; return clock end,
               freeMemory = function() return 123456 end }
selftest.init({ fs = F, computer = comp })

-- ── The real command ───────────────────────────────────────────────
-- The sandbox hands a package its globals; `fs` is the session-bound one.
local mod
do
  local src = io.open(base .. "usr/modules/selftest/init.lua", "rb")
    or assert(io.open("modules/selftest/usr/modules/selftest/init.lua", "rb"))
  local text = src:read("*a"); src:close()
  mod = assert(load(text, "=selftest", "t", setmetatable({ fs = F }, { __index = _G })))()
end
local function cmd(...)
  local out = {}
  mod.commands.selftest({ ... }, function(line) out[#out + 1] = tostring(line) end)
  return table.concat(out, "\n")
end

print("=== `selftest` and the kernel battery agree ===")
print()

print("-- arming: the command writes, the kernel reads --")
local said = cmd("arm", "shutdown", "only=9")
test("root can arm", said:find("Armed", 1, true) ~= nil)
test("the kernel sees the machine armed", selftest.enabled(F))
local cfg = selftest.readMarker(F)
test("...with the shutdown the command was given", cfg.shutdown == true)
test("...and its only= prefix", cfg.only == "9")
test("...and screen left off", cfg.screen == false)
test("status says ARMED", cmd("status"):find("ARMED", 1, true) ~= nil)

-- An option the command was NOT given is not written, so a test disk's
-- own marker still decides it (the machine wins per option only).
cmd("arm")
mounts = { "/mnt/disk" }
files["/mnt/disk/selftest.on"] = "shutdown=true\n"
test("an arm with no options leaves a test disk's shutdown in force",
  selftest.readMarker(F).shutdown == true)
files["/mnt/disk/selftest.on"] = nil
mounts = {}

said = cmd("arm", "--bogus")
test("an unknown option is refused", said:find("unknown option", 1, true) ~= nil)

asRoot = false
files["/etc/selftest.on"] = nil
said = cmd("arm")
test("a non-root session cannot arm", not selftest.enabled(F))
test("...and is told why", said:find("only root", 1, true) ~= nil)
asRoot = true

cmd("arm")
said = cmd("disarm")
test("disarm stops it", not selftest.enabled(F) and said:find("Disarmed", 1, true) ~= nil)

print()
print("-- listing: what the command shows is what the kernel runs --")
files["/usr/lib/selftest/10-boot.lua"] = "return function(t) t.ok('boots', true) end\n"
files["/usr/lib/selftest/20-fails.lua"] = "return function(t) t.ok('deliberately false', false) end\n"
files["/mnt/td/selftest/30-disk.lua"] = "return function(t) t.skip('needs a printer', 'none here') end\n"
files["/mnt/loose/40-loose.lua"] = "return function(t) t.note('loose at the root') end\n"
files["/mnt/loose/selftest.on"] = ""
files["/mnt/other/50-not-a-check.lua"] = "error('must never load')\n"
-- The Optional Utilities disk keeps this package in a folder named
-- selftest/, which is not a folder of checks. Both sides once took it for
-- one: `selftest list` showed package.lua, and an armed boot ran it.
files["/mnt/pack/selftest/package.lua"] = "return { name = 'selftest' }\n"
files["/mnt/pack/selftest/usr/lib/selftest/60-packed.lua"] = "error('installed by pkg, not run from the disk')\n"
mounts = { "/mnt/td", "/mnt/loose", "/mnt/other", "/mnt/pack" }
local kernelSees = selftest.discover(F)
local commandSees = mod.lib.discover(F)
local same = #kernelSees == #commandSees
for i, p in ipairs(kernelSees) do same = same and commandSees[i] and commandSees[i].path == p end
test("the command lists exactly the kernel's checks (" .. #kernelSees .. ")", same and #kernelSees == 4)
said = cmd("list")
test("a disk without selftest.on at its root lends no loose checks",
  said:find("50-not-a-check", 1, true) == nil)
test("the selftest package on a pack disk is not listed as a check",
  said:find("package.lua", 1, true) == nil)
test("each check names where it came from", said:find("disk /mnt/td", 1, true) ~= nil
  and said:find("installed", 1, true) ~= nil)

print()
print("-- the log: the kernel writes, the command reads --")
_G.computer = comp
selftest.run({ fs = F, computer = comp, cfg = { shutdown = false }, files = kernelSees })
said = cmd("status")
-- 10 passes, 20 fails, 30 skips, 40 only notes (no verdict at all).
test("status reports the run's outcome", said:find("pass=1 fail=1 skip=1", 1, true) ~= nil)
said = cmd("log")
test("log shows the failing check", said:find("deliberately false", 1, true) ~= nil)
test("...the skip and its reason", said:find("needs a printer", 1, true) ~= nil)
test("...and the note", said:find("loose at the root", 1, true) ~= nil)
test("...and not the passes", said:find("RUN", 1, true) == nil)
test("log all shows every line", cmd("log", "all"):find("RUN  10-boot", 1, true) ~= nil)

-- A run that never finished: the last RUN line names the culprit.
files["/var/selftest.log"] = "SELFTEST BEGIN at=1.0 files=2 version=1.5.0 build=abc variant=minified\n"
  .. "RUN  10-boot\nPASS 10-boot  pass=1 fail=0 skip=0\nRUN  20-wedge\n"
said = cmd("status")
test("a run with no END is reported as stalled", said:find("STALLED in 20-wedge", 1, true) ~= nil)
test("...naming the build it ran on", said:find("build=abc", 1, true) ~= nil)

print()
print("-- a developer's own check --")
local tmpl = mod.lib.TEMPLATE
local chunk = load(tmpl, "=template", "t", setmetatable({ computer = comp }, { __index = _G }))
test("the template compiles", chunk ~= nil)
local reported = {}
if chunk then
  chunk()({ ok = function(n, c) reported[#reported + 1] = { n, c } end })
end
test("...and reports through t.ok", #reported == 1 and reported[1][2] == true)
files["/usr/lib/selftest/99-mine.lua"] = tmpl
local st = selftest.run({ fs = F, computer = comp, cfg = { shutdown = false },
                          files = { "/usr/lib/selftest/99-mine.lua" } })
test("...and passes under the real runner", st.pass == 1 and st.fail == 0)
cmd("template", "/home/dev/99-mine.lua")
test("template <file> writes it out", files["/home/dev/99-mine.lua"] == tmpl)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
