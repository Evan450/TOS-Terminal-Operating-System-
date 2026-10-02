-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Lint: MANUAL's command reference agrees with the registry      ║
-- ║                                                                ║
-- ║  Chapter 14 is the alphabetical command reference, and the     ║
-- ║  command registry (shell/panels/commands.lua) is what the      ║
-- ║  shells dispatch from -- including each command's TIER, which  ║
-- ║  executor.lua has enforced at dispatch since Sep 2026. Nothing ║
-- ║  compared the two. When this lint was written, 23 registered   ║
-- ║  commands had no entry, 14 entries understated who may run     ║
-- ║  them (`pkg list`, `edit`, `run` read as open to anyone; they  ║
-- ║  are admin-only), and `profile` documented a different         ║
-- ║  command altogether.                                           ║
-- ║                                                                ║
-- ║  Three rules:                                                  ║
-- ║   * every registered command (not an alias) has an entry, or   ║
-- ║     is named in one ("**a** / **b**", "(alias `b`)",           ║
-- ║     "(also `b`)");                                              ║
-- ║   * an admin (tier 2) or root (tier 3) command's FIRST marker   ║
-- ║     says so: **(admin...)** / **(root...)**;                    ║
-- ║   * every entry is a registered command, a program shipped in   ║
-- ║     /usr/bin, or says it was folded/retired/removed.            ║
-- ║  And the release README, MANUAL and CHANGELOG name is the one   ║
-- ║  /init.lua carries (the "bump them together" release rule).     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_docs_sync.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local here = (arg and arg[0]) or "usr/lib/tests/test_docs_sync.lua"
local base = here:gsub("[^/\\]*$", "")
package.path = base .. "../../../tos/?.lua;tos/?.lua;" .. package.path
local function readAll(p) local f = io.open(p, "rb"); if not f then return nil end local d = f:read("a"); f:close(); return d end
local function firstOf(...) for _, p in ipairs({ ... }) do local d = readAll(p); if d then return d, p end end end

local okR, reg = pcall(require, "shell.panels.commands")
test("the command registry loads", okR and type(reg) == "table" and reg.commandNames ~= nil, reg)
local manual = firstOf(base .. "../../../MANUAL.md", "MANUAL.md")
test("MANUAL.md is readable", manual ~= nil)
if not (okR and manual) then print("*** TESTS FAILED ***"); os.exit(1) end
manual = manual:gsub("\r\n", "\n")

local from = manual:find("\n## 14%. ")
local to = from and manual:find("\n## 15%. ", from)
test("chapter 14 found", from ~= nil and to ~= nil)
local ch = manual:sub(from or 1, to or #manual)

-- Entries: "**name** [/ **name2** ...] — rest-of-heading"
local entries, mentioned = {}, {}
-- A heading is "**a**", optionally " / **b**"..., then " — ". Bold words
-- at the start of a paragraph INSIDE an entry are not headings.
local function heading(line)
  local first, mid, rest = line:match("^%*%*([%w_-]+)%*%*(.-) — (.*)$")
  if not first or mid:gsub(" / %*%*[%w_-]+%*%*", "") ~= "" then return nil end
  local names = { first }
  for n in mid:gmatch("%*%*([%w_-]+)%*%*") do names[#names + 1] = n end
  return names, rest
end
for line in ch:gmatch("[^\n]+") do
  local names, rest = heading(line)
  if names then
    for _, n in ipairs(names) do entries[n] = { heading = rest, first = names[1] } end
  end
  for list in line:gmatch("%(alias ([^)]*)%)") do
    for n in list:gmatch("`([%w_-]+)`") do mentioned[n] = true end
  end
  for list in line:gmatch("%(also ([^)]*)%)") do
    for n in list:gmatch("`([%w_-]+)`") do mentioned[n] = true end
  end
end

print("=== MANUAL chapter 14 vs the command registry ===")
print()

-- 1. Every registered command is documented.
local missing = {}
for _, name in ipairs(reg.commandNames()) do
  local e = reg.entry(name)
  if not e.alias and not entries[name] and not mentioned[name] then missing[#missing + 1] = name end
end
test("every registered command has an entry in chapter 14", #missing == 0, table.concat(missing, ", "))

-- 2. Admin and root commands say so in their first marker.
local wrong = {}
for _, name in ipairs(reg.commandNames()) do
  local e, entry = reg.entry(name), entries[name]
  local tier = tonumber(e.tier) or 0
  if entry and tier >= 2 then
    local mark = entry.heading:match("%*%*%(([^)]*)%)%*%*") or ""
    local ok = (tier >= 3 and mark:match("^root")) or (tier == 2 and (mark:match("^admin") or mark:match("^root")))
    if not ok then
      wrong[#wrong + 1] = name .. " (" .. (tier >= 3 and "root" or "admin") .. ", manual: "
        .. (mark ~= "" and mark or "unmarked") .. ")"
    end
  end
end
test("admin and root commands are marked so", #wrong == 0, table.concat(wrong, "; "))

-- 3. Every entry is something you can run, or says it is gone.
local stray = {}
for name, entry in pairs(entries) do
  local inRegistry = reg.entry(name) ~= nil
  local program = firstOf(base .. "../../../usr/bin/" .. name .. ".lua", "usr/bin/" .. name .. ".lua")
  local gone = entry.heading:find("folded into", 1, true) or entry.heading:find("retired", 1, true)
    or entry.heading:find("removed", 1, true)
  if not inRegistry and not program and not gone then stray[#stray + 1] = name end
end
table.sort(stray)
test("every entry is a command, a /usr/bin program, or marked as gone", #stray == 0, table.concat(stray, ", "))

-- The reference is alphabetical within each letter, as its title says.
local unsorted = {}
for section in (ch .. "\n### "):gmatch("\n### %u\n(.-)\n### ") do
  local prev
  for line in section:gmatch("[^\n]+") do
    local names = heading(line)
    local name = names and names[1]
    if name then
      if prev and name < prev then unsorted[#unsorted + 1] = prev .. " > " .. name end
      prev = name
    end
  end
end
test("entries are alphabetical within each letter", #unsorted == 0, table.concat(unsorted, "; "))

-- ── The release the docs name is the one the OS reports ─────────────
-- "Version bumps and docs stay in sync" is a release rule here, and it
-- was enforced by remembering. /init.lua's _G._TOS carries the number
-- and codename the machine prints at boot and in `about`.
print()
print("--- the release named in the docs ---")
do
  local init = firstOf(base .. "../../../init.lua", "init.lua") or ""
  local ver = init:match('\n%s*version%s*=%s*"([%d%.]+)"')
  local name = init:match('\n%s*codename%s*=%s*"([^"]+)"')
  test("/init.lua names a version and codename", ver ~= nil and name ~= nil)
  local tag = ("v%s \"%s\""):format(tostring(ver), tostring(name))
  local readme = firstOf(base .. "../../../README.md", "README.md") or ""
  local changelog = firstOf(base .. "../../../CHANGELOG.md", "CHANGELOG.md") or ""
  test("README's current release is " .. tag,
    readme:find("Current release: **" .. tag .. "**", 1, true) ~= nil)
  test("MANUAL's title page names " .. tag,
    manual:sub(1, 400):find("Terminal Operating System " .. tag, 1, true) ~= nil)
  test("CHANGELOG has a section for " .. tag,
    changelog:find("\n## " .. tag, 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
