-- ╔══════════════════════════════════════════════════════════════╗
-- ║  /etc/rc.d/intercom.lua — TOS service shim (intercom package) ║
-- ╚══════════════════════════════════════════════════════════════╝
-- Registers the "intercom" handler on the kernel's mesh transport at boot,
-- so announcements are heard with nobody logged in — which is the normal
-- state of a machine sitting in a corridor being an announcement speaker.
--
-- This service IS the "so long as they're willing to hear it" switch. A box
-- without it running still RELAYS announcements for its trusted neighbours
-- (relaying is the transport's job), it just doesn't listen to them itself.
-- It ships disabled: accepting messages that can raise a modal on your
-- screen is an operator decision, not a default.
--
-- NOTE (cluster lesson): rc.d runs BEFORE the OpenOS compat aliases exist —
-- this shim requires only the package lib, which uses kernel.* directly.

local intercom = require("intercom")

return {
  start = intercom.start,
  stop  = intercom.stop,
  -- The kernel restart supervisor can ask whether we're still live.
  check = intercom.running,
}
