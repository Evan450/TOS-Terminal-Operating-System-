local d="scroll"local c={}
function c.parse(a,b,e,f,g,h)
if a=="touch"then
return{type="click",x=e,y=f,button=g or 0,screen=b,player=h}elseif a=="drag"then return{type="drag",x=e,y=f,button=g or 0,screen=b,player=h}elseif a==
"drop"then return{type="drop",x=e,y=f,button=g or 0,screen=b,player=h}elseif a==d then local i=
(g or 0)>=0 and 1 or-1
return{type=d,x=e,y=f,dir=i,screen=b,player=h}end;return nil end;function c.isMouse(a)return
a=="touch"or a=="drag"or a=="drop"or a==d end
function c.pull(a)
local b=require("computer")local e=b.uptime()+ (a or math.huge)
repeat
local f=e-b.uptime()if f<0 then f=0 end;local g=table.pack(b.pullSignal(f))
local h=c.parse(table.unpack(g,1,g.n))if h then return h end until b.uptime()>=e;return nil end;function c.region(a,b,e,f,g)return{x=a,y=b,w=e,h=f,payload=g}end
function c.inside(a,b,e)return b>=
a.x and b<=a.x+a.w-1 and e>=a.y and
e<=a.y+a.h-1 end;function c.hit(a,b,e)
for g,f in ipairs(a)do if c.inside(f,b,e)then return f.payload,f end end;return nil end
c._VERSION="1.1.0"return c