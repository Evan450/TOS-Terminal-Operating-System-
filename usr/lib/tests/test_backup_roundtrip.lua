-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: a backup restores every file, or says which  ║
-- ║                                                                ║
-- ║  On the headless runner a snapshot of five files restored      ║
-- ║  four. The empty one was never written: restore's write sat    ║
-- ║  inside `if crypto and #data > 0`, which also meant a machine  ║
-- ║  without kernel.crypto restored nothing, and a bad hash or a   ║
-- ║  failed write went only to the log. The shell said "Restore    ║
-- ║  OK: 4/7 files", counting two directories as files. The        ║
-- ║  snapshot side stored a file it could not read as an EMPTY     ║
-- ║  file (`readFile(...) or ""`) and said OK, so a restore then   ║
-- ║  wrote a zero-byte stand-in over the real one.                 ║
-- ║                                                                ║
-- ║  Drives the real kernel/backup.lua over an in-memory securefs, ║
-- ║  then the real `backup` shell command for what it prints.      ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_backup_roundtrip.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end
local function has(s, needle) return tostring(s):find(needle, 1, true) ~= nil end

local sha = dofile("tos/kernel/sha256.lua")
local CRYPTO = { hash = function(d) return sha.hex(d) end, ctEquals = function(a, b) return a == b end }

