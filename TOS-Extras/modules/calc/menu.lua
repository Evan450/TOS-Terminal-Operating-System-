-- ╔══════════════════════════════════════════════════════════════╗
-- ║  calc — the / menu, as data                                  ║
-- ║                                                              ║
-- ║  1-2-3's command tree, trimmed to what calc does. Each item  ║
-- ║  is picked by its FIRST LETTER (they are unique per level,   ║
-- ║  as in 1-2-3) or by the arrows and Enter; the third line of  ║
-- ║  the control panel shows the highlighted item's submenu, or  ║
-- ║  what it does. A leaf names a command `cmd` that init.lua    ║
-- ║  carries out; `stay` keeps its menu open afterwards, the way ║
-- ║  1-2-3's Print, Graph and Sort menus wait for Quit.          ║
-- ║                                                              ║
-- ║  The Print menu is built per call: Printer only appears with ║
-- ║  the printer driver installed and Document only with write,  ║
-- ║  so calc never offers what the machine cannot do.            ║
-- ╚══════════════════════════════════════════════════════════════╝

local MENU = {}

local function item(label, desc, x)
  local it = { label = label, desc = desc }
  if type(x) == "table" then it.items = x else it.cmd = x end
  return it
end
local function leaf(label, desc, cmd, stay) local it = item(label, desc, cmd); it.stay = stay; return it end

local function formats(prefix)
  return {
    leaf("Fixed", "Fixed number of decimal places: x.xx", prefix .. "F"),
    leaf("Scientific", "Exponential notation: x.xxE+xx", prefix .. "S"),
    leaf("Currency", "Dollar sign, thousands separators: $x,xxx.xx", prefix .. "C"),
    leaf(",", "Thousands separators: x,xxx.xx", prefix .. ","),
    leaf("General", "As many digits as fit the column", prefix .. "G"),
    leaf("+/-", "A bar of + or - characters, one per unit", prefix .. "+"),
    leaf("Percent", "Times 100, with a % sign: x.xx%", prefix .. "P"),
    leaf("Text", "Show the formula instead of its value", prefix .. "T"),
    leaf("Hidden", "Show nothing at all", prefix .. "H"),
  }
end

