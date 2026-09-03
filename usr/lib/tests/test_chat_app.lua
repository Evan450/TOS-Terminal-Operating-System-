-- ╔══════════════════════════════════════════════════════════╗
-- ║  Regression Test: Chat app tab (shell.panels.chatapp)      ║
-- ║                                                            ║
-- ║  Chat as a persistent tab: the NM.on(MSG) listener keeps   ║
-- ║  receiving while the tab is backgrounded (unread badge),   ║
-- ║  the TRUSTED gate + ack survive the port from the old TUI, ║
-- ║  send paths (broadcast/directed/slash) reuse shell.chat's  ║
-- ║  pure helpers, and closing the tab unregisters the         ║
-- ║  listener via the tabs.close onClose lifecycle hook.       ║
-- ╚══════════════════════════════════════════════════════════╝
-- Run: lua usr/lib/tests/test_chat_app.lua   (from the TOS-Dev root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

package.path = "tos/?.lua;../../../tos/?.lua;TOS-Dev/tos/?.lua;" .. package.path
package.loaded["computer"] = {
  uptime = function() return 42 end,
  pullSignal = function() return "key_down", "kb", 17, 16 end,  -- ^Q: cancels prompts
}

local chatApp = require("shell.panels.chatapp")

-- ── Network stub ───────────────────────────────────────────────────
local sent, acks, mailQueued = {}, {}, {}
local listener = { cb = nil, onCalls = 0, offCalls = 0 }
local TRUST = {
  LEVEL = { TRUSTED = 2 },
  listPeers = function()
    return {
      { address = "aaaa1111", hostname = "alpha", level = 2 },
      { address = "bbbb2222", hostname = "beta",  level = 1 },  -- not trusted
    }
  end,
  getLevel = function(addr) return addr == "aaaa1111" and 2 or 0 end,
  getPeer = function(addr)
    return addr == "aaaa1111" and { hostname = "alpha" } or nil
  end,
}
local NM = {
  getProtocol = function()
    return { TYPE = { MSG = "MSG", MSG_ACK = "MSG_ACK" },
      makePacket = function(t, payload, opts) return { type = t, to = opts and opts.to } end }
  end,
  getTrust = function() return TRUST end,
  getHostname = function() return "myhost" end,
  on = function(t, cb) listener.cb = cb; listener.onCalls = listener.onCalls + 1; return 7 end,
  off = function(t, id) listener.offCalls = listener.offCalls + 1 end,
  send = function(addr, pkt) acks[#acks + 1] = { addr = addr, pkt = pkt } end,
  sendMessage = function(addr, text) sent[#sent + 1] = { addr = addr, text = text }; return true end,
}

-- Stage 5: mail is an ADD-ON, so chat's /mail bridge pcall-requires the
-- package lib instead of calling NM.sendMail. Stub it as "installed".
package.loaded["mail"] = {
  send = function(m) mailQueued[#mailQueued + 1] = m; return "id1", true end,
}

local function newS()
  return {
    D = { set = function() end, fill = function() end },
    T = { fg = 1, bg = 2, dim = 3, title = 4, highlight = 5, warning = 6,
          error = 7, border = 8, sel_fg = 9, sel_bg = 10 },
    W = 80, H = 25, who = "root", NM = NM,
    tabs = { { type = "shell", label = "Shell" } },
    activeTab = 1,
  }
end

print("=== Chat app tab Tests ===")
print()

-- ── open: tab + listener ───────────────────────────────────────────
local S = newS()
local tab = chatApp.open(S)
eq("open creates a chat tab", "chat", tab.type)
eq("open focuses it", 2, S.activeTab)
eq("listener registered once", 1, listener.onCalls)
test("welcome lines present", #tab.messages > 0)
chatApp.open(S)
eq("second open reuses (no second listener)", 1, listener.onCalls)

-- ── incoming: trusted gate, ack, unread badge when backgrounded ────
S.activeTab = 1                       -- switch away from the chat tab
local before = #tab.messages
listener.cb({ payload = { text = "hello there" } }, "aaaa1111")
eq("trusted message appended", before + 1, #tab.messages)
test("message names the sender", tab.messages[#tab.messages].text:find("alpha", 1, true) ~= nil)
eq("ack sent back", 1, #acks)
eq("unread badge while backgrounded", 1, tab.unread)
eq("label carries the badge", "Chat(1)", tab.label)
test("dirty flagged for the tick repaint", tab._dirty == true)

listener.cb({ payload = { text = "spoof" } }, "bbbb2222")
eq("untrusted message ignored", before + 1, #tab.messages)

-- ── draw clears the badge ──────────────────────────────────────────
S.activeTab = 2
chatApp.draw(S, tab)
eq("draw resets unread", 0, tab.unread)
eq("draw resets the label", "Chat", tab.label)
test("draw clears dirty", tab._dirty == false)

-- ── tick: dirty-driven repaint ─────────────────────────────────────
tab._dirty = true
eq("tick repaints when dirty", 3, chatApp.tick(S, tab))
tab._dirty = false
eq("tick idles when clean", 0, chatApp.tick(S, tab))

-- ── sending ────────────────────────────────────────────────────────
local function typeLine(str)
  for i = 1, #str do chatApp.handleKey(S, tab, str:byte(i), 0) end
  chatApp.handleKey(S, tab, 13, 28)   -- Enter
end

sent = {}
typeLine("hello everyone")
eq("broadcast goes to trusted peers only", 1, #sent)
eq("broadcast target", "aaaa1111", sent[1].addr)
test("own line echoed", tab.messages[#tab.messages].text:find("myhost", 1, true) ~= nil)

-- ── A refused broadcast must NOT look delivered ────────────────────
-- Bug from the emulator: two boxes were elevated to TRUSTED by hand,
-- which provisions no shared secret, so net.send refused to downgrade to
-- plaintext and returned false. chat's broadcast branch discarded that
-- result and echoed the operator's own line anyway, so the message
-- looked sent. The reason existed only in kernel.log:
--   "Refusing plaintext send to TRUSTED peer ...: no shared secret"
do
  local REFUSAL = "TRUSTED peer has no shared secret; refusing plaintext send"
  local realSend = NM.sendMessage
  NM.sendMessage = function() return false, REFUSAL end
  local before = #tab.messages
  sent = {}
  typeLine("did this go?")

  local shown = {}
  for i = before + 1, #tab.messages do shown[#shown + 1] = tab.messages[i].text end
  local blob = table.concat(shown, " | ")

  test("a wholly refused broadcast is not echoed as sent",
    blob:find("did this go?", 1, true) == nil)
  test("the failure is reported", blob:find("0 of 1", 1, true) ~= nil)
  test("...with the reason", blob:find("shared secret", 1, true) ~= nil)
  test("...and the actionable command", blob:find("net trust gen", 1, true) ~= nil)

  NM.sendMessage = realSend
end

sent = {}
typeLine("alpha:psst")
eq("directed send", 1, #sent)
eq("directed resolves hostname to address", "aaaa1111", sent[1].addr)
eq("directed text", "psst", sent[1].text)

sent = {}
typeLine("beta:psst")
eq("directed to UNTRUSTED peer refused", 0, #sent)
test("and explained", tab.messages[#tab.messages].text:find("Unknown peer", 1, true) ~= nil)

typeLine("/mail alpha remember the milk")
eq("/mail bridges to the mail add-on", 1, #mailQueued)
eq("/mail recipient resolved", "aaaa1111", mailQueued[1].to)
eq("/mail carries the chat line as the body", "remember the milk", mailQueued[1].body)

-- Without the add-on installed, the bridge degrades gracefully instead of
-- erroring (the transport is base, but mailbox semantics are the package's).
do
  local savedMail = package.loaded["mail"]
  package.loaded["mail"] = nil
  local before = #mailQueued
  typeLine("/mail alpha still there?")
  eq("no add-on -> nothing queued", before, #mailQueued)
  test("no add-on -> an install hint, not a crash",
    tab.messages[#tab.messages].text:find("not installed", 1, true) ~= nil)
  package.loaded["mail"] = savedMail
end

typeLine("/clear")
eq("/clear empties history", 0, #tab.messages)
typeLine("/zzz")
test("unknown slash command warns",
  tab.messages[#tab.messages].text:find("Unknown command", 1, true) ~= nil)

-- ── backspace edits ────────────────────────────────────────────────
tab.input = ""
chatApp.handleKey(S, tab, 97, 30)     -- 'a'
chatApp.handleKey(S, tab, 98, 48)     -- 'b'
chatApp.handleKey(S, tab, 0, 14)      -- Backspace
eq("backspace edits the buffer", "a", tab.input)
tab.input = ""

-- ── close: ^Q unregisters via the tabs.close onClose hook ──────────
S.activeTab = 2
chatApp.handleKey(S, tab, 17, 16)     -- Ctrl+Q
eq("tab closed", 1, #S.tabs)
eq("listener unregistered on close", 1, listener.offCalls)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed.") end
return true
