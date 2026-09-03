-- ╔══════════════════════════════════════════════════════════╗
-- ║  Lint: a full-row write must cover the FULL row            ║
-- ║                                                            ║
-- ║  Found the hard way. renderFileListRow built its line from  ║
-- ║  the column widths and only TRUNCATED it — `line:sub(1,W)`  ║
-- ║  — never padding. The widths summed to W-1, so every row    ║
-- ║  left its last column unwritten. Invisible on an unselected ║
-- ║  row; on a SELECTED one that cell kept the highlight, and    ║
-- ║  arrow-key navigation (which repaints ONLY the old and new  ║
-- ║  rows) left a one-cell fragment behind on every move.        ║
-- ║                                                            ║
-- ║  It is a one-character difference in a line that looks      ║
-- ║  entirely reasonable, which is exactly the sort of thing    ║
-- ║  neither review nor play-testing reliably catches. So it    ║
-- ║  gets a lint instead of a memo.                             ║
-- ║                                                            ║
-- ║  THE RULE. A `D.set(1, <row>, ...)` that paints a row must  ║
-- ║  do one of:                                                 ║
-- ║    * pad to width   — `(s .. S.padW):sub(1, W)`             ║
-- ║    * clear first    — a `D.fill(1, <row>, W, 1, ...)` above ║
-- ║    * say why        — a `ROWPAINT-OK:` comment on the line  ║
-- ║      or just above, for a deliberate partial write          ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_rowpaint_lint.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_rowpaint_lint.lua"
local base = here:gsub("[^/\\]*$", "")

local function readFile(rel)
  for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
    local fh = io.open(p, "r")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end

-- The shell files that paint rows. Listed explicitly rather than walked,
-- so the lint cannot quietly stop covering a file that gets renamed.
local FILES = {
  "tos/shell/panels/draw.lua",
  "tos/shell/panels/menus.lua",
  "tos/shell/panels/dialogs.lua",
  "tos/shell/panels/filebrowser.lua",
  "tos/shell/panels/monitorapp.lua",
  "tos/shell/panels/events.lua",
  "tos/shell/panels/chatapp.lua",
  "tos/shell/cli.lua",
}

-- How far back to look for the D.fill that clears the row. Generous: the
-- fill is often at the top of a loop with the line built in between, and
-- a window that was too short reported menus.lua's widget picker as a
-- fault when its fill sits ten lines up.
local LOOKBACK = 14

print("=== row-paint lint ===")
print()

local scanned, flagged = 0, 0
for _, rel in ipairs(FILES) do
  local src = readFile(rel)
  if not src then
    test("could read " .. rel, false)
  else
    local lines = {}
    for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end

    for i, ln in ipairs(lines) do
      if ln:find("D%.set%(1,") then
        -- Take the statement plus a couple of continuation lines.
        local stmt = table.concat(lines, " ", i, math.min(#lines, i + 2))
        -- Only rows truncated to the screen width are candidates; a
        -- deliberate short write to a column (a glyph, a marker) is not
        -- claiming to paint a row at all.
        if stmt:find("sub%(1,%s*W%)") then
          scanned = scanned + 1
          local padded  = stmt:find("padW", 1, true) ~= nil
          local excused = stmt:find("ROWPAINT%-OK") ~= nil
            or (lines[i - 1] or ""):find("ROWPAINT%-OK") ~= nil
          local back = table.concat(lines, " ", math.max(1, i - LOOKBACK), i - 1)
          local cleared = back:find("D%.fill%(1,[^)]-W,%s*1") ~= nil
            or back:find("D%.fill%(1,%s*2,%s*W") ~= nil   -- whole content area

          local ok = padded or cleared or excused
          if not ok then flagged = flagged + 1 end
          test(rel .. ":" .. i .. " pads, clears first, or is excused"
            .. (ok and "" or "\n        " .. ln:gsub("^%s+", "")), ok)
        end
      end
    end
  end
end

print()
test("the lint actually scanned some row writes (" .. scanned .. ")", scanned > 0)

-- Self-check: the rule has to be able to FAIL, or it is decoration. This
-- is the exact shape of the bug it exists to catch.
print()
print("-- the matcher can fail --")
do
  local bad = 'D.set(1, y, line:sub(1, W), fg, bg)'
  local good = 'D.set(1, y, (line .. S.padW):sub(1, W), fg, bg)'
  test("an unpadded truncate is recognised as a candidate",
    bad:find("sub%(1,%s*W%)") ~= nil and bad:find("padW", 1, true) == nil)
  test("a padded write is recognised as safe",
    good:find("padW", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  print()
  print("A flagged line paints part of a row and leaves the rest as it was.")
  print("Fix by padding:  D.set(1, y, (line .. S.padW):sub(1, W), fg, bg)")
  print("or clear first:  D.fill(1, y, W, 1, \" \", fg, bg)")
  print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
