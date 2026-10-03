# calc — a spreadsheet

Cells, formulas, save and load, and CSV export, in a full-screen grid drawn in the TOS look. A sheet has up to 78 columns (A to BZ) and 512 rows.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install calc`. With an internet card and a repository configured, `pkg fetch calc` does the same from the network (TOS manual, §7.9).

It is complete on the keyboard. With the `mouse` driver also installed, a click selects the cell under the pointer and the wheel scrolls.

## Use

```
calc                 a new, empty sheet
calc budget.calc     open a sheet
```

| Key | Does |
|---|---|
| arrows, PgUp, PgDn | move the cursor |
| Home, End | first column, last column in use |
| Enter, or just start typing | edit the cell; Enter then moves down a row |
| Del, Backspace | clear the cell |
| Ctrl+S | save (asks for a name the first time) |
| Ctrl+O | open another sheet |
| Ctrl+E | export as CSV |
| Ctrl+B | send it to the background; Ctrl+T brings it back |
| Ctrl+Q | quit, asking first if there are unsaved changes |

A cell holds a number, some text, or a formula starting with `=`:

```
=A1*2
=SUM(B1:B9)
=IF(C3>100, "over", "ok")
=C3%7          remainder; ^ is power
```

Operators are `+ - * / % ^`, the comparisons `= <> < > <= >=`, and parentheses. The functions are `SUM`, `AVERAGE` (or `AVG`), `MIN`, `MAX`, `COUNT`, `ABS`, `SQRT`, `FLOOR`, `CEIL` (or `CEILING`), `INT`, `ROUND`, `POWER`, `MOD`, `IF`, `AND`, `OR`, `NOT`, `LEN`, `UPPER`, `LOWER` and `CONCAT`.

An error spreads to every cell that depends on it, as in any spreadsheet: `#DIV/0!`, `#REF!`, `#NAME?` (an unknown function), `#VALUE!`, `#SYNTAX!`, and `#CYCLE!` on each cell of a reference loop, which is reported rather than hanging the program.

## The file

A `.calc` file is plain text: a `TOSCALC1` line, then one cell per line as `A1`, a tab, and what you typed, with tabs and newlines inside a cell escaped. You can read it, diff it and fix it by hand. Loading one only ever puts text into cells.

## Why the formulas are parsed, not run

The usual shortcut for a spreadsheet is to rewrite `=A1*2` into Lua and `load()` it. That would make every saved sheet an executable file, with the sandbox the only thing between a shared `.calc` and the machine. calc has a hand-written tokenizer and recursive-descent parser over a fixed grammar instead, so nothing a cell contains is ever executed: the worst a hostile formula can do is evaluate to an error. It is also why the package does not ask for the `load` capability. It runs with `fs.read`, `fs.write` and `component` only, and a sheet is saved with the permissions of the user who ran `calc`.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/calc/init.lua` | the program: drawing, keys, the file prompts |
| `/usr/modules/calc/sheet.lua` | the sheet model and formula engine; pure, no I/O |

## Tests

From `TOS-Extras/`: `lua modules/calc/test_calc.lua` covers the engine, including a canary that fails if any cell content can make code run, and `lua modules/calc/test_calc_keybar.lua` checks the key bar is measured in screen columns and never cut mid-word. `python run_tests.py` in the TOS source runs every add-on test with the OS's own.
