-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: what an HTTP transfer is allowed to call     ║
-- ║  success (pentest, Sep 2026)                                   ║
-- ║                                                                ║
-- ║   1. A non-2xx reply is not the resource. The status was read  ║
-- ║      and ignored, so a 404 page came back as the file.         ║
-- ║   2. A download whose append FAILS must fail. It fell through  ║
-- ║      to writeFile, truncated the .part to the latest chunk,    ║
-- ║      and renamed that into place as a finished download.       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_internet_transport.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

-- One scripted internet card: status code + body chunks per request.
local reply = { status = 200, chunks = {} }
package.loaded["component"] = {
  list = function(filter)
    local done = false
    return function()
      if done or (filter and filter ~= "internet") then return nil end
      done = true; return "inet-1"
    end
  end,
  proxy = function()
    return {
      isHttpEnabled = function() return true end,
      isTcpEnabled = function() return false end,
      request = function()
        local i = 0
        return {
          read = function() i = i + 1; return reply.chunks[i] end,
          response = function() return reply.status, "msg", {} end,
          close = function() end,
        }
      end,
    }
  end,
}
package.loaded["computer"] = { uptime = function() return 0 end }

-- A disk whose appendFile works once and then reports failure (disk full).
local files, appends = {}, 0
package.loaded["kernel.fs"] = {
  readFile = function(p) return files[p] end,
  writeFile = function(p, d) files[p] = d; return true end,
  appendFile = function(p, d)
    appends = appends + 1
    if appends > 1 then return false, "disk full" end
    files[p] = (files[p] or "") .. d; return true
  end,
  remove = function(p) files[p] = nil; return true end,
  rename = function(a, b) files[b] = files[a]; files[a] = nil; return true end,
}

local here = (arg and arg[0]) or "usr/lib/tests/test_internet_transport.lua"
local base = here:gsub("[^/\\]*$", "")
local internet
for _, p in ipairs({ base .. "../../../tos/kernel/internet.lua",
    "tos/kernel/internet.lua", "TOS-Dev/tos/kernel/internet.lua" }) do
  local chunk = loadfile(p); if chunk then internet = chunk(); break end
end
assert(internet, "cannot find internet.lua")

print("=== internet transport Tests ===")

do
  reply.status, reply.chunks = 404, { "<html>Not Found</html>" }
  local body, err = internet.get("https://repo.example/programs.cfg")
  test("a 404 reply is refused, not returned as the body", body == nil)
  test("  ...and the error names the status (" .. tostring(err) .. ")",
    type(err) == "string" and err:find("404", 1, true) ~= nil)

  reply.status, reply.chunks = 302, { "<a href='https://x'>moved</a>" }
  test("an unfollowed redirect page is refused", internet.get("http://repo.example/x") == nil)

  reply.status, reply.chunks = 200, { "hel", "lo" }
  test("a 200 reply still returns its body", internet.get("https://repo.example/ok") == "hello")
end

do
  local big = string.rep("x", 9000)          -- > the 8 KB flush size
  reply.status, reply.chunks = 200, { big, big, big }
  local ok = internet.download("https://repo.example/f.lua", "/var/pkg/remote/r/f.lua")
  test("a download whose append fails is reported as failed", not ok)
  test("  ...and no truncated file is left at the destination",
    files["/var/pkg/remote/r/f.lua"] == nil)
  test("  ...nor the .part", files["/var/pkg/remote/r/f.lua.part"] == nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
