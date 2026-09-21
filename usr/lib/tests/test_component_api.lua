-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  Test: every component method we call is one the mod declares      ║
-- ║                                                                    ║
-- ║  THE FAILURE MODE THIS EXISTS FOR: a method name that does not      ║
-- ║  exist costs nothing off-box, because a mock proxy answers to       ║
-- ║  anything with anything. It fails only on hardware, and usually     ║
-- ║  inside a pcall, so it reads as a hardware quirk rather than a      ║
-- ║  typo. Three shipped in TOS before this check existed:              ║
-- ║                                                                    ║
-- ║    robot.durabilityLevel()  -- the callback is `durability`, so     ║
-- ║      every robot reported an empty tool slot, tool or not.          ║
-- ║    robot.use(side, sneaking) -- `sneaking` landed in the mod's      ║
-- ║      `face:number` slot, so use() raised bad-argument on every      ║
-- ║      call, whatever you passed.                                     ║
-- ║    tape.getSpeed() / getVolume() -- Computronics has the setters    ║
-- ║      and no getters, so three commands answered "?" forever.        ║
-- ║                                                                    ║
-- ║  The authority is the mods' own @Callback declarations, extracted   ║
-- ║  into Reference/oc-component-api/oc_api.lua by build/gen_oc_api.py. ║
-- ║  Vendored on purpose: a check that first clones 14 MB of Scala is   ║
-- ║  a check that skips on most runs, and a skipped check is one        ║
-- ║  nobody trusts.                                                     ║
-- ║                                                                    ║
-- ║  The fixtures below re-create all three bugs and assert this        ║
-- ║  checker catches each one, so the check cannot rot into something   ║
-- ║  that passes everything. It was also run against the PRE-FIX files  ║
-- ║  from git, where it names all five dead call sites by line:         ║
-- ║  peripheral/robot.lua:248 and tape/init.lua:1036, 1038, 1046, 1062. ║
-- ║                                                                    ║
-- ║  WHAT IT DOES NOT CATCH, so nobody trusts it further than it goes:  ║
-- ║  argument shapes are judged for LITERALS only. The real use() bug   ║
-- ║  passed `sneaking or false` -- an expression -- and no static check ║
-- ║  here can type that. The fixture covers the literal form; the       ║
-- ║  general case is what reading the signature is for.                 ║
-- ╚══════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_component_api.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

-- ── The vendored table ─────────────────────────────────────────────
local API, apiPath
for _, p in ipairs({ "../Reference/oc-component-api/oc_api.lua",
                     "Reference/oc-component-api/oc_api.lua",
                     "../../Reference/oc-component-api/oc_api.lua" }) do
  local f = io.open(p, "r")
  if f then f:close(); API = dofile(p); apiPath = p; break end
end
if type(API) ~= "table" or type(API.types) ~= "table" then
  --! Deliberately NOT a skip. The table is vendored in this repo, so a
  --! missing one means it was deleted or moved, and the honest answer to
  --! "can we still check this?" is no, loudly.
  print("  FAIL: Reference/oc-component-api/oc_api.lua not found or unreadable")
  print("Results: 0 passed, 1 failed")
  print("*** TESTS FAILED ***")
  os.exit(1)
end

local ALL = {}
for _, n in ipairs(API.all_names or {}) do ALL[n] = true end
for _, n in ipairs(API.libcomputer or {}) do ALL[n] = true end
for _, n in ipairs(API.libcomponent or {}) do ALL[n] = true end

--! Methods TOS adds to its OWN filesystem-shaped and display proxies
--! (netfs, jbod, blockfs, the per-seat display proxy). They are not mod
--! callbacks and are not meant to be; fs.lua calls proxy.unmount() when a
--! proxy offers it, which is how TBFS volumes learn they were unmounted.
local TOS_EXT = {
  unmount = true, mount = true, available = true, refresh = true,
  init = true, getTheme = true, isMonochrome = true, fit = true,
  getGpuDepth = true, getGpuTier = true, c = true, clear = true,
  isReady = true,
}

