-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: command aliases + `which` resolution     ║
-- ║                                                            ║
-- ║  Three things that must hold for the shell's name lookup:  ║
-- ║                                                            ║
-- ║   1. ALIAS EXPANSION terminates. `alias ls='ls -a'` is the ║
-- ║      single most common alias anyone writes, and naive     ║
-- ║      re-expansion turns it into an infinite loop that      ║
-- ║      hangs the seat. A name expands at most ONCE per       ║
-- ║      chain; chains through other aliases still resolve.    ║
-- ║   2. THE PROFILE SANITIZER refuses alias names that could  ║
-- ║      carry punctuation into the command-name position,     ║
-- ║      and values spanning more than one line.               ║
-- ║   3. resolveProgram HONOURS #SEC H9 — system bins win, and ║
-- ║      PATH entries under /mnt, /tmp, /public, /home, /root  ║
-- ║      are refused so they cannot shadow a system binary.    ║
-- ║      `which` reports what the executor runs by calling     ║
-- ║      this same function, so its rules are pinned here.     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_alias_which.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end
local function joined(parts) return table.concat(parts, " ") end

package.loaded["computer"] = { uptime = function() return 0 end }
package.path = "tos/?.lua;tos/?/init.lua;" .. package.path
local helpers   = require("shell.panels.helpers")
local profile   = require("kernel.profile")
local serialize = require("kernel.serialize")

print("=== alias + which Tests ===\n")

-- ════════════════════════════════════════════════════════════════════
-- 1. Alias expansion (helpers.expandAlias — pure given a cached table)
-- ════════════════════════════════════════════════════════════════════
-- S._aliases is the cache expandAlias reads; setting it directly skips
-- the profile load, which part 2 covers separately.
local function withAliases(map)
  return { _aliases = map }
end

do
  local S = withAliases({ ll = "ls -l", l = "ll" })

  eq("simple alias expands",
    "ls -l", joined(helpers.expandAlias(S, { "ll" })))

  eq("alias keeps the caller's trailing args",
    "ls -l /etc", joined(helpers.expandAlias(S, { "ll", "/etc" })))

  eq("alias chains through another alias",
    "ls -l", joined(helpers.expandAlias(S, { "l" })))
end

do
  -- THE case that matters: expanding `ls` must reach the real `ls`, once.
  local S = withAliases({ ls = "ls -a" })
  eq("self-referential alias expands exactly once",
    "ls -a", joined(helpers.expandAlias(S, { "ls" })))
  eq("self-referential alias keeps args after the flags",
    "ls -a /tos", joined(helpers.expandAlias(S, { "ls", "/tos" })))
end

do
  -- The two features INTERACT, and this is the surprising-looking result
  -- that falls out of them: `ll` expands to `ls -l`, and the head of that
  -- expansion is itself an alias, so it expands too — once. Flags from both
  -- survive, outermost alias last. This matches how bash resolves the same
  -- pair, and it is the direct consequence of chaining being supported at
  -- all; pinning it here so it reads as a decision rather than an accident.
  local S = withAliases({ ll = "ls -l", ls = "ls -a" })
  eq("an expansion's head is itself expanded, once",
    "ls -a -l", joined(helpers.expandAlias(S, { "ll" })))
  eq("...and the caller's args still come last",
    "ls -a -l /etc", joined(helpers.expandAlias(S, { "ll", "/etc" })))
end

do
  -- A two-name cycle must terminate too, not just self-reference.
  local S = withAliases({ a = "b", b = "a" })
  local out = joined(helpers.expandAlias(S, { "a" }))
  test("a->b->a cycle terminates (got '" .. out .. "')",
    out == "a" or out == "b")
end

do
  local S = withAliases({})
  eq("no aliases: parts pass through untouched",
    "ls -l", joined(helpers.expandAlias(S, { "ls", "-l" })))
  eq("empty parts survive an empty alias table",
    "", joined(helpers.expandAlias(S, {})))
end

do
  -- Alias lookup is case-insensitive on the NAME (dispatch lowercases too),
  -- but must not mangle the arguments' case.
  local S = withAliases({ ll = "ls -l" })
  eq("alias name matches case-insensitively",
    "ls -l", joined(helpers.expandAlias(S, { "LL" })))
  eq("argument case is preserved",
    "ls -l /Home/Alice", joined(helpers.expandAlias(S, { "ll", "/Home/Alice" })))
end

-- ════════════════════════════════════════════════════════════════════
-- 2. Profile storage + sanitizer
-- ════════════════════════════════════════════════════════════════════
local disk = {}
profile.init({
  securefs = {
    exists    = function(path) return disk[path] ~= nil end,
    readFile  = function(path) return disk[path] end,
    writeFile = function(path, data) disk[path] = data; return true end,
  },
  serialize = serialize,
})
local sess = { user = "alice", home = "/home/alice" }

do
  local p = profile.load(sess)
  test("fresh profile has an empty alias table", type(p.aliases) == "table")

  p.aliases = { ll = "ls -l" }
  test("saving an alias succeeds", profile.save(p, sess) == true)
  eq("alias survives the round trip", "ls -l", profile.load(sess).aliases.ll)
end

