# calc — a spreadsheet, the Lotus 1-2-3 way

A keyboard program of the kind that kept the world's books before windows: the three-line control panel across the top, the mode in the corner, and every command a `/` and a few letters away. Formulas are typed or pointed at; ranges are anchored and stretched with the arrows; numbers take formats; ranges copy, move, sort and graph. A sheet has up to 78 columns (A to BZ) and 512 rows.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install calc`. With an internet card and a repository configured, `pkg fetch calc` does the same from the network (TOS manual, §7.9).

It needs nothing else. Three packages make it better and are offered, never installed for you:

| With | You also get |
|---|---|
| `printer` | `/Print Printer`: the range on paper, columns lined up by the pixel, cost shown before anything is spent |
| `write` | `/Print Document`: the range laid out as pages and opened in write, unsaved, to finish as a report |
| `mouse` | click a cell, a menu item, or a cell while pointing |

## Opening files

`calc budget.calc` opens a worksheet; `calc data.csv` imports the CSV into a new one named after it (`data.calc`), so saving never turns the CSV itself into a worksheet file. calc tells TOS that `.calc` is its own format and that it can open `.csv`, so `open budget.calc`, and Enter on either in the file browser, bring them here (`man open`).

## The screen

```
A5: (C2) [W12] @SUM(A2..A4)                                          READY
                                                       <- what you type, or the menu
                                                       <- the menu's next level, or a message
     A        B        C ...
1    Sales
...
▓▒░ budget.calc *  / Menu · F1 Help · F2 Edit · F5 Goto · F9 Calc       CALC ░▒▓
```

The first line is the cell under the pointer: its address, its format and width when they are its own, and what is in it. The corner shows the mode: **READY**, **LABEL** or **VALUE** while you type, **EDIT**, **POINT** while you point at cells, **MENU**, and a few others. The bottom line shows the file, `*` for unsaved changes, and **CALC** (recalculation is due), **CIRC** (a circular reference) and **END** (the End key is waiting for an arrow).

## Entering

Just type. A digit or one of `+ - . ( @ # $ =` starts a **value** (a number or a formula); anything else starts a **label**. Enter stores it and leaves the pointer where it is; an arrow stores it and moves.

While you type a formula, an arrow after an operator, `(` or `,` starts **pointing**: the pointer moves and its address is written into the formula; `.` anchors it so the arrows stretch a range; typing the next operator carries on. **F4** cycles the reference before the cursor through `A1`, `$A$1`, `A$1`, `$A1`. A value that does not parse beeps and drops into EDIT with the reason, as 1-2-3 did: fix it, or put `'` in front to make it a label.

A label can start with a prefix: `'` left, `"` right, `^` centred, `\` repeated across the column (`\-` draws a rule). One typed without a prefix gets the worksheet's default.

| Key | Does |
|---|---|
| arrows, PgUp, PgDn, Tab | move a cell, a screen of rows, a screen of columns |
| Home | to A1 (or the first cell past frozen titles) |
| End, then an arrow | to the edge of the data that way |
| F1 / F2 / F3 | help / edit the cell / range names |
| F5 | go to a cell or a range name |
| F9 | recalculate (in manual recalculation) |
| Del | clear the cell |
| `/` | the menu |
| Ctrl+S | save |
| Ctrl+B | send it to the background; Ctrl+T brings it back |
| Ctrl+Q | quit, asking first if there are unsaved changes |

Esc belongs to Minecraft (it closes the screen), so where 1-2-3 used Esc, calc uses **Backspace** to go back a step and **Ctrl+Q** to cancel outright.

## Formulas

```
+A1*2          @SUM(A1..A9)          @IF(C3>100,"over","ok")
=A1*2          =SUM(A1:A9)           (calc 1's spelling still works)
+B1&" "&C1     text formulas start with + too
@SUM(SALES)    a range name
```

Operators: `+ - * / % ^`, the comparisons `= <> < > <= >=`, `#AND# #OR# #NOT#`, and `&` to join text. A range is `A1..B9`, `A1.B9` or `A1:B9`. `$A$1` is absolute: Copy leaves it alone where `A1` moves with the copy.

The @functions are `@SUM @AVG @AVERAGE @MIN @MAX @COUNT @STD @VAR`, `@ABS @SQRT @INT @ROUND @MOD @POWER @FLOOR @CEIL @EXP @LN @LOG @PI @SIN @COS @TAN @ASIN @ACOS @ATAN @ATAN2`, `@PMT @PV @FV @NPV`, `@IF @AND @OR @NOT @TRUE @FALSE @CHOOSE @VLOOKUP @HLOOKUP @ISERR @ISNA @ISNUMBER @ISSTRING @NA @ERR`, and the text functions `@LEFT @RIGHT @MID @FIND @LENGTH @LEN @REPEAT @TRIM @PROPER @UPPER @LOWER @EXACT @STRING @VALUE @CONCAT`. Their argument orders are 1-2-3's, and like 1-2-3, `@CHOOSE`, `@MID`, `@FIND` and the lookups' offset count from **zero**. `@STD` and `@VAR` are the population figures.

An error spreads to every cell that depends on it: `#DIV/0!`, `#REF!`, `#NAME?`, `#VALUE!`, `#SYNTAX!`, `#N/A`, and `#CYCLE!` on each cell of a reference loop, which is reported (CIRC) rather than hanging the program.

## The menu

`/` opens it. Each item is picked by its first letter, or by the arrows and Enter; the third line shows what is under the highlighted item. Backspace goes back a level.

| | |
|---|---|
| **Worksheet** | Global (format, label prefix, column width, recalculation), Insert and Delete columns or rows, Column width, Erase, Titles (freeze rows and columns), Status |
| **Range** | Format, Label, Erase, Name (create, delete, reset, table), Value (freeze formulas into numbers) |
| **Copy**, **Move** | ranges, with every reference adjusted the 1-2-3 way |
| **File** | Retrieve, Save, Import (CSV), Export (CSV), List, Directory |
| **Print** | Printer (with the driver), File (.prn text), Document (with write); then Range, Options, Preview, Go |
| **Graph** | Type (bar or line), the X labels and A/B/C data ranges, View, titles |
| **Data** | Fill (start, step, stop), Sort (data range, primary and secondary keys) |
| **Quit** | |

A range prompt starts anchored at the pointer, as in 1-2-3: the arrows stretch it, Backspace lets go of the anchor, `.` drops it again, and you can always type an address or a range name instead.

Formats: Fixed, Scientific, Currency (`$1,234.50`, a negative one bracketed), `,` (thousands), General, `+/-` (a bar of `+` or `-`, one per unit), Percent, Text (show the formula), Hidden. A number too wide for its column shows asterisks, never a wrong number.

## Printing

A range lays out the same way for every destination, so the preview is what you get. On paper (OpenPrinter: 164 pixels by 20 lines, in a proportional font) columns are placed by the pixel, and a range wider than a page continues on further pages, down first and then across. Every print asks first and shows its cost in paper and ink. A header or footer splits into left, centre and right with `|`, and `#` is the page number. **Cell-Formulas** prints what is in each cell instead of what it shows.

**Document** hands the pages to write inside calc's own process, as no-fill text (write 1.1's `.nf`) so the columns survive. Nothing reaches the disk unless you save it in write; quitting write brings you back.

