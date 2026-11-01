# Prefab: designing and building bases

The operator's idea: like `warhead`, but for building. Read the site with a geolyzer, draw your own blueprints a slice at a time in a 2.5D designer, and have robots and drones build them.

Status: the blueprint format, the designer, the build planner, the survey and the robot program exist as `prefab` 0.6.0 in `TOS-Extras/modules/prefab`. A 0.x package stays off the Optional Utilities pack by rule, so nothing here needs signing yet.

## What the hardware can do

Read from OpenComputers 1.8.10 for Minecraft 1.12.2: its `application.conf`, its in-game manual, its callback signatures and, for the geolyzer, its bytecode (`EventHandlerVanilla.onGeolyzerScan`). None of this has been tried in a world. The survey has run through TOS's real sandbox against the runner's stand-in geolyzer (`--geolyzer`), which follows that bytecode, so it proves the path and not the bytecode reading.

| | Robot | Drone |
|---|---|---|
| Inventory | 16 slots per inventory upgrade, 64 at most | 4 slots per upgrade, 8 at most |
| Program | an OS, or an EEPROM | an EEPROM only: 4 KB, no disk |
| Places a block | `robot.place(side)` | `drone.place(side)` |
| Moves | one block at a time, and turns | to any offset, fast, no facing |
| Height | 8 above a block by default, 64 and 256 with hover upgrades; can always climb a face | unlimited |
| Tools | yes | no |

The geolyzer's `scan(x, z, y, w, d, h)` reads up to 64 cells a call, reaches 32 blocks in each direction, and takes one call a tick. It costs 10 energy a **call**, whatever its size: `application.conf` says a block, and the code charges once. So a 4x4x4 cube is the best buy, at 64 cells for 10 energy. `analyze` and `detect` only reach the adjacent block.

The answer is always 64 values long. It's filled with noise first and only the box is written over, so anything past the box is noise and has to be left unread.

**The noise only touches real blocks.** A position that's air, not loaded, or skipped as replaceable is left at exactly 0. Anything else reads as its hardness plus noise of up to `distance * 2 / 33`, which is ±2 at 33 blocks with the default `geolyzerNoise`. Stone's hardness is 1.5, so past about 25 blocks a single reading can't tell what a block is. It can always tell whether one is there.

The code also settles a few limits. An unloaded chunk reads as air. A block with no hardness that isn't replaceable, like a torch, reads as air about 1 time in 256, when its noise happens to be zero. Bedrock is -1, so it can only be told from stone close to the geolyzer. Water and lava are 100, and the hardest ordinary block is 50, so a liquid stands clear of the noise everywhere. And `isReplaceable` is asked at the geolyzer's own position rather than the block's, which only matters for blocks whose answer depends on where they are.

## Decisions

**Robots build, drones don't, at first.** A drone carries 8 stacks and has 4 KB to know the whole job in. A robot carries 64 stacks and can run a real program. Drones come back later as couriers, because their speed and height suit fetching.

**The robot gets a program, not a remote control.** `prefab export` writes one self-contained Lua file holding the build, to run on the robot's own OpenOS from a floppy. Driving it live through `rc-pilot` would need its wireless setup, which isn't finished (see RC-PILOT CANNOT BE SET UP in the TODO), a shared secret, and a machine in range for the whole build. A file needs none of those, and it can be tested off-box by running the generated program against a simulated world.

**The survey asks one question exactly.** Each cell needs one reading, because "is something there?" has no noise in it. Only liquids and bedrock use the hardness at all.

**There is no such thing as "the ground".** A trunk is joined to the earth under it and a cave leaves a gap beneath it, so any rule for finding the surface gets one of them wrong. The survey doesn't look for one. It prices a floor at every height and takes the cheapest.

**A block is placed from above, working upward.** The robot stands at `y + 1` and places downward. That one move works everywhere and needs nothing but a neighbour to place against, so the build order is every layer from the bottom, and within a layer the blocks that have something to touch.

**A blueprint is a text file.** It's one grid of characters per layer, so it can be read, compared and shared, and it's parsed by hand and never executed, because blueprints will come from other people.

**Item identity is the registry name and damage**, never a display label, for the reason `stock` gives: two mods can both have a "Copper Ingot".

## The blueprint format

