
local F,G,z,H,I,C,A="drop failed","inventory_controller","no inventory component","no inventory on that side","peripheral.inventory","requires inventory_controller","transposer"local D=require("kernel.hal")local J=require("compat.sides")
local u={}local s;local w;local t;local function E()s=nil;w=nil;t=nil end
do
local b,a=pcall(require,"kernel.event")
if b and a and a.on then
a.on("component_removed",function(d,e,c)if
c==G or c==A or c=="tank_controller"then E()end end,I)
a.on("component_added",function(d,e,c)if c==G or c==A then E()end end,I)end end
local function v()local b,a=pcall(require,"kernel.process")if b and a and a.current then
local c=a.current()
if c and not(c.caps and c.caps[I])then return nil end end;if t then return t end
s=D.proxy(G)if s then t="ic"return t end;w=D.proxy(A)if w then t=A;return t end;return nil end
local function x(a)
if type(a)=="string"then local b=J[a:lower()]if not b then
return nil,"unknown side: "..a end;return b elseif
type(a)=="number"and a>=0 and a<=5 then return a end;return nil,"invalid side"end
local function B(a)a=tonumber(a)if not a or a~=a then return 64 end;a=math.floor(a)if a<
0 then a=0 end;return a end
local function y(a)a=tonumber(a)
if not a or a~=a then return nil,"invalid slot"end;a=math.floor(a)
if a<1 then return nil,"invalid slot (must be >= 1)"end;return a end
function u.size(a)if not v()then return nil,z end;local b,c=x(a)if not b then return nil,c end
local d=s or w;local e,f=pcall(d.getInventorySize,b)if not e then return nil,H end;return f end
function u.getSlot(a,b)if not v()then return nil,z end;local c,d=x(a)if not c then return nil,d end
local e=s or w;local f,g=pcall(e.getStackInSlot,c,b)
if not f then return nil,"failed to read slot"end;return g end
function u.getInternalSlot(a)if not v()or t~="ic"then return nil,C end
local b,c=pcall(s.getStackInInternalSlot,a)if not b then return nil,"failed to read internal slot"end;return c end
function u.list(a)if not v()then return nil,z end;local b,f=x(a)if not b then return nil,f end
local d=s or w;local g,e=pcall(d.getInventorySize,b)
if not g or not e then return nil,H end;local c={}
for h=1,e do local j,i=pcall(d.getStackInSlot,b,h)if j and i then
c[#c+1]={slot=h,name=
i.label or i.name or"?",count=i.size or i.count or 0}end end;return c end
function u.stacks(a)if not v()then return nil,z end;local b,g=x(a)if not b then return nil,g end
local c=s or w
local function e(j,i)if type(i)~="table"then return nil end;local k=
tonumber(i.size or i.count)or 0;if k<=0 then return nil end;local l=
i.name or i.label or"?"local m=tonumber(i.damage)or 0;return
{slot=j,id=l,label=
i.label or i.name or"?",count=k,max=tonumber(i.maxSize or i.maxDamage)or nil,damage=m,key=
l.."#"..tostring(m)}end
if c.getAllStacks then local j,i=pcall(c.getAllStacks,b)
if j and i then
local l,k=pcall(function()return i.getAll()end)
if l and type(k)=="table"then local m={}for n=0,#k do local o=e(n+1,k[n])
if o then m[#m+1]=o end end;return m end end end;local h,f=pcall(c.getInventorySize,b)
if not h or not f then return nil,H end;local d={}
for j=1,f do local i,k=pcall(c.getStackInSlot,b,j)if i then local l=e(j,k)if l then
d[#d+1]=l end end end;return d end
function u.sides()if not v()then return{}end;local b=s or w;local a={}
local c={[0]="bottom","top","north","south","west","east"}
for d=0,5 do local f,e=pcall(b.getInventorySize,d)if
f and type(e)=="number"and e>0 then
a[#a+1]={side=d,name=c[d]or tostring(d),size=e}end end;return a end
function u.transfer(e,d,b,c,a)if not v()then return nil,z end;b=B(b)if c~=nil then local f,g=y(c)if not f then
return nil,"fromSlot: "..g end;c=f end
if a~=nil then
local f,g=y(a)if not f then return nil,"toSlot: "..g end;a=f end
if t==A then local f,h=x(e)if not f then return nil,h end;local g,i=x(d)if not g then return nil,i end
local j,k=pcall(w.transferItem,f,g,b,c,a)if not j then return nil,"transfer failed"end;return k end
if t=="ic"then local f,g=x(d)if not f then return nil,g end
if a then
local h,i=pcall(s.dropIntoSlot,f,a,b)if not h then return nil,F end;return i else local h,i=pcall(s.dropIntoSlot,f,1,b)if
not h then return nil,F end;return i end end;return nil,"no transfer method available"end
function u.suckFromSlot(a,b,c)if not v()or t~="ic"then return nil,C end;local d,f=x(a)if not d then
return nil,f end;local e,g=y(b)if not e then return nil,g end
local h,i=pcall(s.suckFromSlot,d,e,B(c))if not h then return nil,"suck failed"end;return i end
function u.dropIntoSlot(a,b,c)if not v()or t~="ic"then return nil,C end;local d,f=x(a)if not d then
return nil,f end;local e,g=y(b)if not e then return nil,g end
local h,i=pcall(s.dropIntoSlot,d,e,B(c))if not h then return nil,F end;return i end
function u.equip()if not v()or t~="ic"then return nil,C end;return s.equip()end;function u.available()return v()~=nil end;function u.getMode()v()return t end;function u.refresh()s,w,t=
nil,nil,nil;return v()~=nil end;return u