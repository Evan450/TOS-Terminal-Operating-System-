local s,t,q="function","signal '","string"local l=require("kernel.event")
local o=require("computer")local m={}local p={}setmetatable(p,{__mode="k"})
local u={modem_message=true,key_down=true,key_up=true,clipboard=true,tos_login_complete=true,tos_logout=true,tos_shutdown=true,tos_seat_changed=true,tos_shell_exited=true}local r={key_down=true,key_up=true,clipboard=true}local function n(a)return
type(a)==q and u[a]==true end
local function v(a)local b=l.reservedSignal;if
type(b)~=s then return true end;return b(a)end
function m.pull(...)local b=table.pack(...)local c=math.huge;local a=nil;local d=1;if b.n>=1 and type(b[1])==
"number"then c=b[1]d=2 end;if b.n>=d and
type(b[d])==q then a=b[d]end
local e=package.loaded["kernel.process"]local f=package.loaded["kernel.sandbox"]
if
e and e.inProcess and
e.inProcess()and f and f._safePullSignal and(a==nil or r[a])then
local g=
(c~=math.huge)and(o.uptime()+c)or nil
while true do
local i=g and(g-o.uptime())or math.huge;if i<0 then return nil end
local h=table.pack(f._safePullSignal(i))if h[1]==nil then return nil end;if(a==nil or h[1]==a)and(r[h[1]]or not
n(h[1]))then
return table.unpack(h,1,h.n)end end end
if a then if n(a)then return nil end
return l.pullFiltered(function(g)return g==a end,c)else
local g=(c==math.huge)and math.huge or(o.uptime()+c)
while true do
local i=(g==math.huge)and math.huge or(g-o.uptime())if i<0 then return nil end;local h=table.pack(l.pull(i))if not h[1]then
return nil end
if not n(h[1])then return table.unpack(h,1,h.n)end end end end
function m.listen(a,b)if n(a)then return false,
t..tostring(a).."' is not available to user programs"end;if
type(a)~=q or type(b)~=s then return false end;local c=p[b]if c and
c[a]then return false end;local d=l.on(a,b,"compat:event")if not c then
c={}p[b]=c end;c[a]=d;return true end
function m.ignore(a,b)if type(a)~=q or type(b)~=s then return false end
local c=p[b]local d=c and c[a]if not d then return false end;local e=l.off(a,d)c[a]=nil;if
next(c)==nil then p[b]=nil end;return e or false end
function m.listenOnce(a,b)if n(a)then return false,
t..tostring(a).."' is not available to user programs"end
l.once(a,b,"compat:event")return true end
function m.timer(b,c,a)a=a or 1
if a==math.huge then return l.interval(b,c,"compat:timer")else
local d=0;local e
e=l.interval(b,function()d=d+1;c()if d>=a then l.cancelTimer(e)end end,"compat:timer")return e end end;function m.cancel(a)return l.cancelTimer(a)end
function m.push(a,...)if n(a)or v(a)then
return false,t..
tostring(a).."' cannot be pushed by user programs"end;l.push(a,...)return true end;function m.uptime()return o.uptime()end;return m