-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: shell.chat input parsing (pure)         ║
-- ║                                                            ║
-- ║  chat.parseInput classifies a typed line (command /        ║
-- ║  directed / broadcast / empty) and chat.resolveTarget      ║
-- ║  maps a peer token to a trusted address. Both are pure, so ║
-- ║  they're tested without a display or network.              ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_chat_parse.lua

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;" .. package.path
-- chat.lua require()s "computer" at load; stub it so the pure helpers load.
package.loaded["computer"] = { uptime = function() return 0 end,
  pullSignal = function() end }
local chat = require("shell.chat")

print("=== shell.chat parse Tests ===")
print()

-- ── parseInput: classification ─────────────────────────────────────
eq("empty line", "empty", chat.parseInput("").kind)
eq("whitespace-only is empty", "empty", chat.parseInput("   ").kind)
eq("nil is empty", "empty", chat.parseInput(nil).kind)

do
  local a = chat.parseInput("/who")
  eq("slash -> command", "command", a.kind)
  eq("command name lowercased", "who", a.name)
end
do
  local a = chat.parseInput("/MAIL bob hi there")
  eq("command name case-folded", "mail", a.name)
  eq("command arg captured", "bob hi there", a.arg)
end
do
  local a = chat.parseInput("bob:hello world")
  eq("peer:msg -> directed", "directed", a.kind)
  eq("directed target", "bob", a.target)
  eq("directed text (colon space trimmed)", "hello world", a.text)
end
do
  local a = chat.parseInput("abc123:multi: colon: msg")
  eq("only first colon splits target", "abc123", a.target)
  eq("rest kept verbatim", "multi: colon: msg", a.text)
end
do
  -- A sentence with a colon but a space before it is NOT directed.
  local a = chat.parseInput("note to self: remember")
  eq("space before colon -> broadcast", "broadcast", a.kind)
  eq("broadcast keeps the whole line", "note to self: remember", a.text)
end
do
  local a = chat.parseInput("just a normal message")
  eq("plain text -> broadcast", "broadcast", a.kind)
end

-- ── resolveTarget: prefix + hostname, level-gated ──────────────────
local TRUSTED = 3
local peers = {
  { address = "ab12cd34ef", hostname = "alpha",  level = 3 },
  { address = "ff00aa11bb", hostname = "bravo",  level = 3 },
  { address = "9911223344", hostname = "charlie", level = 1 },  -- only KNOWN
}
eq("resolve by address prefix", "ab12cd34ef", chat.resolveTarget(peers, "ab12", TRUSTED))
eq("resolve by exact hostname", "ff00aa11bb", chat.resolveTarget(peers, "bravo", TRUSTED))
test("untrusted peer not resolved", chat.resolveTarget(peers, "charlie", TRUSTED) == nil)
test("unknown token -> nil", chat.resolveTarget(peers, "zzz", TRUSTED) == nil)
test("empty target -> nil", chat.resolveTarget(peers, "", TRUSTED) == nil)
-- Below the gate, the KNOWN peer resolves.
eq("lower gate resolves KNOWN peer", "9911223344", chat.resolveTarget(peers, "charlie", 1))

-- ── Groups: the multi-operator addressing mode ─────────────────────
print()
do
  local a = chat.parseInput("@ops:status report")
  eq("@group:msg -> group", "group", a.kind)
  eq("group name", "ops", a.group)
  eq("group text", "status report", a.text)
end
do
  local a = chat.parseInput("@NIGHT-SHIFT:handover done")
  eq("group name case-folded", "night-shift", a.group)
  eq("hyphens allowed in group names", "group", a.kind)
end
-- The ordering that matters: a group must NOT fall through to `directed`,
-- where it would be looked up as a peer literally named "@ops" and fail
-- with a message about peers instead of groups.
do
  local a = chat.parseInput("@ops:hi")
  test("group is not misparsed as a peer", a.kind == "group" and a.target == nil)
end
-- An @ that isn't the group form stays whatever it was.
eq("@ with no colon is a broadcast", "broadcast", chat.parseInput("@ops hello").kind)
eq("email-ish text stays broadcast", "broadcast",
  chat.parseInput("mail me at bob@example").kind)
do
  local a = chat.parseInput("bob:hello")
  eq("plain peer still directed", "directed", a.kind)
end

