# warhead — a nuke designer and simulator for HBM's Nuclear Tech Mod

Design the best custom nuke for the blast you want, and see what any of the mod's warheads would do before you set it off in your world: how far it carves, how deep it digs, who it kills, how far the radiation and the fallout reach, and how thick a wall has to be to stand behind. With a transposer next to a bomb it reads the bomb as it is actually loaded, missing parts and all.

The numbers are the mod's own. Every table and formula was read out of **NTM Community Edition 1.12.2-2.5.0.5** with `javap`, and `data.lua` names the class each one came from. A different NTM version may differ: see [Checking it against another version](#checking-it-against-another-version).

## Install

As admin, with the Optional Utilities disk inserted: `pkg install warhead`. It needs nothing else. With a transposer (or an inventory controller) attached it can read bombs and chests; without one, everything else still works.

## Use

```
warhead                         the full-screen simulator (80x24 or larger)
warhead list                    every warhead it knows, with its radius
warhead sim <name>              what one would do:  warhead sim tsar
warhead sim design <name>       a custom nuke you saved
warhead best <kind> [radius N] [salt] [stock <side>]
warhead scan [side]             read the bomb next to the transposer
warhead shelter <name> <distance> <material> [thickness]
warhead materials               what a shelter can be built from
warhead config [set K V | reset [K]]
```

`<kind>` for `best` is one of `tnt` (a clean MK5 blast, no fallout), `nuke` (fission), `hydro` (thermonuclear), `bale` (balefire), `schrab` (antimatter, FLEIJA-type), `sol` (Solinium, the Blue Rinse) and `euph` (Anti Mass).

### The screen

| Where | Keys |
|---|---|
| the list | arrows select · Enter opens the designer · M map · S shelter · K scan · C config |
| the designer | arrows move between the 27 slots · Enter (or just type) picks an ingredient · Del clears · B best design · G save · L load · K scan · M map · S shelter |
| the map | A adds a place (your base, a farm) by its offset from ground zero · X removes one |
| the shelter | Up/Down distance by 1, PgUp/PgDn by 10 · Left/Right material · + / - thickness |
| everywhere | ^Q goes back, and quits from the list |

The map draws the rings to scale, north up, with your places marked and a verdict for each: destroyed, killed in one tick, in blast range, in the fallout, or untouched.

## The custom nuke, as the mod actually runs it

These rules are `TileEntityNukeCustom.update` and `NukeCustom.explodeCustom`, and they are why "best" has an answer:

- **27 slots, and a slot counts once.** The mod looks each slot up and adds its value once; the stack size never enters into it. 64 plutonium ingots in one slot are worth exactly one.
- **Each stage is (sum of its adders) × (product of its multipliers).** Redstone, Plutonium ingots, Nuclear Waste and the like multiply their stage instead of adding to it.
- **Stages switch each other on.** Nuclear needs TNT ≥ 16; Hydrogen needs Nuclear ≥ 100; Balefire and Schrabidium need Nuclear ≥ 50; Solinium needs Nuclear ≥ 25; Anti Mass needs Schrabidium and Solinium both ≥ 1. A stage below its gate is set to zero, silently in-game; here it says why.
- **Each stage is capped** by the server's `maxCustom…Radius`.
- **The highest live stage fires and takes a halving share of every stage below it**: Anti Mass, then Solinium, Schrabidium, Balefire, Hydrogen, Nuclear, and TNT (75 or more is a clean MK5 blast; less is an ordinary explosion). A thermonuclear passes on only a quarter of the Salted stage as extra fallout.

`best` searches all of that exactly — the most it can do with each stage and n slots, then the best way to split 27 slots between the stages — and takes the design that reaches the result in the fewest slots. It then swaps each item for the weakest one that still gives the same blast, so it does not spend Balefire Eggs where Shards would do. Given `stock <side>`, it designs from what is in that chest. `salt` fills the spare slots with Salted material for a longer fallout.

With unlimited materials the caps are reached in: TNT 6 slots, fission 9, thermonuclear 8, balefire 7, antimatter 8, Solinium 10, Anti Mass 26 (20 levels, 2000 beams).

