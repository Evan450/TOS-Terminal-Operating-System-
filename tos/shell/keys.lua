local r="string"local m={}
local n={quit={"^Q","F10","Esc"},help={"F1"},save={"^S"},find={"/"},refresh={"^R"},view={"F2"},copy={"Ctrl+Insert"},cut={"Shift+Delete","^X"},paste={"Shift+Insert","^V"}}
local w={quit="Close the current program, prompt or dialog",help="Show the program's help",save="Save",find="Filter / search within a list",refresh="Re-read and redraw",view="Switch the view (Home: tiles or files)",copy="Copy the selection (^C is the kernel's interrupt)",cut="Cut the selection",paste="Paste the clipboard"}
local s={["^B"]="background the current program (kernel)",["^T"]="switch tasks / open the Monitor (kernel)",["^C"]="interrupt the foreground program (kernel)"}
local o={esc={code=1},enter={code=28},tab={code=15},space={code=57},backspace={code=14},delete={code=211},insert={code=210},home={code=199},["end"]={code=207},pageup={code=201},pagedown={code=209},up={code=200},down={code=208},left={code=203},right={code=205}}for a=1,10 do o["f"..a]={code=58+a}end
o.f11,o.f12={code=87},{code=88}
function m.parse(a)if type(a)~=r then return nil end
local b=a:match("^%s*(.-)%s*$")if b==""then return nil end;local f=b:match("^%^(.)$")or
b:match("^[Cc][Tt][Rr][Ll][%+%-](.)$")if f then
local c=f:upper():byte()
if c and c>=64 and c<=95 then return{ch=c-64,ctrl=f:upper()}end;return nil end;local d,e={},b
while true do
local h,i=e:match("^([%a]+)[%+%-](.+)$")if not h then break end;local c=h:lower()
if c=="ctrl"or c=="control"then
d.ctrl=true elseif c=="shift"then d.shift=true elseif c=="alt"then d.alt=true else break end;e=i end;local g=o[e:lower()]if g then local c={code=g.code}
c.needCtrl,c.needShift,c.needAlt=d.ctrl,d.shift,d.alt;return c end
if e==b and#b==1 then
local c=b:byte()if c>=32 and c<127 then return{ch=c}end end;return nil end
function m.name(a)if type(a)~="table"then return"?"end
if a.ctrl then return"^"..a.ctrl end
if a.ch then
if a.ch<32 then return"^"..string.char(a.ch+64)end;return string.char(a.ch)end;local b=""if a.needCtrl then b=b.."Ctrl+"end
if a.needShift then b=b.."Shift+"end;if a.needAlt then b=b.."Alt+"end
for c,d in pairs(o)do if d.code==a.code then return b..
(c:gsub("^%l",string.upper))end end;return b.."code "..tostring(a.code)end
local t={[42]="shift",[54]="shift",[29]="ctrl",[157]="ctrl",[56]="alt",[184]="alt"}local q=15
function m.newMods()return{shift=false,ctrl=false,alt=false,at=0}end
function m.trackMods(a,c,d,e,b)if type(a)~="table"then return false end;b=b or 0
if a.at>0 and
(b-a.at)>q then a.shift,a.ctrl,a.alt=false,false,false end;local f=t[e]
if c=="key_down"then if f then a[f]=true;a.at=b;return true end;if
d and d>=32 then a.ctrl,a.alt=false,false end;a.at=b elseif c=="key_up"then if f then a[f]=false
a.at=b;return true end;a.at=b end;return false end;function m.modDown(a,b,c)if type(a)~="table"then return false end;if a.at>0 and
((c or 0)-a.at)>q then return false end
return a[b]==true end
m.MOD_CODES=t;m.STALE_AFTER=q;local p={}
local function u(a)local f,b=pcall(require,"kernel.fs")
local g,d=pcall(require,"kernel.serialize")if not
(f and g and b and d and b.exists and b.exists(a))then return nil end
local c=b.readFile(a)
if type(c)~=r or#c==0 or#c>8192 then return nil end;local h,e=pcall(d.decode,c,{maxBytes=8192})if
h and type(e)=="table"then return e end;return nil end
local function v(b,a)if type(a)~="table"then return end
for d,c in pairs(a)do
if n[d]~=nil and(type(c)==r or
type(c)=="table")then local f=
(type(c)==r)and{c}or c;local e={}for h,g in ipairs(f)do local i=m.parse(g)
if i then e[#e+1]=i end end;if#e>0 then b[d]=e end end end end
local function x(a)if not a or a==""then return nil end;return(a=="root")and"/root"or
("/home/"..a)end
function m.load(a)if not a then local f,e=pcall(require,"kernel.users")
if
f and e and e.currentSession then local g=e.currentSession()a=g and g.user or nil end end
local c=a or"*"if p[c]then return p[c]end;local b={}
for e,f in pairs(n)do local g={}for i,h in ipairs(f)do local j=m.parse(h)if j then
g[#g+1]=j end end;b[e]=g end;v(b,u("/etc/keys.cfg"))local d=x(a)if d then
v(b,u(d.."/.keys.cfg"))end;p[c]=b;return b end;function m.reload()p={}return true end
function m.is(d,b,c,e,a)local f=m.load(e)[d]
if not f then return false end
for h,g in ipairs(f)do if g.ch and b and g.ch==b then return true end
if g.code and c and
g.code==c then if not a then return true end;local i=g.needCtrl==true;local j=
g.needShift==true;local k=g.needAlt==true;if

(a.ctrl==true)==i and(a.shift==true)==j and(a.alt==true)==k then return true end end end;return false end
function m.label(a,b)local c=m.load(b)[a]if not c or#c==0 then return""end;local d={}
for f,e in
ipairs(c)do if e.code~=1 then d[#d+1]=m.name(e)end end;return table.concat(d," / ")end
function m.actions(a)local d=m.load(a)local b={}for e in pairs(n)do b[#b+1]=e end
table.sort(b)local c={}
for f,e in ipairs(b)do local g={}
for f,h in ipairs(d[e]or{})do g[#g+1]=m.name(h)end
c[#c+1]={action=e,keys=table.concat(g," "),help=w[e]or"",isDefault=table.concat(g," ")==
table.concat(n[e]," ")}end;return c end;function m.reserved()local a={}for b,c in pairs(s)do a[#a+1]={key=b,help=c}end
table.sort(a,function(c,d)return
c.key<d.key end)return a end;function m.isReserved(a)
local b=m.parse(a)if not b or not b.ctrl then return false end;return
s["^"..b.ctrl]~=nil end
m.DEFAULTS=n;return m