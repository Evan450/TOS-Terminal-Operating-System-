-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the installer checks the space first         ║
-- ║                                                                ║
-- ║  install.lua copied file after file until the drive filled,    ║
-- ║  then stopped halfway -- on a Tier 2 drive that already holds  ║
-- ║  OpenOS, the common case. The README warned about it; nothing  ║
-- ║  on screen did. It now adds up what the copy will take before   ║
-- ║  writing anything: each file, less what a re-install already    ║
-- ║  occupies at the same path, plus OpenComputers' 512-byte cost   ║
-- ║  for every new file and directory.                              ║
-- ║                                                                ║
-- ║  spaceNeeded is LIFTED from install.lua and run on a fake       ║
-- ║  filesystem; the real check is also run on the release.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_space.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local src = assert(io.open("install.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local body = src:match("(local function spaceNeeded.-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
local cost = tonumber(src:match("local FILE_COST = (%d+)"))
test("found spaceNeeded", body ~= nil)
test("found FILE_COST", cost == 512, cost)
if not body then print("*** TESTS FAILED ***"); os.exit(1) end
local spaceNeeded = assert(load("local FILE_COST = " .. cost .. "\n" .. body .. "\nreturn spaceNeeded",
  "=spaceNeeded", "t"))()

-- ── A fake source disk and target drive ─────────────────────────────
local function fsOf(files, dirs)
  local function size(p) return files[p] end
  local function exists(p) return files[p] ~= nil or (dirs and dirs[p]) or false end
  return size, exists
end

print("=== the installer checks the space first ===")
print()

do
  local files = { ["/src/tos/a.lua"] = 1000, ["/src/tos/b.lua"] = 3000 }
  local size, exists = fsOf(files)
  local m = { { path = "/tos/a.lua" }, { path = "/tos/b.lua" } }
  local need = spaceNeeded("/src", m, size, exists)
  -- 4000 bytes + 512 per file (2) + 512 for the new /tos directory
  test("a fresh drive needs the bytes plus a cost per new file and directory",
    need == 4000 + 2 * 512 + 512, need)
end

do
  -- A re-install: /tos/a.lua is already there at 900 bytes, /tos exists.
  local files = { ["/src/tos/a.lua"] = 1000, ["/src/tos/b.lua"] = 3000, ["/tos/a.lua"] = 900 }
  local size, exists = fsOf(files, { ["/tos"] = true })
  local m = { { path = "/tos/a.lua" }, { path = "/tos/b.lua" } }
  local need = spaceNeeded("/src", m, size, exists)
  test("a re-install counts only what the overwrite adds", need == 100 + 3000 + 512, need)
end

do
  local files = { ["/src/tos/a.lua"] = 100, ["/tos/a.lua"] = 5000 }
  local size, exists = fsOf(files, { ["/tos"] = true })
  local need = spaceNeeded("/src", { { path = "/tos/a.lua" } }, size, exists)
  test("a smaller replacement never counts as negative", need == 0, need)
end

do
  local files = { ["/src/a/b/c/d.lua"] = 10 }
  local size, exists = fsOf(files)
  local need = spaceNeeded("/src", { { path = "/a/b/c/d.lua" } }, size, exists)
  test("every new directory on the way down is counted once", need == 10 + 512 + 3 * 512, need)
end

-- ── The real release, from this tree ───────────────────────────────
do
  local okM, manifest = pcall(dofile, "tos/system_manifest.lua")
  test("the system manifest loads", okM and type(manifest) == "table", manifest)
  if okM and type(manifest) == "table" then
    local function size(p)
      local h = io.open(p:sub(2), "rb")      -- "/<src>" is the tree root here
      if not h then return nil end
      local n = h:seek("end"); h:close(); return n
    end
    local need = spaceNeeded("", manifest, size, function() return false end)
    -- The dev tree carries comments the release strips, so this is an upper
    -- bound on the release; it must still be far above the old "80 KB" line.
    test("the whole OS needs well over a megabyte", need > 1024 * 1024, need)
    print(string.format("     (dev tree: %d KB for %d files)", math.ceil(need / 1024), #manifest))
  end
end

-- ── The call site: refuse before copying, and stop ─────────────────
local site = src:match("local function copyFromDisk.-\nend\n")
test("copyFromDisk checks the space before creating anything",
  site and site:find("spaceNeeded", 1, true)
  and site:find("spaceNeeded", 1, true) < site:find("makeDirectory", 1, true))
test("...and says nothing was copied", site and site:find("Nothing was copied", 1, true) ~= nil)
test("the main flow ends the install on a space refusal",
  src:find('if copyWhy == "space" then print(); return end', 1, true) ~= nil)
test("the old 80 KB line is gone", not src:find("80KB minimum", 1, true))

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
