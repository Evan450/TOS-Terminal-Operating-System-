-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: every "run 'x'" hint names a real command    ║
-- ║                                                                ║
-- ║  v1.4.0 retired the `launcher` command: the Desktop took its   ║
-- ║  place, and the tape toolbox became `tape-menu`. Two hints     ║
-- ║  went on sending people to it. `kiosk` said "Looking for the   ║
-- ║  OPERATOR multi-tool? Run 'launcher'", and tape-auth, after    ║
-- ║  you build a personal menu, said "Then open it with: launcher  ║
-- ║  tape". Both answer "unknown command".                         ║
-- ║                                                                ║
-- ║  A hint that names a command nobody can run is worse than no   ║
-- ║  hint, so this reads every one in shipped code -- the base OS  ║
-- ║  and the add-ons -- and checks the command it names exists:    ║
-- ║  in the shell's registry, as an add-on's command, or as a      ║
-- ║  program an add-on installs in /usr/bin.                       ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_hint_commands.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function readText(path)
  local fh = io.open(path, "rb"); if not fh then return nil end
  local s = fh:read("*a"); fh:close()
  return (s:gsub("\r\n", "\n"))
end

local WINDOWS = package.config:sub(1, 1) == "\\"
--- Every .lua under `base`, as paths relative to it.
local function listLua(base)
  base = base:gsub("/+$", "")
  local absBase = base
  if WINDOWS then
    local p = io.popen('cd /d "' .. base:gsub("/", "\\") .. '" && cd')
    if p then absBase = (p:read("*l") or ""):gsub("\\", "/"):gsub("/+$", ""); p:close() end
  end
  local cmd = WINDOWS and ('dir /b /s "' .. base:gsub("/", "\\") .. '\\*.lua" 2>nul')
                      or ('find "' .. base .. '" -name "*.lua" 2>/dev/null')
  local out = {}
  local fh = io.popen(cmd)
  if fh then
    for line in fh:lines() do
      line = line:gsub("\\", "/"):gsub("%s+$", "")
      local rel
      if line:sub(1, #absBase + 1) == absBase .. "/" then rel = line:sub(#absBase + 2)
      elseif line:sub(1, #base + 1) == base .. "/" then rel = line:sub(#base + 2) end
      if rel then out[#out + 1] = rel end
    end
    fh:close()
  end
  table.sort(out)
  return out
end

print("=== every \"run 'x'\" hint names a real command ===")

-- ── What can be run ───────────────────────────────────────────────
local known = {}
local reg = readText("tos/shell/panels/commands.lua") or ""
local body = reg:match("\nlocal REGISTRY = (%b{})")
test("found the shell's command registry", body ~= nil)
for name in (body or ""):gmatch("\n%s+([%a_][%w_]*)%s*=%s*{") do known[name] = true end
for name in (body or ""):gmatch('\n%s+%["([^"]+)"%]%s*=%s*{') do known[name] = true end
test("the registry lists the commands a hint names most (net, srm, verify)",
  known.net and known.srm and known.verify)

local extras
for _, p in ipairs({ "../TOS-Extras/", "TOS-Extras/" }) do
  local fh = io.open(p .. "README.md", "r")
  if fh then fh:close(); extras = p; break end
end

local sources = {}
for _, rel in ipairs(listLua("tos")) do sources[#sources + 1] = "tos/" .. rel end

if extras then
  for _, rel in ipairs(listLua(extras)) do
    local file = rel:match("[^/]+$") or ""
    if rel:match("/package%.lua$") and not rel:match("^dist/") then
      local chunk = loadfile(extras .. rel, "t", {})
      local okM, m = pcall(chunk or error)
      if okM and type(m) == "table" then
        for name in pairs(type(m.commands) == "table" and m.commands or {}) do
          if type(name) == "string" then known[name] = true end
        end
        for _, f in ipairs(type(m.files) == "table" and m.files or {}) do
          local prog = type(f) == "string" and f:match("^/usr/bin/([%w_%-]+)%.lua$")
          if prog then known[prog] = true end
        end
      end
    elseif not rel:match("^dist/") and not rel:match("^build/") and not file:match("^test_") then
      sources[#sources + 1] = extras .. rel
    end
  end
  test("the add-ons' own commands are known (tape-auth, rc, cluster)",
    known["tape-auth"] and known.rc and known.cluster)
else
  print("  (TOS-Extras not found: checking the base OS only)")
end
test("found the shipped sources (" .. #sources .. " files)", #sources > 100)

-- ── Every hint in them ────────────────────────────────────────────
-- Only text a person reads: string literals, never comments.
local function literals(src)
  local out = {}
  local i, n, line = 1, #src, 1
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then line = line + 1; i = i + 1
    elseif src:sub(i, i + 1) == "--" then
      local lvl = src:match("^%-%-%[(=*)%[", i)
      if lvl then
        local close = src:find("]" .. lvl .. "]", i, true) or n
        for _ in src:sub(i, close):gmatch("\n") do line = line + 1 end
        i = close + #lvl + 2
      else
        local e = src:find("\n", i, true) or n + 1
        i = e
      end
    elseif c == '"' or c == "'" then
      local j, buf = i + 1, {}
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1); j = j + 2
        elseif d == c or d == "\n" then break
        else buf[#buf + 1] = d; j = j + 1 end
      end
      out[#out + 1] = { text = table.concat(buf), line = line }
      i = j + 1
    elseif src:match("^%[=*%[", i) then
      local lvl = src:match("^%[(=*)%[", i)
      local close = src:find("]" .. lvl .. "]", i, true) or n
      local text = src:sub(i, close)
      out[#out + 1] = { text = text, line = line }
      for _ in text:gmatch("\n") do line = line + 1 end
      i = close + #lvl + 2
    else i = i + 1 end
  end
  return out
end

local HINTS = {
  "[Rr]un '([%a][%w_%-]*)",        -- Run 'theme' ...
  "[Rr]un `([%a][%w_%-]*)",        -- run `doctor` ...
  "open it with:%s+([%a][%w_%-]*)", -- Then open it with:  tape-menu
}

local seen, bad = 0, {}
for _, path in ipairs(sources) do
  local src = readText(path)
  if src then
    for _, lit in ipairs(literals(src)) do
      for _, pat in ipairs(HINTS) do
        for name in lit.text:gmatch(pat) do
          seen = seen + 1
          if not known[name] then
            bad[#bad + 1] = path .. ":" .. lit.line .. " names '" .. name .. "'"
          end
        end
      end
    end
  end
end
test("found the hints (" .. seen .. ")", seen >= 10, seen)
test("every hint names a command that exists", #bad == 0, table.concat(bad, "; "))

print(string.format("\nResults: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
