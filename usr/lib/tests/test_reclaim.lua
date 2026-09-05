-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: `reclaim` never deletes anything TOS owns   ║
-- ║                                                                ║
-- ║  reclaim removes the OpenOS install left behind when TOS is    ║
-- ║  installed over it. That is only safe while TOS installs       ║
-- ║  nothing into those trees -- which is true today (152 manifest ║
-- ║  entries, zero under /bin, /boot or /lib) and is exactly the   ║
-- ║  kind of fact that stops being true quietly.                   ║
-- ║                                                                ║
-- ║  So this crosses the reclaim list against the REAL manifest    ║
-- ║  rather than restating it. Add a TOS file under /bin and this  ║
-- ║  fails before anyone's disk does.                              ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_reclaim.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local function readAll(p)
  local h = io.open(p, "rb"); if not h then return nil end
  local s = h:read("*a"); h:close(); return s
end
local function findUp(rel)
  for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
    local s = readAll(pre .. rel); if s then return s end
  end
end

print("=== reclaim: blast radius ===")
print()

local adminSrc = findUp("tos/shell/panels/commands/admin.lua")
local manSrc   = findUp("tos/system_manifest.lua")
test("admin.lua readable", adminSrc ~= nil)
test("system_manifest.lua readable", manSrc ~= nil)

