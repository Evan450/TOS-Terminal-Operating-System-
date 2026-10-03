# PaneUI — the TOS look on OpenOS

What Windows 3.x was to DOS, PaneUI is to OpenOS: a full-screen environment you live in. Browse files, view and edit them with Lua syntax highlighting, and run OpenOS programs from a command line inside the window, all in the TOS look, coming back to the environment when they finish. It is a single Lua file for machines that run OpenOS rather than TOS.

It is not part of TOS and does not install through `pkg`, so it is not on the Optional Utilities disk.

## Install

Copy `PaneUI.lua` onto the OpenOS machine as `/home/paneui.lua`, then run `paneui`. Give it a directory to start in, `paneui /some/dir`, or it opens `/home`.

## Use

The file browser:

| Key | Does |
|---|---|
| Up, Down, PgUp, PgDn, Home, End | move the selection |
| Enter | open a folder, or view a file |
| Backspace | up one folder |
| F3 | view the selected file |
| F4 | edit it, or a new file when nothing is selected |
| F5 | copy it |
| F6 | move or rename it |
| F7 | make a folder |
| F8 | delete it, after asking |
| F9 | drop to the OpenOS shell; `exit` comes back |
| F1 | help |
| F2 | the next tab |
| F10 or Ctrl+Q | quit to OpenOS |

The command line under the browser is always live: type a command and press Enter, and its output opens in a viewer tab. Up and Down recall earlier commands once you have started typing. `cd`, `clear` and `exit` are handled by PaneUI itself, and `themes` and `theme <name>` choose a theme.

The editor saves with Ctrl+S and undoes with Ctrl+Z; Ctrl+Q or F10 closes its tab, asking first if there are unsaved changes. The browser tab is always there. A tab with unsaved work or live output is shown in brackets, and tabs that do not fit collapse into a `«N` chip.

## The same look as TOS

PaneUI carries the nine TOS themes (default, midnight, amber, green, plasma, classic, contrast, nord and solarized), colour for colour, worked out for the GPU tier the same way TOS does it. The chosen one is kept in `/home/.paneui-theme`. It also follows TOS's visual grammar: a double line and a shadow mark a dialog that wants an answer, dim rails carry the structure, shading appears only at edges, and data is bright while chrome is dim.

It runs on OpenOS, so it cannot load TOS's code; it keeps copies instead. The tests below hold those copies to the originals in the TOS source, so the two cannot drift apart unnoticed.

**PaneUI is not a security boundary.** It runs with whatever permissions OpenOS gave it, with no TOS file protection underneath. It is an environment and a file manager, not a sandbox.

## Tests

From `TOS-Extras/`:

- `lua pane-ui/test_paneui_grammar.lua`: PaneUI's glyphs and visual grammar match TOS's own `tos/shell/panels/ui.lua`
- `lua pane-ui/test_paneui_themes.lua`: its nine themes are TOS's nine themes
- `lua pane-ui/test_paneui_syntax_utf8.lua`: the highlighter never splits a multi-byte character
- `lua pane-ui/test_paneui_move.lua`: Move reports what actually happened
