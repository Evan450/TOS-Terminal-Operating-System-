# ttt — tic-tac-toe

Noughts and crosses against a machine that cannot lose, or against a friend on the same keyboard.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install ttt`. It needs a screen of at least 34 by 18 characters, so a Tier 2 screen or better. It is its own package: installing it pulls in nothing else. A click on a cell plays there too.

## Play

```
ttt play     against the machine: you are X, and it never loses
ttt 2p       two players taking turns at one keyboard
ttt help     the list
```

| Key | Does |
|---|---|
| arrows | move the cursor |
| Enter or Space | play in the cursor's cell |
| 1 to 9 | play in that cell, counted left to right from the top row |
| N | a new game |
| Q, or Ctrl+Q | quit |

## The machine really cannot lose

The opponent is a minimax search over the whole game. That it is unbeatable is a tested property rather than a claim: `test_ttt.lua` plays every line a human could choose against it, 569 finished games in all, and the human wins none of them. Perfect play draws, any slip loses, and ties between equally good moves are broken randomly, so the machine does not always open the same way.

`ttt` also hides a mode that the list above leaves out. It is there to be found.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/ttt/init.lua` | drawing and input |
| `/usr/modules/ttt/logic.lua` | the rules and the opponent; pure, no I/O |

It runs entirely inside the package sandbox, with `fs.read`, `fs.write` and `component` only.

## Tests

From `TOS-Extras/`: `lua modules/ttt/test_ttt.lua` covers wins on every kind of line, draws, illegal moves, the opponent taking a win and blocking a loss, and the exhaustive proof above.