## The file

A `.calc` file is plain text: a `TOSCALC2` line, then one cell per line as `A1`, a tab, and what you typed (tabs and newlines inside a cell escaped), then the settings, each on a line starting with `#`: formats, widths, range names, recalculation, and the print, graph and sort settings. You can read it, diff it and fix it by hand; loading one only ever puts text into cells and validated values into settings. A calc 1 sheet (`TOSCALC1`) opens with its meaning intact: text that 1-2-3's rules would now read as a formula, like `(note)` or `5 apples`, is given the `'` that keeps it a label.

A file name without a directory is taken in your home directory; `/File Directory` changes that.

## Why the formulas are parsed, not run

The usual shortcut for a spreadsheet is to rewrite `=A1*2` into Lua and `load()` it. That would make every saved sheet an executable file, with the sandbox the only thing between a shared `.calc` and the machine. calc has a hand-written tokenizer and recursive-descent parser over a fixed grammar instead, so nothing a cell contains is ever executed: the worst a hostile formula can do is evaluate to an error. It is also why the package does not ask for the `load` capability. It runs with `fs.read`, `fs.write`, `component` and `peripheral.printer` (for `/Print Printer`, which asks before it spends paper or ink), and a sheet is saved with the permissions of the user who ran `calc`.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/calc/init.lua` | the screen, the keys, the menus' commands |
| `/usr/modules/calc/sheet.lua` | the sheet model and formula engine; pure, no I/O |
| `/usr/modules/calc/ops.lua` | Copy, Move, Insert, Delete, Sort, Fill: the operations that rewrite formulas |
| `/usr/modules/calc/menu.lua` | the `/` menu tree, as data |
| `/usr/modules/calc/print.lua` | page layout for the printer, a file and write |
| `/usr/modules/calc/graph.lua` | `/Graph`, drawn in characters |

The last four are loaded only when used.

calc 2 is a bigger program than calc 1: on the headless test machine, a short session leaves about 267 KB less memory free where calc 1 left 171 KB (measured the same way, menu opened once). That is well inside what TOS needs anyway, but on a machine near its floor it is the price of the menus.

## Tests

From `TOS-Extras/`: `lua modules/calc/test_calc.lua` (the engine, including a canary that fails if any cell content can make code run), `lua modules/calc/test_calc_lotus.lua` (1-2-3's syntax, the new functions, formats, names, the v2 file and v1 compatibility, and every operation that rewrites formulas), `lua modules/calc/test_calc_ui.lua` (the real screen driven key by key through a fake GPU, keyboard, home, printer and write) and `lua modules/calc/test_calc_keybar.lua`. `python run_tests.py` in the TOS source runs them all with the OS's own.
