local t=require("component")local y=require("computer")
local z=require("web.render")local r=internet
if
type(r)~="table"or type(r.get)~="function"then local b,a=pcall(require,"internet")r=
(b and type(a)=="table"and
type(a.get)=="function")and a or nil end;local A=256*1024
local function B(a,b,c)local k=t.list and t.list("gpu")()if not k then
a("No GPU found.",0xFF0000)return nil end;local l,d=pcall(t.proxy,k)if not l or not d then
a("Cannot open the GPU.",0xFF0000)return nil end;local f,g=d.getResolution()
if not f or not
g then a("Cannot detect screen size.",0xFF0000)return nil end;if f<b or g<c then
a(string.format("Screen too small: need %dx%d, have %dx%d.",b,c,f,g),0xFF6600)return nil end
local m,i=pcall(d.getDepth)
local e=(m and type(i)=="number")and(i<=1 and 1 or
(i<=4 and 2 or 3))or 1
local j=(e==1)and
{fg=0xFFFFFF,dim=0xFFFFFF,border=0xFFFFFF,title=0xFFFFFF,hi=0xFFFFFF,warn=0xFFFFFF,bg=0x000000}or
{fg=0xFFFFFF,dim=0xAAAAAA,bg=0x000000,border=
e==2 and 0x55FFFF or 0x00FFFF,title=e==2 and 0xFFFF55 or 0xFFFF00,hi=e==2 and 0x55FF55 or 0x00FF00,warn=
e==2 and 0xFF5555 or 0xFF4040}local h={W=f,H=g,tier=e,T=j,gpu=d}function h.set(p,G,H,n,o)
if n then pcall(d.setForeground,n)end;if o then pcall(d.setBackground,o)end
pcall(d.set,p,G,H)end
function h.fill(p,G,H,I,J,n,o)if n then
pcall(d.setForeground,n)end;if o then pcall(d.setBackground,o)end;pcall(d.fill,p,G,H,I,
J or" ")end;function h.clear()h.fill(1,1,f,g," ",j.fg,j.bg)end;return h end
local function u(a,b)a=tostring(a or"")if#a>b then return
a:sub(1,math.max(1,b-1)).."~"end;return a..
string.rep(" ",math.max(0,b-#a))end
local q={ESC=1,ENTER=28,BACK=14,UP=200,DOWN=208,LEFT=203,RIGHT=205,PGUP=201,PGDN=209,HOME=199,END=207,F10=68}local x=17;local s
do local a,b=pcall(require,"shell.keys")s=a and b or nil end
local function v(b,a)if s and s.is then return s.is("quit",b,a)end;return a==q.F10 or b==x or
a==q.ESC end
local function w(a)local b={y.pullSignal(a)}
if b[1]=="key_down"then return b[3],b[4]end;if b[1]=="interrupted"then return x,nil end;return nil,nil end
local function C(a)
if not r then return nil,"this package was not granted the internet capability"end;local d,b=pcall(r.status)
if d and b and not
(b.present and b.http and b.enabled)then return nil,"no internet card: "..
tostring(b.reason or"unavailable")end;local c,e=r.get(a,{maxBytes=A})if not c then
return nil,tostring(e or"fetch failed")end;return c end
local function D(a)
a=tostring(a or""):gsub("^%s+",""):gsub("%s+$","")if a==""then return a end
if not a:match("^%a+://")then a="http://"..a end;return a end
local function E(a,b)local d=B(b,40,10)if not d then return end;local e=d.T
local c={url=nil,lines={},links={},status=nil,statusColor=e.fg,scroll=0,hscroll=0,history={}}local g,h=2,d.H-1
local function i(l,m)l=D(l)if l==""then return end
c.status="Loading "..l.." ..."c.statusColor=e.dim;d.fill(1,d.H,d.W,1," ",e.fg,e.bg)d.set(2,d.H,u(c.status,
d.W-2),c.statusColor,e.bg)
local n,p=C(l)if not n then c.lines,c.links={},{}c.status="Failed: "..tostring(p)
c.statusColor=e.warn;return end;if m and c.url then c.history[
#c.history+1]=c.url end;c.url=l
local o=z.render(n,d.W)c.lines,c.links=o.lines,o.links;c.scroll,c.hscroll=0,0;c.status=l
c.statusColor=e.dim end
local function f()
d.fill(1,1,d.W,1," ",e.menubar_fg or e.bg,e.title)
d.set(2,1,u("web -- ".. (c.url or"(no page loaded)"),d.W-2),
e.menubar_fg or e.bg,e.title)d.fill(1,g,d.W,h-g+1," ",e.fg,e.bg)local l=h-g+1;local m=math.max(0,#
c.lines-l)if c.scroll>m then c.scroll=m end;if
c.scroll<0 then c.scroll=0 end
for n=0,l-1 do
local o=c.lines[c.scroll+n+1]if o then local p=o:sub(c.hscroll+1,c.hscroll+d.W)
d.set(1,g+n,p,e.fg,e.bg)end end;d.fill(1,d.H,d.W,1," ",e.fg,e.bg)
d.set(2,d.H,u(c.status or"",d.W-2),c.statusColor,e.bg)end
local function k(l)d.fill(1,d.H,d.W,1," ",e.fg,e.bg)
d.set(2,d.H,l,e.hi,e.bg)local m=""local n=2+#l
while true do d.fill(n,d.H,d.W-n,1," ",e.fg,e.bg)
d.set(n,d.H,m,e.fg,e.bg)local o,p=w(nil)
if p==q.ENTER then return m elseif v(o,p)then return nil elseif p==q.BACK then
if#m>0 then m=m:sub(1,-2)end elseif o and o>=32 and o<127 then
if n+#m<d.W then m=m..string.char(o)end end end end
if a and a~=""then i(a,false)else c.status="o = open a URL   |   F10/^Q = quit"end;d.clear()f()local j=true
while j do local l,m=w(nil)
if v(l,m)then j=false elseif m==q.UP then
c.scroll=math.max(0,c.scroll-1)f()elseif m==q.DOWN then c.scroll=c.scroll+1;f()elseif m==q.PGUP then
c.scroll=math.max(0,c.scroll- (h-g))f()elseif m==q.PGDN then c.scroll=c.scroll+ (h-g)f()elseif m==q.HOME then c.scroll=0;f()elseif m==
q["END"]then
c.scroll=math.max(0,#c.lines- (h-g+1))f()elseif m==q.LEFT then c.hscroll=math.max(0,c.hscroll-8)f()elseif
m==q.RIGHT then c.hscroll=c.hscroll+8;f()elseif l==111 or l==79 then local n=k("Open: ")if
n and n~=""then i(n,true)end;d.clear()f()elseif l==98 or l==66 then
local n=table.remove(c.history)if n then i(n,false)end;d.clear()f()elseif l and l>=48 and l<=57 then
local o=string.char(l)
while true do d.fill(1,d.H,d.W,1," ",e.fg,e.bg)
d.set(2,d.H,"Go to link: "..o,e.hi,e.bg)local n,H=w(nil)
if H==q.ENTER then break elseif v(n,H)then o=nil;break elseif n and n>=48 and n<=57 then o=o..
string.char(n)elseif H==q.BACK then o=o:sub(1,-2)if o==""then break end end end;local p=o and tonumber(o)local G=p and c.links[p]
if G then
i(G.url,true)elseif p then c.status="No such link: ["..p.."]"c.statusColor=e.warn end;d.clear()f()end end;d.clear()end
local function F(b,a)b=b or{}local c=b[1]
if not c or c=="help"then
a("web -- a text-mode browser",0xFFFF55)
a("  web <url>        Fetch and read a page",0xFFFFFF)a("",0xFFFFFF)
a("Needs this machine's own internet card -- no fetch proxy yet",0xAAAAAA)
a("(that is a separate, not-yet-built piece; see the README).",0xAAAAAA)
a("Inside: o open a url, digits+Enter follow a numbered link,",0xAAAAAA)
a("b back, arrows scroll (left/right for a wide <pre> block),",0xAAAAAA)a("F10/^Q quit.",0xAAAAAA)return end;E(c,a)end;return{commands={web=F}}