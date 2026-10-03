# printer — the printer driver

TOS has no built-in printing, the same way it has no built-in mouse. This is the DOS-style driver you install when the base actually has the hardware: a `printer` command, and a `require("printer")` library for programs that want to print.

It drives the **OpenPrinter** add-on by PC-Logix, its `openprinter` component. OpenComputers' own `printer3d` prints 3D models and is a different device entirely.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install printer`. The command is complete on the keyboard; `mouse` is recommended, not needed. The `write` word processor depends on this package.

## Use

```
printer                     the attached printer, and its paper and ink levels
printer test                print one test page, to prove the wiring
printer file <path>         print a text file
printer preview <path>      paginate it without printing anything
printer scan [<path>]       read the page in the input slot, optionally into a file
printer tag <text>          print a name tag
printer clear               empty the printer's buffer
```

`file` and `preview` take:

| Flag | Does |
|---|---|
| `--title=T` | the printed item's name |
| `--copies=N` | print N copies |
| `--center` | centre every line |
| `--color=0xRRGGBB` | print in a colour |
| `--no-wrap` | cut long lines instead of wrapping them |
| `--dry-run` | say what it would cost, print nothing |
| `--force` | try even when the paper or ink looks short |

`preview` exists because paper is a real resource. The way to find out that a three-line footer pushed your document onto a fourth sheet should not be finding a fourth sheet in the output chest.

A page holds 20 lines, and a line is measured in pixels rather than characters (164, or whatever the printer reports), using OpenPrinter's own character widths. A file over 64 KB is refused; print the part you want instead.

## Three things it does on purpose

**A job is checked before it starts.** It is built in memory, its paper and ink are compared with what the printer actually holds, and only then is it sent. The printer's buffer is shared and persistent, so a job that fails halfway leaves half a document in the output chest. Short on either and it refuses, says what the job needs, and suggests `--force`.

**A failed print says how far it got.** If the printer runs dry mid-job, the error reports how many pages were already printed, so you don't reprint the lot.

**Colour is opt-in, per line.** OpenPrinter charges a unit of colour ink for every line that carries a colour, so a colour default would quietly drain the cartridge on an all-black document.

## In your own program

```lua
local p = require("printer")
if p.available() then
  p.printText("Hello, base.", { title = "Note" })
end
```

For more control, `p.job(title)` returns a job: add text with `:line(text, color, align)`, `:text(body, opts)`, `:blank()` and `:pageBreak()`, set `:copies(n)`, ask `:pages()` and `:cost()`, then `:check()` before `:commit()`. `p.status()`, `p.scan()`, `p.tag(text)` and `p.clear()` cover the rest. The pure layout helpers are in `require("printerfmt")`.

## Files

| Installed at | What it is |
|---|---|
| `/usr/lib/printerfmt.lua` | pure layout: character widths transcribed from the mod, wrapping, pagination, paper and ink costs. No component, no files. |
| `/usr/lib/printer.lua` | the hardware, the job, and the capability check |
| `/usr/modules/printer/init.lua` | the `printer` command |

The split is load-bearing: because the layout half is pure, it is tested off-box and works on a machine with no printer attached, which is how `printer preview` and `write`'s page view work.

## Why it asks for `peripheral.printer`

A printer writes to the world. It uses the player's paper and ink and drops physical pages into a chest, which is real actuation with a running cost: the same reason `piston` and `robot` are gated rather than covered by the blanket `component` grant. Installing a game must not also hand it your ink.

A library under `/usr/lib` is loaded through the real `require`, outside the sandbox's per-component filter, so the gate alone would not cover it. `printer.lua` therefore checks the capability itself, on every call. Its header explains the details; the base OS's `tos/peripheral/redstone.lua` (`#SEC H34`) is the precedent.

## Tests

From `TOS-Extras/`: `lua modules/printer/test_printer.lua`, against a fake printer that throws on failure the way the mod does.