do
  -- Junk written straight to the stub disk must be sanitized on load,
  -- not propagated into the shell's dispatch path.
  disk["/home/alice/.profile.cfg"] = serialize.encode({
    aliases = {
      ok            = "ls -l",
      ["bad name"]  = "ls",          -- space: would split into two tokens
      ["rm;reboot"] = "ls",          -- punctuation in a command-name slot
      ["../etc"]    = "ls",          -- path traversal shape
      multiline     = "ls\nreboot",  -- two commands in one value
      [42]          = "ls",          -- non-string key
      nonstr        = 7,             -- non-string value
    },
  })
  local a = profile.load(sess).aliases
  eq("valid alias survives sanitization", "ls -l", a.ok)
  eq("alias name with a space is dropped", nil, a["bad name"])
  eq("alias name with punctuation is dropped", nil, a["rm;reboot"])
  eq("alias name shaped like a path is dropped", nil, a["../etc"])
  eq("multi-line alias value is dropped", nil, a.multiline)
  eq("non-string alias value is dropped", nil, a.nonstr)
end

do
  -- Names are normalized to lower case on the way IN, so the cache and the
  -- lowercased dispatch name always agree.
  disk["/home/alice/.profile.cfg"] = serialize.encode({ aliases = { LL = "ls -l" } })
  local a = profile.load(sess).aliases
  eq("alias name is stored lower-cased", "ls -l", a.ll)
  eq("original upper-case key is not kept", nil, a.LL)
end

-- ════════════════════════════════════════════════════════════════════
-- 3. External program resolution (#SEC H9)
-- ════════════════════════════════════════════════════════════════════
local function fsWith(files)
  return {
    join   = function(a, b) return (a:sub(-1) == "/") and (a .. b) or (a .. "/" .. b) end,
    exists = function(p) return files[p] == true end,
  }
end

do
  local F = fsWith({ ["/usr/bin/share.lua"] = true })
  local path, source = helpers.resolveProgram(F, "share")
  eq("resolves a .lua program in a system bin", "/usr/bin/share.lua", path)
  eq("reports it as a system-bin hit", "system", source)
end

do
  local F = fsWith({ ["/bin/thing"] = true })
  eq("resolves an extension-less program", "/bin/thing", helpers.resolveProgram(F, "thing"))
end

do
  eq("unknown name resolves to nil", nil, helpers.resolveProgram(fsWith({}), "nosuchprog"))
  eq("empty name resolves to nil", nil, helpers.resolveProgram(fsWith({}), ""))
end

do
  -- /bin precedes /usr/bin in SYSTEM_BIN_DIRS: first hit wins.
  local F = fsWith({ ["/bin/ls.lua"] = true, ["/usr/bin/ls.lua"] = true })
  eq("first system bin dir wins", "/bin/ls.lua", helpers.resolveProgram(F, "ls"))
end

do
  -- The security property: a PATH entry in a user-writable location must
  -- never resolve, even when the file is really there.
  package.loaded["kernel.env"] = {
    read = function() return "/mnt/floppy:/tmp:/home/alice/bin:/public" end,
  }
  local F = fsWith({
    ["/mnt/floppy/ls.lua"]     = true,
    ["/tmp/ls.lua"]            = true,
    ["/home/alice/bin/ls.lua"] = true,
    ["/public/ls.lua"]         = true,
  })
  eq("PATH entries under unsafe roots are refused", nil, helpers.resolveProgram(F, "ls"))

  for _, dir in ipairs({ "/mnt", "/tmp", "/public", "/home", "/root" }) do
    test("dirIsSafe rejects " .. dir .. "/x", helpers.dirIsSafe(dir .. "/x") == false)
    -- The BARE root is the shape a PATH is actually written with, and is
    -- exactly the case the trailing-slash prefix list used to miss.
    test("dirIsSafe rejects bare " .. dir, helpers.dirIsSafe(dir) == false)
    test("dirIsSafe rejects " .. dir .. "/", helpers.dirIsSafe(dir .. "/") == false)
  end
  test("dirIsSafe allows /usr/bin", helpers.dirIsSafe("/usr/bin") == true)
  test("dirIsSafe allows /usr/bin/", helpers.dirIsSafe("/usr/bin/") == true)
  -- A directory that merely starts with the same letters is NOT the
  -- unsafe root and must keep resolving.
  test("dirIsSafe allows /tmpfiles", helpers.dirIsSafe("/tmpfiles") == true)
  test("dirIsSafe rejects an empty entry", helpers.dirIsSafe("") == false)
end

do
  -- A safe PATH entry still resolves, and is reported as a PATH hit so
  -- `which` can say where it came from.
  package.loaded["kernel.env"] = { read = function() return "/opt/bin" end }
  local F = fsWith({ ["/opt/bin/tool.lua"] = true })
  local path, source = helpers.resolveProgram(F, "tool")
  eq("safe PATH entry resolves", "/opt/bin/tool.lua", path)
  eq("reported as a PATH hit", "path", source)
end

do
  -- System bins outrank PATH even when PATH also has the name.
  package.loaded["kernel.env"] = { read = function() return "/opt/bin" end }
  local F = fsWith({ ["/opt/bin/ls.lua"] = true, ["/usr/bin/ls.lua"] = true })
  eq("system bin outranks a safe PATH entry",
    "/usr/bin/ls.lua", helpers.resolveProgram(F, "ls"))
end

-- ════════════════════════════════════════════════════════════════════
print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); os.exit(1) end
print("All tests passed.")
