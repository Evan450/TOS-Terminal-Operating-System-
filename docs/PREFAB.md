# Prefab: designing and building bases

The operator's idea: like `warhead`, but for building. Read the site with a geolyzer, draw your own blueprints a slice at a time in a 2.5D designer, and have robots and drones build them.

Status: the blueprint format, the designer and the build planner exist as `prefab` 0.1.0 in `TOS-Extras/modules/prefab`. The survey and the robot are designed here and not built. A 0.x package stays off the Optional Utilities pack by rule, so nothing here needs signing yet.

## What the hardware can do

Read from OpenComputers 1.8.10 for Minecraft 1.12.2: its `application.conf`, its in-game manual, its callback signatures and, for the geolyzer, its bytecode (`EventHandlerVanilla.onGeolyzerScan`). None of this has been tried in a world.

| | Robot | Drone |
|---|---|---|
| Inventory | 16 slots per inventory upgrade, 64 at most | 4 slots per upgrade, 8 at most |
| Program | an OS, or an EEPROM | an EEPROM only: 4 KB, no disk |
| Places a block | `robot.place(side)` | `drone.place(side)` |
| Moves | one block at a time, and turns | to any offset, fast, no facing |
| Height | 8 above a block by default, 64 and 256 with hover upgrades; can always climb a face | unlimited |
| Tools | yes | no |

The geolyzer's `scan(x, z, y, w, d, h)` returns up to 64 values a call, reaches 32 blocks in each direction, and costs 10 energy a block. `analyze` and `detect` only reach the adjacent block.

**The noise only touches real blocks.** A position that's air, not loaded, or skipped as replaceable is left at exactly 0. Anything else reads as its hardness plus noise of up to `distance * 2 / 33`, which is ±2 at 33 blocks with the default `geolyzerNoise`. Stone's hardness is 1.5, so past about 25 blocks a single reading can't tell what a block is. It can always tell whether one is there.

## Decisions

**Robots build, drones don't, at first.** A drone carries 8 stacks and has 4 KB to know the whole job in. A robot carries 64 stacks and can run a real program. Drones come back later as couriers, because their speed and height suit fetching.

**The robot gets a program, not a remote control.** `prefab export` will write one self-contained Lua file holding the build, to run on the robot's own OpenOS from a floppy. Driving it live through `rc-pilot` would need its wireless setup, which isn't finished (see RC-PILOT CANNOT BE SET UP in the TODO), a shared secret, and a machine in range for the whole build. A file needs none of those, and it can be tested off-box by running the generated program against a simulated world.

**The survey asks one question exactly.** Finding the height of the ground and any obstacles needs "is something there?", and the scan answers that without noise. Hardness is only for showing the player what's there, averaged over repeat scans.

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

## Still to build, in order

1. **`prefab survey`:** column scans from a geolyzer, to a height map and a list of what's in the way.
2. **`prefab export`:** the robot program, with a simulated world to run it against.
3. **Supply:** the robot fetching from a chest with an inventory controller, finding each item by name and damage.
4. **Clearing the site**, before anything is placed.
5. **Drones as couriers.**
6. **In a real world:** nothing above reaches 1.0.0 until a robot has built something in one.

## Open questions

- Stairs, doors and anything else with an orientation: a blueprint's damage value doesn't say which way a block faces when it's placed. The robot's facing decides that, so these need their own step, and probably a facing column on `block`.
- Does `robot.place(down)` work on the first layer of a site that isn't flat? The survey has to answer where the ground is first.
