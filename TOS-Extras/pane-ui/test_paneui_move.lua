-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: PaneUI's Move reports what actually happened ║
-- ║                                                              ║
-- ║  moveSelected judged a rename by `pcall(fs.rename, ...)` --   ║
-- ║  true for a rename that ANSWERED false -- and then by whether ║
-- ║  the destination existed, which it already did whenever the   ║
-- ║  user had just confirmed an overwrite. So a rename a Windows  ║
-- ║  host refuses (it will not overwrite) said "Moved to: ..." and ║
-- ║  left both files exactly as they were.                        ║
-- ║                                                              ║
-- ║  PaneUI self-executes on load, so -- as the other PaneUI      ║
-- ║  tests do -- this reads the SOURCE, lifts moveSelected out,   ║
-- ║  and runs that one function over a stub filesystem.           ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua pane-ui/test_paneui_move.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local src
for _, p in ipairs({ "pane-ui/PaneUI.lua", "PaneUI.lua", "../pane-ui/PaneUI.lua" }) do
  local h = io.open(p, "rb")
  if h then src = h:read("*a"); h:close(); break end
end
-- A Windows checkout (core.autocrlf) has CRLF, and "\nend\n" never matches.
if src then src = src:gsub("\r\n", "\n") end
local body = src and src:match("\n(local function moveSelected%(%).-\nend)\n")
if not body then
  print("FAIL: could not find moveSelected in PaneUI.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- A disk whose rename, like OpenOS on a Windows host, will not overwrite.
local function scenario(files, dstAnswer)
  local store = {}
  for k, v in pairs(files) do store[k] = v end
  local fs = {
    exists = function(p) return store[p] ~= nil end,
    concat = function(a, b) return a .. "/" .. b end,
    rename = function(a, b)
      if store[b] ~= nil then return nil, "file exists" end
      store[b], store[a] = store[a], nil
      return true
    end,
    remove = function(p) store[p] = nil; return true end,
  }
  local State = { cwd = "/home" }
  local env = {
    pcall = pcall, tostring = tostring,
    fs = fs, State = State,
    selectedEntry = function() return { path = "/home/a.txt", name = "a.txt" } end,
    promptInput = function() return dstAnswer end,
    confirmDialog = function() return true end,
    copyFile = function(a, b) store[b] = store[a]; return true end,
    c = function(k) return k end,
    refresh = function() end,
  }
  local chunk = assert(load(body .. "\nreturn moveSelected", "=moveSelected", "t", env))
  chunk()()
  return store, State
end

print("=== PaneUI move ===")
print()
do
  local store, State = scenario({ ["/home/a.txt"] = "NEW", ["/home/b.txt"] = "OLD" }, "/home/b.txt")
  test("an overwrite the rename refused still lands", store["/home/b.txt"] == "NEW")
  test("...and the source is gone, as a move should leave it", store["/home/a.txt"] == nil)
  test("...and it says Moved", tostring(State.out):find("Moved", 1, true) ~= nil)
end
do
  local store, State = scenario({ ["/home/a.txt"] = "NEW" }, "/home/c.txt")
  test("a plain rename still moves", store["/home/c.txt"] == "NEW" and store["/home/a.txt"] == nil)
  test("...and says Moved", tostring(State.out):find("Moved", 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
