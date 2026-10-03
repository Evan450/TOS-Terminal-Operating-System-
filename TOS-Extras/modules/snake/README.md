# snake — classic snake

Eat, grow, and don't hit the walls or yourself. The snake speeds up as your score climbs, and each player keeps their own high-score board.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install snake`. It needs a screen of at least 44 by 22 characters, so a Tier 2 screen or better. It is its own package on purpose: you can take snake without `ttt` or `tetris`, and installing it pulls in nothing else.

## Play

```
snake
```

| Key | Does |
|---|---|
| arrows, or W A S D | turn |
| P | pause, and resume |
| Q, or Ctrl+Q | quit |

The board is 40 by 16. Each piece of food is a point, and the snake steps faster with every point, from about four and a half steps a second up to a ceiling of about fourteen. The walls are solid: there is no wrapping. You cannot reverse straight into your own neck, and chasing your own tail is legal, as in the arcade.

Sending the game to the background with Ctrl+B freezes it, and it comes back paused, so a run is never lost while you were away.

## High scores

Your five best scores are kept in `.snake_hs` in your home directory, a line each, and the game-over screen shows the top three. Every player has their own board. A game played with no one logged in saves nothing.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/snake/init.lua` | drawing and input |
| `/usr/modules/snake/logic.lua` | the rules; pure, no I/O |

It runs entirely inside the package sandbox, with `fs.read`, `fs.write` and `component` only.

## Tests

From `TOS-Extras/`: `lua modules/snake/test_snake.lua` covers the rules (movement, growth, the reversal guard, walls, self-collision and the legal tail-chase, food never landing on the snake, the speed ramp). `lua modules/snake/test_snake_scores.lua` plays real games as two players and checks each keeps their own board.
