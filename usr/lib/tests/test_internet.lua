-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: internet card transport + remote repos   ║
-- ║                                                            ║
-- ║  This is the path by which executable code from OUTSIDE     ║
-- ║  the Minecraft world reaches a TOS machine, so the tests    ║
-- ║  here are mostly about refusal:                             ║
-- ║                                                            ║
-- ║   1. URL VETTING — only http/https, no credentials, no      ║
-- ║      control characters (a newline in a URL is where        ║
-- ║      header injection starts).                              ║
-- ║   2. REMOTE PATH VETTING — a source path in a stranger's    ║
-- ║      index is used to build both a URL and a staging        ║
-- ║      destination. "master/../../../tos/kernel/fs.lua"       ║
-- ║      must never become either. validateManifest also        ║
-- ║      checks this, but only at INSTALL time — after the      ║
-- ║      bytes are on disk — so it cannot be the only check.    ║
-- ║   3. THE ALLOWLIST — /etc/pkg-repos.cfg IS the list of      ║
-- ║      hosts this machine will take code from; an unparseable ║
-- ║      URL must not sit in it looking configured.             ║
-- ║   4. FAIL-CLOSED with no card: every entry point reports    ║
-- ║      "no internet card" rather than erroring or hanging.    ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_internet.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- ── Component stub: no internet card unless a test installs one ──
local installed = {}
package.loaded["component"] = {
  list = function(filter)
    local names = {}
    for addr, ctype in pairs(installed) do
      if not filter or ctype == filter then names[#names + 1] = addr end
    end
    local i = 0
    return function() i = i + 1; return names[i] end
  end,
  proxy = function(addr)
    if installed[addr] == "internet" then
      return {
        isHttpEnabled = function() return _G.__httpOn ~= false end,
        isTcpEnabled  = function() return _G.__tcpOn == true end,
        request = function() return nil, "stub: no network in tests" end,
      }
    end
    error("no such component")
  end,
  type = function(addr) return installed[addr] end,
}
package.loaded["computer"] = { uptime = function() return 0 end }

package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local internet = require("kernel.internet")

print("=== internet card Tests ===\n")

-- ════════════════════════════════════════════════════════════════════
-- 1. URL vetting
-- ════════════════════════════════════════════════════════════════════
print("-- URL vetting --")

do
  local ok, scheme, host = internet.parseUrl("https://example.com/oc/master")
  test("https URL accepted", ok)
  eq("...scheme parsed", "https", scheme)
  eq("...host parsed", "example.com", host)

  local ok2, _, host2 = internet.parseUrl("http://Example.COM:8080/x")
  test("http URL accepted", ok2)
  eq("host is lower-cased and port-stripped", "example.com", host2)
end

do
  local bad = {
    ["ftp://example.com/x"]        = "ftp scheme",
    ["file:///etc/users.dat"]      = "file scheme",
    ["gopher://example.com"]       = "gopher scheme",
    ["example.com/no-scheme"]      = "missing scheme",
    ["https://"]                   = "no host",
    [""]                           = "empty string",
    ["https://user:pw@example.com"] = "embedded credentials",
    ["https://example.com/\nX: y"] = "newline (header injection shape)",
    ["https://example.com/\0evil"] = "NUL byte",
  }
  for url, why in pairs(bad) do
    test("refused: " .. why, internet.parseUrl(url) == false)
  end
  test("refused: an over-long URL",
    internet.parseUrl("https://example.com/" .. string.rep("a", 3000)) == false)
end

do
  eq("hostOf returns the host", "example.com",
    internet.hostOf("https://example.com/a/b"))
  eq("hostOf on a bad URL is nil", nil, internet.hostOf("ftp://example.com"))
end

-- ════════════════════════════════════════════════════════════════════
-- 2. Status with and without a card
-- ════════════════════════════════════════════════════════════════════
print("\n-- card detection --")

do
  local st = internet.status()
  test("no card: not present", st.present == false)
  test("no card: not available", internet.available() == false)
  test("no card: says why", tostring(st.reason):find("no internet card") ~= nil)

  local body, err = internet.get("https://example.com/")
  eq("get with no card returns nil", nil, body)
  test("...with a reason", tostring(err):find("no internet card") ~= nil)

  local sock, sErr = internet.socket("example.com", 80)
  eq("socket with no card returns nil", nil, sock)
  test("...with a reason", tostring(sErr):find("no internet card") ~= nil)

  -- A bad URL must be refused BEFORE the missing-card check, so the
  -- operator is told the real problem with what they typed.
  local _, urlErr = internet.get("ftp://example.com/x")
  test("a bad URL is refused on its own terms",
    tostring(urlErr):find("scheme", 1, true) ~= nil)
end

do
  installed["aaaa-bbbb-cccc-dddd"] = "internet"
  _G.__httpOn, _G.__tcpOn = true, false
  local st = internet.status()
  test("card present", st.present == true)
  test("HTTP reported available", st.http == true)
  test("TCP reported unavailable", st.tcp == false)
  test("available() true with card + HTTP", internet.available() == true)

  local sock, sErr = internet.socket("example.com", 80)
  eq("socket refused when the server has TCP off", nil, sock)
  test("...naming TCP", tostring(sErr):find("TCP", 1, true) ~= nil)

  -- A card whose HTTP the SERVER disabled is the confusing case: present,
  -- and useless. It must not read as "no card".
  _G.__httpOn = false
  local st2 = internet.status()
  test("HTTP-off card still reports present", st2.present == true)
  test("...but is not available", internet.available() == false)
  test("...and blames the server",
    tostring(st2.reason):find("server", 1, true) ~= nil)
  _G.__httpOn = true
end

do
  -- The machine-wide kill switch overrides a perfectly good card.
  package.loaded["kernel.config"] = nil
  internet.init({ config = { get = function(k)
    if k == "internet" then return false end
    return nil
  end } })
  test("config kill switch disables access", internet.available() == false)
  test("...and says so", tostring(internet.status().reason):find("disabled") ~= nil)

  internet.init({ config = { get = function() return nil end } })
  test("unset config defaults to enabled", internet.available() == true)
end

-- ════════════════════════════════════════════════════════════════════
-- 3. Remote repo path vetting  (#SEC — the sharpest edge)
-- ════════════════════════════════════════════════════════════════════
print("\n-- remote repo path vetting --")

local pkgremote = require("kernel.pkgremote")
local safe = pkgremote._safeRepoPath

do
  eq("a plain repo-relative path is kept", "master/gui/gui.lua",
    safe("master/gui/gui.lua"))
  eq("doubled slashes are collapsed", "master/gui/gui.lua",
    safe("master//gui///gui.lua"))
end

do
  local bad = {
    ["../../../tos/kernel/fs.lua"]      = "leading traversal",
    ["master/../../etc/users.dat"]      = "embedded traversal",
    ["master/./x.lua"]                  = "single-dot segment",
    ["/etc/users.dat"]                  = "absolute path",
    ["//evil.example.com/x.lua"]        = "protocol-relative host swap",
    ["https://evil.example.com/x.lua"]  = "absolute URL (host swap)",
    ["master/x.lua?a=b"]                = "query string",
    ["master/x.lua#frag"]               = "fragment",
    ["user@host/x.lua"]                 = "userinfo",
    ["master\\..\\x.lua"]               = "backslash traversal",
    ["master/\nx.lua"]                  = "newline",
    ["master/\0x.lua"]                  = "NUL byte",
    [""]                                = "empty",
  }
  for p, why in pairs(bad) do
    eq("refused: " .. why, nil, safe(p))
  end
  eq("refused: an over-long path", nil, safe(string.rep("a/", 200) .. "x.lua"))
end

-- ════════════════════════════════════════════════════════════════════
-- 4. The repo list is the allowlist
-- ════════════════════════════════════════════════════════════════════
print("\n-- repo configuration --")

do
  -- In-memory fs stub standing in for /etc.
  local disk = {}
  package.loaded["kernel.fs"] = {
    exists    = function(p) return disk[p] ~= nil end,
    readFile  = function(p) return disk[p] end,
    writeFile = function(p, d) disk[p] = d; return true end,
    writeFileAtomic = function(p, d) disk[p] = d; return true end,
    remove    = function(p) disk[p] = nil; return true end,
    join      = function(a, b) return a .. "/" .. b end,
    makeDirectory = function() return true end,
  }
  package.loaded["kernel.pkgremote"] = nil
  local pr = require("kernel.pkgremote")
  local serialize = require("kernel.serialize")

  eq("no config file = no repos", 0, #pr.repos())

  local ok, err = pr.addRepo("oc", "https://example.com/oc/master", "test repo")
  test("adding a repo succeeds", ok)
  if not ok then print("        " .. tostring(err)) end
  local list = pr.repos()
  eq("one repo configured", 1, #list)
  eq("...name kept", "oc", list[1] and list[1].name)
  eq("...host derived for the allowlist", "example.com", list[1] and list[1].host)
  eq("...trailing slash normalized away", "https://example.com/oc/master",
    list[1] and list[1].url)

  test("a repo with a bad URL is refused", pr.addRepo("bad", "ftp://x/y") == false)
  test("a repo with a bad name is refused",
    pr.addRepo("has space", "https://example.com") == false)
  eq("neither was added", 1, #pr.repos())

  -- Re-adding under the same name REPLACES rather than duplicating; two
  -- entries with one name would make "which URL is trusted?" ambiguous.
  pr.addRepo("oc", "https://other.example.com/x")
  eq("re-adding replaces in place", 1, #pr.repos())
  eq("...with the new URL", "other.example.com", pr.repos()[1].host)

  test("removing works", pr.removeRepo("oc") == true)
  eq("...and it is gone", 0, #pr.repos())
  test("removing a missing repo is refused", pr.removeRepo("nope") == false)

  -- A hand-edited config with junk in it must degrade to "that entry is
  -- unusable", not "no repos work".
  disk["/etc/pkg-repos.cfg"] = serialize.encode({
    { name = "good", url = "https://good.example.com/r" },
    { name = "noscheme", url = "good.example.com/r" },
    { name = "bad name", url = "https://x.example.com" },
    { url = "https://nameless.example.com" },
    "not a table",
  })
  local mixed = pr.repos()
  eq("only the valid entry survives", 1, #mixed)
  eq("...and it is the good one", "good", mixed[1] and mixed[1].name)
end

-- ════════════════════════════════════════════════════════════════════
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
