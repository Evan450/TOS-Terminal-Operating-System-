local s,n,t="peripheral.robot","no robot component","invalid tank"
local u=require("kernel.hal")local v=require("compat.sides")local l={}local q
do
local b,a=pcall(require,"kernel.event")
if b and a and a.on then local function c(e,f,d)if d=="robot"then q=nil end end
a.on("component_removed",c,s)a.on("component_added",c,s)end end
local function m()local b,a=pcall(require,"kernel.process")if b and a and a.current then
local c=a.current()
if c and not(c.caps and c.caps[s])then return nil end end;if not q then
q=u.proxy("robot")end;return q end
local function o(a)if a==nil then return 3 end
if type(a)=="string"then local b=v[a:lower()]if not b then return nil,
"unknown side: "..a end;return b elseif type(a)=="number"and
a>=0 and a<=5 then return a end;return nil,"invalid side"end
local function p(a)a=tonumber(a)
if not a or a~=a then return nil,"invalid slot"end;a=math.floor(a)
if a<1 then return nil,"invalid slot (must be >= 1)"end;return a end
function l.forward()local a=m()if not a then return nil,n end;return a.move(3)end
function l.back()local a=m()if not a then return nil,n end;return a.move(2)end
function l.up()local a=m()if not a then return nil,n end;return a.move(1)end
function l.down()local a=m()if not a then return nil,n end;return a.move(0)end
function l.turnLeft()local a=m()if not a then return nil,n end;return a.turn(false)end
function l.turnRight()local a=m()if not a then return nil,n end;return a.turn(true)end;local function r(a)if a==nil then return nil end;return o(a)end
function l.swing(c,a,b)
local e=m()if not e then return nil,n end;local d,h=o(c)if not d then return nil,h end;local g,i=r(a)if
a~=nil and not g then return nil,i end;if g or b then return
e.swing(d,g or d,b and true or false)end;return e.swing(d)end
function l.use(d,a,b,c)local g=m()if not g then return nil,n end;local e,i=o(d)if not e then return nil,i end
local h,j=r(b)if b~=nil and not h then return nil,j end
if c~=nil then local f=tonumber(c)if
not f or f~=f or f<0 then return nil,"invalid duration"end;return g.use(e,h or e,
a and true or false,f)end
if h or a then return g.use(e,h or e,a and true or false)end;return g.use(e)end
function l.place(c,a,b)local e=m()if not e then return nil,n end;local d,h=o(c)if not d then return nil,h end
local g,i=r(a)if a~=nil and not g then return nil,i end;if g or b then return
e.place(d,g or d,b and true or false)end;return e.place(d)end;function l.detect(a)local b=m()if not b then return nil,n end;local c,d=o(a)if not c then return nil,d end;return
b.detect(c)end
function l.drop(a,b)
local c=m()if not c then return nil,n end;local d,e=o(a)if not d then return nil,e end;return
c.drop(d,b or 64)end
function l.suck(a,b)local c=m()if not c then return nil,n end;local d,e=o(a)if not d then return nil,e end;return c.suck(d,
b or 64)end
function l.select(a)local b=m()if not b then return nil,n end
if a==nil then return b.select()end;local c,d=p(a)if not c then return nil,d end;return b.select(c)end
function l.count(a)local b=m()if not b then return nil,n end;if a~=nil then local c,d=p(a)
if not c then return nil,d end;return b.count(c)end;return
b.count(b.select())end
function l.space(a)local b=m()if not b then return nil,n end;if a~=nil then local c,d=p(a)
if not c then return nil,d end;return b.space(c)end;return
b.space(b.select())end
function l.inventorySize()local a=m()if not a then return nil,n end;return a.inventorySize()end
function l.inventory()local a=m()if not a then return nil,n end;local c=a.inventorySize()local b={}for d=1,c
do local e=a.count(d)if e>0 then
b[#b+1]={slot=d,count=e,space=a.space(d)}end end
return b end
function l.durability()local a=m()if not a then return nil,n end;if a.durability==nil then return nil,
"robot component has no durability()"end
local c,b,d=pcall(a.durability)if not c then return nil,tostring(b)end;if b==nil then
return nil,d or"no tool equipped"end;return b end;function l.compare(a)local b=m()if not b then return nil,n end;local c,d=o(a)if not c then return nil,d end;return
b.compare(c)end
function l.compareTo(a)
local b=m()if not b then return nil,n end;local c,d=p(a)if not c then return nil,d end;return
b.compareTo(c)end
function l.transferTo(b,a)local c=m()if not c then return nil,n end;local d,f=p(b)
if not d then return nil,f end
if a~=nil then local e=tonumber(a)
if not e or e~=e or e<0 then return nil,"invalid count"end;return c.transferTo(d,math.floor(e))end;return c.transferTo(d)end
function l.tankCount()local a=m()if not a then return nil,n end;return a.tankCount()end
function l.selectTank(a)local b=m()if not b then return nil,n end;local c,d=p(a)
if not c then return nil,t end;return b.selectTank(c)end
function l.tankLevel(a)local b=m()if not b then return nil,n end;if a~=nil then local c=p(a)
if not c then return nil,t end;return b.tankLevel(c)end;return
b.tankLevel()end
function l.tankSpace(a)local b=m()if not b then return nil,n end;if a~=nil then local c=p(a)
if not c then return nil,t end;return b.tankSpace(c)end;return
b.tankSpace()end
function l.getLightColor()local a=m()if not a then return nil,n end;return a.getLightColor()end
function l.setLightColor(a)local c=m()if not c then return nil,n end;local b=tonumber(a)if not b or b~=b then return nil,
"invalid colour"end;return
c.setLightColor(math.floor(b))end
function l.name()local a=m()if not a then return nil,n end;return a.name()end;function l.available()return m()~=nil end
function l.refresh()q=nil;return m()~=nil end;return l