-- ── An in-memory securefs: path -> content, or true for a directory ──
local tree, unreadable, unwritable
local function norm(p) p = ("/" .. tostring(p)):gsub("//+", "/"); if #p > 1 then p = p:gsub("/$", "") end return p end
local securefs = {
  normalize = norm,
  exists = function(p) return tree[norm(p)] ~= nil end,
  isDirectory = function(p) return tree[norm(p)] == true end,
  size = function(p) local v = tree[norm(p)]; return type(v) == "string" and #v or 0 end,
  readFile = function(p)
    p = norm(p)
    if unreadable[p] then return nil, "permission denied" end
    local v = tree[p]
    return type(v) == "string" and v or nil, type(v) ~= "string" and "not a file" or nil
  end,
  writeFile = function(p, d)
    p = norm(p)
    if unwritable[p] then return false, "disk full" end
    local parent = p:match("^(.*)/[^/]+$")
    if parent ~= "" and tree[parent] ~= true then return false, "no such directory" end
    tree[p] = d
    return true
  end,
  makeDirectory = function(p) tree[norm(p)] = true; return true end,
  list = function(p)
    local base, out = norm(p), {}
    for k, v in pairs(tree) do
      local parent, name = k:match("^(.*)/([^/]+)$")
      if name and norm(parent == "" and "/" or parent) == base then
        out[#out + 1] = name .. (v == true and "/" or "")
      end
    end
    table.sort(out)
    return out
  end,
}

local BIN
do
  local t = {}
  for i = 0, 255 do t[#t + 1] = string.char(i) end
  BIN = string.rep(table.concat(t), 300)   -- 76800 bytes, every byte value
end
local function fresh()
  tree = { ["/"] = true, ["/root"] = true, ["/root/bk"] = true,
    ["/root/bk/a.txt"] = "hello\n",
    ["/root/bk/empty"] = "",
    ["/root/bk/sp ace.txt"] = "space name",
    ["/root/bk/sub"] = true, ["/root/bk/sub/crlf.txt"] = "a\r\nb\r\n",
    ["/root/bk/sub/deep"] = true, ["/root/bk/sub/deep/b.bin"] = BIN }
  unreadable, unwritable = {}, {}
end
local FILES = { "/a.txt", "/empty", "/sp ace.txt", "/sub/crlf.txt", "/sub/deep/b.bin" }

local backup = dofile("tos/kernel/backup.lua")
local function init(crypto)
  backup.init({ securefs = securefs, fs = securefs, log = nil, crypto = crypto })
end
local SESSION = { user = "root", tier = 3 }
local function snap(src, dst) return backup.snapshot(src, dst, { session = SESSION }) end
local function restore(src, dst, force)
  return backup.restore(src, { session = SESSION, destRoot = dst, force = force })
end
local function sameTree(from, to)
  for _, rel in ipairs(FILES) do
    if tree[from .. rel] ~= nil and tree[to .. rel] ~= tree[from .. rel] then return false, rel end
  end
  return true
end

print("=== every file round-trips, the empty one too ===")
do
  fresh(); init(CRYPTO)
  local ok, s = snap("/root/bk", "/root/bk.bak")
  test("snapshot succeeds", ok == true, s)
  test("counting 5 files and 2 directories", s.files == 5 and s.dirs == 2,
    tostring(s.files) .. "/" .. tostring(s.dirs))
  test("with nothing left out", type(s.skipped) == "table" and #s.skipped == 0)
  local okR, r = restore("/root/bk.bak", "/root/out")
  test("restore succeeds", okR == true, r)
  test("restoring all 5 files", r.restored == 5 and r.files == 5, r.restored)
  test("the empty file comes back, empty", tree["/root/out/empty"] == "", tree["/root/out/empty"])
  local same, which = sameTree("/root/bk", "/root/out")
  test("every byte matches, binary and CRLF included", same, which)
  test("nothing reported missing", #r.skipped == 0)
end

print("=== without a hasher, restore still writes every file ===")
do
  fresh(); init(nil)
  local ok = snap("/root/bk", "/root/bk.bak")
  test("snapshot succeeds", ok == true)
  local okR, r = restore("/root/bk.bak", "/root/out")
  test("restore succeeds", okR == true, r)
  test("all 5 files written (it wrote none)", r.restored == 5, r.restored)
  test("and they match", (sameTree("/root/bk", "/root/out")))
end

print("=== a file that cannot be read is named, not stored empty ===")
do
  fresh(); init(CRYPTO)
  unreadable["/root/bk/a.txt"] = true
  local ok, s = snap("/root/bk", "/root/bk.bak")
  test("snapshot still succeeds", ok == true, s)
  test("4 files in it", s.files == 4, s.files)
  test("a.txt is named as left out", #s.skipped == 1 and s.skipped[1].rel == "/a.txt",
    s.skipped[1] and s.skipped[1].rel)
  test("saying why", has(s.skipped[1] and s.skipped[1].why, "permission denied"))
  unreadable = {}
  tree["/root/out"] = true
  tree["/root/out/a.txt"] = "the real one"
  local okR, r = restore("/root/bk.bak", "/root/out", true)
  test("restore succeeds", okR == true, r)
  test("and does not write an empty a.txt over the real one", tree["/root/out/a.txt"] == "the real one",
    tree["/root/out/a.txt"])
end

print("=== a tampered entry and a failed write are named ===")
do
  fresh(); init(CRYPTO)
  snap("/root/bk", "/root/bk.bak")
  -- Swap a.txt's stored hash for a wrong one and re-seal the body, so the
  -- whole-file check passes and only the entry's own check can catch it.
  local raw = tree["/root/bk.bak"]
  local info = backup.inspect("/root/bk.bak", { session = SESSION })
  local body = raw:sub(info.bodyOff)
  local good = sha.hex("hello\n")
  local at = body:find(good, 1, true)
  test("setup: found a.txt's hash in the body", at ~= nil)
  body = body:sub(1, at - 1) .. string.rep("f", 64) .. body:sub(at + 64)
  local head = raw:sub(1, info.bodyOff - 65)
  tree["/root/bk.bak"] = head .. sha.hex(body) .. body
  unwritable["/root/out/sp ace.txt"] = true
  local okR, r = restore("/root/bk.bak", "/root/out")
  test("restore runs", okR == true, r)
  test("3 of 5 files restored", r.restored == 3 and r.files == 5, r.restored)
  local why = {}
  for _, e in ipairs(r.skipped) do why[e.rel] = e.why end
  test("a.txt named: its hash", has(why["/a.txt"], "do not match"), why["/a.txt"])
  test("sp ace.txt named: the write", has(why["/sp ace.txt"], "disk full"), why["/sp ace.txt"])
end

print("=== the destination refusals ===")
do
  fresh(); init(CRYPTO)
  snap("/root/bk", "/root/bk.bak")
  tree["/root/afile"] = "x"
  local okR, err = restore("/root/bk.bak", "/root/afile", true)
  test("a file as the destination is refused, --force or not", okR == false, err)
  test("saying so", has(err, "is a file"), err)
  tree["/root/full"] = true
  tree["/root/full/x"] = "x"
  okR, err = restore("/root/bk.bak", "/root/full")
  test("a non-empty destination is refused", okR == false)
  test("naming the shell's flag, not the API's", has(err, "--force") and not has(err, "force=true"), err)
end

-- ── The shell: what an operator reads ───────────────────────────
print("=== the backup command says what it did ===")
do
  package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
  package.loaded["computer"]  = { uptime = function() return 0 end,
                                  freeMemory = function() return 1e6 end,
                                  pullSignal = function() return nil end,
                                  beep = function() end }
  package.loaded["component"] = { list = function() return function() end end,
                                  isAvailable = function() return false end }
  package.loaded["kernel.screen"]  = {}
  package.loaded["kernel.display"] = {}
  package.loaded["kernel.sha256"] = sha
  package.loaded["kernel.users"] = { TIER = { ADMIN = 2, ROOT = 3 },
    currentSession = function() return SESSION end }
  local okA, register = pcall(require, "shell.panels.commands.admin")
  test("admin.lua loads", okA and type(register) == "function", register)
  if okA and type(register) == "function" then
    _G._TOS = _G._TOS or {}
    _G._TOS.backup = backup
    local S = { K = {}, E = { push = function() end }, P = {}, F = {}, D = {},
      T = { fg = 1, dim = 2, error = 3, warning = 4, highlight = 5, title = 6 },
      tier = 3, W = 80, H = 25, cwd = "/", displayIdx = 1, tabs = {},
      U = { currentSession = function() return SESSION end } }
    local deps = { rp = function(p) return p end, refreshBrowser = function() end,
      adminOnly = function() return true end, rootOnly = function() return true end,
      canRead = function() return true end, canWrite = function() return true end,
      canAccess = function() return true end, makeProgramEnv = function() return {} end,
      openViewTab = function() end, openEditTab = function() end }
    local C = {}
    local okR = pcall(register, C, S, deps)
    test("the commands register", okR and type(C.backup) == "function")
    local function run(...)
      local out = {}
      local okC, e = pcall(C.backup, { ... }, function(t) out[#out + 1] = tostring(t) end)
      if not okC then out[#out + 1] = "THREW: " .. tostring(e) end
      return table.concat(out, "\n")
    end
    if type(C.backup) == "function" then
      fresh(); init(CRYPTO)
      local out = run("snapshot", "/root/bk", "/root/bk.bak")
      test("snapshot: files and directories counted apart",
        has(out, "Snapshot OK: 5 file(s), 2 directories"), out)
      out = run("restore", "/root/bk.bak", "/root/out")
      test("restore: OK with 5 of 5", has(out, "Restore OK: 5 of 5 file(s), 2 directories"), out)

      fresh(); init(CRYPTO)
      unreadable["/root/bk/a.txt"] = true
      out = run("snapshot", "/root/bk", "/root/bk.bak")
      test("a partial snapshot says INCOMPLETE", has(out, "Snapshot INCOMPLETE"), out)
      test("and names the file", has(out, "/a.txt  (permission denied)"), out)

      fresh(); init(CRYPTO)
      run("snapshot", "/root/bk", "/root/bk.bak")
      unwritable["/root/out/empty"] = true
      out = run("restore", "/root/bk.bak", "/root/out")
      test("a partial restore says INCOMPLETE, 4 of 5", has(out, "Restore INCOMPLETE: 4 of 5"), out)
      test("and names what it could not write", has(out, "/empty  (could not be written"), out)
    end
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed."); return true end