```
PREFAB1
name Starter hut
size 5 2 3
block a minecraft:cobblestone 0 Cobblestone
block g minecraft:glass 0 Glass
layer 1
aaaaa
aaaaa
aaaaa
layer 2
agaga
a...a
aaaaa
```

`size` is width, height and depth, in X, Y and Z, up to 64 each. Each `layer` has one row per Z, each row one character per X. `.` is air. A `block` line gives a key (a letter or digit), a registry name, a damage value and a label.

## The planner

`prefab info`, and M in the designer, report what the build takes:

- **Materials:** a count per block, and the stacks that needs.
- **Trips:** how many times the robot has to fill up, for its inventory size. Stacks are taken as 64, which is too many for doors and the like.
- **Moves:** the number of steps along the build order.
- **Floating blocks:** anything with nothing to place against when its turn comes. Those need an angel upgrade, or a change to the blueprint.

## The survey

`prefab survey hut.bp` reads a box around the geolyzer, or one placed with `--at`, in 4x4x4 cubes from the bottom up. A floor at each height is then priced:

- **In the way:** blocks in the building's space.
- **Above it:** blocks over the building. These count because a robot works from above. Without them a cave is free, since it has nothing to clear and a floor already there, and every site with a cave under it would be built underground.
- **To fill:** the gap down to the first solid block, under each column.
- **Warnings:** liquid in the space, cells that can't be broken, and columns with nothing under them in the scan. Those last two rule a floor out ahead of cost.

The map shows the site from above against the chosen floor: `.` is ready, a digit stands that far too high, a letter is that far too low, `~` is liquid and `?` read nothing.

## The robot program

`prefab export hut.bp build.lua` writes one Lua file holding the build order and a small builder. It needs OpenOS and `component.robot`, and nothing else.

**There's no compass.** Stand the robot in the corner of the first layer, at the floor the survey found. The building goes ahead of it and to its right, whichever way it's facing.

**It walks one block above the layer it's laying**, so it never meets the building. Up first, then along X, then along Z.

**Loading:** export prints which slots to fill. Each block gets a slot, and the rest go to whatever needs the most. When a block runs out the robot walks back to the corner, says what it wants, and waits. With an inventory controller it also checks each item's name and damage, so the wrong thing in a slot is refused rather than built.

**Fetching from a chest:** with `--chest` the robot starts empty, and a chest goes right behind where it starts. It stands on the chest and reads every slot, taking only what the rest of the build needs, by name and damage, so a chest shared with anything else is safe. It goes back whenever it runs out, and at the end it returns any leftovers and parks on the chest. The chest is outside the building, so the way there is clear at any height. This needs an inventory controller. If the chest runs short the robot waits on it and says what it wants. Export counts the trips by walking the same route, taking a stack as 64: anything that stacks lower only makes more trips.

**Clearing the site:** with `--clear` as well, the robot empties the building's space first, top down, standing a block above each layer so it's always in cells it has already cleared. What `detect` calls solid or passable gets dug; tall grass and water stay, because a block can go straight in. Anything in its way on the route is dug through too, which is safe because the route is outside the building or above it. Debris goes in the same chest, so that should be a double chest, and it walks back to empty itself whenever its last slot is in use. When its tool wears out it takes anything named a pickaxe from the chest and equips it. This needs `--chest`: debris has to go somewhere, and a robot loaded by hand can't tell what it dug from what it was given.

**When it can't go on:** a player or a flat battery gets 30 seconds of patience. After that, or for a block in the way or nothing to place against, it stops, says where, and saves its place in `/home/.prefab-state`. Running the file again carries on from there, and `fresh` as an argument starts over. A block already standing in a target cell is left alone and counted.

**A hover problem is known in advance.** Export walks the same path as the robot, under OpenComputers' flight rule, and names the step that would need a hover upgrade.

**What a stranger's blueprint can do:** nothing. The generator is the one place a blueprint becomes code, so every string goes through `%q`, and comments have control characters taken out, because a bare carriage return would end the comment and turn the rest of the line into code.

