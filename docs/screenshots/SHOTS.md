# Screenshots: what to capture, and where they go

The repository had no images. That is the single largest thing standing between TOS and anyone finding it: on the OpenComputers forum, on Discord, on Reddit, **the screenshot is the post**. A wall of text about an OS gets scrolled past.

This file is the shot list so the capture session is mechanical.

## Captured 2026-11-06

Taken from Ocelot Desktop 1.14.2, running build `07bf795` (the signed release) freshly copied onto the boot disk of a scratch copy of the workspace. The screen is a Tier 2 GPU at 80×25, captured losslessly at its native 640×400: exactly the screen's content, with no window frame. The stills are logged in as an ordinary user, `steve`, in the default theme, except where a shot needs otherwise.

| File | What it shows |
|---|---|
| `desktop.png` | `steve`'s tile Desktop, just after `theme set default` |
| `files.png` | `steve`'s home in the file browser, with F8's delete dialog open on `notes.txt` (then cancelled) |
| `themes.png` | the Desktop in `default`, `amber` and `nord`: three captures of the same screen, placed side by side |
| `login.png` | the login screen |
| `monitor.png` | the System Monitor as **root**, which lists the services too; as `steve` it shows only steve's own shell |
| `boot.gif` | power on → boot → login as `steve` → Desktop → `theme set amber` |

`boot.gif` is real frames, 4.8 per second, in recorded order and unaltered. What was taken out: `steve`'s first-login tutorial (a one-time screen), the ten seconds the Desktop sat still before the theme switch (its first frame is held instead), and frames that differed from the last only by the in-game clock or the cursor blinking (under 300 changed pixels). Long waits are cut to half a second. 60 s were recorded and 16.9 s loop. The login screen in it says the last shutdown was unsafe: the machine was switched off at the case button before recording, and that is TOS's real power-loss check.

**Still to capture: `rbmk.png`.** The RBMK supervisor needs HBM's reactor console, which only exists in a Minecraft world with HBM's Nuclear Tech Mod; Ocelot has no such component. Take it in-world. Until then the README shows `files.png` in its place.

## Where the files go

`docs/screenshots/` on the **`dev`** branch, at the exact filenames below. The README references them by absolute `raw.githubusercontent.com` URL pinned to `dev`, so one copy renders correctly on every branch.

`publish.ps1` refuses any top-level directory that is not on its allowlist. `docs` is on the `dev` list (so screenshots publish with the source) and deliberately **not** on `main`'s: that is the branch installers download, and a Tier 2 drive with about 150 KB left after first boot has no business carrying images it will never open.

Then delete the `<!-- SCREENSHOTS ... -->` comment wrapper at the top of `README.md` — the markup inside it is already written.

## The shots

Capture at a readable resolution (a Tier 2 GPU on an 80×25 screen reads well; Tier 3 at higher density looks better but shrinks the text in a thumbnail). Crop to the screen — no emulator chrome, no desktop wallpaper.

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

TOS is developed against Ocelot Desktop, the standalone OpenComputers emulator, which is the practical way to get a clean, croppable frame without launching Minecraft. Any screen recorder that can export a GIF will do for `boot.gif`.

Two things to check before shooting:

- **Log in as a normal user, not root**, for `desktop.png` and `files.png`. Root's landing view defaults to the file list and its Desktop is missing the tiles a normal account sees.
- **Set the theme deliberately.** The default is fine, but pick one and use the same one for every still except `themes.png`, so the set looks like one system rather than seven screenshots of different programs.

## What not to do

Do not reconstruct these from `screendump` output or draw them by hand. A screendump is text plus a colour map — useful for bug reports, not a substitute for a capture. An image that looks like a screenshot but was generated is the same class of claim this project spent v1.5.0 removing.