if adminSrc and manSrc then
  -- The trees reclaim will delete, read out of the command itself.
  local treesExpr = adminSrc:match("local TREES = (%b{})")
  local extraExpr = adminSrc:match("local EXTRA = (%b{})")
  test("reclaim declares its TREES list", treesExpr ~= nil)
  test("reclaim declares its EXTRA list", extraExpr ~= nil)

  local targets = {}
  for _, expr in ipairs({ treesExpr, extraExpr }) do
    if expr then
      for path in expr:gmatch('"([^"]+)"') do targets[#targets + 1] = path end
    end
  end
  test("parsed the deletion set (" .. #targets .. " entries)", #targets > 0)

  -- Every path TOS actually installs.
  local installed = {}
  for path in manSrc:gmatch('path%s*=%s*"([^"]+)"') do installed[#installed + 1] = path end
  test("parsed the manifest (" .. #installed .. " entries)", #installed > 100)

  -- THE check: no manifest path may fall inside a reclaim target.
  local collisions = {}
  for _, t in ipairs(targets) do
    for _, p in ipairs(installed) do
      if p == t or p:sub(1, #t + 1) == t .. "/" then
        collisions[#collisions + 1] = p .. " is inside " .. t
      end
    end
  end
  if #collisions > 0 then
    print("    reclaim would delete files TOS installs:")
    for i = 1, math.min(8, #collisions) do print("      " .. collisions[i]) end
  end
  test("reclaim deletes nothing the manifest installs", #collisions == 0)

  -- /init.lua is the one file TOS overwrites, and it must never be in
  -- the deletion set: removing it makes the machine unbootable.
  local deletesInit = false
  for _, t in ipairs(targets) do
    if t == "/init.lua" or t == "/" then deletesInit = true end
  end
  test("reclaim never targets /init.lua or /", not deletesInit)

  -- Nor anything TOS lives in.
  for _, danger in ipairs({ "/tos", "/etc", "/usr", "/var", "/home", "/root" }) do
    local hit = false
    for _, t in ipairs(targets) do if t == danger then hit = true end end
    test("reclaim does not target " .. danger, not hit)
  end

  -- Safety interlocks in the command itself.
  test("reclaim is a dry run unless --apply is given",
    adminSrc:find("--apply", 1, true) ~= nil and
    adminSrc:find("Dry run. Nothing was removed", 1, true) ~= nil)
  test("reclaim refuses when /init.lua is not TOS's",
    adminSrc:find("this machine boots OpenOS", 1, true) ~= nil)
  -- Line-ending agnostic: the source is CRLF on Windows checkouts, so a
  -- literal "\n" in the needle matches nothing and the test fails for a
  -- reason that has nothing to do with the gate.
  test("reclaim is root-gated",
    adminSrc:match("C%.reclaim = function%(args, o%)%s*if not rootOnly%(o%) then return end") ~= nil)
  test("protect is root-gated",
    adminSrc:match("C%.protect = function%(args, o%)%s*if not rootOnly%(o%) then return end") ~= nil)

  --! S.session does not exist on the seat state -- the token is S.st and
  --! helpers.sessionOf resolves it. Reaching for S.session made `protect`
  --! report "no session" to a perfectly good root seat, even after sudo.
  --! Four older call sites had the same mistake and worked only because
  --! the kernel fell back to the module-global current session, which is
  --! wrong the moment a machine has two seats.
  test("no command reaches for the non-existent S.session",
    adminSrc:find("S and S.session", 1, true) == nil)
  test("protect resolves the session like everything else does",
    adminSrc:find("local sess = helpers.sessionOf(S)", 1, true) ~= nil)
  test("reclaim warns that /bin leaving PATH changes behaviour",
    adminSrc:find("not a command", 1, true) ~= nil)
end

-- ══════════════════════════════════════════════════════════════════════
-- The installer and the command must agree on what OpenOS owns
-- ══════════════════════════════════════════════════════════════════════
--! install.lua offers the cleanup at install time; `reclaim` does it
--! later for a machine that said no then, or was never asked (the offer
--! is gated on a fully verified copy, so a partial install skips it).
--! Same job, two lists, two files -- and they had ALREADY diverged:
--! install.lua listed /bin and /lib and not /boot, so its "clean
--! install" left twelve OpenOS boot scripts behind.
do
  local installSrc = findUp("install.lua")
  local adminSrc2  = findUp("tos/shell/panels/commands/admin.lua")
  test("install.lua readable", installSrc ~= nil)
  if installSrc and adminSrc2 then
    local instExpr  = installSrc:match("local OPENOS_ONLY_TREES = (%b{})")
    local reclExpr  = adminSrc2:match("local TREES = (%b{})")
    test("install.lua declares OPENOS_ONLY_TREES", instExpr ~= nil)
    test("reclaim declares TREES", reclExpr ~= nil)
    if instExpr and reclExpr then
      local function parse(e)
        local t = {}
        for v in e:gmatch('"([^"]+)"') do t[#t + 1] = v end
        table.sort(t); return t
      end
      local a, b = parse(instExpr), parse(reclExpr)
      local same = #a == #b
      if same then
        for i = 1, #a do if a[i] ~= b[i] then same = false end end
      end
      if not same then
        print("    install.lua: " .. table.concat(a, " "))
        print("    reclaim   : " .. table.concat(b, " "))
      end
      test("the installer and reclaim delete exactly the same trees", same)
      test("/boot is included (it was missed)", (function()
        for _, v in ipairs(a) do if v == "/boot" then return true end end
        return false
      end)())
    end
  end
end

-- The command registry must know about both new commands, or they are
-- unreachable no matter how well they work.
do
  local regSrc = findUp("tos/shell/panels/commands.lua")
  test("commands.lua readable", regSrc ~= nil)
  if regSrc then
    test("reclaim is registered", regSrc:find("reclaim%s*=%s*{") ~= nil)
    test("protect is registered", regSrc:find("protect%s*=%s*{") ~= nil)
    test("reclaim is root-tier in the registry",
      regSrc:match("reclaim%s*=%s*{[^}]-tier%s*=%s*3") ~= nil)
    test("protect is root-tier in the registry",
      regSrc:match("protect%s*=%s*{[^}]-tier%s*=%s*3") ~= nil)
  end
end

-- ══════════════════════════════════════════════════════════════════════
-- Remote packages reach the search and the picker
-- ══════════════════════════════════════════════════════════════════════
--! `pkg search` looked only at disks, and the picker showed only what
--! was mounted -- so a configured repo was invisible in both, and the
--! operator had to know a package's name to fetch it.
do
  local function slurp(rel)
    for _, pre in ipairs({ "", "../", "../../", "../../../" }) do
      local h = io.open(pre .. rel, "rb")
      if h then local x = h:read("*a"); h:close(); return x end
    end
  end
  local admin  = slurp("tos/shell/panels/commands/admin.lua")
  local picker = slurp("tos/shell/pkgpicker.lua")
  test("admin.lua readable", admin ~= nil)
  test("pkgpicker.lua readable", picker ~= nil)

  if admin then
    test("pkg search asks for remote entries",
      admin:find("listAllAvailable({ includeRemote = true })", 1, true) ~= nil)
    test("...and names the repo in the source column",
      admin:find('"repo:" .. tostring(e.repo', 1, true) ~= nil)
    test("an empty result explains WHY it is empty",
      admin:find("none answered", 1, true) ~= nil)
    test("...including the no-repos-configured case",
      admin:find("No remote repos are configured", 1, true) ~= nil)
  end

  if picker then
    -- Both listing sites, or the picker and its detail pane disagree.
    local n = select(2, picker:gsub("includeRemote = true", ""))
    test("the picker asks for remote entries everywhere it lists (" .. n .. "/2)", n == 2)
    test("no bare listAllAvailable() call is left",
      picker:find("listAllAvailable()", 1, true) == nil)
    --! The install path MUST branch. installByName searches local roots
    --! and would report a remote package missing.
    test("the picker installs a remote entry with installRemote",
      picker:find("pkg.installRemote(e.name", 1, true) ~= nil)
    test("...and still uses installByName for local ones",
      picker:find("pkg.installByName(e.name", 1, true) ~= nil)
    test("the detail pane says a remote one downloads on install",
      picker:find("downloads on install", 1, true) ~= nil)
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