--- The whole tree. `env.printer` and `env.write` say which optional
--- packages are installed.
function MENU.root(env)
  env = env or {}
  local rangeFormat = formats("range.format:")
  rangeFormat[#rangeFormat + 1] = leaf("Reset", "Back to the worksheet's global format", "range.format:reset")

  local printTargets = {}
  local printSub = function(target)
    return {
      leaf("Range", "Choose the range to print", "print.range", true),
      item("Options", "Header, footer, and what to print", {
        leaf("Header", "A line at the top of every page (| splits left|centre|right, # is the page)", "print.header", true),
        leaf("Footer", "A line at the bottom of every page", "print.footer", true),
        item("Other", "Print values or the formulas behind them", {
          leaf("As-Displayed", "Print cells as they appear", "print.displayed", true),
          leaf("Cell-Formulas", "List every cell's contents, one per line", "print.formulas", true),
        }),
        leaf("Quit", "Back to the Print menu", "menu.up"),
      }),
      leaf("Preview", "See the pages before anything is used up", "print.preview:" .. target, true),
      leaf("Go", "Print the range", "print.go:" .. target, true),
      leaf("Clear", "Forget the print range and options", "print.clear", true),
      leaf("Quit", "Leave the Print menu", "menu.quit"),
    }
  end
  if env.printer then
    printTargets[#printTargets + 1] = item("Printer", "Print on paper, through the printer driver", printSub("printer"))
  end
  printTargets[#printTargets + 1] = item("File", "Print to a text file", printSub("file"))
  if env.write then
    printTargets[#printTargets + 1] = item("Document", "Lay it out as a page and open it in write", printSub("write"))
  end

  return {
    item("Worksheet", "Global settings, insert and delete, columns, titles, erase", {
      item("Global", "Settings for the whole worksheet", {
        item("Format", "The format of every cell without its own", formats("global.format:")),
        item("Label-Prefix", "How a label typed without a prefix lines up", {
          leaf("Left", "Labels line up on the left ( ' )", "global.prefix:'"),
          leaf("Right", "Labels line up on the right ( \" )", "global.prefix:\""),
          leaf("Center", "Labels are centred ( ^ )", "global.prefix:^"),
        }),
        leaf("Column-Width", "The width of every column without its own", "global.width"),
        item("Recalculation", "When formulas are worked out", {
          leaf("Automatic", "After every entry", "global.recalc:auto"),
          leaf("Manual", "Only when F9 is pressed (CALC shows when it is due)", "global.recalc:manual"),
        }),
      }),
      item("Insert", "Insert blank columns or rows", {
        leaf("Column", "Insert columns at the cursor", "ws.insert:col"),
        leaf("Row", "Insert rows at the cursor", "ws.insert:row"),
      }),
      item("Delete", "Delete whole columns or rows", {
        leaf("Column", "Delete columns", "ws.delete:col"),
        leaf("Row", "Delete rows", "ws.delete:row"),
      }),
      item("Column", "This column's width", {
        leaf("Set-Width", "Set the width (the arrows change it as you watch)", "col.width"),
        leaf("Reset-Width", "Back to the global width", "col.reset"),
      }),
      item("Erase", "Clear the whole worksheet", {
        leaf("No", "Keep it", "menu.quit"),
        leaf("Yes", "Erase everything", "ws.erase"),
      }),
      item("Titles", "Freeze rows and columns while the rest scrolls", {
        leaf("Both", "Freeze the rows above and the columns left of the cursor", "titles:both"),
        leaf("Horizontal", "Freeze the rows above the cursor", "titles:h"),
        leaf("Vertical", "Freeze the columns left of the cursor", "titles:v"),
        leaf("Clear", "Unfreeze", "titles:clear"),
      }),
      leaf("Status", "The worksheet's settings and memory", "ws.status"),
    }),
    item("Range", "Format, label, erase, name, or freeze the values of a range", {
      item("Format", "The format of a range of cells", rangeFormat),
      item("Label", "Line up the labels in a range", {
        leaf("Left", "Left", "range.label:'"),
        leaf("Right", "Right", "range.label:\""),
        leaf("Center", "Centre", "range.label:^"),
      }),
      leaf("Erase", "Clear a range (its formats stay)", "range.erase"),
      item("Name", "Give a range a name formulas can use", {
        leaf("Create", "Name a range", "name.create"),
        leaf("Delete", "Forget one name", "name.delete"),
        leaf("Reset", "Forget every name", "name.reset"),
        leaf("Table", "Write the list of names into the sheet", "name.table"),
      }),
      leaf("Value", "Copy a range's values, not its formulas", "range.value"),
    }),
    leaf("Copy", "Copy a range; references adjust, $ parts stay", "copy"),
    leaf("Move", "Move a range; everything pointing at it follows", "move"),
    item("File", "Retrieve, save, import, export", {
      leaf("Retrieve", "Open a worksheet", "file.retrieve"),
      leaf("Save", "Save this worksheet", "file.save"),
      leaf("Import", "Read a CSV file in at the cursor", "file.import"),
      leaf("Export", "Write the values as a CSV file", "file.export"),
      leaf("List", "Worksheets in the current directory", "file.list"),
      leaf("Directory", "The directory files are read from and saved to", "file.dir"),
    }),
    item("Print", "Print a range on paper, to a file, or into write", printTargets),
    item("Graph", "Draw a bar or line graph of a range", {
      item("Type", "Bar or line", {
        leaf("Line", "Points joined by a line", "graph.type:line", true),
        leaf("Bar", "Bars side by side", "graph.type:bar", true),
      }),
      leaf("X", "The labels along the bottom", "graph.range:x", true),
      leaf("A", "The first data range", "graph.range:a", true),
      leaf("B", "The second data range", "graph.range:b", true),
      leaf("C", "The third data range", "graph.range:c", true),
      leaf("Reset", "Forget every graph setting", "graph.reset", true),
      leaf("View", "Draw it", "graph.view", true),
      item("Options", "Titles", {
        leaf("First-Title", "The graph's title", "graph.title:title1", true),
        leaf("Second-Title", "A second line under it", "graph.title:title2", true),
        leaf("Quit", "Back to the Graph menu", "menu.up"),
      }),
      leaf("Quit", "Leave the Graph menu", "menu.quit"),
    }),
    item("Data", "Fill a range with numbers, or sort it", {
      leaf("Fill", "Start, step, stop: down each column in turn", "data.fill"),
      item("Sort", "Sort the rows of a range", {
        leaf("Data-Range", "The rows to sort (not their headings)", "sort.range", true),
        leaf("Primary-Key", "The column to sort by, and which way", "sort.key1", true),
        leaf("Secondary-Key", "The column for ties", "sort.key2", true),
        leaf("Reset", "Forget the sort settings", "sort.reset", true),
        leaf("Go", "Sort", "sort.go"),
        leaf("Quit", "Leave the Sort menu", "menu.quit"),
      }),
    }),
    item("Quit", "Leave calc", {
      leaf("No", "Stay", "menu.quit"),
      leaf("Yes", "Leave (asking about unsaved changes first)", "app.quit"),
    }),
  }
end

--- The item a key picks in a menu: its first letter, case aside. "," is
--- the Comma format's own key, as in 1-2-3.
function MENU.byKey(items, ch)
  if type(ch) ~= "string" or ch == "" then return nil end
  ch = ch:lower()
  for i, it in ipairs(items) do
    if it.label:sub(1, 1):lower() == ch then return i end
  end
  return nil
end

--- First letters must be unique per level, or a key would pick two
--- items. Returns the first clash found, for the test.
function MENU.clash(items, path)
  path = path or "/"
  local seen = {}
  for _, it in ipairs(items) do
    local k = it.label:sub(1, 1):lower()
    if seen[k] then return path .. " " .. seen[k] .. "/" .. it.label end
    seen[k] = it.label
    if it.items then
      local c = MENU.clash(it.items, path .. it.label .. " ")
      if c then return c end
    end
  end
  return nil
end

return MENU
