local g=require("peripheral.robot")local h,i,j=3,1,0;local f={}function f.name()
return g.name()end;function f.level()return 0 end;function f.getLightColor()
return g.getLightColor()end
function f.setLightColor(a)return g.setLightColor(a)end;function f.detect()return g.detect(h)end
function f.detectUp()return g.detect(i)end;function f.detectDown()return g.detect(j)end;function f.inventorySize()
return g.inventorySize()end;function f.select(a)return g.select(a)end;function f.count(a)return
g.count(a)end;function f.space(a)return g.space(a)end;function f.compareTo(a)return
g.compareTo(a)end
function f.transferTo(a,b)return g.transferTo(a,b)end;function f.compare()return g.compare(h)end
function f.compareUp()return g.compare(i)end;function f.compareDown()return g.compare(j)end
function f.drop(a)return g.drop(h,a)end;function f.dropUp(a)return g.drop(i,a)end
function f.dropDown(a)return g.drop(j,a)end;function f.suck(a)return g.suck(h,a)end
function f.suckUp(a)return g.suck(i,a)end;function f.suckDown(a)return g.suck(j,a)end
function f.place(a,b)return g.place(h,a,b)end;function f.placeUp(a,b)return g.place(i,a,b)end;function f.placeDown(a,b)
return g.place(j,a,b)end
function f.durability()return g.durability()end;function f.swing(a,b)return g.swing(h,a,b)end;function f.swingUp(a,b)
return g.swing(i,a,b)end
function f.swingDown(a,b)return g.swing(j,a,b)end;function f.use(a,b,c)return g.use(h,b,a,c)end
function f.useUp(a,b,c)return g.use(i,b,a,c)end;function f.useDown(a,b,c)return g.use(j,b,a,c)end;function f.forward()
return g.forward()end;function f.back()return g.back()end
function f.up()return g.up()end;function f.down()return g.down()end
function f.turnLeft()return g.turnLeft()end;function f.turnRight()return g.turnRight()end
function f.turnAround()
local a,b=g.turnLeft()if not a then return a,b end;return g.turnLeft()end;function f.tankCount()return g.tankCount()end;function f.selectTank(a)
return g.selectTank(a)end
function f.tankLevel(a)return g.tankLevel(a)end;function f.tankSpace(a)return g.tankSpace(a)end;return f