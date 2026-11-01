# pic — pictures on a text screen

Shows a MineOS `.pic` or a PNG on any GPU, from a disk or straight off the internet card. Tier 3 gets 256 colours, tier 2 gets 16, and tier 1 gets dithered black and white. It's a viewer and a converter in one, and the PNG decoder runs on the machine, so nothing outside it is involved.

## Install

As admin, with the Optional Utilities disk inserted: `pkg install pic`. No disk? [Install it over the network](../../README.md).

## Use

```
pic picture.png                 show one picture
pic /home/me/pictures           show a directory; N and P move between them
pic http://example.com/a.png    fetch one and show it
pic info picture.pic            its format and size
pic convert in.png out.pic      make a .pic
```

`open picture.png` works too, once `pic` is installed.

| Key | Does |
|---|---|
| F | full size, or fit to the screen |
| Arrows | pan a picture bigger than the screen, Home for the top left |
| B | hide the bar, for the whole screen |
| N, P | next and previous, also PgDn and PgUp |
| Ctrl+Q | quit |

`pic convert` takes `--width N` and `--height N` in cells, `--tier 1|2|3` for the screen it's meant for, and `--no-dither`. It defaults to 160x50 and tier 3, so say `--tier` if the picture is for a smaller GPU: dithering for the colours a screen really has looks far better than letting the GPU pick the nearest one.

## What to expect

A cell is `▀` with one colour above and one below, so a picture gets two square pixels per cell. A full tier 3 screen is 160x100 pixels, tier 2 is 80x50 and tier 1 is 50x32.

- **Photographs** look best on tier 3. Tier 2 has only 16 fixed colours, so a photograph comes out grainy, and flat artwork fares better there.
- **A big PNG takes time**, because it's unpacked in Lua. A 512x384 picture took about 3 seconds on an emulated machine with a tier 2 APU. Keep `.pic` for anything you open often: it needs no unpacking.
- **Memory**: a `.pic` showed on 1.25 MB, the least an add-on runs on. A 512x384 PNG needed 2 MB: at 1.25 MB it says there isn't enough memory and goes back to the shell. Unpacking holds a 32 KB window, and Lua stores that a number at a time. On a small machine, convert the picture on a bigger one and bring the `.pic`.
- **Interlaced PNGs and JPEGs** aren't read. Save as a plain PNG.
- **Transparency** shows the dark behind the picture.

## The format

`.pic` is MineOS's OCIF, methods 5 to 8, worked out from MineOS's own `Image.lua` and `Color.lua`. None of its code is used here, only its file format. Pictures made for MineOS open here, and what `pic convert` writes is the same format. A cell in a `.pic` can hold any character, so braille and text art show as drawn, though only whole cells of them can be scaled.
