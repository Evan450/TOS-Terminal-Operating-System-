-- ╔══════════════════════════════════════════════════════════════╗
-- ║  Regression Test: the mail PACKAGE (stage 5)                 ║
-- ║                                                              ║
-- ║  Mail left the base image: the kernel owns the generic mesh  ║
-- ║  TRANSPORT (tested by TOS-Dev's test_meshctl) and this       ║
-- ║  package owns mailbox semantics + the UIs. Covers:           ║
-- ║   • pure helpers (senderName / inboxRow / resolveRecipient)  ║
-- ║   • Mailbox: add + id de-dup + prune + unread/read/delete    ║
-- ║   • the delivery handler: mesh message -> inbox record, and  ║
-- ║     ACK-worthiness (true only when actually stored)          ║
-- ║   • #SEC inbox access is principal-enforced (owner/ADMIN+),  ║
-- ║     not caller-claimed                                       ║
-- ║   • send(): rides net.meshSend, forwards refuse-plaintext,   ║
-- ║     auto-allows the "*" bulletin                             ║
-- ║   • start/stop register + unregister the mesh handler        ║
-- ║   • the panels Mail TAB (list/read/delete/badge/compose)     ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Run: lua modules/mail/test_mail.lua   (from the TOS-Extras root)

local passed, failed = 0, 0
local function test(name, cond)
  if cond then passed = passed + 1; print("  PASS: " .. name)
  else failed = failed + 1; print("  FAIL: " .. name) end
end
local function eq(name, expected, actual)
  test(name .. "  (got " .. tostring(actual) .. ")", expected == actual)
end

-- ── Resolve paths: package libs + the base kernel's serialize ──────
local HERE = "modules/mail/usr/lib/"
package.path = HERE .. "?.lua;" .. package.path

local serialize
for _, p in ipairs({ "../TOS-Dev/tos/kernel/serialize.lua", "../tos/kernel/serialize.lua",
                     "TOS-Dev/tos/kernel/serialize.lua",
                     "../../TOS-Dev/tos/kernel/serialize.lua" }) do
  local chunk = loadfile(p)
  if chunk then serialize = chunk(); break end
end
if not serialize then
  print("FAIL: could not load TOS-Dev's kernel/serialize.lua")
  print("Results: 0 passed, 1 failed"); print("*** TESTS FAILED ***"); return false
end
package.loaded["kernel.serialize"] = serialize

-- ── Kernel stubs ───────────────────────────────────────────────────
local FS = {}            -- path -> content (in-memory disk)
local dirs = {}
package.loaded["kernel.fs"] = {
  exists = function(p) return FS[p] ~= nil or dirs[p] == true end,
  readFile = function(p) return FS[p] end,
  writeFile = function(p, d) FS[p] = d; return true end,
  makeDirectory = function(p) dirs[p] = true; return true end,
}
package.loaded["kernel.log"] = {
  info = function() end, warn = function() end, error = function() end,
}

local meshSends, meshHandlers = {}, {}
local MESH_UP = true
package.loaded["kernel.net"] = {
  meshAvailable = function() return MESH_UP end,
  meshSend = function(opts)
    meshSends[#meshSends + 1] = opts
    -- Mirror the real transport's refuse-plaintext contract.
    local unicast = opts.to ~= nil and opts.to ~= "*"
    local paired  = (opts.to == "PAIRED")
    if not paired and not opts.allowPlaintext then
      return nil, unicast and "no shared secret with " .. tostring(opts.to)
        or "broadcasts can't be sealed"
    end
    return "id-" .. #meshSends, paired
  end,
  meshOn  = function(svc, fn) meshHandlers[svc] = fn; return true end,
  meshOff = function(svc) meshHandlers[svc] = nil end,
  meshPending = function() return 0 end,
  meshTick = function() end,
}

-- Principal stub: the "logged in" user the lib should enforce against.
local CURRENT = { user = "alice", tier = 1 }
package.loaded["kernel.users"] = {
  currentSession = function() return CURRENT end,
}

local mail = require("mail")

print("=== mail package Tests ===")
print()

-- ── Pure helpers ───────────────────────────────────────────────────
eq("senderName uses fromUser", "alice",
  mail.senderName({ fromUser = "alice", from = "3f8a1c2d99" }))
eq("senderName falls back to a short address", "3f8a1c2d",
  mail.senderName({ from = "3f8a1c2d99" }))
eq("senderName survives junk", "?", mail.senderName(nil))

do
  local row = mail.inboxRow({ fromUser = "bob", subject = "hi", read = false }, 3, 60)
  test("inboxRow marks unread with *", row:find("%*") ~= nil)
  test("inboxRow carries index + sender + subject",
    row:find("3") and row:find("bob") and row:find("hi"))
  local readRow = mail.inboxRow({ fromUser = "bob", subject = "hi", read = true }, 3, 60)
  test("inboxRow leaves read mail unmarked", readRow:find("%*") == nil)
  local long = mail.inboxRow({ fromUser = "bob", subject = string.rep("x", 200) }, 1, 40)
  test("inboxRow truncates to width", #long <= 40)
end

do
  local addr, user = mail.resolveRecipient("carol@node7", function(h)
    return h == "node7" and "ADDR7" or nil end)
  eq("resolveRecipient splits user@host", "carol", user)
  eq("resolveRecipient resolves the host alias", "ADDR7", addr)
  local a2, u2 = mail.resolveRecipient("*")
  eq("resolveRecipient passes the bulletin through", "*", a2)
  eq("bulletin has no user part", nil, u2)
  local a3 = mail.resolveRecipient("rawaddr", function() return nil end)
  eq("unresolvable alias falls back to the literal", "rawaddr", a3)
end

-- ── Mailbox semantics ──────────────────────────────────────────────
do
  local mem = {}
  local box = mail.newMailbox({
    exists = function(p) return mem[p] ~= nil end,
    read = function(p) return mem[p] end,
    write = function(p, d) mem[p] = d; return true end,
  }, "/box.dat")

  eq("empty box lists nothing", 0, #box:list())
  test("add stores", box:add({ id = "m1", subject = "one" }))
  test("add de-dups by id", box:add({ id = "m1", subject = "one again" }) == false)
  eq("one message after the duplicate", 1, #box:list())
  eq("new mail arrives unread", 1, box:unread())
  box:add({ id = "m2", subject = "two" })
  eq("markRead marks it", true, box:markRead(1))
  eq("unread count drops", 1, box:unread())
  eq("delete removes", true, box:delete(1))
  eq("list shrank", 1, #box:list())
  eq("survivor is the right one", "two", box:get(1).subject)
  test("delete past the end is refused", box:delete(99) == false)

  -- Persistence: a fresh Mailbox over the same store sees the writes.
  local box2 = mail.newMailbox({
    exists = function(p) return mem[p] ~= nil end,
    read = function(p) return mem[p] end,
    write = function(p, d) mem[p] = d; return true end,
  }, "/box.dat")
  eq("a reopened box loads persisted mail", 1, #box2:list())
  eq("persisted subject round-trips", "two", box2:get(1).subject)
end

do
  -- Pruning keeps the box bounded (oldest dropped).
  local mem = {}
  local box = mail.newMailbox({
    exists = function(p) return mem[p] ~= nil end,
    read = function(p) return mem[p] end,
    write = function(p, d) mem[p] = d; return true end,
  }, "/p.dat")
  for i = 1, mail.MAX_BOX + 5 do box:add({ id = "x" .. i, subject = "s" .. i }) end
  eq("box prunes to MAX_BOX", mail.MAX_BOX, #box:list())
  eq("the OLDEST entries were dropped", "s6", box:get(1).subject)
end

-- ── Delivery handler (mesh message -> inbox record) ────────────────
do
  FS, dirs = {}, {}
  local msg = {
    id = "d1", from = "PEERADDR", fromUser = "bob", to = "ME", user = "alice",
    payload = { subject = "Hello", body = "body text" },
    ts = 99, sealed = true, readable = true, how = "sealed",
  }
  eq("delivery stores and reports ACK-worthy", true, mail._onMeshMail(msg))
  eq("a re-flood of the same id is NOT re-stored", false, mail._onMeshMail(msg))

  local box = mail.inboxBox("alice")
  local m = box and box:get(1)
  test("the record landed in the recipient's box", m ~= nil)
  eq("subject taken from the payload", "Hello", m and m.subject)
  eq("body taken from the payload", "body text", m and m.body)
  eq("sender carried", "bob", m and m.fromUser)
  eq("sealed flag carried", true, m and m.sealed)
  eq("arrives unread", false, m and m.read)
  test("stored under /var/mail/<user>/", FS["/var/mail/alice/inbox.dat"] ~= nil)

  -- An unopenable (sealed, no key) delivery still stores, honestly labelled.
  local sealedMsg = {
    id = "d2", from = "P", user = "alice", payload = nil,
    sealed = true, readable = false, how = "sealed but no secret",
  }
  eq("unopenable mail is still stored", true, mail._onMeshMail(sealedMsg))
  local m2 = mail.inboxBox("alice"):get(2)
  eq("unopenable mail is marked unreadable", false, m2 and m2.readable)
  eq("unopenable mail gets a placeholder subject", "(unreadable)", m2 and m2.subject)

  -- A username that tries to escape /var/mail is sanitised.
  mail._onMeshMail({ id = "d3", from = "P", user = "../../etc/evil",
    payload = { subject = "x", body = "y" } })
  test("a traversal username is sanitised, not honoured",
    FS["/var/mail/.._.._etc_evil/inbox.dat"] ~= nil)
  test("nothing was written outside /var/mail", (function()
    for p in pairs(FS) do
      if p:sub(1, 10) ~= "/var/mail/" then return false end
    end
    return true
  end)())
end

-- ── #SEC inbox access is principal-enforced ────────────────────────
do
  FS, dirs = {}, {}
  mail._onMeshMail({ id = "s1", from = "P", user = "alice",
    payload = { subject = "for alice", body = "" } })
  mail._onMeshMail({ id = "s2", from = "P", user = "bob",
    payload = { subject = "for bob", body = "" } })

  CURRENT = { user = "alice", tier = 1 }
  test("owner may open their own inbox", mail.inboxBox("alice") ~= nil)
  local box, err = mail.inboxBox("bob")
  test("a USER may NOT open someone else's inbox", box == nil)
  test("the refusal explains why",
    type(err) == "string" and err:find("owner") ~= nil)
  local list, lerr = mail.inbox("bob")
  test("inbox() refuses the same way", list == nil and lerr ~= nil)

  CURRENT = { user = "carol", tier = 2 }         -- ADMIN
  test("ADMIN may open any inbox", mail.inboxBox("bob") ~= nil)

  CURRENT = { user = "dave", tier = 0 }          -- guest
  test("a guest may not open another inbox", mail.inboxBox("alice") == nil)

  CURRENT = nil                                   -- no session at all
  test("no session -> fail closed", mail.inboxBox("alice") == nil)
  CURRENT = { user = "alice", tier = 1 }
end

-- ── send(): transport passthrough + plaintext policy ───────────────
do
  meshSends = {}
  local id, sealed = mail.send({ to = "PAIRED", user = "bob", fromUser = "alice",
    subject = "hi", body = "there" })
  test("a paired unicast send succeeds", id ~= nil)
  eq("and reports sealed", true, sealed)
  local sent = meshSends[#meshSends]
  eq("rides the mesh as service 'mail'", "mail", sent.svc)
  eq("subject travels in the payload", "hi", sent.payload.subject)
  eq("body travels in the payload", "there", sent.payload.body)
  test("no allowPlaintext was requested for a normal send",
    sent.allowPlaintext == nil)

  local id2, err2 = mail.send({ to = "STRANGER", subject = "x", body = "y" })
  test("an UNPAIRED unicast send is refused by the transport", id2 == nil)
  test("the refusal is surfaced to the caller", type(err2) == "string")

  local id3 = mail.send({ to = "*", subject = "notice", body = "all hands" })
  test("a '*' bulletin sends (public by definition)", id3 ~= nil)
  eq("the bulletin explicitly opted into plaintext", true,
    meshSends[#meshSends].allowPlaintext)

  local long = mail.send({ to = "PAIRED", subject = string.rep("s", 500),
    body = string.rep("b", 99999) })
  test("oversize content is truncated, not rejected", long ~= nil)
  eq("subject capped", mail.MAX_SUBJECT, #meshSends[#meshSends].payload.subject)
  eq("body capped", mail.MAX_BODY, #meshSends[#meshSends].payload.body)
end

-- ── Service lifecycle ──────────────────────────────────────────────
do
  meshHandlers = {}
  eq("not running before start", false, mail.running())
  eq("start registers the mesh handler", true, mail.start())
  test("the 'mail' kind now has a handler", meshHandlers["mail"] ~= nil)
  eq("running() reports it", true, mail.running())
  eq("start is idempotent", true, mail.start())
  eq("stop unregisters", true, mail.stop())
  test("the handler is gone", meshHandlers["mail"] == nil)
  eq("running() reports stopped", false, mail.running())

  MESH_UP = false
  local ok, why = mail.start()
  test("start fails cleanly with no network", ok == false)
  test("and explains", type(why) == "string" and why:find("mesh") ~= nil)
  MESH_UP = true
end

-- ── The panels Mail TAB ────────────────────────────────────────────
-- Stub the shell toolkit the app draws with (it runs inside panels).
package.loaded["computer"] = {
  uptime = function() return 0 end,
  -- Compose's blocking field reader pulls signals; feed ^Q so any compose
  -- entered during the test cancels immediately.
  pullSignal = function() return "key_down", "kb", 17, 16 end,
}
package.loaded["shell.panels.ui"] = {
  drawRail = function() end, drawRampBar = function() end,
}
package.loaded["shell.panels.tabs"] = {
  find = function(S, t)
    for i, tab in ipairs(S.tabs) do if tab.type == t then return i end end
  end,
  create = function(S, t, label, data)
    local tab = data or {}
    tab.type, tab.label = t, label
    S.tabs[#S.tabs + 1] = tab
    S.activeTab = #S.tabs
    return tab
  end,
  close = function(S, idx)
    table.remove(S.tabs, idx or S.activeTab)
    S.activeTab = 1
  end,
}

local mailApp = require("mailapp")

FS, dirs = {}, {}
CURRENT = { user = "root", tier = 3 }
mail._onMeshMail({ id = "t1", from = "aaaa1111", fromUser = "alice", user = "root",
  payload = { subject = "hi", body = "line1\nline2" } })
mail._onMeshMail({ id = "t2", from = "bbbb2222", fromUser = "bob", user = "root",
  payload = { subject = "yo", body = "b" } })

local function newS()
  return {
    D = { set = function() end, fill = function() end },
    T = { fg = 1, bg = 2, dim = 3, title = 4, highlight = 5, warning = 6,
          error = 7, sel_fg = 8, sel_bg = 9 },
    W = 80, H = 25, who = "root", NM = {},
    tabs = { { type = "shell", label = "Shell" } },
    activeTab = 1,
  }
end

local S = newS()
local tab = mailApp.open(S)
eq("open creates a mail tab", "mail", tab.type)
eq("open focuses it", 2, S.activeTab)
eq("active tab label carries NO badge (you're looking at it)", "Mail", tab.label)

S.activeTab = 1
mailApp.refresh(S, tab)
eq("backgrounded refresh shows the unread badge", "Mail(2)", tab.label)
S.activeTab = 2
mailApp.draw(S, tab)
eq("draw clears the badge", "Mail", tab.label)

eq("starts in list mode", "list", tab.mode)
mailApp.handleKey(S, tab, nil, 208)          -- Down
eq("down moves selection", 2, tab.sel)
mailApp.handleKey(S, tab, nil, 199)          -- Home
eq("home returns to 1", 1, tab.sel)
mailApp.handleKey(S, tab, 13, 28)            -- Enter = read
eq("enter opens read mode", "read", tab.mode)
eq("opening marks it read", true, mail.inboxBox("root"):get(1).read)
test("body lines wrapped in", #tab.bodyLines >= 4)
mailApp.handleKey(S, tab, 113, nil)          -- q = back
eq("q returns to the list", "list", tab.mode)

tab.sel = 2
mailApp.handleKey(S, tab, 100, nil)          -- d = delete
eq("delete removed one", 1, #mail.inboxBox("root"):list())

local okC = pcall(mailApp.handleKey, S, tab, 99, nil)   -- c = compose (^Q cancels)
test("compose with immediate ^Q cancels without error", okC)
eq("still in list mode after cancel", "list", tab.mode)

mailApp.handleClick(S, tab, { y = 4, button = 0 })   -- first row (LIST_TOP=4)
eq("click selects the row under it", 1, tab.sel)
eq("tick repaints the list", 3, mailApp.tick(S, tab))
tab.mode = "read"
eq("tick leaves the read view alone", 0, mailApp.tick(S, tab))

tab.mode = "list"
S.activeTab = 2
mailApp.handleKey(S, tab, 17, 16)
eq("Ctrl+Q closes the mail tab", 1, #S.tabs)

print()
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then print("*** TESTS FAILED ***"); return false
else print("All tests passed."); return true end
