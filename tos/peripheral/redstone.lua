local t,p,s="bundled not supported","no redstone component","peripheral.redstone"
local u=require("kernel.hal")local v=require("compat.sides")local l={}local q
do
local b,a=pcall(require,"kernel.event")
if b and a and a.on then local function c(e,f,d)if d=="redstone"then q=nil end end
a.on("component_removed",c,s)a.on("component_added",c,s)end end
local function n()local b,a=pcall(require,"kernel.process")
if b and a and a.current then
local c=a.current()if not c then return true end
if c.caps and c.caps[s]then return true end;return false,"peripheral.redstone cap required"end;return true end
local function m()local b,a=pcall(require,"kernel.process")if b and a and a.current then
local c=a.current()
if c and not(c.caps and c.caps[s])then return nil end end;if not q then
q=u.proxy("redstone")end;return q end
local function o(a)
if type(a)=="string"then local b=v[a:lower()]if not b then
return nil,"unknown side: "..a end;return b elseif
type(a)=="number"and a>=0 and a<=5 then return a end;return nil,"invalid side (expected 0-5 or name)"end
local function r(a)if type(a)=="number"then return a end
if type(a)=="string"then
local c,b=pcall(require,"compat.colors")if c and b[a:lower()]then return b[a:lower()]end;return nil,
"unknown color: "..a end;return nil,"invalid color"end
function l.getInput(a)local d,e=n()if not d then return nil,e end;local b=m()if not b then return nil,p end
local c,f=o(a)if not c then return nil,f end;return b.getInput(c)end
function l.getOutput(a)local d,e=n()if not d then return nil,e end;local b=m()if not b then return nil,p end
local c,f=o(a)if not c then return nil,f end;return b.getOutput(c)end
function l.setOutput(b,a)local f,c=n()if not f then return nil,c end;local d=m()if not d then return nil,p end
local e,c=o(b)if not e then return nil,c end
a=math.max(0,math.min(15,math.floor(a or 0)))d.setOutput(e,a)return true end
function l.getComparatorInput(a)local d,e=n()if not d then return nil,e end;local b=m()
if not b then return nil,p end;local c,f=o(a)if not c then return nil,f end;return b.getComparatorInput(c)end
function l.getBundledInput(a,b)local d,h=n()if not d then return nil,h end;local e=m()
if not e then return nil,p end;local f,i=o(a)if not f then return nil,i end;local g,j=r(b)if not g then return nil,j end
local d,k=pcall(e.getBundledInput,f,g)if not d then return nil,t end;return k end
function l.getBundledOutput(a,b)local d,h=n()if not d then return nil,h end;local e=m()
if not e then return nil,p end;local f,i=o(a)if not f then return nil,i end;local g,j=r(b)if not g then return nil,j end
local d,k=pcall(e.getBundledOutput,f,g)if not d then return nil,t end;return k end
function l.setBundledOutput(b,c,a)local d,h=n()if not d then return nil,h end;local e=m()
if not e then return nil,p end;local f,i=o(b)if not f then return nil,i end;local g,j=r(c)if not g then return nil,j end
a=math.max(0,math.min(255,math.floor(
a or 0)))local d,k=pcall(e.setBundledOutput,f,g,a)
if not d then return nil,t end;return true end
function l.pulse(b,a)local c=30;a=tonumber(a)or 0.5;if a~=a then a=0.5 end;if a<0 then a=0 end;if
a>c then a=c end;local d,e=l.setOutput(b,15)if not d then return nil,e end
if os.sleep then
os.sleep(a)else require("computer").pullSignal(a)end;l.setOutput(b,0)return true end
function l.status()local c,d=n()if not c then return nil,d end;local a=m()if not a then return nil,p end
local e={"bottom","top","back","front","right","left"}local b={}for f=0,5 do
b[#b+1]={name=e[f+1],input=a.getInput(f),output=a.getOutput(f)}end;return b end;function l.available()return m()~=nil end
function l.refresh()q=nil;return m()~=nil end;return l