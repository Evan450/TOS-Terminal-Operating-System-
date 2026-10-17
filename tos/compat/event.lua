local p,q,r="string","function","signal '"local k=require("kernel.event")
local o=require("computer")local l={}local m={}setmetatable(m,{__mode="k"})
local s={modem_message=true,key_down=true,key_up=true,clipboard=true,tos_login_complete=true,tos_logout=true,tos_shutdown=true,tos_seat_changed=true,tos_shell_exited=true}
local function n(a)return type(a)==p and s[a]==true end
local function t(a)local b=k.reservedSignal;if type(b)~=q then return true end;return b(a)end
function l.pull(...)local a=table.pack(...)local b=math.huge;local c=nil;local d=1;if a.n>=1 and type(a[1])==
"number"then b=a[1]d=2 end;if a.n>=d and
type(a[d])==p then c=a[d]end
if c then if n(c)then return nil end;return k.pullFiltered(function(e)return
e==c end,b)else
local e=(b==
math.huge)and math.huge or(o.uptime()+b)
while true do
local g=(e==math.huge)and math.huge or(e-o.uptime())if g<0 then return nil end;local f=table.pack(k.pull(g))if not f[1]then
return nil end
if not n(f[1])then return table.unpack(f,1,f.n)end end end end
function l.listen(a,b)if n(a)then return false,
r..tostring(a).."' is not available to user programs"end;if
type(a)~=p or type(b)~=q then return false end;local c=m[b]if c and
c[a]then return false end;local d=k.on(a,b,"compat:event")if not c then
c={}m[b]=c end;c[a]=d;return true end
function l.ignore(a,b)if type(a)~=p or type(b)~=q then return false end
local c=m[b]local d=c and c[a]if not d then return false end;local e=k.off(a,d)c[a]=nil;if
next(c)==nil then m[b]=nil end;return e or false end
function l.listenOnce(a,b)if n(a)then return false,
r..tostring(a).."' is not available to user programs"end
k.once(a,b,"compat:event")return true end
function l.timer(b,c,a)a=a or 1
if a==math.huge then return k.interval(b,c,"compat:timer")else
local d=0;local e
e=k.interval(b,function()d=d+1;c()if d>=a then k.cancelTimer(e)end end,"compat:timer")return e end end;function l.cancel(a)return k.cancelTimer(a)end
function l.push(a,...)if n(a)or t(a)then
return false,r..
tostring(a).."' cannot be pushed by user programs"end;k.push(a,...)return true end;function l.uptime()return o.uptime()end;return l