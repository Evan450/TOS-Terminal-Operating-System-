-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the picker knows dependencies over the wire  ║
-- ║                                                                ║
-- ║  On a machine installing from a repo the picker showed no [+], ║
-- ║  no Needs, no Suggests, and an R key that added nothing, and   ║
-- ║  filed every add-on under one "Remote" heading. Three seams    ║
-- ║  each dropped them: make-repo-index never wrote requires or    ║
-- ║  recommends, pkgremote.search kept four fields, and            ║
-- ║  pkg.listRemoteAvailable copied fewer. A floppy showed all of  ║
-- ║  it, because a disk's manifests are read directly.             ║
-- ║                                                                ║
-- ║  Drives the REAL chain: the built programs.cfg when there is   ║
-- ║  one, a fake card, pkgremote.search, pkg.listAllAvailable and  ║
-- ║  shell/pkgpicker.lua on a fake GPU.                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_picker_remote_deps.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path

local script, shots = {}, {}
local W, H = 80, 25
local grid = {}
local function chars(s)
  local out = {}
  for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
  return out
end
local gpu = {
  getResolution = function() return W, H end,
  getDepth = function() return 8 end,
  setForeground = function() end, setBackground = function() end,
  set = function(x, y, s)
    if not grid[y] then return end
    for i, ch in ipairs(chars(s)) do
      if x + i - 1 >= 1 and x + i - 1 <= W then grid[y][x + i - 1] = ch end
    end
  end,
  fill = function(x, y, w, h, ch)
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do if grid[yy] and xx >= 1 and xx <= W then grid[yy][xx] = ch end end
    end
  end,
}
local function screen()
  local t = {}
  for y = 1, H do t[y] = table.concat(grid[y]) end
  return table.concat(t, "\n")
end

package.loaded["computer"] = {
  uptime = function() return 0 end, freeMemory = function() return 1e6 end,
  pullSignal = function()
    shots[#shots + 1] = screen()
    local k = table.remove(script, 1)
    if not k then error("the picker asked for more keys than the test has") end
    return "key_down", "kb", k[1], k[2]
  end,
}
package.loaded["component"] = {
  list = function(kind) local done = false
    return function() if kind == "gpu" and not done then done = true; return "gpu-1" end end end,
  proxy = function() return gpu end,
}
package.loaded["kernel.process"] = { currentSession = function() return nil end, yieldCooperative = function() end }
package.loaded["kernel.sandbox"] = { build = function() return {} end }
local ROOT = { tier = 3, user = "root" }
package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 }, currentSession = function() return ROOT end }
package.loaded["kernel.sha256"] = dofile("tos/kernel/sha256.lua")
local serialize = dofile("tos/kernel/serialize.lua")
package.loaded["kernel.serialize"] = serialize
local sha = package.loaded["kernel.sha256"]
package.loaded["kernel.crypto"] = { hash = function(d) return sha.hex(d) end,
                                    ctEquals = function(a, b) return a == b end }

