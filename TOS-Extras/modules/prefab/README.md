# prefab — design a base, a slice at a time

A blueprint designer. A screen is flat and a building isn't, so you draw one slice of the building at a time, looking along X, Y or Z, with the slice behind it showing faintly under the one you're drawing. It also counts what a build takes and finds any block a robot couldn't place.

**Not on the pack yet.** This is 0.1.0: the designer and the planner work, but nothing builds a blueprint in a world so far. `docs/PREFAB.md` on the `dev` branch has the design for the survey and the robot, and what was checked against OpenComputers itself.

## Use

```
prefab                          a new blueprint, 16x8x16
prefab hut.bp                   open one
prefab new 9 5 7 Starter hut    a new one of that size, with a name
prefab info hut.bp 32           what it takes, for a robot with 32 slots
```

`open hut.bp` works too, once `prefab` is installed. A box can be up to 64 on each side.

| Key | Does |
|---|---|
| Arrows | move |
| Space | paint with the selected block |
| Del, Backspace | erase |
| Tab, 1 to 9 | pick a block |
| X, Y, Z | look along that axis: Y is the plan, Z the front, X the side |
| PgUp, PgDn | the next slice, or the one before |
| R | mark a corner. Move, then R fills the rectangle and Del clears it |
| C, V | copy this slice, paste it onto another |
| U | undo, up to 32 steps |
| A | add a block by registry name |
| M | what the build takes |
| S, O | save, open |
| Ctrl+Q | quit, asking first if there's unsaved work |

**With a mouse**, install the `mouse` package: the left button paints and drags, the right button erases, and clicking the list picks a block. Everything works from the keyboard too.

## What the report tells you

- **Materials**, by count.
- **Loads:** how many times a robot has to fill up. It takes a stack as 64, so doors and the like will need more.
- **Moves** along the build order.
- **Floating blocks:** a robot places each block from above and needs something beside or under it, so a block touching nothing can't go in. It needs an angel upgrade, or a change to the blueprint.

## The file

A blueprint is plain text, one grid of letters per layer, so you can read it, compare two of them and hand one to someone else. It's only ever parsed, never run, so one from a stranger is safe to open. `docs/PREFAB.md` has the format.
