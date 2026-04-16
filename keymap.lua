-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Panels — keymap                                  ║
-- ║                                                       ║
-- ║  Central scancode table for the Panels TUI.          ║
-- ║  Kept in its own file so keybinds are searchable and  ║
-- ║  so additional bindings (editor / browser / REPL)    ║
-- ║  can accrete here as the split progresses.           ║
-- ╚══════════════════════════════════════════════════════╝

-- OpenComputers scancodes. See http://www.pichotjoseph.com/oc/keycodes
-- or the OC wiki for the authoritative table. These are the keys the
-- Panels shell cares about at the top level — submodule-specific binds
-- (editor shortcuts, dialog navigation) can live in a sub-table here as
-- they are lifted out of init.lua in follow-up work.
local keymap = {
  -- Function-row
  help     = 59,  -- F1
  tabNext  = 60,  -- F2
  view     = 61,  -- F3
  tabClose = 62,  -- F4
  copy     = 63,  -- F5
  move     = 64,  -- F6
  mkdir    = 65,  -- F7
  delete   = 66,  -- F8
  menu     = 67,  -- F9
  quit     = 68,  -- F10
}

return keymap