local F = { _f = {} }
local function under(p, k) return k == p or k:sub(1, #p + 1) == p .. "/" end
function F.exists(p) for k in pairs(F._f) do if under(p, k) then return true end end return false end
function F.readFile(p) return F._f[p] end
function F.writeFile(p, d) F._f[p] = d; return true end
function F.writeFileAtomic(p, d) F._f[p] = d; return true end
function F.remove(p) for k in pairs(F._f) do if under(p, k) then F._f[k] = nil end end return true end
function F.isDirectory(p) return F.exists(p) and F._f[p] == nil end
function F.makeDirectory() return true end
function F.mounts() return {} end
function F.list() return {} end
function F.join(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
function F.normalize(p) return (p:gsub("//+", "/"):gsub("(.)/$", "%1")) end
package.loaded["kernel.fs"] = F

local BASE = "https://r.example"
local SERVED = {}
package.loaded["kernel.internet"] = {
  available = function() return true end,
  status = function() return { ok = true } end,
  parseUrl = function() return true end,
  hostOf = function() return "r.example" end,
  get = function(url)
    if SERVED[url] then return SERVED[url] end
    return nil, "HTTP 404 Not Found", { status = 404, bytes = 0 }
  end,
}
F._f["/etc/pkg-repos.cfg"] = serialize.encode({ { name = "r", url = BASE } })

local pkgsign = dofile("tos/kernel/pkgsign.lua")
pkgsign.init({ fs = F, serialize = serialize })
package.loaded["kernel.pkgsign"] = pkgsign
local pkgremote = dofile("tos/kernel/pkgremote.lua")
package.loaded["kernel.pkgremote"] = pkgremote
local pkg = dofile("tos/kernel/pkg.lua")
pkg.init({ fs = F, log = nil, users = package.loaded["kernel.users"] })
package.loaded["kernel.pkg"] = pkg

--- The index a build would publish. The real one when this checkout has a
--- built pack, because that is the half that was missing; otherwise the
--- same shape by hand, so the test still means something on a bare clone.
local function builtIndex()
  local fh = io.open("../TOS-Extras/dist/optional-utilities/programs.cfg", "rb")
  if fh then
    local s = fh:read("a"); fh:close()
    print("  (reading the built programs.cfg, " .. #s .. " bytes)")
    return s
  end
  print("  (no built pack: using a hand-written index)")
  local function entry(cat, extra)
    local e = { version = "1.0.0", description = "d", category = cat, kind = "app", files = {} }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
  end
  return serialize.encode({
    write = entry("productivity", { requires = { "printer" }, recommends = { "mouse" } }),
    printer = entry("productivity"),
    tetris = entry("games", { recommends = { "mouse" } }),
    mouse = entry("drivers"),
  })
end

print("=== what the index says reaches the listing ===")
print()

SERVED[BASE .. "/programs.cfg"] = builtIndex()
local list = pkg.listAllAvailable({ includeRemote = true })
local byName = {}
for _, e in ipairs(list) do byName[e.name] = e end

test("the index decodes inside pkgremote's own budget", byName.write ~= nil, #list)
local w = byName.write or {}
test("requires survive", w.requires and w.requires[1] == "printer")
test("recommends survive", byName.tetris and byName.tetris.recommends
  and byName.tetris.recommends[1] == "mouse")
test("the category survives", w.category == "productivity", w.category)
test("the kind survives", type(w.kind) == "string", w.kind)
test("they are still marked remote", w.remote == true and w.root == nil)

print()
print("=== the picker works from them ===")
print()

local function run(keys)
  for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = " " end end
  script, shots = keys, {}
  local ok, err = pcall(function() return require("shell.pkgpicker").run({}) end)
  test("the picker ran the keys through", ok, err)
  return shots
end
local function has(s, needle) return s:find(needle, 1, true) ~= nil end
local function typed(word)
  local k = { { 47, 53 } }                    -- / opens the filter
  for c in word:gmatch(".") do k[#k + 1] = { c:byte(), 0 } end
  k[#k + 1] = { 13, 28 }                      -- Enter keeps it
  return k
end
local function with(a, b) for _, v in ipairs(b) do a[#a + 1] = v end return a end

local s = run(with(typed("write"), { { 32, 57 }, { 113, 16 } }))
local shot = s[#s]
test("picking write marks printer [+]", has(shot, "[x] write") and has(shot, "write + printer"), shot)
test("...and counts both", has(shot, "2 selected"), shot)
test("the panel says Needs", has(s[#s], "Needs") and has(s[#s], "printer"), s[#s])

s = run(with(typed("tetris"), { { 32, 57 }, { 114, 19 }, { 113, 16 } }))
test("R takes a suggestion from the index", has(s[#s], "Added 1 suggested"), s[#s])

s = run({ { 113, 16 } })
test("the add-ons sit under their categories", has(s[1], "Games"), s[1])
test("...and not under one Remote heading", not has(s[1], "Remote"), s[1])

print()
print("=== the index is a stranger's data ===")
print()

pkgremote.clearCache()
SERVED[BASE .. "/programs.cfg"] = serialize.encode({
  hostile = { version = "1.0.0", description = "d", category = { "not", "a", "string" },
              kind = 7, author = {}, files = {},
              requires = { "../../tos", 42, { name = "ok-dep" }, { name = {} } },
              recommends = { { nested = true }, "fine", "two words" } },
  oppm = { files = {}, dependencies = { libgui = "/", ["http://x/y"] = "/" } },
})
list = pkg.listAllAvailable({ includeRemote = true })
byName = {}
for _, e in ipairs(list) do byName[e.name] = e end
local h = byName.hostile or {}
test("a category that is not a string falls back", h.category == "remote", h.category)
test("a kind that is not a string is dropped", h.kind == nil)
test("an author that is not a string is dropped", h.author == nil)
test("a path in requires never reaches the picker",
  #(h.requires or {}) == 1 and h.requires[1] == "ok-dep", #(h.requires or {}))
test("recommends keep only names, cut at the first word",
  #(h.recommends or {}) == 2 and h.recommends[1] == "fine" and h.recommends[2] == "two")
test("OPPM's dependencies read as requires, URLs refused",
  byName.oppm and #byName.oppm.requires == 1 and byName.oppm.requires[1] == "libgui")
run({ { 32, 57 }, { 114, 19 }, { 113, 16 } })

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