-- ── The checker ────────────────────────────────────────────────────
-- Returns an array of { line, var, method, why }.
local JUDGED = { typed = 0, loose = 0 }
local function check(src, label)
  local findings = {}
  local typed, loose = {}, {}      -- var -> component type / var -> true
  local lineNo = 0

  --! PROXY FACTORIES FIRST, and this is the difference between a check with
  --! teeth and one that only catches the bugs in its own fixtures. Real TOS
  --! code almost never binds a proxy inline: peripheral/robot.lua has
  --! `local p = getProxy()` and tape/init.lua has `local drive = findDrive()`,
  --! where the component.proxy() call is inside the helper. An earlier draft
  --! of this checker recognised only inline bindings, so it passed the very
  --! file whose getSpeed() bug prompted it.
  --!   So: any function whose body reaches component.proxy / hal.proxy /
  --! hal.get is a proxy factory, and a variable assigned from one holds a
  --! proxy. When that body names exactly one component type, the factory is
  --! TYPED and calls on its result get checked against that type; when it
  --! names several (or none), they fall back to the weaker
  --! "does this name exist on anything at all" check. The window is bounded
  --! rather than parsed -- 30 lines covers every factory in the tree, and a
  --! miss costs coverage, never a false accusation.
  local lines = {}
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  local factory = {}          -- function name -> component type or true
  for i, line in ipairs(lines) do
    local fname = line:match("^%s*local function ([%w_]+)%s*%(")
                  or line:match("^%s*function ([%w_]+)%s*%(")
                  or line:match("^%s*function [%w_]+%.([%w_]+)%s*%(")
    if fname then
      local body, types = "", {}
      for j = i, math.min(i + 30, #lines) do
        if j > i and (lines[j]:match("^%s*local function ")
                      or lines[j]:match("^function ")) then break end
        body = body .. lines[j] .. "\n"
      end
      if body:find("component%.proxy%s*%(") or body:find("hal%.proxy%s*%(")
         or body:find("hal%.get%s*%(") then
        for t in body:gmatch("component%.list%s*%(%s*[\"']([%a_]+)[\"']") do
          types[t] = true
        end
        for t in body:gmatch("[Pp]roxy%s*%(%s*[\"']([%a_]+)[\"']") do
          types[t] = true
        end
        local only, n = nil, 0
        for t in pairs(types) do only, n = t, n + 1 end
        factory[fname] = (n == 1 and API.types[only]) and only or true
      end
    end
  end
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    lineNo = lineNo + 1
    if not line:match("^%s*%-%-") then
      -- A binding that NAMES a component type.
      for var, t in line:gmatch(
          "([%a_][%w_]*)%s*=%s*[^\n]-[Pp]roxy%s*%(%s*[\"']([%a_]+)[\"']") do
        typed[var] = t; loose[var] = nil
      end
      for var, t in line:gmatch(
          "([%a_][%w_]*)%s*=%s*[^\n]-component%.list%s*%(%s*[\"']([%a_]+)[\"']") do
        typed[var] = t; loose[var] = nil
      end
      for var, t in line:gmatch("([%a_][%w_]*)%s*=%s*hal%.get%s*%(%s*[\"']([%a_]+)[\"']") do
        typed[var] = t; loose[var] = nil
      end
      for var, t in line:gmatch("([%a_][%w_]*)%s*=%s*component%.([%a_]+)%s*$") do
        if API.types[t] then typed[var] = t; loose[var] = nil end
      end
      -- A binding from a proxy whose type this file does not name.
      for var in line:gmatch("([%a_][%w_]*)%s*=%s*[%a_][%w_.]*[Pp]roxy%s*%(") do
        if not typed[var] then loose[var] = true end
      end
      -- A variable assigned from a proxy factory found above. `local a, b =
      -- findDrive()` binds the proxy to the FIRST name only; the second is
      -- the error string.
      for names, fn in line:gmatch("local%s+([%w_,%s]+)%s*=%s*([%w_]+)%s*%(") do
        local kind = factory[fn]
        if kind then
          local first = names:match("^%s*([%w_]+)")
          if first then
            if kind ~= true then typed[first] = kind; loose[first] = nil
            elseif not typed[first] then loose[first] = true end
          end
        end
      end
      for var, fn in line:gmatch("([%a_][%w_]*)%s*=%s*([%w_]+)%s*%(") do
        local kind = factory[fn]
        if kind then
          if kind ~= true then typed[var] = kind; loose[var] = nil
          elseif not typed[var] then loose[var] = true end
        end
      end
      -- Calls: var.method( ... )   and   pcall(var.method)
      local function judge(var, meth, argtext)
        local t = typed[var]
        if t then JUDGED.typed = JUDGED.typed + 1 else if loose[var] then JUDGED.loose = JUDGED.loose + 1 end end
        if t then
          local set = API.types[t]
          if set and not set[meth] and not TOS_EXT[meth] then
            findings[#findings + 1] = { line = lineNo, var = var, method = meth,
              why = ALL[meth]
                and ("not a '" .. t .. "' method (it exists on another component)")
                or  ("not a '" .. t .. "' method, and exists on no component") }
            return
          end
          -- Literal argument types against the declared signature.
          if set and set[meth] and argtext then
            local sig = set[meth]:match("^function%s*%((.*)$")
            if sig then
              local want = {}
              for param in sig:gmatch("[^,%)]+") do
                local ty = param:match(":%s*([%a]+)")
                if ty then want[#want + 1] = ty:lower() end
              end
              local i = 0
              for arg in (argtext .. ","):gmatch("%s*([^,]*),") do
                i = i + 1
                local got
                if arg == "true" or arg == "false" then got = "boolean"
                elseif arg:match("^%-?%d+%.?%d*$") or arg:match("^0[xX]%x+$") then
                  got = "number"
                elseif arg:match('^".*"$') or arg:match("^'.*'$") then got = "string"
                end
                local w = want[i]
                if got and w and w ~= got and not w:find("or") then
                  findings[#findings + 1] = { line = lineNo, var = var,
                    method = meth,
                    why = ("argument " .. i .. " is a " .. got ..
                           " where the mod declares " .. w) }
                end
              end
            end
          end
        elseif loose[var] then
          if not ALL[meth] and not TOS_EXT[meth] then
            findings[#findings + 1] = { line = lineNo, var = var, method = meth,
              why = "exists on no component in any of the three mods" }
          end
        end
      end
      for var, meth, args in line:gmatch("([%a_][%w_]*)%.([%w_]+)%s*(%b())") do
        judge(var, meth, args:sub(2, -2))
      end
      for var, meth in line:gmatch("pcall%s*%(%s*([%a_][%w_]*)%.([%w_]+)%s*[,%)]") do
        judge(var, meth, nil)
      end
    end
  end
  return findings
end

-- ── Fixtures: the checker must catch all three historical bugs ─────
print("── the checker has teeth ──")
do
  local function flags(src)
    local f = check(src, "fixture")
    return #f, f[1] and f[1].why or ""
  end

  local n, why = flags([[
local p = hal.proxy("robot")
local ok, result = pcall(p.durabilityLevel)
]])
  test("catches robot.durabilityLevel (bug 1)", n == 1)
  test("...and says it exists nowhere", why:find("exists on no component") ~= nil)

  n, why = flags([[
local drive = component.proxy(component.list("tape_drive")())
local ok, v = pcall(drive.getSpeed)
]])
  test("catches tape.getSpeed (bug 3)", n == 1)

  n, why = flags([[
local p = hal.proxy("robot")
return p.use(3, false)
]])
  test("catches a boolean in the mod's face:number slot (bug 2)", n >= 1)
  test("...and names the argument", why:find("argument 2 is a boolean") ~= nil)

  n = flags([[
local p = hal.proxy("robot")
p.move(3)
p.swing(3, 3, true)
local ok, d = pcall(p.durability)
local gpu = hal.proxy("gpu")
gpu.set(1, 1, "hello")
gpu.fill(1, 1, 10, 2, " ")
]])
  test("and stays quiet on correct calls", n == 0)
end

-- ── The real tree ──────────────────────────────────────────────────
print("── the shipped source ──")
local WINDOWS = package.config:sub(1, 1) == "\\"
local cwd
do
  local p = io.popen(WINDOWS and "cd" or "pwd")
  if p then cwd = (p:read("*l") or ""):gsub("\\", "/"):gsub("/+$", ""); p:close() end
end

--! Enumeration copied from test_manifest_completeness.lua, including its
--! reasoning: native Windows Lua routes io.popen through cmd.exe, where
--! `find` is a text search and there is no `ls`, so `dir /b /s` is the only
--! form that works whichever shell launched the suite. It prints absolute
--! paths, so the working directory is stripped back off.
local ROOTS = { "tos", "../TOS-Extras/modules" }
local ROOT_FILES = { "init.lua", "bios.lua", "bootstrap.lua", "install.lua" }
local files = {}
for _, r in ipairs(ROOTS) do
  local cmd = WINDOWS
    and ('dir /b /s "' .. r:gsub("/", "\\") .. '\\*.lua" 2>nul')
    or  ('find "' .. r .. '" -name "*.lua" 2>/dev/null')
  local fh = io.popen(cmd)
  if fh then
    for line in fh:lines() do
      line = line:gsub("\\", "/"):gsub("%s+$", "")
      if cwd and cwd ~= "" and line:sub(1, #cwd + 1) == cwd .. "/" then
        line = line:sub(#cwd + 2)
      end
      if line:match("%.lua$") and not line:match("No such")
         and not line:match("cannot find") then
        files[#files + 1] = line
      end
    end
    fh:close()
  end
end
for _, f in ipairs(ROOT_FILES) do
  local h = io.open(f, "r"); if h then h:close(); files[#files + 1] = f end
end

-- Sanity gate: an empty enumeration would pass everything vacuously.
local sawKernel = false
for _, p in ipairs(files) do
  if p:find("tos/kernel/init.lua", 1, true) then sawKernel = true end
end
test("file enumeration works (found kernel/init.lua)", sawKernel)
test("enumerated a plausible number of files", #files > 100)

local all, scanned = {}, 0
for _, path in ipairs(files) do
  if not path:find("/tests/", 1, true) and not path:match("test_[%w_]*%.lua$") then
    local fh = io.open(path, "r")
    if fh then
      local src = fh:read("*a"); fh:close()
      scanned = scanned + 1
      for _, f in ipairs(check(src, path)) do
        f.file = path
        all[#all + 1] = f
      end
    end
  end
end

test("scanned the tree (" .. scanned .. " files)", scanned > 100)
--! The second vacuity gate, and the one that matters more. Enumerating files
--! proves nothing if the checker resolves no proxies in them: an earlier draft
--! judged 18 calls and passed the tree happily, including the file whose bug
--! prompted it. With factory resolution it judges ~320. If this number
--! collapses, the check has stopped checking, whatever its verdict says.
print(("    judged %d calls against a named component type, %d by name only")
      :format(JUDGED.typed, JUDGED.loose))
test("the checker actually resolved proxies (not vacuously clean)",
     JUDGED.typed > 80 and (JUDGED.typed + JUDGED.loose) > 200)
test("no component call contradicts the mod source", #all == 0)
for _, f in ipairs(all) do
  print(("    %s:%d  %s.%s()  -- %s"):format(f.file, f.line, f.var, f.method, f.why))
end

print("")
print("Table: " .. apiPath .. "  (" ..
      (API.sources and API.sources.opencomputers or "?") .. ", generated " ..
      tostring(API.generated_on) .. ")")
print("Results: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
