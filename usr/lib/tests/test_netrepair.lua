-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Test: online repair cannot make things worse                   ║
-- ║                                                                ║
-- ║  kernel/netrepair.lua puts back a system file that fails its    ║
-- ║  manifest digest, fetched from the published release. The      ║
-- ║  operator asked for it to be treated as fragile, so this test   ║
-- ║  is mostly about the ways it must NOT act: a wrong byte from    ║
-- ║  the server, a dropped connection, a full disk, an unanchored   ║
-- ║  or tampered manifest, no card -- each must leave the machine   ║
-- ║  exactly as it was. And operator state under /etc is never      ║
-- ║  "restored".                                                    ║
-- ║                                                                ║
-- ║  Drives the REAL netrepair with the REAL sha256 over an         ║
-- ║  in-memory disk and a fake card serving a fake repo.            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_netrepair.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
package.loaded["computer"] = { uptime = function() return 0 end }
local sha = dofile("tos/kernel/sha256.lua")
local crypto = { hash = function(d) return sha.hex(d) end }
local netrepair = dofile("tos/kernel/netrepair.lua")

local GOOD = {
  ["/tos/kernel/a.lua"] = "return 'a'\n",
  ["/tos/kernel/b.lua"] = "return 'b'\n",
  ["/init.lua"] = "-- boot\n",
  ["/etc/rc.d/20-rshd.disabled"] = "",
  ["/etc/rc.d/20-rshd.lua"] = "return {}\n",
}
local function manifest()
  local m = {}
  for _, p in ipairs({ "/init.lua", "/tos/kernel/a.lua", "/tos/kernel/b.lua",
                       "/etc/rc.d/20-rshd.lua", "/etc/rc.d/20-rshd.disabled" }) do
    m[#m + 1] = { path = p, critical = false, hash = sha.hex(GOOD[p]) }
  end
  m[#m + 1] = { path = "/usr/bin/nodigest.lua", critical = false }   -- no hash field
  return m
end

-- ── A machine ──────────────────────────────────────────────────────
local function machine()
  local files = {}
  for p, v in pairs(GOOD) do files[p] = v end
  local F = { files = files, free = 10 * 1024 * 1024 }
  local function under(p, d) return p:sub(1, #d + 1) == d .. "/" end
  function F.exists(p)
    if files[p] then return true end
    for k in pairs(files) do if under(k, p) then return true end end
    return false
  end
  function F.readFile(p) return files[p] end
  function F.writeFile(p, d) files[p] = d; return true end
  function F.writeFileAtomic(p, d) files[p] = d; return true end
  function F.appendFile(p, d) files[p] = (files[p] or "") .. d; return true end
  function F.rename(a, b) files[b] = files[a]; files[a] = nil; return true end
  function F.makeDirectory() return true end
  function F.remove(p)
    files[p] = nil
    for k in pairs(files) do if under(k, p) then files[k] = nil end end
    return true
  end
  function F.spaceFree() return F.free end
  return F
end

-- ── A card and a repo ──────────────────────────────────────────────
local function card(fs, served, opts)
  opts = opts or {}
  local C = { requests = {}, up = opts.up ~= false }
  function C.available() return C.up end
  function C.status() return { reason = "no internet card installed" } end
  function C.download(url, dest, o)
    C.requests[#C.requests + 1] = url
    if opts.dropAfter and #C.requests > opts.dropAfter then return false, "connection reset" end
    local body = served[url]
    if not body then return false, "404 Not Found" end
    o.fs.writeFile(dest, body)
    return true, nil, { bytes = #body }
  end
  return C
end
local function url(ref, path) return netrepair.urlFor(ref, path) end
local function servedFor(ref, override)
  local s = {}
  for p, v in pairs(GOOD) do s[url(ref, p)] = v end
  for p, v in pairs(override or {}) do s[url(ref, p)] = v end
  return s
end

local function deps(fs, inet, o)
  o = o or {}
  return { fs = fs, crypto = crypto, internet = inet, manifest = manifest(),
           build = o.build or "abc1234", log = { warn = function() end },
           anchor = o.anchor or function() return true end }
end
local function said(rep, needle)
  for _, l in ipairs(rep.lines) do if l.text:find(needle, 1, true) then return true end end
  return false
end

print("=== online repair cannot make things worse ===")
print()

print("-- a healthy machine --")
do
  local fs = machine(); local inet = card(fs, servedFor("build-abc1234"))
  local rep = netrepair.run(deps(fs, inet), { apply = true })
  test("nothing to repair is reported as such", said(rep, "nothing to repair"))
  test("...and nothing is fetched", #inet.requests == 0)
end

print()
print("-- the plan touches nothing --")
do
  local fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  fs.files["/tos/kernel/b.lua"] = nil
  local inet = card(fs, servedFor("build-abc1234"))
  local rep = netrepair.run(deps(fs, inet), {})
  test("a dry run lists the changed file", said(rep, "CHANGED  /tos/kernel/a.lua"))
  test("...and the missing one", said(rep, "MISSING  /tos/kernel/b.lua"))
  test("...fetches nothing", #inet.requests == 0)
  test("...and changes nothing", fs.files["/tos/kernel/a.lua"] == "return 'tampered'\n"
    and fs.files["/tos/kernel/b.lua"] == nil)
  test("...and says how to act", said(rep, "Add --apply"))
end

print()
print("-- a repair, from this machine's own release --")
do
  local fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  fs.files["/tos/kernel/b.lua"] = nil
  local inet = card(fs, servedFor("build-abc1234"))
  local rep = netrepair.run(deps(fs, inet), { apply = true })
  test("both files are put back", fs.files["/tos/kernel/a.lua"] == GOOD["/tos/kernel/a.lua"]
    and fs.files["/tos/kernel/b.lua"] == GOOD["/tos/kernel/b.lua"])
  test("...from the build's own tag", inet.requests[1] and inet.requests[1]:find("/build-abc1234/", 1, true))
  test("...and nothing else was fetched", #inet.requests == 2)
  test("the staging area is gone afterwards", not fs.exists(netrepair.STAGE))
  test("the report counts them", rep.fixed == 2 and rep.ok)
end

print()
print("-- the source it picks --")
test("a clean build stamp fetches its tag", netrepair.sourceRef("abc1234") == "build-abc1234")
test("a dirty one falls back to main", netrepair.sourceRef("abc1234-dirty") == "main")
test("so does a source tree", netrepair.sourceRef("source") == "main")
test("an explicit ref wins", netrepair.sourceRef("abc1234", "build-0ld") == "build-0ld")

print()
print("-- a wrong byte from the server is never written --")
do
  local fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  fs.files["/tos/kernel/b.lua"] = nil
  local inet = card(fs, servedFor("build-abc1234", { ["/tos/kernel/a.lua"] = "return 'evil'\n" }))
  local rep = netrepair.run(deps(fs, inet), { apply = true })
  test("the bad copy is rejected", said(rep, "REJECTED the fetched /tos/kernel/a.lua"))
  test("...and the file is left as it was", fs.files["/tos/kernel/a.lua"] == "return 'tampered'\n")
  test("the good one is still repaired", fs.files["/tos/kernel/b.lua"] == GOOD["/tos/kernel/b.lua"])
  test("...and the run says it is not whole", not rep.ok and rep.rejected == 1)
end

print()
print("-- a dropped connection changes nothing --")
do
  local fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  fs.files["/tos/kernel/b.lua"] = nil
  local inet = card(fs, servedFor("build-abc1234"), { dropAfter = 1 })
  local rep = netrepair.run(deps(fs, inet), { apply = true })
  test("the first file, already staged, is NOT written", fs.files["/tos/kernel/a.lua"] == "return 'tampered'\n")
  test("...nor the second", fs.files["/tos/kernel/b.lua"] == nil)
  test("...staging is cleared", not fs.exists(netrepair.STAGE))
  test("...and it says nothing was changed", said(rep, "Nothing was changed"))
end

print()
print("-- a full disk changes nothing --")
do
  local fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  fs.free = 20 * 1024
  local inet = card(fs, servedFor("build-abc1234"))
  local rep = netrepair.run(deps(fs, inet), { apply = true })
  test("with too little space it stops before fetching", #inet.requests == 0
    and said(rep, "Not enough free disk"))
  test("...and the file is untouched", fs.files["/tos/kernel/a.lua"] == "return 'tampered'\n")
end

print()
print("-- operator state is not ours --")
do
  local fs = machine()
  fs.files["/etc/rc.d/20-rshd.disabled"] = nil      -- the operator enabled rshd
  fs.files["/etc/rc.d/20-rshd.lua"] = "-- my edit\n"
  local inet = card(fs, servedFor("build-abc1234"))
  local rep = netrepair.run(deps(fs, inet), { apply = true })
  test("a removed .disabled marker is not put back", fs.files["/etc/rc.d/20-rshd.disabled"] == nil)
  test("an edited rc.d script is not overwritten", fs.files["/etc/rc.d/20-rshd.lua"] == "-- my edit\n")
  test("...nothing under /etc was even fetched", #inet.requests == 0)
  test("...and the report says why", said(rep, "operator state"))
  fs.files["/usr/bin/nodigest.lua"] = nil
  rep = netrepair.run(deps(fs, inet), {})
  test("a file with no digest is listed as uncheckable", said(rep, "no digest"))
end

print()
print("-- the manifest has to be trustworthy --")
do
  local fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  local inet = card(fs, servedFor("build-abc1234"))
  local unanchored = function() return false, "no anchored hash (run `verify anchor` as admin)" end
  local rep = netrepair.run(deps(fs, inet, { anchor = unanchored }), { apply = true })
  test("an unanchored manifest is refused", said(rep, "not anchored") and #inet.requests == 0)
  test("...and nothing changed", fs.files["/tos/kernel/a.lua"] == "return 'tampered'\n")
  rep = netrepair.run(deps(fs, inet, { anchor = unanchored }), { apply = true, unanchored = true })
  test("--unanchored accepts it, saying so", said(rep, "NOT anchored")
    and fs.files["/tos/kernel/a.lua"] == GOOD["/tos/kernel/a.lua"])

  fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  inet = card(fs, servedFor("build-abc1234"))
  local mismatch = function() return false, "manifest hash mismatch (live=1234 anchored=abcd)" end
  rep = netrepair.run(deps(fs, inet, { anchor = mismatch }), { apply = true, unanchored = true })
  test("a manifest that FAILS its anchor is refused even with --unanchored",
    said(rep, "failed its EEPROM anchor") and #inet.requests == 0)
  test("...and nothing changed", fs.files["/tos/kernel/a.lua"] == "return 'tampered'\n")
end

print()
print("-- no card, and too much to repair --")
do
  local fs = machine()
  fs.files["/tos/kernel/a.lua"] = "return 'tampered'\n"
  local inet = card(fs, servedFor("build-abc1234"), { up = false })
  local rep = netrepair.run(deps(fs, inet), { apply = true })
  test("no card: refused, naming why", said(rep, "No usable internet card"))
  test("...and nothing changed", fs.files["/tos/kernel/a.lua"] == "return 'tampered'\n")

  fs = machine()
  local d = deps(fs, card(fs, {}))
  for i = 1, netrepair.MAX_FILES + 1 do
    d.manifest[#d.manifest + 1] = { path = "/tos/gone" .. i .. ".lua", hash = sha.hex("x") }
  end
  rep = netrepair.run(d, { apply = true })
  test("more broken files than a repair takes on is a reinstall", said(rep, "That is a reinstall"))
end

print()
print("-- the shell's gate --")
do
  local h = io.open("tos/shell/panels/commands/admin.lua", "rb")
  local src = h and h:read("*a") or ""; if h then h:close() end
  test("`srm repair --online --apply` needs root",
    src:find('if flags.apply and not rootOnly(o) then return end', 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
