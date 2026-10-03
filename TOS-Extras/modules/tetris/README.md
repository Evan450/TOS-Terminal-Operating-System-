# tetris — classic Tetris

Falling pieces, line clears, levels that speed up, and a high-score table for each player.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install tetris`. It needs a screen at least 24 rows tall, so a Tier 2 screen or better. It is its own package: installing it pulls in nothing else. `mouse` is recommended, not needed.

## Play

```
tetris            play
tetris scores     your high-score table
tetris help       the keys and the scoring
```

| Key | Does |
|---|---|
| Left, Right, or A, D | move |
| Up, W or X | rotate clockwise |
| Z | rotate anticlockwise |
| Down or S | soft drop, a point for each row |
| Space | hard drop, two points for each row |
| P | pause, and resume |
| Q, Esc or Ctrl+Q | quit |

Clearing lines scores 100, 300, 500 or 800 points for one to four lines at once, times the level. The level goes up every 10 lines, and the pieces fall faster with each one.

## High scores

Your five best games are kept in `.tetris_hs` in your home directory, with the lines and level of each. Every player has their own table, and a game played with no one logged in saves nothing.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/tetris/init.lua` | the whole game |

It runs entirely inside the package sandbox, with `fs.read`, `fs.write` and `component` only.

## Tests

From `TOS-Extras/`: `lua modules/tetris/test_tetris_sandbox.lua` loads the game inside a faithful fake of the sandbox, where any `kernel.*` require fails as it does for real, plays and quits, and checks the score file round trip and multi-line clears.
