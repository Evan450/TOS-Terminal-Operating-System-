# prefab — design a base, a slice at a time

A base designer, two ways. Lay out a base from ready-made hallways and rooms, which fit together because they all share one grid. Or draw a building yourself: a screen is flat and a building isn't, so you draw one slice at a time, looking along X, Y or Z, with the slice behind it showing faintly under the one you're drawing. Either way it counts what a build takes, finds any block a robot couldn't place, reads a real site with a geolyzer to find the best place for the floor, and writes a program for a robot to build it.

**Not on the pack yet.** This is 0.7.0: it has been tested against simulations of a geolyzer and a robot, but never in a real world. `docs/PREFAB.md` on the `dev` branch has what was checked against OpenComputers itself, and what's left.

## Use

```
prefab                          a new blueprint, 16x8x16
prefab hut.bp                   open one
prefab new 9 5 7 Starter hut    a new one of that size, with a name
prefab info hut.bp 32           what it takes, for a robot with 32 slots
prefab survey hut.bp            find the best floor for it, with a geolyzer
prefab survey 9 7 --height 4    the same, for a size
prefab export hut.bp build.lua  a program for a robot to build it
prefab parts                    the parts a base is built from
prefab base 3 3 Camp            lay out a new base, 3 by 3 tiles
prefab camp.base                open a layout
prefab check camp.base          doors that lead nowhere, rooms cut off
prefab compile camp.base out.bp the base as one blueprint
```

`open hut.bp` works too, once `prefab` is installed, and so does `open camp.base`. A box can be up to 64 on each side.

## Laying out a base

A base is a map of tiles, and each tile is 7 by 7 by 5 high. A doorway is always the middle three cells of a tile's edge, so any door meets any door, whichever way the parts are turned.

```
  hall      Hallway                    doors N S
  gallery   Hallway with windows       doors N S
  corner    Corner                     doors N E
  tee       T junction                 doors N E S
  cross     Crossroads                 doors N E S W
  end       Dead end                   doors N
  room      Room, one door             doors N
  sunroom   Room with windows          doors N
  passage   Room, doors at both ends   doors N S
  hub       Room, four doors           doors N E S W
  hall2     Great hall, 2 by 2 tiles   doors N E S W
```

`prefab base 3 3 Camp` opens the map. Each tile shows its part's walls, with a gap for each door, so you can see what joins what:

```
      ┌────┐
      │end │
      └─  ─┘
┌────┐┌─  ─┐┌────┐
│room  cros  room│
└────┘└─  ─┘└────┘
      ┌─  ─┐
      │pass│
      └─  ─┘
```

| Key | Does |
|---|---|
| Arrows | move |
| Tab | pick a part |
| R | turn the part under the cursor, or the one in hand |
| Space, Enter | place it |
| Del, Backspace | take away the part here |
| C | check: a door into a wall, a part cut off, no way in |
| M | what the base takes |
| B | what the walls, floor, roof and windows are made of |
| A | add a blueprint of your own as a part |
| S, O | save, open |
| X | save the base as one blueprint |
| Ctrl+Q | quit, asking first if there's unsaved work |

**With a mouse**, the left button places, the right button removes, and clicking the list picks a part.

A door with nothing past it isn't a fault: it's a way in, and a base needs at least one.

**A `.base` file goes anywhere a `.bp` does.** `prefab info`, `survey`, `export`, `need`, `watch`, `print` and `csv` all take it, so this just works:

```
prefab export camp.base build.lua --chest --clear
```

That 5-part camp is 21x5x21: 705 blocks, 13 stacks, and 1297 moves along the build order. A base has one floor for now, because stairs need blocks that face a set way.

**Your own parts.** Draw a blueprint whose footprint is whole tiles, say `prefab new 7 5 7`, leave a gap in the middle of an edge for a door, and press A in the layout to add it by its full path. Its doors are found by looking. It keeps its own blocks, while B changes only the built-in parts. To change a built-in part, put it alone in a 1 by 1 base, compile that, and draw on the blueprint.

## Drawing a blueprint

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

**Or let it fetch for itself:** `prefab export hut.bp build.lua --chest` leaves the robot empty. Put a chest right behind where it starts, holding what the build needs. It takes only those blocks, so the chest can hold other things too, goes back whenever it runs out, and finishes parked on the chest with any leftovers returned. It needs an inventory controller for this.

- **No compass needed.** The building goes ahead of the robot and to its right, whichever way it's facing.
- **Running out:** it walks back to the corner, or the chest, says what it wants, and carries on once it's there.
- **An inventory controller** lets it check each item, so the wrong block in a slot is refused rather than built.
- **If it stops,** it says why and saves its place. Fix the problem and run the file again. Run it with `fresh` to start over.
- **Clearing:** `--chest --clear` has it empty the building's space first, top down, and dig through anything on its route. It needs a pickaxe in its tool slot, and takes spares from the chest. Debris goes in the chest too, so use a double chest. Tall grass and water are left, because a block can go straight in.
- **It doesn't fill holes.** Gaps under the floor are still yours to fill: `prefab survey` tells you how many.
- **A power cut loses its place.** It only saves when it stops itself, so after one, stand it back in the corner and run it with `fresh`.
- **Stairs and doors** may come out facing the wrong way, because a blueprint doesn't record facing yet.

## With other add-ons

These all work without the other package, or tell you what to install. The picker suggests them when you pick `prefab`.

```
prefab need hut.bp              what you have against what it takes
prefab watch hut.bp             put its materials on stock's watch list
prefab watch hut.bp --off       take them off again
prefab print hut.bp             print the materials and a plan of each layer
prefab print hut.bp --dry       what that would cost, without printing
prefab csv hut.bp mats.csv      the materials, for calc or anything else
```

- **`need`** reads everything next to a transposer or inventory controller. It only reads, and never moves an item.
- **`watch`** needs `stock` 1.0.2 and an admin. After it, `stock low` and the monitor flag what's short. A higher threshold you already set stays, and `--off` only removes what this build set.
- **`print`** needs `printer`. Rows wider than the paper go across several strips.
- **`csv`** adds what you have when it can read your inventories.

## The file

A blueprint is plain text, one grid of letters per layer, so you can read it, compare two of them and hand one to someone else. It's only ever parsed, never run, so one from a stranger is safe to open. `docs/PREFAB.md` has the format.
