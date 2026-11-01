# Prefab: designing and building bases

The operator's idea: like `warhead`, but for building. Read the site with a geolyzer, draw your own blueprints a slice at a time in a 2.5D designer, and have robots and drones build them.

Status: the blueprint format, the designer, the build planner and the survey exist as `prefab` 0.2.0 in `TOS-Extras/modules/prefab`. The robot is designed here and not built. A 0.x package stays off the Optional Utilities pack by rule, so nothing here needs signing yet.

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

**The robot gets a program, not a remote control.** `prefab export` will write one self-contained Lua file holding the build, to run on the robot's own OpenOS from a floppy. Driving it live through `rc-pilot` would need its wireless setup, which isn't finished (see RC-PILOT CANNOT BE SET UP in the TODO), a shared secret, and a machine in range for the whole build. A file needs none of those, and it can be tested off-box by running the generated program against a simulated world.

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

## Still to build, in order

1. **`prefab export`:** the robot program, with a simulated world to run it against. It takes the floor the survey found.
2. **Supply:** the robot fetching from a chest with an inventory controller, finding each item by name and damage.
3. **Clearing the site**, before anything is placed.
4. **Drones as couriers.**
5. **In a real world:** nothing above reaches 1.0.0 until a robot has built something in one.

## Open questions

- Stairs, doors and anything else with an orientation: a blueprint's damage value doesn't say which way a block faces when it's placed. The robot's facing decides that, so these need their own step, and probably a facing column on `block`.
- Does `robot.place(down)` work on the first layer of a site that isn't flat? The survey now gives the floor, but filling under it is still untested.
- Does a real geolyzer match the bytecode? Nothing has checked that yet.
