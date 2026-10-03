# write — a word processor

TOS already has `edit`, and this is not a second text editor. The difference is the **page**: `write` knows how wide a printed line is in pixels and how many lines fit on a sheet, so it shows where your document breaks, live, while you type, along with what it will cost in paper and ink before you spend either.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install write`. It **requires** the `printer` package, and the picker selects `printer` alongside it, marks it `[+]` and counts it in what will be installed, so nothing arrives behind your back. `mouse` is recommended, not needed.

The printer *hardware* is optional. Writing, pagination, the page view and saving all work on a machine with no printer in the world.

## Use

```
write /home/report.txt
```

opens the document, creating it if it doesn't exist. Give a full path.

| Key | Does |
|---|---|
| F1 | help |
| F2 or Ctrl+S | save |
| F3 | print |
| F4 | set the title |
| F5 | switch between the text and the page view |
| F6 | start a new page here |
| F7 | centre this line, or un-centre it |
| Ctrl+B | send it to the background; Ctrl+T brings it back |
| Ctrl+Q | quit, asking to save first if there are changes |

The page view is a read-only proof: PgUp and PgDn turn the sheets.

The rail under the title shows the page and line you are on, the word count, and the cost in sheets, black ink and colour ink. It ends `[printer widths]` when the breaks come from the attached printer's own measurements, or `[estimated widths]` when they come from the driver's transcribed table, because an estimated break and a real one are not equally trustworthy.

## The file is plain text

Formatting rides on dot commands at the start of a line, the roff way:

```
.title My Report      the printed item's name
.center               centre from here on (.left goes back)
.color 0xFF0000       colour from here on (.color off stops)
.page                 start a new page
..                    a line that really does start with a dot
```

So a document can be read with `cat`, searched with `grep`, fixed in `edit` and sent by `mail`, and it is never executable. Colour costs a unit of colour ink for every line printed in it, which is why it is something you turn on rather than a default.

## Why it depends on `printer`

It is the one hard dependency between add-ons in the set, and it is deliberate. The page model (widths, wrapping, pagination, costs) lives in the driver's `printerfmt.lua`. Without it there is no page, and a word processor with no page is `edit` with extra steps. A `write` that carried its own copy would mean two definitions of how tall a page is, drifting apart. The reverse does not hold: plenty of machines want the driver and the `printer` command with no word processor anywhere near them, so the two stay separate packages.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/write/init.lua` | the program: drawing, keys, files |
| `/usr/modules/write/doc.lua` | the document model: parsing the dot commands and finding the page breaks; pure |

It asks for `fs.read` and `fs.write` for documents, `component` for the screen and `peripheral.printer` to print. No `load`, because a document is never run, and no network. When backgrounded it freezes completely, since an editor holds unsaved work and nothing should touch it while you are not looking.

## Tests

From `TOS-Extras/`: `lua modules/write/test_write.lua`. Most of it pins the mapping from a line of the source to its page, because when that goes wrong the ruler drifts silently.
