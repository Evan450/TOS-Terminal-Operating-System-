-- ╔══════════════════════════════════════════════════════════╗
-- ║  Lint: no bare sandbox-unavailable globals in the tree    ║
-- ║                                                            ║
-- ║  OpenComputers' sandbox does NOT expose `collectgarbage`   ║
-- ║  as a global — a bare `collectgarbage("collect")` panics   ║
-- ║  the kernel at runtime ("attempt to call a nil value       ║
-- ║  (global 'collectgarbage')"). It must always go through a  ║
-- ║  `type(collectgarbage) == "function"` guard. This class of ║
-- ║  bug hides in rarely-hit paths (OOM recovery) that no unit ║
-- ║  test exercises, so we scan every shipped source file for  ║
-- ║  the DIRECT-call form `collectgarbage(`. The guarded forms ║
-- ║  only ever write `pcall(collectgarbage, …)` (no "(" after  ║
-- ║  the name) or `type(collectgarbage)`, so they don't match. ║
-- ║                                                            ║
-- ║  File list comes from the system manifest, so it covers    ║
-- ║  the whole tree and picks up new files automatically.      ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_sandbox_globals.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

print("=== sandbox-globals lint ===")
print()

-- Load the manifest (the single source of truth for shipped files).
local manifest
for _, p in ipairs({ "tos/system_manifest.lua", "TOS-Dev/tos/system_manifest.lua" }) do
  local chunk = loadfile(p)
  if chunk then manifest = chunk(); break end
end
if type(manifest) ~= "table" then
  print("  FAIL: could not load system_manifest.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end

-- Globals OC's sandbox does not provide as bare callables. Each must be
-- reached only through a guard; a literal `<name>(` is a direct call.
local BANNED = { "collectgarbage" }

-- A direct call `<g>(` is fine when a `type(<g>)` guard sits on the same
-- line or the preceding couple of lines (the established TOS idiom, e.g.
-- `if type(collectgarbage) == "function" then collectgarbage("collect") end`,
-- or that split across an if/end). It's a bug only when UNguarded.
local scanned, hits = 0, {}
for _, entry in ipairs(manifest) do
  local rel = (entry.path or ""):gsub("^/", "")   -- "/tos/x.lua" -> "tos/x.lua"
  if rel:match("%.lua$") then
    local fh = io.open(rel, "r")
    if fh then
      scanned = scanned + 1
      local prev = { "", "", "" }   -- sliding window: 2 prior lines + current
      local ln = 0
      for line in fh:lines() do
        ln = ln + 1
        prev[1], prev[2], prev[3] = prev[2], prev[3], line
        for _, g in ipairs(BANNED) do
          if line:find(g .. "(", 1, true) then
            local guarded = false
            for _, w in ipairs(prev) do
              if w:find("type(" .. g .. ")", 1, true) then guarded = true break end
            end
            if not guarded then
              hits[#hits + 1] = string.format("%s:%d: %s", rel, ln, (line:gsub("^%s+", "")))
            end
          end
        end
      end
      fh:close()
    end
  end
end

test("scanned a meaningful number of files", scanned >= 50)
if #hits > 0 then
  print("  Bare sandbox-global call(s) found — guard with")
  print("  `if type(<g>) == \"function\" then pcall(<g>, ...) end`:")
  for _, h in ipairs(hits) do print("    " .. h) end
end
test("no bare collectgarbage( in shipped source (" .. scanned .. " files)", #hits == 0)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
