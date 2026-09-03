-- ╔══════════════════════════════════════════════════════════╗
-- ║  Lint: writing the GPU raw means telling the caches        ║
-- ║                                                            ║
-- ║  TOS keeps two caches over one piece of glass:              ║
-- ║    * kernel.display's _lastFg/_lastBg — "the hardware is    ║
-- ║      already set to this colour, skip the call"             ║
-- ║    * the seat proxy's dirty-cell shadow — "this cell        ║
-- ║      already reads like that, skip the repaint"             ║
-- ║  Both are correct ONLY while every write goes through them. ║
-- ║                                                            ║
-- ║  A raw gpu.set / gpu.fill / gpu.setBackground moves the     ║
-- ║  hardware without moving either cache, and then the very    ║
-- ║  next repaint is skipped as redundant — so the row keeps    ║
-- ║  whatever the raw writer left. That is the status bar going ║
-- ║  black, and it has now been the cause three times:          ║
-- ║  display.scrollUp, compat's term.gpu() proxy, and a         ║
-- ║  restoreRow helper inside the self-test check written to    ║
-- ║  DETECT this class of bug.                                  ║
-- ║                                                            ║
-- ║  Raw writes are sometimes right — pkgpicker paints raw so   ║
-- ║  it still works in an emergency shell where kernel.display  ║
-- ║  is not up. The rule is not "never"; it is "say so".        ║
-- ║                                                            ║
-- ║  IF YOU ARE HERE CHASING A BLACK STATUS BAR AND THIS LINT   ║
-- ║  IS GREEN, the fifth cause was not a raw write at all: the  ║
-- ║  frame's off-screen page and the dirty-cell shadow describe ║
-- ║  DIFFERENT SURFACES, so a redraw inside a frame elides       ║
-- ║  exactly the cells the page is wrong about and the closing  ║
-- ║  blit paints that over the glass. See test_screen_frame.lua ║
-- ║  and screen.lua's beginFrame. This lint cannot see it —     ║
-- ║  every write involved goes properly through both caches.    ║
-- ║                                                            ║
-- ║  THE RULE. A file outside kernel/display.lua and            ║
-- ║  kernel/screen.lua that calls a mutating gpu method must    ║
-- ║  also either:                                               ║
-- ║    * invalidate  — call display.invalidateColors and/or     ║
-- ║      screen.invalidateAll somewhere in the file             ║
-- ║    * say why     — carry a `GPURAW-OK:` comment explaining  ║
-- ║      why no cache can be affected                           ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_gpuraw_lint.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_gpuraw_lint.lua"
local base = here:gsub("[^/\\]*$", "")

local function readFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local fh = io.open(p, "r")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end

-- The files that legitimately OWN the caches. They are the layer being
-- protected, not a caller of it.
local OWNERS = {
  ["tos/kernel/display.lua"] = true,
  ["tos/kernel/screen.lua"]  = true,
}

-- Listed explicitly rather than walked: a walk that silently stops
-- finding a renamed file reports success for coverage it lost. Every
-- file here either draws or hands out something that draws.
local FILES = {
  "tos/kernel/display.lua",
  "tos/kernel/screen.lua",
  "tos/kernel/init.lua",
  "tos/kernel/sandbox.lua",
  "tos/compat/term.lua",
  "tos/shell/init.lua",
  "tos/shell/cli.lua",
  "tos/shell/pkgpicker.lua",
  "tos/shell/panels/draw.lua",
  "tos/shell/panels/menus.lua",
  "tos/shell/panels/dialogs.lua",
  "tos/shell/panels/filebrowser.lua",
  "tos/shell/panels/monitorapp.lua",
  "tos/shell/panels/chatapp.lua",
  "tos/shell/panels/events.lua",
}

-- The gpu methods that move the glass or rebind it. Read-only queries
-- (get, getResolution, getBackground, …) cannot desynchronise anything.
local MUTATING = {
  "set", "fill", "copy", "bitblt",
  "setBackground", "setForeground", "setPaletteColor",
  "setResolution", "setViewport", "setDepth", "bind",
}

print("=== raw-GPU lint ===")
print()

local scanned, flagged = 0, 0
for _, rel in ipairs(FILES) do
  local src = readFile(rel)
  if not src then
    test("could read " .. rel, false)
  else
    -- Find raw writes: a `gpu.<method>(` or `gpu.<method>,` call on
    -- something *named* gpu. Covers both direct calls and the pcall
    -- form `pcall(gpu.setBackground, fg)` that pkgpicker uses.
    local hits = {}
    local lineNo = 0
    for ln in (src .. "\n"):gmatch("([^\n]*)\n") do
      lineNo = lineNo + 1
      for _, m in ipairs(MUTATING) do
        if ln:find("[%w_]*gpu%.%s*" .. m .. "%s*[(,]") then
          hits[#hits + 1] = lineNo .. ": " .. ln:gsub("^%s+", "")
          break
        end
      end
    end

    if #hits > 0 and not OWNERS[rel] then
      scanned = scanned + 1
      local declares = src:find("invalidateColors", 1, true) ~= nil
        or src:find("invalidateAll", 1, true) ~= nil
        or src:find("markGlassDirty", 1, true) ~= nil
      local excused = src:find("GPURAW%-OK") ~= nil
      local ok = declares or excused
      if not ok then flagged = flagged + 1 end
      test(rel .. " (" .. #hits .. " raw write(s)) invalidates or is excused"
        .. (ok and "" or "\n        first at " .. hits[1]), ok)
    end
  end
end

print()
test("the lint found files that write the GPU raw (" .. scanned .. ")", scanned > 0)

-- Self-check: the matcher has to recognise the shapes it exists to find,
-- and has to NOT fire on a read. A lint that cannot fail is decoration.
print()
print("-- the matcher --")
do
  local function isWrite(s)
    for _, m in ipairs(MUTATING) do
      if s:find("[%w_]*gpu%.%s*" .. m .. "%s*[(,]") then return true end
    end
    return false
  end
  test("a direct call is a write",  isWrite("gpu.setBackground(0x000000)"))
  test("a pcall form is a write",   isWrite("pcall(gpu.setForeground, fg)"))
  test("a renamed local counts",    isWrite("seatgpu.fill(1, 1, 80, 1, x)"))
  test("a read is not a write",     not isWrite("local w, h = gpu.getResolution()"))
  test("getBackground is not a write", not isWrite("local b = gpu.getBackground()"))
  -- display.* is this module's own safe API, not a raw write.
  test("display.fill is not flagged", not isWrite("display.fill(1, 1, W, 1)"))
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print()
  print("A flagged file writes the GPU directly and never says so, which")
  print("leaves kernel.display's colour cache and the seat proxy's shadow")
  print("asserting something that is no longer true. Hand the screen back:")
  print("  require(\"kernel.display\").invalidateColors()")
  print("  require(\"kernel.screen\").invalidateAll()")
  print("or add a `GPURAW-OK:` comment saying why no cache can be affected.")
  print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
