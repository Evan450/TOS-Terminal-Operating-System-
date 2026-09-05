-- ╔══════════════════════════════════════════════════════════╗
-- ║  Coverage Test: system_manifest.lua is complete            ║
-- ║                                                            ║
-- ║  Every runtime .lua file under /tos, /etc/rc.d, /usr/bin,  ║
-- ║  /usr/modules plus the root bootstrap files (init.lua,     ║
-- ║  install.lua) MUST be listed in system_manifest.lua, or    ║
-- ║  `deploy`/install silently ships an incomplete image and   ║
-- ║  `verify` can't detect tampering with the omitted file.    ║
-- ║                                                            ║
-- ║  DUAL-MODE: runs in-TOS (kernel.fs) AND under the host     ║
-- ║  `lua` harness (find + dofile). It used to require kernel  ║
-- ║  .fs and was therefore SKIPPED by run_tests.sh — which is  ║
-- ║  how /tos/kernel/net/{mail,mailctl,mesh}.lua drifted out   ║
-- ║  of the manifest uncaught. Now the harness actually runs   ║
-- ║  it. /usr/lib/tests is excluded (dev-only).                ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_manifest_completeness.lua   (from TOS-Dev root)
--   or: run /usr/lib/tests/test_manifest_completeness.lua  (inside TOS)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end

local ROOTS      = { "/tos", "/etc/rc.d", "/usr/bin", "/usr/modules" }
local ROOT_FILES = { "/init.lua", "/install.lua" }

-- Acquire (manifest array, list of absolute runtime file paths) two ways.
local manifest, actual = nil, {}

local fs = _G._TOS and _G._TOS.fs
if not fs then local ok, m = pcall(require, "kernel.fs"); if ok then fs = m end end

if fs and fs.list and fs.exists then
  -- ── In-TOS mode: walk the live filesystem ──────────────────────
  do
    local ok, mod = pcall(require, "system_manifest")
    if ok and type(mod) == "table" then manifest = mod
    else
      local data = fs.readFile and fs.readFile("/tos/system_manifest.lua")
      if data then local fn = load(data, "=manifest", "t"); if fn then manifest = fn() end end
    end
  end
  local EXCLUDE = { ["/usr/lib/tests"] = true }
  local function walk(root)
    if EXCLUDE[root] or not fs.exists(root) then return end
    if not fs.isDirectory(root) then
      if root:sub(-4) == ".lua" then actual[#actual + 1] = root end; return
    end
    local entries = fs.list(root)
    if type(entries) ~= "table" then return end
    for _, name in ipairs(entries) do
      local clean = name:gsub("/$", "")
      local p = root .. "/" .. clean
      if fs.isDirectory(p) then walk(p)
      elseif clean:sub(-4) == ".lua" then actual[#actual + 1] = p end
    end
  end
  for _, r in ipairs(ROOTS) do walk(r) end
  for _, f in ipairs(ROOT_FILES) do if fs.exists(f) then actual[#actual + 1] = f end end
else
  -- ── Host mode: `find` + dofile, from the TOS-Dev root ──────────
  manifest = dofile("tos/system_manifest.lua")
  --! PLATFORM-AWARE ENUMERATION. The old form shelled out to POSIX `find`
  --! and claimed to be portable across Git-Bash and cmd. It is not:
  --! native Windows Lua routes io.popen through cmd.exe, whose `find` is
  --! a TEXT SEARCH utility, not a file finder, and which has no `ls` at
  --! all. It only ever worked when the suite happened to be launched from
  --! a shell with Git's bin on PATH -- so the same checkout passed from
  --! Git Bash and failed from cmd, and the failure surfaced as this
  --! test's own "file enumeration works" gate rather than as anything
  --! resembling a shell problem.
  --!
  --! `dir /b /s` is a cmd builtin and works whichever shell launched us,
  --! but prints ABSOLUTE paths where `find <rel>` prints relative ones,
  --! so the working directory is stripped back off to keep both shapes
  --! identical to everything downstream.
  local WINDOWS = package.config:sub(1, 1) == "\\"
  local cwd
  do
    local p = io.popen(WINDOWS and "cd" or "pwd")
    if p then cwd = (p:read("*l") or ""):gsub("\\", "/"):gsub("/+$", ""); p:close() end
  end
  for _, r in ipairs(ROOTS) do
    local rel = r:gsub("^/", "")
    local cmd = WINDOWS
      and ('dir /b /s "' .. rel:gsub("/", "\\") .. '\\*.lua" 2>nul')
      or  ('find "' .. rel .. '" -name "*.lua" 2>/dev/null')
    local fh = io.popen(cmd)
    if fh then
      for line in fh:lines() do
        line = line:gsub("\\", "/"):gsub("%s+$", "")
        if cwd and cwd ~= "" and line:sub(1, #cwd + 1) == cwd .. "/" then
          line = line:sub(#cwd + 2)
        end
        if line:match("%.lua$") and not line:match("No such") and not line:match("cannot find") then
          actual[#actual + 1] = "/" .. line
        end
      end
      fh:close()
    end
  end
  for _, f in ipairs(ROOT_FILES) do
    local h = io.open(f:gsub("^/", ""), "r"); if h then h:close(); actual[#actual + 1] = f end
  end
end

test("manifest loads as an array", type(manifest) == "table" and #manifest > 0)

-- Sanity gate: empty enumeration would pass everything vacuously. Fail loudly.
local sawKernel = false
for _, p in ipairs(actual) do if p == "/tos/kernel/init.lua" then sawKernel = true end end
test("file enumeration works (found kernel/init.lua)", sawKernel)

local listed = {}
for _, e in ipairs(manifest or {}) do
  if type(e) == "table" and type(e.path) == "string" then listed[e.path] = true end
end

-- COMPLETENESS (fatal): every real runtime file must be in the manifest.
local missing = {}
for _, p in ipairs(actual) do
  if not listed[p] and not p:match("^/usr/lib/tests/") then missing[#missing + 1] = p end
end
table.sort(missing)
for _, m in ipairs(missing) do print("    not in manifest: " .. m) end
test("no runtime file is missing from the manifest", #missing == 0)

-- Regression guard for the mesh transport (stage 5: mail's private
-- mail.lua/mailctl.lua became the shared, service-multiplexed meshctl,
-- and mailbox semantics left with the mail ADD-ON).
test("net/mesh.lua listed",    listed["/tos/kernel/net/mesh.lua"]    == true)
test("net/meshctl.lua listed", listed["/tos/kernel/net/meshctl.lua"] == true)
test("net/mail.lua NOT listed (moved to the add-on)",
  listed["/tos/kernel/net/mail.lua"] == nil)
test("shell/panels/mailapp.lua NOT listed (moved to the add-on)",
  listed["/tos/shell/panels/mailapp.lua"] == nil)

-- DANGLING (informational only): Dev intentionally over-lists bundled modules
-- (tape-storage, tetris) that ship via Optional Utilities; the Release strip
-- pass prunes any entry whose file is absent. So this is a notice, not a fail.
local actualSet = {}
for _, p in ipairs(actual) do actualSet[p] = true end
local dangling = 0
for p in pairs(listed) do
  local underRoot = (p == "/init.lua" or p == "/install.lua")
  for _, r in ipairs(ROOTS) do if p == r or p:sub(1, #r + 1) == r .. "/" then underRoot = true end end
  if underRoot and not actualSet[p] then dangling = dangling + 1 end
end
if dangling > 0 then print("  note: " .. dangling .. " manifest entry(ies) have no file in this tree (pruned in Release)") end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1)
else print("All tests passed.") end
