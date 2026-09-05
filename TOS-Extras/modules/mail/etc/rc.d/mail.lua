-- ╔══════════════════════════════════════════════════════════════╗
-- ║  /etc/rc.d/mail.lua — TOS service shim (mail package)        ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Registers the "mail" handler on the kernel's mesh transport at boot,
-- so store-and-forward delivery works with nobody logged in (the whole
-- point of a mailbox). Without this service the box can still SEND and
-- read its inbox, but arriving mail is dropped un-ACKed and the sender
-- keeps retrying.
--
-- NOTE (cluster lesson): rc.d runs BEFORE the OpenOS compat aliases
-- exist — this shim requires only the package lib, which in turn uses
-- kernel.* modules directly.

local mail = require("mail")

return {
  start = mail.start,
  stop  = mail.stop,
  -- The kernel restart supervisor can ask whether we're still live.
  check = mail.running,
}
