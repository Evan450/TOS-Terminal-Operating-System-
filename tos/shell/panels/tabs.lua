local r,m,s="content","_swapKey","_swapLines"local l={}local t=120;local u=25;local o=0;local p=nil
local function v()if p==nil then
local b,a=pcall(require,"computer")
p=(b and type(a)=="table")and a or false end;return p or nil end
local function q()local b=_G._TOS and _G._TOS.kernel;if
not(b and b.getSwap)then return nil end;local c,a=pcall(b.getSwap)
if
c and type(a)=="table"and a.store and a.fetch then return a end;return nil end;local n
n={__index=function(a,b)if b~=r then return nil end;local e=rawget(a,m)if not e then return nil end
local c=q()local d=c and c.fetch(e)or nil;if type(d)~="table"then
d={{"(view content was paged out and could not be restored)"}}end;if c and c.free then
pcall(c.free,e)end;rawset(a,m,nil)rawset(a,s,nil)
rawset(a,r,d)if getmetatable(a)==n then setmetatable(a,nil)end;return
d end}function l.isPaged(a)
return type(a)=="table"and rawget(a,m)~=nil end
function l.pageOut(a)if
type(a)~="table"or l.isPaged(a)then return false end;if
a.type~="view"and a.type~="output"then return false end;if a.live then return false end
local b=rawget(a,r)if type(b)~="table"or#b<t then return false end;local c=q()if not c then return
false end;o=o+1;local d="shell.view."..o
local e,f=pcall(c.store,d,b)if not e or not f then return false end;rawset(a,m,d)
rawset(a,s,#b)rawset(a,r,nil)setmetatable(a,n)return true end
function l.dropPaged(a)if not l.isPaged(a)then return false end;local b=q()if b and b.free then
pcall(b.free,rawget(a,m))end;rawset(a,m,nil)if getmetatable(a)==n then
setmetatable(a,nil)end;return true end
function l.underPressure()local a=v()if not a then return false end;local c=
a.totalMemory and a.totalMemory()or 0;local e=
a.freeMemory and a.freeMemory()or 0;if c<=0 then return false end;local d=u;local b=
_G._TOS and _G._TOS.kernel
if b and b.getConfig then
local g,f=pcall(b.getConfig)
if g and f and f.get then
local h=tonumber(f.get("swapPressurePct"))if h and h>=0 and h<=100 then d=h end end end;return e< (c*d/100)end
function l.sweepCold(a,b)
if type(a)~="table"or type(a.tabs)~="table"then return 0 end
if not b and not l.underPressure()then return 0 end;local c=0;for d,e in ipairs(a.tabs)do
if d~=a.activeTab and l.pageOut(e)then c=c+1 end end;return c end
function l.pagedStats(a)local b,c=0,0
if
type(a)=="table"and type(a.tabs)=="table"then for e,d in ipairs(a.tabs)do if l.isPaged(d)then b=b+1
c=c+ (rawget(d,s)or 0)end end end;return b,c end
function l.create(a,c,d,b)local e={type=c,label=d}
if b then for f,g in pairs(b)do e[f]=g end end;a.tabs[#a.tabs+1]=e;a.activeTab=#a.tabs;return e end
function l.close(a,b)b=b or a.activeTab;local c=a.tabs[b]if not c or c.type=="shell"then return
false end
local e,d=pcall(require,"shell.panels.apps")
if e and d then if d.ensureBuiltins then pcall(d.ensureBuiltins)end
local f=d.get(c.type)if f and f.onClose then pcall(f.onClose,a,c)end end;l.dropPaged(c)table.remove(a.tabs,b)if
a.activeTab>#a.tabs then a.activeTab=#a.tabs end
if a.activeTab<1 then a.activeTab=1 end;return true end
function l.cycle(a,b)if#a.tabs<=1 then return end
a.activeTab=a.activeTab+ (b or 1)if a.activeTab>#a.tabs then a.activeTab=1 end;if a.activeTab<1 then a.activeTab=
#a.tabs end end;function l.find(a,b,c)
for e,d in ipairs(a.tabs)do if d.type==b and d.path==c then return e end end;return nil end;return l