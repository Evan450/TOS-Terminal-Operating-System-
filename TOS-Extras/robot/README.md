# robot — programs for the robot's own chip

`eeprom-rc-pilot.lua` is the robot half of the `rc-pilot` add-on: the program an OpenComputers robot or Computronics drone runs from its EEPROM, with no operating system, to take signed movement frames from `rc` on a TOS computer. How to set up and fly a robot is in [the rc-pilot README](../modules/rc-pilot/README.md).

## Burn the minified file, not this one

An EEPROM holds 4096 bytes, and `flash` refuses anything larger. This source, with its comments, is about 6 KB; minified it is 3,683 bytes. So the program is written for its minified size, short names and all, and the comments here never reach the chip.

You do not usually need to minify it yourself. Since rc-pilot 1.2.0 the Optional Utilities build does it and ships the result inside the package, as `/usr/share/rc-pilot/eeprom-rc-pilot.lua`, hashed and signed with the rest of the package. The build refuses to produce a pack if the image is over 4096 bytes or does not load as Lua.

To minify it by hand, from `TOS-Extras/` in a clone of the dev branch:

```
lua ../build/strip.lua robot <out-dir> --minify
```

## Tests

`modules/rc-pilot/test_rc_pilot.lua` runs this program against the real `rc` command and checks that the minified image fits the chip.
