
local function B(a,b,c)if c and a and a>=32 and a<127 then return false end
local e,d=pcall(require,"shell.keys")if e and d and d.is then return d.is("quit",a,b)end;return
a==17 or b==1 end
local function u()local c,b=pcall(require,"shell.keys")local a=c and b and b.label and
b.label("quit")or""
a=a:gsub(" / .*","")return a~=""and a or"^Q"end;local F=require("computer")local w=require("shell.panels.ui")
local x=require("shell.panels.tabs")local s=require("mail")local r={}local t=4
local function y(a)return math.max(1,(a-1)-t)end
function r.label(a)if(a or 0)>0 then return"Mail("..a..")"end;return"Mail"end
local function G(a,b)return(s.inboxBox(a.who or"user"))end
function r.refresh(b,a)s.tick()local c=G(b,a)a._box=c;local d=
(c and c.unread and c:unread())or 0;a.unread=d
if
b.tabs[b.activeTab]==a then a.label=r.label(0)else a.label=r.label(d)end end;local function v(a)local c=a._box
return(c and c.list and c:list())or{}end
function r.open(a)local c=x.find(a,"mail")local b;if c then
b=a.tabs[c]a.activeTab=c else
b=x.create(a,"mail","Mail",{mode="list",sel=1,scroll=0,readScroll=0,live=true,interval=2})end
r.refresh(a,b)return b end
local function H(b,a)local c={}
for d in
(tostring(b or"").."\n"):gmatch("(.-)\n")do if d==""then c[#c+1]=""else
while#d>0 do c[#c+1]=d:sub(1,a-1)d=d:sub(a)end end end;return c end
local function C(c,a,b)local f=a._box;local d=f and f.get and f:get(b)
if not d then return false end
if f.markRead then pcall(function()f:markRead(b)end)end;local e=c.T;a.openIdx=b
a.bodyLines={{"From:    "..
s.senderName(d).. (
d.from and("  ("..
tostring(d.from):sub(1,12)..")")or""),e.fg},{
"Subject: "..
(d.subject~=""and d.subject or"(no subject)"),e.title},{"Sent:    "..
s.formatTs(d.ts).." (sender's uptime)",e.dim}}if not d.readable then
a.bodyLines[#a.bodyLines+1]={"[sealed — no shared secret to open this]",e.warning}end
a.bodyLines[#a.bodyLines+1]={"",e.fg}for h,g in ipairs(H(d.body,c.W))do
a.bodyLines[#a.bodyLines+1]={g,e.fg}end;a.readScroll=0;a.mode="read"return true end
local function D(a)if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end;return
F.pullSignal(a or 0.1)end
local function z(a,b,d,e,c)local h,g,i=a.D,a.T,a.W;local f=d or""
while true do h.fill(1,c,i,1," ",g.fg,g.bg)
h.set(1,c,b,g.highlight,g.bg)local l=math.max(1,i-#b-1)
local n=#f>l and f:sub(#f-l+1)or f;h.set(#b+1,c,n.."_",g.fg,g.bg)local m,o,j,k=D()
if m=="key_down"then
if k==28 then
return f elseif B(j,k,true)then return nil elseif k==14 then if#f>0 then f=f:sub(1,-2)end elseif
j and j>=32 and j<127 and#f< (e or 256)then f=f..string.char(j)end elseif m=="clipboard"and type(j)=="string"then
f=f..j:gsub("\n","")end end end
local function A(a,d,b,c)local f,e,m,g,j=a.D,a.T,a.W,a.H,a.NM;f.fill(1,2,m,g-1," ",e.fg,e.bg)
f.set(1,2,
" Compose mail   (Enter = next field/line, "..u().." = cancel)",e.title,e.bg)
local k=z(a," To (peer / alias / user@peer / * = all): ",b,64,4)if not k or k==""then return end;local n=z(a," Subject: ",c,100,6)if
n==nil then return end
f.set(1,8," Body — Enter for a new line, a blank line sends, "..u().." cancels:",e.dim,e.bg)local h,i={},10
while#h<64 and i<=g-1 do local I=z(a,"  ","",200,i)
if I==nil then return end;if I==""then break end;h[#h+1]=I;i=i+1 end
local p,q=s.resolveRecipient(k,j and j.aliases and j.aliases.resolve)
local o,l=s.send({to=p,user=q,fromUser=a.who or"user",subject=n,body=table.concat(h,"\n")})f.fill(1,g,m,1," ",e.fg,e.bg)
if o then
f.set(1,g,"Queued "..

tostring(o):sub(1,18).. (l and"  (sealed)"or"  (PLAINTEXT bulletin)"),l and e.highlight or e.warning,e.bg)else
f.set(1,g,"Send failed: "..tostring(l),e.error,e.bg)end;D(1.4)end
function r.draw(b,a)local d,c,e,g=b.D,b.T,b.W,b.H;if not a._box then r.refresh(b,a)end;d.fill(1,2,e,
g-1," ",c.fg,c.bg)
w.drawRail(d,c,2,e,{{label="§ Mail — "..
(b.who or"user")}},{labelFg=c.title or c.fg})local f=v(a)local i=a._box
local l=(i and i.unread and i:unread())or 0;local j=s.pending()
local k=s.running()and""or"  [service stopped — receive off]"
d.set(2,3,string.format("%d message(s), %d unread%s%s",#f,l,
j>0 and(", "..j.." sending")or"",k),
k~=""and c.warning or c.dim,c.bg)local h=y(g)
if a.mode=="read"then local m=a.bodyLines or{}for n=0,h-1 do local o=m[
(a.readScroll or 0)+n+1]
if o then d.set(1,t+n,tostring(o[1]):sub(1,e),
o[2]or c.fg,c.bg)end end
w.drawRampBar(d,c,g,e,
"q Back · Arrows Scroll · R Reply · D Delete · "..u().." Close",nil,c.statusbar_fg or c.bar_fg,
c.statusbar_bg or c.bar_bg)else
if#f==0 then d.set(2,t,"(inbox empty)",c.dim,c.bg)else if a.sel>#f then
a.sel=#f end;if a.sel<1 then a.sel=1 end;if a.sel<=a.scroll then
a.scroll=a.sel-1 end
if a.sel>a.scroll+h then a.scroll=a.sel-h end;if a.scroll<0 then a.scroll=0 end
for m=0,h-1 do local n=a.scroll+m+1;local o=f[n]
if
o then local q=s.inboxRow(o,n,e-1)local p=t+m
if n==a.sel then d.fill(1,p,e,1," ",c.sel_fg or c.bg,c.sel_bg or
c.highlight)
d.set(1,p,q:sub(1,e),
c.sel_fg or c.bg,c.sel_bg or c.highlight)else
d.set(1,p,q:sub(1,e),o.read and c.dim or c.fg,c.bg)end end end end
w.drawRampBar(d,c,g,e,"Enter Read · C Compose · R Reply · D Delete · "..u().." Close",
nil,c.statusbar_fg or c.bar_fg,c.statusbar_bg or c.bar_bg)end;a.label=r.label(0)end
local function E(a)
local b=

(a.fromUser and a.fromUser~=""and a.fromUser)or(a.from and tostring(a.from))or""
local c=
(a.subject and not a.subject:match("^[Rr][Ee]:"))and("Re: "..a.subject)or
(a.subject or"")return b,c end
function r.handleKey(b,a,d,c,e)if not a._box then r.refresh(b,a)end;local g=y(b.H)if B(d,c,true)then
x.close(b)return 3 end
if a.mode=="read"then local h=math.max(0,
# (a.bodyLines or{})-g)
if c==1 or d==113 then
a.mode="list"return 3 elseif c==200 then
a.readScroll=math.max(0,(a.readScroll or 0)-1)return 3 elseif c==208 then
a.readScroll=math.min(h,(a.readScroll or 0)+1)return 3 elseif c==201 then
a.readScroll=math.max(0,(a.readScroll or 0)-g)return 3 elseif c==209 then
a.readScroll=math.min(h,(a.readScroll or 0)+g)return 3 elseif d==114 or d==82 then local i=a._box;local j=a.openIdx and i and i.get and
i:get(a.openIdx)if j then local k,l=E(j)A(b,a,k,l)
a.mode="list"r.refresh(b,a)end;return 3 elseif d==100 or d==68 then
local i=a._box
if a.openIdx and i and i.delete then
pcall(function()i:delete(a.openIdx)end)a.mode="list"r.refresh(b,a)end;return 3 end;return 0 end;local f=v(a)
if c==200 then a.sel=math.max(1,a.sel-1)return 3 elseif c==208 then a.sel=math.min(math.max(1,
#f),a.sel+1)return 3 elseif c==201 then
a.sel=math.max(1,a.sel-g)return 3 elseif c==209 then
a.sel=math.min(math.max(1,#f),a.sel+g)return 3 elseif c==199 then a.sel=1;return 3 elseif c==207 then a.sel=math.max(1,#f)return 3 elseif c==28 then if#f>0 then
C(b,a,a.sel)end;return 3 elseif d==99 or d==67 then A(b,a)r.refresh(b,a)return 3 elseif d==114 then
local h=f[a.sel]if h then local i,j=E(h)A(b,a,i,j)r.refresh(b,a)end;return 3 elseif
d==82 then r.refresh(b,a)return 3 elseif d==100 or d==68 then local h=a._box;if
#f>0 and h and h.delete then pcall(function()h:delete(a.sel)end)
r.refresh(b,a)end;return 3 end;return 0 end
function r.handleClick(c,a,b,d)if a.mode~="list"then return 0 end;local f=v(a)local e=(a.scroll or 0)+ (b.y-t+
1)
if b.y>=t and f[e]then if
e==a.sel and b.button~=1 then C(c,a,e)else a.sel=e end;return 3 end;return 0 end
function r.handleScroll(b,a,c)local d=(c.dir or 0)>0 and-1 or 1
if a.mode==
"read"then
local f=math.max(0,# (a.bodyLines or{})-y(b.H))
local e=math.max(0,math.min(f,(a.readScroll or 0)+d))if e==a.readScroll then return 0 end;a.readScroll=e else local f=v(a)
local e=math.max(1,math.min(math.max(1,
#f),(a.sel or 1)+d))if e==a.sel then return 0 end;a.sel=e end;return 3 end
function r.tick(b,a)r.refresh(b,a)if a.mode=="list"then return 3 end;return 0 end;return r