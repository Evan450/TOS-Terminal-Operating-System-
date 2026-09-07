# Screenshots: what to capture, and where they go

The repository has no images. That is the single largest thing standing between
TOS and anyone finding it: on the OpenComputers forum, on Discord, on Reddit,
**the screenshot is the post**. A wall of text about an OS gets scrolled past.

This file is the shot list so the capture session is mechanical.

## Where the files go

`docs/screenshots/` on the **`dev`** branch, at the exact filenames below. The
README references them by absolute `raw.githubusercontent.com` URL pinned to
`dev`, so one copy renders correctly on every branch.

**Before publishing, one prerequisite:** `publish.ps1` refuses any top-level
directory that is not on its allowlist, and `docs` is not on it. Add it to the
`$Dev` branch's `$AllowedDirs` (beside `build` and `TOS-Extras`) or the first
`-Dev -Push` after adding images will stop with "Refusing to publish files that
are not on the allowlist." Keep it out of the `main` allowlist: install payloads
should not carry screenshots.

Then delete the `<!-- SCREENSHOTS ... -->` comment wrapper at the top of
`README.md` — the markup inside it is already written.

## The shots

Capture at a readable resolution (a Tier 2 GPU on an 80×25 screen reads well;
Tier 3 at higher density looks better but shrinks the text in a thumbnail).
Crop to the screen — no emulator chrome, no desktop wallpaper.

| File | What is on screen | Why this one |
|---|---|---|
| `desktop.png` | The tile Desktop, populated (`desktop`, or System → Desktop) | The single best "this is not a shell" image. Lead with it. |
| `rbmk.png` | The RBMK supervisor's reactor core map | The cross-fandom hook. Coordinate-ruled grid, ░▒▓ ramps — it does not look like anything else in OC. |
| `files.png` | The file browser with type glyphs and a modal open | Shows the double-line frame, the shadow, and that dialogs are real UI. |
| `themes.png` | Two or three themes side by side, same screen | The nine named themes are invisible in text. One image settles it. |
| `login.png` | The login screen | First thing a new operator sees; establishes "this has accounts". |
| `monitor.png` | `monitor` (Ctrl+T) with processes and memory live | Evidence of multitasking and the memory discipline the project is built around. |
| `boot.gif` | boot → login → Desktop → one theme switch | The motion shot. Keep it under ~15 s and loop it. |

## Capturing

TOS is developed against the Ocelot desktop emulator
(`Documents\Ocelot Destop Emulator\`), which is the practical way to get a
clean, croppable frame without launching Minecraft. Any screen recorder that
can export a GIF will do for `boot.gif`.

Two things to check before shooting:

- **Log in as a normal user, not root**, for `desktop.png` and `files.png`.
  Root's landing view defaults to the file list and its Desktop is missing the
  tiles a normal account sees.
- **Set the theme deliberately.** The default is fine, but pick one and use the
  same one for every still except `themes.png`, so the set looks like one
  system rather than seven screenshots of different programs.

## What not to do

Do not reconstruct these from `screendump` output or draw them by hand. A
screendump is text plus a colour map — useful for bug reports, not a substitute
for a capture. An image that looks like a screenshot but was generated is the
same class of claim this project spent v1.5.0 removing.
