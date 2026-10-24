-- Optional Utilities — printer driver (OpenPrinter).
--
-- TOS has no baked-in printer support, the same way it has no baked-in
-- mouse support: this is the DOS-style driver you install when the base
-- actually has the hardware. It targets PC-Logix's OpenPrinter addon
-- (the `openprinter` component), which is the OC printer people actually
-- have — OpenComputers' own printer3d is a 3D model printer and a
-- different device entirely.
--
-- TWO LIBRARIES, and the split is load-bearing:
--   /usr/lib/printerfmt.lua  PURE layout — measuring, wrapping,
--                            paginating, costing. No component, no fs.
--                            Unit-tested off-box and usable on a machine
--                            with no printer attached (that is how
--                            `printer preview` and the word processor's
--                            page view work).
--   /usr/lib/printer.lua     the hardware, the job, and the capability
--                            check. Re-checks peripheral.printer on
--                            every call for the #SEC H34 reason: a
--                            /usr/lib library is loaded through the REAL
--                            require, so the sandbox's gated-component
--                            split does not cover it and the driver has
--                            to police itself. See its header.
--
-- WHY IT DECLARES peripheral.printer AND NOT JUST component: a printer
-- WRITES to the world. It consumes the player's paper and ink and drops
-- physical pages into a chest — real actuation with a running cost,
-- which is the same reason `piston` and `robot` are gated rather than
-- covered by the blanket `component` grant. Installing a game must not
-- also hand it your ink.
return {
  name        = "printer",
  version     = "1.0.0",
  kind        = "command",
  category    = "drivers",
  description = "Printer driver for OpenPrinter: require(\"printer\") + a `printer` command (status, print, preview, scan, tags).",
  author      = "Strata Systems",
  files       = {
    "/usr/lib/printerfmt.lua",            -- pure layout
    "/usr/lib/printer.lua",               -- driver + job + cap check
    "/usr/modules/printer/init.lua",      -- the `printer` command
  },
  commands     = { printer = "/usr/modules/printer/init.lua" },
  -- fs.read/fs.write for `printer file <path>` and `printer scan <path>`;
  -- both go through the session-bound securefs, so printing a file you
  -- cannot read is refused by the filesystem rather than by us.
  capabilities = { "fs.read", "fs.write", "component", "peripheral.printer" },
  requires    = {},
  -- Soft: the command is keyboard-first and complete without a mouse.
  recommends  = { "mouse" },
}