## What a detonation does

| | Where it comes from |
|---|---|
| **Blocks** | The MK5 blast (`ExplosionNukeRayParallelized`) fires 2.5π(2r)² rays, each starting with 0.6r energy. Air costs nothing; a block costs `(resistance + 1)^(3t) − 1` per block crossed, where t is how far out it is as a fraction of r. So a nuke always digs a crater near ground zero, and a wall near the rim stops it cold. The crater depths it reports are straight down, through one material. |
| **People** | Everything within 2r with a clear line of sight to ground zero takes 250 × (1 − d/2r) damage every tick the blast runs (`ExplosionNukeGeneric.dealDamage`), and is set on fire. One block in the way stops it. "One tick kills" is 20 health with no armour. |
| **Radiation** | The pulse (`EntityNukeExplosionMK5`) runs on ticks 2 to 9 at 2,500,000 / (5t + 1) RAD, divided by the shielding on the line and the distance squared: about 864,000 RAD at one metre through air. 1000 RAD kills and 200 makes you sick (`EntityEffectHandler`). It needs a radius of 38 or more, and only reaches 2r. |
| **Fallout** | `(int)(2.5r + salt) × falloutRange / 100`. Mobs within 1.5r may turn into Glowing Ones. |
| **Antimatter** | FLEIJA-type bombs delete every block in the sphere except bedrock-class ones. A Field Disturber or a DFC core within 300 blocks jams them: nothing happens. |
| **Solinium** | Everything alive in the sphere takes 15,000–250,000 RAD a tick; plants and wood go, and wasteland, trinitite and taint turn back into land. |

The shelter planner fires one ray straight at your wall. That is the blast's shortest path through it — every slanted ray loses more — so a wall it says holds, holds. Radiation counts each block's ordinary explosion resistance instead, which is why obsidian (18 against the blast, a special case in the mod) shields radiation like 1200.

## What it does not know

- **It has never watched a real detonation.** Every number is checked off-box against the mod's code; none has been checked against a bomb going off in a world. If one disagrees, the README's version line and `data.lua`'s class names are where to start.
- **The transposer's view of HBM items is unverified in a world.** Items are matched by registry name and metadata read from the jar (`hbm:cell` with damage 9 is a Tritium Cell). Anything it cannot place is reported, not guessed.
- **Armour is not modelled**, nor HBM's radiation protection. Doses are what reaches you.
- **A block whose class overrides its explosion resistance** is not in the material table, which uses each block's `setResistance` figure.
- **The radiation dose is an upper bound**: it assumes the blast is still being computed on ticks 2 to 9, which a large one always is and a small one may not be.
- **Server config.** The defaults are the mod's. If your server changed `hbm.cfg`, put its values in with `warhead config set`; they are kept in `~/.warhead`, with your saved designs and places.

## Checking it against another version

`data.lua` names, for every table, the class and method it came from: `BombConfig.loadFromConfig`, `TileEntityNukeCustom.registerBombItems`, each `TileEntityNuke….isReady`, `EntityMissile….onMissileImpact`. Disassemble those from the new jar (`javap -p -c -constants`) and compare. `test_warhead.lua` pins the arithmetic, with every expected number taken from a separate reference implementation rather than from this package.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/warhead/init.lua` | the command, the screen and the keys |
| `/usr/modules/warhead/data.lua` | the mod's numbers, each with its source |
| `/usr/modules/warhead/model.lua` | the arithmetic, the way the mod does it (32-bit floats included) |
| `/usr/modules/warhead/best.lua` | the best-design search |
| `/usr/modules/warhead/report.lua` | the words both the command and the screen print |

## Tests

From `TOS-Extras/`: `lua modules/warhead/test_warhead.lua` (the model, the data and the optimizer; 121 checks) and `lua modules/warhead/test_warhead_cli.lua` (the real command and screen driven through a fake GPU, keyboard, home directory and transposer; 48 checks). `python run_tests.py` in the TOS source runs both with everything else.
