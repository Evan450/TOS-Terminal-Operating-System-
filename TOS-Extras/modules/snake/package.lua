-- Optional Utilities — snake: classic snake with per-user high scores.
--
-- Its own standalone package (operator's model: each program is
-- individually installable — you can take snake without ttt or tetris).
-- Grouped with them under category="games" so the installer can offer
-- the games together while still letting you pick just one.
--
-- Sandbox-safe: draws through the sandboxed `component` GPU proxy, pulls
-- raw signals, writes its high-score board through the session-bound
-- `fs`. Rules are pure in snake/logic.lua, unit-tested by test_snake.lua.
return {
  name        = "snake",
  version     = "1.0.0",
  kind        = "command",
  category    = "games",
  description = "Classic snake with per-user high scores. Requires a T2+ screen.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/snake/init.lua",
    "/usr/modules/snake/logic.lua",
  },
  -- Full-screen program: the shell hands it the seat as its own
  -- process, so Ctrl+B can push it to the background and Ctrl+T
  -- brings it back instead of it owning the terminal until it exits.
  fullscreen  = true,
  -- Background policy (freeze): a snake that kept moving while you were in the shell
  -- would be dead when you came back.
  background  = "freeze",

  commands     = { snake = "/usr/modules/snake/init.lua" },
  capabilities = { "fs.read", "fs.write", "component" },
  requires    = {},
}
