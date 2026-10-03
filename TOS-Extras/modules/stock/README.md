# stock — what is in your base, and what is running short

Totals every item across every inventory next to a transposer or an inventory controller, and warns about anything below a level you set. Run it as a live full-screen monitor, or ask once from the shell.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install stock`. It needs a transposer or an inventory controller with at least one inventory beside it. `mouse` is recommended, not needed.

## Use

```
stock            the live monitor, full screen
stock list       one listing, printed to the shell
stock low        only what is below its threshold
stock sides      which inventories are attached
stock help       the keys
```

In the monitor:

| Key | Does |
|---|---|
| R | rescan now (it rescans by itself every 10 seconds) |
| / | filter the list |
| L | show only what is low |
| W | set a threshold on the highlighted item |
| U | remove that item's threshold |
| Ctrl+B | send it to the background; Ctrl+T brings it back |
| Ctrl+Q | quit |

A watched item that has run out entirely still appears, at zero, which is exactly when it should.

## Thresholds

Thresholds are kept in `/etc/stock-watch.cfg`, one item a line: the item's key, a tab, the minimum, a tab, and its name for display.

```
minecraft:iron_ingot#0	64	Iron Ingot
```

The file is plain data, and is never run. Changing it needs admin, because a base-wide alarm level is not a personal preference; the monitor says so instead of quietly dropping the setting.

## Counted by what an item is, not what it is called

Items are totalled by their registry name and damage value, never by the name on screen. Two mods can both ship a "Copper Ingot", and any item can be renamed on an anvil, so a count keyed on the visible name would merge things that are not the same item and split things that are. The display name is carried for showing only.

Where the inventory component offers it, a side is read in one call rather than one per slot, which is what makes a live scan of a large base practical.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/stock/init.lua` | scanning, drawing and keys |
| `/usr/modules/stock/stock.lua` | totalling, thresholds and formatting; pure, no I/O |

It asks for `fs.read` and `fs.write` for the threshold file, `component` for the screen and `peripheral.inventory` for the transposer. Nothing on the network: it reads chests, and has nobody to tell.

## Tests

From `TOS-Extras/`: `lua modules/stock/test_stock.lua` tests the totalling, the thresholds and the formatting off-box, including the registry-name rule in both directions.
