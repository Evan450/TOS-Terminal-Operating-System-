--! THIS FILE IS A RENAME LAYER AND NOTHING ELSE. It holds no component
--! proxy, performs no capability check and never touches `component`:
--! every call goes through kernel.peripheral.robot, where the
--! `peripheral.robot` cap is checked once per call (#SEC H34). That is the
--! whole point of doing it here rather than reimplementing OpenOS's
--! lib/robot.lua against the raw proxy — authority stays in one file, and
--! this one cannot widen it.
--!
--! THE ONLY REAL WORK IS SHAPE. OpenOS names the DIRECTION in the function
--! and takes no side argument:
--!     robot.swingDown()     robot.dropUp(count)     robot.detect()
--! where ours takes the side as a parameter. So every entry below is a
--! direction-bound alias: front (3), top (1), bottom (0). Confirmed
--! against the mod's own Agent.scala callback docs and against Plan9k's
--! lib/robot.lua, which is the reference implementation of the same API
--! (base OpenOS ships no lib/robot.lua — it arrives with the robot).
--!
--! NO ROBOT, OR NO CAP: the peripheral module returns nil plus a reason,
--! so these do too. OpenOS would raise, because `component.robot` is nil
--! there and indexing it throws. Returning the reason is the house
--! convention and it tells a program the difference between "no robot"
--! and "wrong arguments" — but a program that ignores the return and
--! chains calls will simply do nothing rather than stopping, which is
--! worth knowing when one misbehaves. (test_compat_robot.lua)

local P = require("peripheral.robot")

local FRONT, UP, DOWN = 3, 1, 0

local robot = {}

function robot.name() return P.name() end

--! OpenOS reads the experience upgrade here, which is a SEPARATE component
--! type ("experience"), not the robot. Reaching it from under the
--! `peripheral.robot` cap would hand a robot program a component its cap
--! never mentioned, so we do not. 0 is what OpenOS itself returns on a
--! robot with no experience upgrade, so a program reading this sees a
--! state that genuinely occurs rather than an error it has no branch for.
function robot.level() return 0 end

function robot.getLightColor() return P.getLightColor() end
function robot.setLightColor(value) return P.setLightColor(value) end

function robot.detect()     return P.detect(FRONT) end
function robot.detectUp()   return P.detect(UP)    end
function robot.detectDown() return P.detect(DOWN)  end

function robot.inventorySize() return P.inventorySize() end
function robot.select(slot)    return P.select(slot) end
function robot.count(slot)     return P.count(slot) end
function robot.space(slot)     return P.space(slot) end
function robot.compareTo(slot) return P.compareTo(slot) end
function robot.transferTo(slot, count) return P.transferTo(slot, count) end

function robot.compare()     return P.compare(FRONT) end
function robot.compareUp()   return P.compare(UP)    end
function robot.compareDown() return P.compare(DOWN)  end

function robot.drop(count)     return P.drop(FRONT, count) end
function robot.dropUp(count)   return P.drop(UP,    count) end
function robot.dropDown(count) return P.drop(DOWN,  count) end

function robot.suck(count)     return P.suck(FRONT, count) end
function robot.suckUp(count)   return P.suck(UP,    count) end
function robot.suckDown(count) return P.suck(DOWN,  count) end

--! OpenOS's first argument to place/swing/use is the FACE (a finer click
--! target on the block), not the direction — the direction is in the
--! function name. Ours takes (side, face, sneaky), so the direction is
--! supplied here and the caller's `side` argument is passed through as the
--! face, which is what it has always meant on OpenOS.
function robot.place(face, sneaky)     return P.place(FRONT, face, sneaky) end
function robot.placeUp(face, sneaky)   return P.place(UP,    face, sneaky) end
function robot.placeDown(face, sneaky) return P.place(DOWN,  face, sneaky) end

function robot.durability() return P.durability() end

function robot.swing(face, sneaky)     return P.swing(FRONT, face, sneaky) end
function robot.swingUp(face, sneaky)   return P.swing(UP,    face, sneaky) end
function robot.swingDown(face, sneaky) return P.swing(DOWN,  face, sneaky) end

--! use()'s parameters are reordered, not dropped: ours is
--! use(side, sneaking, face, duration) because `sneaking` has been its
--! second parameter since it was written (see the note in
--! peripheral/robot.lua), while OpenOS is use(face, sneaky, duration).
function robot.use(face, sneaky, duration)
  return P.use(FRONT, sneaky, face, duration)
end
function robot.useUp(face, sneaky, duration)
  return P.use(UP, sneaky, face, duration)
end
function robot.useDown(face, sneaky, duration)
  return P.use(DOWN, sneaky, face, duration)
end

function robot.forward()   return P.forward()   end
function robot.back()      return P.back()      end
function robot.up()        return P.up()        end
function robot.down()      return P.down()      end
function robot.turnLeft()  return P.turnLeft()  end
function robot.turnRight() return P.turnRight() end

--! Two turns the SAME way. OpenOS picks the direction at random per call,
--! which is a coin flip inside a movement primitive: a program that tracks
--! its own heading gets the same end facing either way, but a program
--! watching for the intermediate one does not, and an unseeded
--! math.random makes that unreproducible. Left twice, always.
function robot.turnAround()
  local ok, err = P.turnLeft()
  if not ok then return ok, err end
  return P.turnLeft()
end

function robot.tankCount()      return P.tankCount()      end
function robot.selectTank(tank)  return P.selectTank(tank)  end
function robot.tankLevel(tank)   return P.tankLevel(tank)   end
function robot.tankSpace(tank)   return P.tankSpace(tank)   end

return robot
