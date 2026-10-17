local m="program"local i={}local j={}
function i.register(a)
assert(type(a)=="table"and
type(a.type)=="string","app spec needs a string `type`")j[a.type]=a;return a end;function i.get(a)return j[a]end;function i.has(a)return j[a]~=nil end
function i.types()
local a={}for b in pairs(j)do a[#a+1]=b end;table.sort(a)return a end
local p={desktop="shell.panels.desktop",settings="shell.panels.settingsapp",monitor="shell.panels.monitorapp",chat="shell.panels.chatapp",mail="mailapp",intercom="intercomapp"}local k;local l=false
function i.ensureBuiltins()if l then return end;l=true;if k and not j[k.type]then
i.register(k)end
for a,b in pairs(p)do
if not j[a]then local d,c=pcall(require,b)
if
d and c and c.draw then
i.register({type=a,model="inshell",draw=c.draw,onKey=c.handleKey and function(f,g,e)
return c.handleKey(f,g,e.ch,e.co,{exec=e.exec})end or
nil,onMouse=c.handleClick and function(e,f,g,h)
return c.handleClick(e,f,g,h)end or nil,onScroll=

c.handleScroll and function(e,f,g)return c.handleScroll(e,f,g)end or nil,tick=c.tick,onClose=c.onClose,_module=c})end end end end
local function n(a)if not a or not a.pid then return nil,nil end
local d,b=pcall(require,"kernel.process")
if not d or type(b)~="table"or not b.get then return nil,nil end;local c=b.get(a.pid)if not c or
(b.STATE and c.state==b.STATE.DEAD)then return b,nil end;return b,c end
local function o(a,b)local e,c=n(b)if c then return e,c end
local f,d=pcall(require,"shell.panels.tabs")
if f and d and a and a.tabs then for g,h in ipairs(a.tabs)do
if h==b then d.close(a,g)break end end end;return nil,nil end
k={type=m,model="process",title=function(a)return a.prog or a.label or m end,draw=function(a,b)
local c,e=o(a,b)if not e then return end;local d=b.seat or a.displayIdx;if not d then return end
a.suspendIdleDraw=true
if a.D and a.D.invalidate then pcall(a.D.invalidate)end;c.setForeground(b.pid,d,{kernel=true})
(c.signalKernel or c.signal)(b.pid,"tos_focus")end,refresh=function(b,a)
local c,d=o(b,a)if not d then return end
if c.bgState then local e,f=pcall(c.bgState,a.pid)a.live=
e and f~="frozen"or false end end,onClose=function(b,a)
local c,d=n(a)
if c and d then pcall(c.kill,a.pid,{kernel=true})end end}i.register(k)
function i.refreshTabs(a)
if not a or type(a.tabs)~="table"then return end;local b={}for c,d in ipairs(a.tabs)do b[c]=d end
for d,c in ipairs(b)do local e=j[c.type]if e and
e.refresh then pcall(e.refresh,a,c)end end end
function i.chipsChanged(a)
if not a or type(a.tabs)~="table"then return false end;local c=false
for f,e in ipairs(a.tabs)do if e.type==m then c=true;break end end
if not c then local e=a._chipSig;a._chipSig=nil;return e~=nil end;i.refreshTabs(a)local b={}for f,e in ipairs(a.tabs)do
if e.type==m then b[#b+1]=tostring(e.pid).. (
e.live and"+"or"-")end end
b=table.concat(b,",")local d=b~=a._chipSig;a._chipSig=b;return d end;function i._reset()j={}l=false end;return i