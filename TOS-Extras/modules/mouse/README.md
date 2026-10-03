# mouse — the mouse driver

TOS has no built-in mouse support, the way MS-DOS had none: the shell reads the keyboard. OpenComputers screens do report touches, drags, drops and scroll-wheel turns, though, and this package is the small DOS-style driver that turns those into something programs can use.

Install it and the TOS panels shell picks it up by itself: menus, tabs, the file list, dialogs and the editor become clickable and scrollable, with nothing to configure. `calc`, `mail`, `printer`, `stock`, `tetris`, `ttt` and `write` recommend it for the same reason.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install mouse`. `pkg disable mouse` turns mouse support in the shell back off without uninstalling it.

## Try it

```
mousetest
```

draws a few buttons and reports every click, drag, drop and scroll the screen sends. Click QUIT, or press `q` or Esc, to leave.

## Use it in your own program

```lua
local mouse = require("mouse")
local ev = mouse.pull(0.5)        -- nil after half a second with no mouse event
if ev and ev.type == "click" then
  print(("click at %d,%d, button %d"):format(ev.x, ev.y, ev.button))
end
```

| Function | Returns |
|---|---|
| `mouse.parse(name, ...)` | given one raw signal, a mouse event table, or `nil` for anything that is not a mouse signal. Pure, so use it inside your own `pullSignal` loop when you need the keyboard too. |
| `mouse.pull([timeout])` | waits for the next mouse event and returns it, or `nil` at the timeout. Swallows every other signal, keys included. |
| `mouse.isMouse(name)` | true for `touch`, `drag`, `drop` and `scroll` |
| `mouse.region(x, y, w, h, payload)` | a rectangle in screen cells, carrying whatever you like |
| `mouse.inside(region, x, y)` | whether a point falls inside it |
| `mouse.hit(regions, x, y)` | the payload of the first region containing the point, or `nil`. Add the topmost target first. |

An event is a table with `type` (`click`, `drag`, `drop` or `scroll`), `x` and `y` in character cells counted from 1, `screen`, `player`, and either `button` (0 left, 1 right) or, for `scroll`, `dir` (+1 up, -1 down).

## Files

| Installed at | What it is |
|---|---|
| `/usr/lib/mouse.lua` | the driver library, `require("mouse")` |
| `/usr/modules/mouse/init.lua` | the `mousetest` command, also a worked example |

It is pure userspace: it reads input signals and draws through the GPU, with the `component` and `fs.read` capabilities and nothing from the kernel. The shell's side of mouse support lives in the base OS, in `tos/shell/panels/mouse.lua`.

## Tests

From `TOS-Extras/`: `lua modules/mouse/test_mouse.lua`. The shell's side is tested in the base OS by `usr/lib/tests/test_panels_mouse.lua`.
