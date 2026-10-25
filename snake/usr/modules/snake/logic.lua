local c={}
c.DIRS={up={x=0,y=-1},down={x=0,y=1},left={x=-1,y=0},right={x=1,y=0}}local d={up="down",down="up",left="right",right="left"}
function c.newSnake(a,b)local e,f=math.floor(
a/2),math.floor(b/2)
return{w=a,h=b,body={{x=e,y=f},{x=e-1,y=f},{x=e-2,y=f}},dir="right",pendingDir="right",food=
nil,score=0,alive=true,grew=false}end
function c.turn(a,b)if not c.DIRS[b]then return false end;if
#a.body>1 and d[a.dir]==b then return false end;a.pendingDir=b;return true end
function c.hits(a,b,e,f)local g=#a.body- (f and 1 or 0)
for h=1,g do local i=a.body[h]if
i.x==b and i.y==e then return true end end;return false end
function c.placeFood(a,b)local e={}
for f=1,a.h do for g=1,a.w do
if not c.hits(a,g,f,false)then e[#e+1]={x=g,y=f}end end end;if#e==0 then a.food=nil;return false end;a.food=e[b(#e)]return true end
function c.step(a,b)if not a.alive then return a end;a.grew=false;a.dir=a.pendingDir
local g=c.DIRS[a.dir]local h=a.body[1]local e,f=h.x+g.x,h.y+g.y;if
e<1 or f<1 or e>a.w or f>a.h then a.alive=false;return a end
local i=(
a.food~=nil and a.food.x==e and a.food.y==f)if c.hits(a,e,f,not i)then a.alive=false;return a end
table.insert(a.body,1,{x=e,y=f})if i then a.score=a.score+1;a.grew=true;c.placeFood(a,b)else
table.remove(a.body)end;return a end
function c.snakeDelay(a)local b=0.22- (a*0.006)if b<0.07 then b=0.07 end;return b end;return c