-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: full-screen programs are handed the seat as their own  ║
-- ║  process (stage 1b), and everything else still runs inline    ║
-- ║                                                              ║
-- ║  A package command used to run INLINE — pcall(fn, ...) inside ║
-- ║  the shell's own coroutine — so the shell could not run again ║
-- ║  until the program exited. That is why calc/tetris held the   ║
-- ║  seat. Spawned as a seat-bound process they become            ║
-- ║  suspendable (Ctrl+B) and resumable (Ctrl+T).                 ║
-- ║                                                              ║
-- ║  The properties that matter here are the BOUNDARIES:          ║
-- ║   • only a package that DECLARES fullscreen is handed off —   ║
-- ║     everything else keeps the old inline path exactly;        ║
-- ║   • never inside a pipeline (no stdout to hand anyone);       ║
-- ║   • the shell must stop drawing, or it paints over the        ║
-- ║     program it just launched;                                 ║
-- ║   • the suspend key must be one nothing else binds, and must  ║
-- ║     be intercepted in the KERNEL loop — a program holding the ║
-- ║     seat's input can never receive the key that suspends it.  ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_program_handoff.lua  (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
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

print("=== full-screen program hand-off ===")
print()

-- ── The manifest discriminator is OPT-IN ──────────────────────────
do
  local pkgSrc = findUp("tos/kernel/pkg.lua")
  test("pkg.lua readable", pkgSrc ~= nil)
  if pkgSrc then
    test("pkg exposes the fullscreen flag",
      pkgSrc:find("function pkg.getCommandFullscreen", 1, true) ~= nil)
    -- A package that never heard of this must be unaffected.
    local body = pkgSrc:match("function pkg%.getCommandFullscreen.-\nend")
    test("...defaulting to FALSE, so untouched packages run inline",
      body ~= nil and body:find("return false", 1, true) ~= nil)
    test("...and it is an explicit boolean, not truthiness",
      body ~= nil and body:find("m.fullscreen == true", 1, true) ~= nil)
  end
end