-- validGroupName
test("simple name valid", chat.validGroupName("ops"))
test("digits and _- valid", chat.validGroupName("night_shift-2"))
test("empty invalid", not chat.validGroupName(""))
test("spaces invalid", not chat.validGroupName("night shift"))
test("punctuation invalid", not chat.validGroupName("ops!"))
test("over-long invalid", not chat.validGroupName(string.rep("x", 25)))
test("non-string invalid", not chat.validGroupName(nil))

-- normalizeGroups: lowercase, dedupe, drop malformed, keep empties
do
  local n = chat.normalizeGroups({
    OPS = { "alpha", "bravo", "alpha" },     -- dupe
    ["bad name"] = { "x" },                  -- invalid name
    engineers = { "charlie", 42, "" },       -- non-string + empty member
    empty = {},                              -- legal: created, not yet filled
    nope = "not a table",
  })
  test("name lowercased", n.ops ~= nil)
  eq("duplicate member dropped", 2, #n.ops)
  test("invalid group name dropped", n["bad name"] == nil)
  eq("non-string members dropped", 1, #n.engineers)
  test("empty group is KEPT (create-then-add is normal)", n.empty ~= nil)
  eq("empty group has no members", 0, #n.empty)
  test("non-table value dropped", n.nope == nil)
end
do
  local n = chat.normalizeGroups(nil)
  test("nil input -> empty table, not nil", type(n) == "table")
  local many = {}
  for i = 1, chat.MAX_MEMBERS + 10 do many[i] = "peer" .. i end
  local capped = chat.normalizeGroups({ big = many })
  eq("members capped", chat.MAX_MEMBERS, #capped.big)
end

-- resolveGroup: trusted addresses out, unreachable members NAMED
do
  local groups = chat.normalizeGroups({
    ops    = { "alpha", "bravo" },
    mixed  = { "alpha", "charlie", "ghost" },   -- charlie=KNOWN only, ghost=absent
  })
  local addrs, missing = chat.resolveGroup(groups, "ops", peers, TRUSTED)
  eq("group resolves both members", 2, #addrs)
  eq("resolved to addresses", "ab12cd34ef", addrs[1])
  eq("nothing missing", 0, #missing)

  addrs, missing = chat.resolveGroup(groups, "mixed", peers, TRUSTED)
  eq("only trusted members resolve", 1, #addrs)
  -- The important half: an operator must be told their message did NOT
  -- reach everyone, rather than the group silently shrinking.
  eq("unreachable members are reported", 2, #missing)

  test("unknown group -> nil", chat.resolveGroup(groups, "nope", peers, TRUSTED) == nil)
  eq("group lookup is case-insensitive", 2,
    #(chat.resolveGroup(groups, "OPS", peers, TRUSTED)))
end
do
  -- Two members that resolve to the SAME peer must not double-send.
  local groups = chat.normalizeGroups({ dup = { "alpha", "ab12" } })
  local addrs = chat.resolveGroup(groups, "dup", peers, TRUSTED)
  eq("same peer named twice sends once", 1, #addrs)
end

-- Save/load round-trip through injected fs + serializer.
do
  local serialize
  for _, p in ipairs({ "tos/kernel/serialize.lua", "../../../tos/kernel/serialize.lua" }) do
    local c = loadfile(p); if c then serialize = c(); break end
  end
  test("serialize loaded for the round-trip", serialize ~= nil)
  if serialize then
    local files = {}
    local fsStub = {
      exists = function(p) return files[p] ~= nil end,
      readFile = function(p) return files[p] end,
      writeFile = function(p, c) files[p] = c; return true end,
      writeFileAtomic = function(p, c) files[p] = c; return true end,
    }
    eq("no file -> empty table", 0,
      (function() local n = 0
        for _ in pairs(chat.loadGroups(fsStub, serialize)) do n = n + 1 end
        return n end)())
    chat.saveGroups(fsStub, serialize, { OPS = { "alpha", "alpha", "bravo" } })
    local back = chat.loadGroups(fsStub, serialize)
    test("group survives the round-trip", back.ops ~= nil)
    eq("...normalized on the way out too", 2, #back.ops)
    test("written to the documented path", files[chat.GROUPS_PATH] ~= nil)
    -- A corrupt file must read as "no groups", not crash the chat tab.
    files[chat.GROUPS_PATH] = "{{{ not lua"
    eq("corrupt file -> empty, no error", 0,
      (function() local n = 0
        for _ in pairs(chat.loadGroups(fsStub, serialize)) do n = n + 1 end
        return n end)())
  end
end

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
