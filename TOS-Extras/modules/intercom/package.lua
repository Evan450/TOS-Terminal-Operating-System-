-- Optional Utilities — Intercom (facility announcement system).
--
-- A tape drive holds recorded announcements; this package makes them
-- usable. The operator catalogs what is on the tape and where, in the
-- notation they'd jot down anyway:
--
--   fuel-low  [0001] "Warning: Reactor fuel low." [0005]  warn
--
-- `intercom play fuel-low` then seeks the tape to 0001, plays it, stops at
-- 0005, and simultaneously sends those same WORDS over the mesh to every
-- machine willing to hear them — where they land in chat, and (at alert
-- severity or above) raise a message box, rate-limited by a cooldown so an
-- alarm storm can't lock an operator out of their own computer.
--
-- The tape is OPTIONAL. `intercom say "we are out of iron" --severity warn`
-- is a text-only announcement and needs no drive at all; the tape adds a
-- voice to the ones you recorded.
--
-- FULL-PRIV package (mail/blockfs precedent): the library lives in /usr/lib
-- and is loaded by the base shell + rc via the real require, so it may use
-- kernel.net / kernel.fs / kernel.event. The base image keeps a thin
-- `intercom` command stub that pcall-requires this package and prints an
-- install hint when it's absent — exactly how `drive` relates to blockfs.
return {
  name        = "intercom",
  version     = "1.0.0",
  kind        = "service",
  category    = "network",
  description = "Announcement system: plays cataloged tape messages and broadcasts the same words to the network.",
  author      = "Strata Systems",
  files       = {
    "/usr/lib/intercom.lua",     -- catalog, tape playback, mesh send/receive
    "/usr/lib/intercomapp.lua",  -- panels tab (the app registry picks it up)
    "/etc/rc.d/intercom.lua",    -- boot service: register the mesh handler
  },
  -- No sandboxed command entrypoints: the base `intercom` command stub
  -- drives this library with the shell's own display + session context.
  commands     = {},
  capabilities = {},
  requires     = {},
  -- Soft suggestion. The Intercom PLAYS a tape it doesn't know how to make:
  -- `tape` is the package for inspecting, labelling and managing the tape
  -- your announcements are recorded on. Not needed to announce text.
  recommends   = { "tape" },
  -- Hearing announcements means accepting flooded messages from trusted
  -- peers that can raise a modal on your screen — an operator decision, so
  -- it starts OFF. `service start intercom` enables it and persists that.
  service      = { defaultState = "disabled" },
}
