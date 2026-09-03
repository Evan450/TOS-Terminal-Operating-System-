-- ╔══════════════════════════════════════════════════════╗
-- ║  TOS Panels — keymap                                 ║
-- ║                                                      ║
-- ║  Central scancode table for the Panels TUI.          ║
-- ║  Kept in its own file so keybinds are searchable and ║
-- ║  so additional bindings (editor / browser / REPL)    ║
-- ║  can accrete here as the split progresses.           ║
-- ╚══════════════════════════════════════════════════════╝

-- OpenComputers scancodes. See http://www.pichotjoseph.com/oc/keycodes
-- or the OC wiki for the authoritative table. These are the keys the
-- Panels shell cares about at the top level — submodule-specific binds
-- (editor shortcuts, dialog navigation) can live in a sub-table here as
-- they are lifted out of init.lua in follow-up work.
--
-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ESC IS NOT OURS. Read this before binding a key to "quit".  ║
-- ║                                                              ║
-- ║  Found in real Minecraft, 2026-08-11. Esc belongs to the      ║
-- ║  GAME: pressing it closes the screen GUI, so the player walks ║
-- ║  away from the terminal and the keypress never reaches the    ║
-- ║  computer. A program whose only way out is Esc cannot be      ║
-- ║  exited at all — it keeps running, holding the seat, and the  ║
-- ║  operator's only recourse is to re-open the screen and find   ║
-- ║  it still there.                                             ║
-- ║                                                              ║
-- ║  THE CONVENTION, and every full-screen program in this tree   ║
-- ║  follows it:                                                 ║
-- ║                                                              ║
-- ║    Quitting a full-screen program:  Q   (and F10)            ║
-- ║    Quitting one that eats letters   ^Q  (and F10)            ║
-- ║      (an editor, a spreadsheet)                              ║
-- ║    Cancelling a prompt or dialog:   ^Q                       ║
-- ║                                                              ║
-- ║  Esc may still be ACCEPTED wherever it is harmless — on the   ║
-- ║  chance a future OC build or an emulator does deliver it —    ║
-- ║  but it must never be the only way, and no help text should   ║
-- ║  advertise it as the way. usr/lib/tests/test_no_esc_exit.lua  ║
-- ║  enforces both halves.                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
local keymap = {
  -- The two exits every full-screen program should honour, named so a
  -- program can bind them without re-deriving the scancodes.
  ESC      = 1,   -- accepted where harmless; NEVER the only way out
  CTRL_Q   = 17,  -- character code, not a scancode: quit / cancel
  Q        = 16,  -- scancode for the 'q' key

  -- Function-row
  help     = 59,  -- F1
  -- F2 IS THE `view` ACTION, NOT A TAB KEY. It used to cycle tabs, which
  -- meant "Desktop <-> Shell" back when those were two tabs; the merged
  -- Home surface makes them two VIEWS of one tab, so F2 flips the view
  -- instead. The authoritative binding lives in shell/keys.lua (the
  -- `view` action, operator-rebindable via /etc/keys.cfg); this entry is
  -- only the fallback used when that module can't be loaded, and the
  -- default it names must stay in step with keys.DEFAULTS.view.
  homeView = 60,  -- F2
  -- Cycling tabs moved to Tab, and only when the prompt is EMPTY — with
  -- text on the line Tab still completes, the same "what is on the line
  -- decides" rule Enter and Backspace already follow on this surface.
  viewFile = 61,  -- F3 (view the selected FILE — not the same as `view`)
  tabClose = 62,  -- F4
  copy     = 63,  -- F5
  move     = 64,  -- F6
  mkdir    = 65,  -- F7
  delete   = 66,  -- F8
  menu     = 67,  -- F9
  quit     = 68,  -- F10
}

return keymap
