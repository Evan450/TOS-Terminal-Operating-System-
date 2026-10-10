-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the Master's wizard prints its pairing code   ║
-- ║                                                                ║
-- ║  cluster-setup on a Master opens a pairing window and prints   ║
-- ║  the address and code a Manager must be given. The window      ║
-- ║  comes from the cluster-master package's cluster.api, which    ║
-- ║  returns it as a TABLE { code, expires_in }. The wizard took   ║
-- ║  it as (code, secs): "Pairing window open for 0s", then a      ║
-- ║  crash concatenating the table -- on every Master, one line    ║
-- ║  before the code (headless machine, 2026-10-10).               ║
-- ║                                                                ║
-- ║  test_cluster_setup.lua could not see it: its ctx answers      ║
-- ║  startPairing with ("PAIR-CODE-42", 300) itself. This drives   ║
-- ║  the REAL cluster.api (TOS-Extras) through the wizard.         ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_cluster_pairing_seam.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_cluster_pairing_seam.lua"
local base = here:gsub("[^/\\]*$", "")
local function readFirst(rels)
  for _, rel in ipairs(rels) do
    for _, p in ipairs({ base .. "../../../" .. rel, rel, "TOS-Dev/" .. rel }) do
      local f = io.open(p, "rb")
      if f then local s = f:read("*a"); f:close(); return s end
    end
  end
end

local uptime = 1000
package.loaded["computer"] = { uptime = function() return uptime end }
package.loaded["cluster.net"] = {}

local apiSrc = readFirst({ "../TOS-Extras/cluster/master-skeleton/lib/cluster/api.lua" })
local wizSrc = readFirst({ "tos/shell/clustersetup.lua" })
if not (apiSrc and wizSrc) then
  print("  FAIL: could not read cluster/api.lua (TOS-Extras) or tos/shell/clustersetup.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
local function newApi() return assert(load(apiSrc, "=cluster/api.lua"))() end
local wiz = assert(load(wizSrc, "=clustersetup.lua"))()

-- The daemon's half, as clusterd.startPairing hands it over: the code and
-- the window's expiry uptime (pair.startWindow).
local clusterd = { startPairing = function() return "K7Q2X9", uptime + 300 end }

print("=== the window, read through the real cluster.api ===")
print()

do
  local api = newApi()
  api.bind({}, {}, {}, clusterd)
  local raw = api.startPairing()
  test("cluster.api returns the window as a table (the contract this reads)",
    type(raw) == "table" and raw.code == "K7Q2X9")
  local code, secs = wiz.pairingWindow(api.startPairing())
  test("pairingWindow gives the code as a string", code == "K7Q2X9", code)
  test("...and the seconds left", secs == 300, secs)
  local c2, s2 = wiz.pairingWindow("OLDCODE", 120)
  test("the old (code, secs) shape still reads", c2 == "OLDCODE" and s2 == 120)
  local c3, why = wiz.pairingWindow(nil, "pairing_unsupported")
  test("a refusal stays a refusal", c3 == nil and why == "pairing_unsupported")
end

print()
print("=== the whole Master wizard ===")
print()

do
  local api = newApi()
  api.bind({}, {}, {}, clusterd)
  local said = {}
  local ctx = {
    say = function(t) said[#said + 1] = tostring(t or "") end,
    choose = function() return 1 end,            -- Master; then boot-start yes
    ask = function(_, dflt) return dflt end,
    installed = function() return false end,
    install = function() return true end,
    writeFile = function() return true end,
    startService = function() return true end,
    setBootStart = function() return true end,
    modemCount = function() return 1, 1 end,
    myModemAddress = function() return "2e12794b-253b-44ac-a3e1-4c35d4a03b59" end,
    hostname = function() return "master" end,
    -- What extras.lua's ctx does: the real api, read by pairingWindow.
    startPairing = function() return wiz.pairingWindow(api.startPairing()) end,
  }
  local ok, err = pcall(wiz.run, ctx)
  local text = table.concat(said, "\n")
  test("the wizard runs to the end", ok, err)
  test("it prints the pairing code", text:find("Pairing code:%s+K7Q2X9") ~= nil, text)
  test("...and the real window, not 0s", text:find("open for 300s", 1, true) ~= nil)
  test("...and the Master's full address",
    text:find("2e12794b-253b-44ac-a3e1-4c35d4a03b59", 1, true) ~= nil)
end

print()
print("=== the shell's ctx ===")
print()

do
  local ex = readFirst({ "tos/shell/panels/commands/extras.lua" }) or ""
  test("cluster-setup's ctx reads the window through pairingWindow",
    ex:find("return wiz.pairingWindow(w, err)", 1, true) ~= nil)
  test("...and an unbound daemon is a refusal, not a crash",
    ex:find("pcall(api.startPairing)", 1, true) ~= nil)
  local api = newApi()                           -- never bound
  local okS = pcall(api.startPairing)
  test("(an unbound cluster.api does raise, which is why)", okS == false)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