How it was tested: `test_prefab_export.lua` runs the generated program against a simulated world, in all four facings, through refills, wrong items, blocked paths, flat batteries and resuming. Then a file exported on a real TOS machine ran on real OpenOS against the runner's stand-in robot (`--robot`): all 42 blocks of the test hut landed in the right cells from the right slots, none twice. With `--robot-chest` it started empty beside a chest that also held dirt: it took exactly 40 cobblestone and 2 glass, and every cell got the right item. The stand-in and the simulator are both my reading of OpenComputers, so neither proves a real robot behaves this way.

Limits for now:

- It clears the building's space and its route, not the ground under the floor: a gap there still has to be filled by hand, or the floor chosen to avoid it.
- Blocks over the building's top are left, so a tree's canopy stays until it decays.
- Its place is only saved when it stops itself. If the power dies or the chunk unloads, it has lost its position, and the only recovery is standing it back in the corner with `fresh`.
- After a finished build, running the file again builds again from wherever the robot is.
- Blocks are placed facing however the robot's facing lands them, which is the open question below.

## Building from parts

Drawing is right for one building and wrong for a base. Nobody wants to draw the twelfth corridor, and two things drawn apart have no reason to line up. So `parts.lua` fixes a grid, and `base.lua` is a layout on it.

**The grid:** a tile is 7 by 7 by 5 high. A doorway is the middle 3 cells of a tile's edge. That one rule is the whole design: any door meets any door, and because tiles are square a part can be turned and still sit on the grid.

**A built-in part is only its plan,** the cells you can walk in. Walls are whatever touches the plan, and floor and roof run under and over both. So a new part is a few lines, and it can't disagree with the others about where a door is. Walls are one block thick and belong to their own part, so two rooms side by side stand wall to wall.

**Your own blueprint is a part** if its footprint is whole tiles. Its doors are found by looking: air at door height, over a floor, at the middle of a tile's edge. Nothing has to be declared, so drawing a door is enough. A part you add is stored in the layout by its absolute path.

**A layout compiles to one blueprint.** This is the decision that keeps the rest simple: the survey, the planner, the robot program, the chest and the links never learn that a base was assembled. `.base` files are recognised where a blueprint is loaded, in one place.

```
PREFABBASE1
name Camp
size 3 3
block w minecraft:cobblestone 0 Cobblestone
part cross 2 2 0
part end 2 1 2
```

`part` is a name, the tile, and clockwise quarter turns. `block` overrides a role (`w` walls, `f` floor, `r` roof, `g` windows) for the built-in parts. A layout comes from other people, so like a blueprint it's parsed by hand and never executed. A part named by path is read as a blueprint, which is also only parsed.

**The check** finds a door into a wall, a part cut off from the first one, and a base with no way in. A door with nothing past it counts as a way in.

## With the rest of the pack

Nothing here is needed to design or build. Each link does more when another package is installed, and says what to install when it isn't. They're `recommends`, so the picker suggests them.

- **`prefab need`** compares a build with what's in reach of a transposer or inventory controller. It needs no other package, because the inventory library belongs to the base.
- **`prefab watch`** puts a build's materials on `stock`'s watch list, through `stock`'s own `readWatches` and `saveWatches`, so `stock low` and the monitor flag what's short. A higher threshold someone already set stays. `--off` removes only what the build set.
- **`prefab print`** prints a sheet of materials and a plan per layer through `printer`, in evenly wide letters because a printer's font is proportional, in strips where a row is wider than the paper. `--dry` gives the cost without printing.
- **`prefab csv`** writes the bill of materials for `calc` or anything else, with what you have if inventories are in reach.

A library from another package runs inside prefab's sandbox with prefab's capabilities, so prefab has to declare `peripheral.inventory` and `peripheral.printer` itself. `pkg info` shows them. It only reads inventories and never moves an item.

## Still to build, in order

1. **Drones as couriers.**
2. **Bases with more than one floor,** once blocks can face a set way: a staircase needs that.
3. **In a real world:** nothing above reaches 1.0.0 until a robot has built something in one.

## Open questions

- Stairs, doors and anything else with an orientation: a blueprint's damage value doesn't say which way a block faces when it's placed. The robot's facing decides that, so these need their own step, and probably a facing column on `block`.
- Does `robot.place(down)` work on the first layer of a site that isn't flat? The survey now gives the floor, but filling under it is still untested.
- Does a real geolyzer match the bytecode, and a real robot? Nothing has checked either yet.
