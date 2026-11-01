-- ╔════════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the installer asks for a language            ║
-- ║                                                                ║
-- ║  The installer is the first thing a new operator reads, and it ║
-- ║  was English only while the OS shipped a Russian catalog. It   ║
-- ║  reads the same catalogs now, and the choice carries over into ║
-- ║  TOS. Lifts the real reader out of install.lua.                ║
-- ╚════════════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_install_language.lua   (from TOS-Dev)

local passed, failed = 0, 0
local function test(name, cond, detail)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. (detail ~= nil and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local h = assert(io.open("install.lua", "rb"))
local src = h:read("a"):gsub("\r\n", "\n"); h:close()
local body = src:match("(local function readCatalogs.-end)%s*%-%-%[%[/TEST%-EXTRACT%]%]")
test("found readCatalogs", body ~= nil)
local readCatalogs = assert(load(body .. "\nreturn readCatalogs", "=readCatalogs", "t", _G))()

local function disk(files)
  return function()
    local names = {}
    for k in pairs(files) do names[#names + 1] = k end
    local i = 0
    return function() i = i + 1; return names[i] end
  end, function(path) return files[path:match("[^/]+$")] end
end

print("=== reading a disk ===")
print()
do
  local list, read = disk({
    ["ru.lang"] = 'return { meta = { code = "ru", name = "Russian" }, strings = { a = "b" } }',
    ["de.lang"] = 'return { strings = {} }',
    ["notes.txt"] = "not a catalog",
    ["bad.lang"] = "this is not lua (",
    ["evil.lang"] = 'return os.exit(1)',
    ["empty.lang"] = "return 5",
  })
  local langs = readCatalogs("/usr/lang", list, read)
  test("English is always first", langs[1].code == "en" and langs[1].strings == nil)
  test("each catalog is listed, sorted", langs[2].code == "de" and langs[3].code == "ru"
    and #langs == 3, #langs)
  test("with its own name", langs[3].name == "Russian")
  test("and a name of last resort", langs[2].name == "de")
  test("its strings came with it", langs[3].strings.a == "b")
  test("a catalog runs with no globals, so it cannot do anything", true)
  local list2, read2 = disk({})
  test("a disk with none offers only English", #readCatalogs("/usr/lang", list2, read2) == 1)
end

print()
print("=== the real catalog ===")
print()
do
  local f = assert(io.open("usr/lang/ru.lang", "rb"))
  local text = f:read("a"); f:close()
  local ru = assert(load(text, "=ru", "t", {}))()
  local seen, missing = 0, {}
  for key in src:gmatch('t%("(install%.[%w_]+)"') do
    seen = seen + 1
    if not ru.strings[key] then missing[#missing + 1] = key end
  end
  test("the installer asks for strings", seen >= 26, seen)
  test("ru.lang has every one", #missing == 0, table.concat(missing, " "))
  for key, value in pairs(ru.strings) do
    if key:sub(1, 8) == "install." then
      if value:find("%%") then test(key .. " carries no format spec", false, value) end
    end
  end
end

print()
print("=== it carries over ===")
print()
test("the choice reaches /etc/tos.cfg", src:find("cfg.language = language", 1, true) ~= nil)
do
  local c = assert(io.open("tos/kernel/i18n.lua", "rb"))
  local i18n = c:read("a"); c:close()
  test("and the OS reads that key", i18n:find('config.get("language")', 1, true) ~= nil)
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
