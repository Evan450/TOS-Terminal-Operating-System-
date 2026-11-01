# prefab — design a base, a slice at a time

A blueprint designer. A screen is flat and a building isn't, so you draw one slice of the building at a time, looking along X, Y or Z, with the slice behind it showing faintly under the one you're drawing. It also counts what a build takes, finds any block a robot couldn't place, reads a real site with a geolyzer to find the best place for the floor, and writes a program for a robot to build it.

**Not on the pack yet.** This is 0.3.0: it has been tested against simulations of a geolyzer and a robot, but never in a real world. `docs/PREFAB.md` on the `dev` branch has what was checked against OpenComputers itself, and what's left.

## Use

```
prefab                          a new blueprint, 16x8x16
prefab hut.bp                   open one
prefab new 9 5 7 Starter hut    a new one of that size, with a name
prefab info hut.bp 32           what it takes, for a robot with 32 slots
prefab survey hut.bp            find the best floor for it, with a geolyzer
prefab survey 9 7 --height 4    the same, for a size
prefab export hut.bp build.lua  a program for a robot to build it
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

## Reading a site

Attach a geolyzer and run `prefab survey`. It says what it's about to spend, reads the site, and reports the best height for the floor as an offset from the geolyzer:

```
Reading 9x7x21: 36 scans, about 2 s and 360 energy.
Best floor: Y 0 from the geolyzer
12 block(s) in the way, 4 to fill under the floor
9 more above the building, in a robot's way down
Next best: Y -1, 64 in the way, 2 to fill
The site from above, X east and Z south, corner at -4,-3:
.........
.~.......
.........
.........
.....555.
...c.555.
.....555.
. ready  1-9 too high  a-i too low  ~ liquid  ? nothing read
```

The site sits around the geolyzer unless `--at X Z` places its north-west corner. `--down N` and `--up N` set how far it reads, 8 down and the building's height plus 8 up by default. `--height N` gives the building's height when you survey by size. A geolyzer reaches 32 blocks each way.

- **It can't see grass or snow-thin things.** Tall grass and anything else replaceable reads as empty, which is right: a block can go straight in.
- **It can't see unloaded chunks.** They read as empty, so `?` across part of the map usually means you're too far away.
- **Bedrock is only recognised close to the geolyzer.** Further out it counts as an ordinary block.

## Building it

`prefab export hut.bp build.lua` writes the program and tells you what to load:

```
Wrote build.lua: 42 steps, 57 moves, about 48 s and 905 energy.
Load the robot:
  slot 1     40  Cobblestone
  slot 2     2  Glass
Stand it in the corner of the first layer, at the floor the survey found.
The building goes ahead of it and to its right. On OpenOS, run the file.
```

The robot needs an inventory upgrade and OpenOS. Carry the file over on a floppy, load the slots, stand it in the corner, and run the file. `--slots N` says how many inventory slots it has, 16 by default.

- **No compass needed.** The building goes ahead of the robot and to its right, whichever way it's facing.
- **Running out:** it walks back to the corner, says what it wants, and carries on once you've loaded it.
- **An inventory controller** lets it check each item, so the wrong block in a slot is refused rather than built.
- **If it stops,** it says why and saves its place. Fix the problem and run the file again. Run it with `fresh` to start over.
- **It can't dig yet.** Clear the site first: anything solid in its way stops it.
- **A power cut loses its place.** It only saves when it stops itself, so after one, stand it back in the corner and run it with `fresh`.
- **Stairs and doors** may come out facing the wrong way, because a blueprint doesn't record facing yet.

## The file

A blueprint is plain text, one grid of letters per layer, so you can read it, compare two of them and hand one to someone else. It's only ever parsed, never run, so one from a stranger is safe to open. `docs/PREFAB.md` has the format.
