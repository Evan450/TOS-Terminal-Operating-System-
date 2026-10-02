-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: installing TOS keeps the /init.lua it replaces ║
-- ║                                                                ║
-- ║  install.lua replaced /init.lua and nothing put the old one     ║
-- ║  back, so a shared disk that had OpenOS on it did not become    ║
-- ║  bootable again by deleting /tos. The displaced loader is kept  ║
-- ║  as /init.lua.pre-tos -- once, never over TOS's own loader, and ║
-- ║  removed again by a clean install that takes OpenOS's /lib.     ║
-- ║                                                                ║
-- ║  The installer's functions are LIFTED from install.lua and run  ║
-- ║  against a fake disk: the file is a whole interactive program,  ║
-- ║  and these are the parts with a decision in them.               ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_preinit.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local src = assert(io.open("install.lua", "rb")):read("*a"):gsub("\r\n", "\n")
local from = src:find("local OPENOS_ONLY_TREES", 1, true)
local to = select(2, src:find("\n  return removed\nend\n", from, true))
test("found the installer's helpers", from ~= nil and to ~= nil)

local OPENOS_INIT = "local loadfile = load([=[return function(file) ...]=])  -- OpenOS\n"

local function disk(files)
  local F = { files = files }
  local function under(p, d) return p:sub(1, #d + 1) == d .. "/" end
  function F.exists(p)
    if files[p] then return true end
    for k in pairs(files) do if under(k, p) then return true end end
    return false
  end
  function F.remove(p)
    files[p] = nil
    for k in pairs(files) do if under(k, p) then files[k] = nil end end
    return true
  end
  local io_ = {
    open = function(p, mode)
      if mode == "r" then
        local data = files[p]
        if not data then return nil end
        return { read = function() return data end, close = function() end }
      end
      local buf = {}
      return { write = function(_, s) buf[#buf + 1] = s end,
               close = function() files[p] = table.concat(buf) end }
    end,
  }
  return F, io_
end

local function load_(files)
  local F, io_ = disk(files)
  local env = { fs = F, io = io_, pcall = pcall, ipairs = ipairs }
  local chunk = assert(load(src:sub(from, to) .. "\nreturn preserveForeignInit, cleanOpenOsLeftovers, PRE_TOS",
    "=install-helpers", "t", env))
  return files, chunk()
end

print("=== installing TOS keeps the /init.lua it replaces ===")
print()

do
  local files, keep, _, PRE = load_({ ["/init.lua"] = OPENOS_INIT, ["/lib/core/boot.lua"] = "x" })
  test("OpenOS's loader is kept", keep() == true and files[PRE] == OPENOS_INIT)
  test("...under /init.lua.pre-tos", PRE == "/init.lua.pre-tos")
  files["/init.lua"] = "_G._TOS = { version = '1.5.0' }"   -- the install wrote TOS's
  test("a second run does not touch the backup", keep() == false and files[PRE] == OPENOS_INIT)
end

do
  local files, keep, _, PRE = load_({ ["/init.lua"] = "-- TOS\n_G._TOS = {}\n" })
  test("TOS's own loader is not kept as a 'previous system'", keep() == false and files[PRE] == nil)
end

do
  local files, keep, _, PRE = load_({})
  test("no /init.lua: nothing to keep", keep() == false and files[PRE] == nil)
end

do
  local files, keep, clean, PRE = load_({ ["/init.lua"] = OPENOS_INIT,
    ["/lib/core/boot.lua"] = "x", ["/bin/sh.lua"] = "x" })
  keep()
  local removed = clean()
  test("a clean install removes OpenOS's trees", files["/lib/core/boot.lua"] == nil)
  test("...and the backup, which could boot nothing now", files[PRE] == nil)
  local named = false
  for _, r in ipairs(removed) do if r == PRE then named = true end end
  test("...and says so", named)
end

do
  local files, keep, clean, PRE = load_({ ["/init.lua"] = OPENOS_INIT })
  keep()
  clean()
  test("with no OpenOS trees to clean, the backup stays", files[PRE] == OPENOS_INIT)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
