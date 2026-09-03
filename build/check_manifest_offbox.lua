-- Dev-box helper: off-box version of test_manifest_completeness.
-- Walks the source tree (via `dir /s /b` on Windows, `find` elsewhere)
-- and checks every runtime .lua under the deployable roots appears in
-- tos/system_manifest.lua. Run from TOS-Dev: lua build/check_manifest_offbox.lua
local manifest = dofile("tos/system_manifest.lua")
local listed = {}
for _, e in ipairs(manifest) do listed[e.path] = true end

local isWindows = package.config:sub(1, 1) == "\\"
local roots = { "tos", "etc/rc.d", "usr/bin" }
local missing = 0

local function scan(dir)
  local cmd
  if isWindows then
    cmd = 'cmd /c dir /s /b "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul'
  else
    cmd = 'find "' .. dir .. '" -name "*.lua" 2>/dev/null'
  end
  local p = io.popen(cmd)
  if not p then return end
  for line in p:lines() do
    local rel = line:gsub("\\", "/"):match("TOS%-Dev/(.+)$") or line:gsub("\\", "/")
    if rel:sub(1, 1) ~= "/" then rel = rel end
    if not rel:find("^usr/lib/tests/") and not rel:find("^build/") then
      local abs = "/" .. rel
      if not listed[abs] then
        print("MISSING from manifest: " .. abs)
        missing = missing + 1
      end
    end
  end
  p:close()
end

for _, r in ipairs(roots) do scan(r) end
for _, f in ipairs({ "/init.lua", "/install.lua" }) do
  if not listed[f] then print("MISSING: " .. f); missing = missing + 1 end
end

if missing == 0 then
  print("manifest covers all runtime files")
else
  print(missing .. " file(s) missing")
  os.exit(1)
end
