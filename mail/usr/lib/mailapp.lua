local B=require("computer")local t=require("shell.panels.ui")
local u=require("shell.panels.tabs")local q=require("mail")local p={}local r=4
local function v(a)return math.max(1,(a-1)-r)end
function p.label(a)if(a or 0)>0 then return"Mail("..a..")"end;return"Mail"end
local function C(a,b)return(q.inboxBox(a.who or"user"))end
function p.refresh(b,a)q.tick()local c=C(b,a)a._box=c;local d=
(c and c.unread and c:unread())or 0;a.unread=d
if
b.tabs[b.activeTab]==a then a.label=p.label(0)else a.label=p.label(d)end end;local function s(a)local c=a._box
return(c and c.list and c:list())or{}end
function p.open(a)local c=u.find(a,"mail")local b;if c then
b=a.tabs[c]a.activeTab=c else
b=u.create(a,"mail","Mail",{mode="list",sel=1,scroll=0,readScroll=0,live=true,interval=2})end
p.refresh(a,b)return b end
local function D(b,a)local c={}
for d in
(tostring(b or"").."\n"):gmatch("(.-)\n")do if d==""then c[#c+1]=""else
while#d>0 do c[#c+1]=d:sub(1,a-1)d=d:sub(a)end end end;return c end
local function y(c,a,b)local f=a._box;local d=f and f.get and f:get(b)
if not d then return false end
if f.markRead then pcall(function()f:markRead(b)end)end;local e=c.T;a.openIdx=b
a.bodyLines={{"From:    "..
q.senderName(d).. (
d.from and("  ("..
tostring(d.from):sub(1,12)..")")or""),e.fg},{
"Subject: "..
(d.subject~=""and d.subject or"(no subject)"),e.title},{"Sent:    "..
q.formatTs(d.ts).." (sender's uptime)",e.dim}}if not d.readable then
a.bodyLines[#a.bodyLines+1]={"[sealed — no shared secret to open this]",e.warning}end
a.bodyLines[#a.bodyLines+1]={"",e.fg}for h,g in ipairs(D(d.body,c.W))do
a.bodyLines[#a.bodyLines+1]={g,e.fg}end;a.readScroll=0;a.mode="read"return true end
local function z(a)if coroutine.isyieldable and coroutine.isyieldable()then return
coroutine.yield()end;return
B.pullSignal(a or 0.1)end
local function w(a,b,d,e,c)local h,g,i=a.D,a.T,a.W;local f=d or""
while true do h.fill(1,c,i,1," ",g.fg,g.bg)
h.set(1,c,b,g.highlight,g.bg)local k=math.max(1,i-#b-1)
local n=#f>k and f:sub(#f-k+1)or f;h.set(#b+1,c,n.."_",g.fg,g.bg)local l,o,j,m=z()
if l=="key_down"then
if m==28 then
return f elseif j==17 then return nil elseif m==14 then if#f>0 then f=f:sub(1,-2)end elseif j and j>=32 and j<127 and#
f< (e or 256)then f=f..string.char(j)end elseif l=="clipboard"and type(j)=="string"then
f=f..j:gsub("\n","")end end end
local function x(a,d,b,c)local f,e,m,g,j=a.D,a.T,a.W,a.H,a.NM;f.fill(1,2,m,g-1," ",e.fg,e.bg)
f.set(1,2," Compose mail   (Enter = next field/line, ^Q = cancel)",e.title,e.bg)
local k=w(a," To (peer / alias / user@peer / * = all): ",b,64,4)if not k or k==""then return end;local n=w(a," Subject: ",c,100,6)if
n==nil then return end
f.set(1,8," Body — Enter for a new line, a blank line sends, ^Q cancels:",e.dim,e.bg)local h,i={},10
while#h<64 and i<=g-1 do local G=w(a,"  ","",200,i)
if G==nil then return end;if G==""then break end;h[#h+1]=G;i=i+1 end
local E,F=q.resolveRecipient(k,j and j.aliases and j.aliases.resolve)
local o,l=q.send({to=E,user=F,fromUser=a.who or"user",subject=n,body=table.concat(h,"\n")})f.fill(1,g,m,1," ",e.fg,e.bg)
if o then
f.set(1,g,"Queued "..

tostring(o):sub(1,18).. (l and"  (sealed)"or"  (PLAINTEXT bulletin)"),l and e.highlight or e.warning,e.bg)else
f.set(1,g,"Send failed: "..tostring(l),e.error,e.bg)end;z(1.4)end
function p.draw(b,a)local d,c,e,g=b.D,b.T,b.W,b.H;if not a._box then p.refresh(b,a)end;d.fill(1,2,e,
g-1," ",c.fg,c.bg)
t.drawRail(d,c,2,e,{{label="§ Mail — "..
(b.who or"user")}},{labelFg=c.title or c.fg})local f=s(a)local i=a._box
local l=(i and i.unread and i:unread())or 0;local j=q.pending()
local k=q.running()and""or"  [service stopped — receive off]"
d.set(2,3,string.format("%d message(s), %d unread%s%s",#f,l,
j>0 and(", "..j.." sending")or"",k),
k~=""and c.warning or c.dim,c.bg)local h=v(g)
if a.mode=="read"then local m=a.bodyLines or{}for n=0,h-1 do local o=m[
(a.readScroll or 0)+n+1]
if o then d.set(1,r+n,tostring(o[1]):sub(1,e),
o[2]or c.fg,c.bg)end end
t.drawRampBar(d,c,g,e,"q Back · Arrows Scroll · R Reply · D Delete · ^Q Close",
nil,c.statusbar_fg or c.bar_fg,c.statusbar_bg or c.bar_bg)else
if#f==0 then d.set(2,r,"(inbox empty)",c.dim,c.bg)else if a.sel>#f then
a.sel=#f end;if a.sel<1 then a.sel=1 end;if a.sel<=a.scroll then
a.scroll=a.sel-1 end
if a.sel>a.scroll+h then a.scroll=a.sel-h end;if a.scroll<0 then a.scroll=0 end
for m=0,h-1 do local n=a.scroll+m+1;local o=f[n]
if
o then local F=q.inboxRow(o,n,e-1)local E=r+m
if n==a.sel then d.fill(1,E,e,1," ",c.sel_fg or c.bg,c.sel_bg or
c.highlight)
d.set(1,E,F:sub(1,e),
c.sel_fg or c.bg,c.sel_bg or c.highlight)else
d.set(1,E,F:sub(1,e),o.read and c.dim or c.fg,c.bg)end end end end
t.drawRampBar(d,c,g,e,"Enter Read · C Compose · R Reply · D Delete · ^Q Close",nil,c.statusbar_fg or c.bar_fg,c.statusbar_bg or
c.bar_bg)end;a.label=p.label(0)end
local function A(a)
local b=

(a.fromUser and a.fromUser~=""and a.fromUser)or(a.from and tostring(a.from))or""
local c=
(a.subject and not a.subject:match("^[Rr][Ee]:"))and("Re: "..a.subject)or
(a.subject or"")return b,c end
function p.handleKey(b,a,c,d,e)if not a._box then p.refresh(b,a)end;local g=v(b.H)if c==17 then
u.close(b)return 3 end
if a.mode=="read"then local h=math.max(0,
# (a.bodyLines or{})-g)
if d==1 or c==113 then
a.mode="list"return 3 elseif d==200 then
a.readScroll=math.max(0,(a.readScroll or 0)-1)return 3 elseif d==208 then
a.readScroll=math.min(h,(a.readScroll or 0)+1)return 3 elseif d==201 then
a.readScroll=math.max(0,(a.readScroll or 0)-g)return 3 elseif d==209 then
a.readScroll=math.min(h,(a.readScroll or 0)+g)return 3 elseif c==114 or c==82 then local i=a._box;local j=a.openIdx and i and i.get and
i:get(a.openIdx)if j then local k,l=A(j)x(b,a,k,l)
a.mode="list"p.refresh(b,a)end;return 3 elseif c==100 or c==68 then
local i=a._box
if a.openIdx and i and i.delete then
pcall(function()i:delete(a.openIdx)end)a.mode="list"p.refresh(b,a)end;return 3 end;return 0 end;local f=s(a)
if d==200 then a.sel=math.max(1,a.sel-1)return 3 elseif d==208 then a.sel=math.min(math.max(1,
#f),a.sel+1)return 3 elseif d==201 then
a.sel=math.max(1,a.sel-g)return 3 elseif d==209 then
a.sel=math.min(math.max(1,#f),a.sel+g)return 3 elseif d==199 then a.sel=1;return 3 elseif d==207 then a.sel=math.max(1,#f)return 3 elseif d==28 then if#f>0 then
y(b,a,a.sel)end;return 3 elseif c==99 or c==67 then x(b,a)p.refresh(b,a)return 3 elseif c==114 then
local h=f[a.sel]if h then local i,j=A(h)x(b,a,i,j)p.refresh(b,a)end;return 3 elseif
c==82 then p.refresh(b,a)return 3 elseif c==100 or c==68 then local h=a._box;if
#f>0 and h and h.delete then pcall(function()h:delete(a.sel)end)
p.refresh(b,a)end;return 3 end;return 0 end
function p.handleClick(c,a,b,d)if a.mode~="list"then return 0 end;local f=s(a)local e=(a.scroll or 0)+ (b.y-r+
1)
if b.y>=r and f[e]then if
e==a.sel and b.button~=1 then y(c,a,e)else a.sel=e end;return 3 end;return 0 end
function p.handleScroll(b,a,c)local d=(c.dir or 0)>0 and-1 or 1
if a.mode==
"read"then
local f=math.max(0,# (a.bodyLines or{})-v(b.H))
local e=math.max(0,math.min(f,(a.readScroll or 0)+d))if e==a.readScroll then return 0 end;a.readScroll=e else local f=s(a)
local e=math.max(1,math.min(math.max(1,
#f),(a.sel or 1)+d))if e==a.sel then return 0 end;a.sel=e end;return 3 end
function p.tick(b,a)p.refresh(b,a)if a.mode=="list"then return 3 end;return 0 end;return p