-- ── Only the four programs declare it ─────────────────────────────
do
  local declared, undeclared = {}, {}
  local names = { "calc", "snake", "ttt", "tetris",
                  "mail", "mouse", "tape-authenticator", "blockfs" }
  for _, n in ipairs(names) do
    local m = findUp("TOS-Extras/modules/" .. n .. "/package.lua")
    if m then
      if m:find("fullscreen%s*=%s*true") then declared[#declared + 1] = n
      else undeclared[#undeclared + 1] = n end
    end
  end
  table.sort(declared)
  eq("exactly the four full-screen programs declare it",
    "calc,snake,tetris,ttt", table.concat(declared, ","))
  test("the text-mode packages do NOT (" .. table.concat(undeclared, ",") .. ")",
    #undeclared > 0)

  -- Background policies are deliberate, not copy-paste.
  local function policyOf(n)
    local m = findUp("TOS-Extras/modules/" .. n .. "/package.lua") or ""
    return m:match('background%s*=%s*"(%w+)"')
  end
  eq("tetris freezes when you leave (a falling piece must not fall on)",
    "freeze", policyOf("tetris"))
  eq("snake freezes too", "freeze", policyOf("snake"))
  eq("calc stays drowsy — nothing is lost by letting it settle",
    "drowsy", policyOf("calc"))
end

-- ── The executor's boundaries ─────────────────────────────────────
do
  local ex = findUp("tos/shell/panels/executor.lua")
  test("executor.lua readable", ex ~= nil)
  if ex then
    test("there is a hand-off path", ex:find("handOff", 1, true) ~= nil)
    test("it is gated on the fullscreen declaration",
      ex:find("fullscreen and allowHandOff", 1, true) ~= nil)

    -- Pipelines must NOT hand off: a program in a pipeline has no
    -- stdout to give anyone, and a redirect wants a buffer.
    local exec = ex:match("local function exec%(input%).-\n  end")
    test("the single-command path opts in",
      exec ~= nil and exec:find("execSingle(input, nil, true)", 1, true) ~= nil)
    local pipeCall = ex:match("local buf = execSingle%(seg%.cmd, prevOutput%)")
    test("the PIPELINE path does not (no third argument)", pipeCall ~= nil)

    -- If it can't spawn, it must still RUN the program, not refuse.
    test("an un-spawnable hand-off falls back to running inline",
      ex:find("run it inline exactly as before", 1, true) ~= nil)

    -- The seat must be handed back when the program exits.
    test("the program hands the seat back on exit",
      ex:find("proc.setForeground(shellPid", 1, true) ~= nil)
    test("...and tells the shell to repaint",
      ex:find("tos_focus", 1, true) ~= nil)
    test("...after dropping the stale dirty-cell shadow",
      ex:find("S.D.invalidate", 1, true) ~= nil)
    test("text the program printed is not swallowed",
      ex:find("S.outLines = helpers.expandBuf(S, printed)", 1, true) ~= nil)
  end
end

-- ── The shell must stop drawing while handed off ──────────────────
do
  local ev = findUp("tos/shell/panels/events.lua")
  test("events.lua readable", ev ~= nil)
  if ev then
    local apply = ev:match("local function applyDraw%(level%).-\n  end")
    test("applyDraw bails out when something else owns the screen",
      apply ~= nil and apply:find("S.suspendIdleDraw", 1, true) ~= nil)
    -- ...but tos_focus must still get through, or the shell never
    -- comes back.
    local lift = ev:match("if S%.suspendIdleDraw and %(sig ==.-\n    end")
    test("tos_focus lifts the suspension BEFORE the draw",
      lift ~= nil and lift:find("tos_focus", 1, true) ~= nil)
  end
end

-- ── The suspend hotkey ────────────────────────────────────────────
do
  local k = findUp("tos/kernel/init.lua")
  test("kernel/init.lua readable", k ~= nil)
  if k then
    -- Ctrl+B = char 2. It must be handled in the KERNEL loop: a
    -- full-screen program holds the seat's input as foreground, so a
    -- key it is meant to obey can never be a key it receives.
    -- Anchor on "== 2 then": a bare "== 2" also matches Ctrl+T's
    -- "== 20", which sits EARLIER in this file — the first version of
    -- this test was happily inspecting the monitor hotkey instead, and
    -- passing four assertions about the wrong block.
    test("Ctrl+B (char 2) is intercepted in the kernel loop",
      k:find('signal%[1%] == "key_down" and signal%[3%] == 2 then') ~= nil)
    local blk = k:match('signal%[1%] == "key_down" and signal%[3%] == 2 then.-\n      end')
    test("...it hands the seat back to the shell",
      blk ~= nil and blk:find("proc.setForeground(shellPid", 1, true) ~= nil)
    test("...with a repaint signal",
      blk ~= nil and blk:find("tos_focus", 1, true) ~= nil)
    -- At a bare shell prompt it must do nothing, or it could strand a
    -- seat with no foreground at all.
    test("Ctrl+B at the shell itself is a no-op",
      blk ~= nil and blk:find("fg ~= shellPid", 1, true) ~= nil)
    test("...and the key is swallowed so no program sees it",
      blk ~= nil and blk:find("signal = table.pack(nil)", 1, true) ~= nil)
  end
end

-- ── The suspend key must collide with nothing ─────────────────────
-- Ctrl+Z was the obvious pick and is already the editor's Undo. This
-- walks the real sources rather than trusting that memory.
do
  local bound = {}
  local function scan(rel)
    local s = findUp(rel); if not s then return end
    for n in s:gmatch("ch%s*==%s*(%d+)") do bound[tonumber(n)] = rel end
  end
  for _, f in ipairs({ "tos/shell/panels/events.lua",
                       "tos/shell/panels/commands/core.lua",
                       "tos/shell/init.lua",
                       "TOS-Extras/modules/calc/init.lua",
                       "TOS-Extras/modules/ttt/init.lua",
                       "TOS-Extras/modules/snake/init.lua" }) do
    scan(f)
  end
  test("Ctrl+B (2) is bound by nothing else", bound[2] == nil)
  test("...and the test can actually see bindings (Ctrl+Q found in "
    .. tostring(bound[17]) .. ")", bound[17] ~= nil)
  test("Ctrl+Z (26) IS taken, which is why it wasn't used ("
    .. tostring(bound[26]) .. ")", bound[26] ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
