local b="screen truth"
return
function(a)
if not(a.cfg and a.cfg.screen)then return
a.skip(b,"screen checks are opt-in: add screen=true to selftest.on")end;local q,g=pcall(require,"kernel.display")
if
not q or type(g)~="table"then return a.skip(b,"kernel.display unavailable")end;local i=g.getGpu and g.getGpu()if not i or not i.get then return
a.skip(b,"no GPU, or gpu.get unavailable here")end
local c,n=i.getResolution()local e=math.max(2,n-6)local f,j=0x336699,0x000000;local function r(v)local w={}
for y=1,c do
local x,z,A,B=pcall(i.get,y,v)w[y]=x and{ch=z,fg=A,bg=B}or nil end;return w end
local function s(v,w)for z=1,c do
local A=w[z]
if A then pcall(g.set,z,v,A.ch or" ",A.fg,A.bg)end end
local y,x=pcall(require,"kernel.screen")
if y and x and x.invalidateAll then pcall(x.invalidateAll)end end;local t=r(e)
local function o(v)local w,y,z,x=pcall(i.get,v,e)if not w then return nil end;return x end
local function h(v)local w=0;for y=1,c do if o(y)==v then w=w+1 end end;return w end;local l={}
local function p(v)if l[v]then return l[v]end;if g.invalidateColors then
pcall(g.invalidateColors)end
pcall(g.fill,1,e,1,1," ",0xFFFFFF,v)l[v]=o(1)or v;return l[v]end;g.fill(1,e,c,1," ",0xFFFFFF,f)
a.eq("a full-width fill covers every column",c,h(f))g.set(1,e,string.rep("x",10),0xFFFFFF,j)
a.eq("a 10-cell write changes exactly 10 cells",10,h(j))
a.eq("...and leaves the other W-10 as they were",c-10,h(f))g.fill(1,e,c,1," ",0xFFFFFF,f)
a.eq("baseline row is A",c,h(f))g.scrollUp(e,e+1)g.fill(1,e,c,1," ",0xFFFFFF,f)
a.eq("the same colour still reaches the glass after a scroll",c,h(f))local u,k=pcall(require,"kernel.screen")local d,m=nil,nil
if
u and k and k.displayProxy then
for w,v in
ipairs({(k.active and k.active())or 1,1})do local y,x=pcall(k.displayProxy,v)if
y and type(x)=="table"and x.fill then d,m=x,v;break end end end
if type(d)=="table"and d.fill and d.set then
d.fill(1,e,c,1," ",0xFFFFFF,f)if d.endFrame then pcall(d.endFrame)end
a.eq("proxy fill reaches every column",c,h(f))d.fill(1,e,c,1," ",0xFFFFFF,f)
if d.endFrame then pcall(d.endFrame)end
a.eq("a repeated proxy fill leaves the glass correct",c,h(f))pcall(i.setBackground,j)pcall(i.fill,1,e,c,1," ")
d.fill(1,e,c,1," ",0xFFFFFF,f)if d.endFrame then pcall(d.endFrame)end;local z=h(f)
a.ok(
"an UNDECLARED write behind the proxy is invisible to it ("..z.."/"..c..")",z<c)pcall(i.setBackground,j)pcall(i.fill,1,e,c,1," ")if
k.invalidateAll then pcall(k.invalidateAll)end
d.fill(1,e,c,1," ",0xFFFFFF,f)if d.endFrame then pcall(d.endFrame)end
a.eq("proxy repaints after a DECLARED write behind it",c,h(f))g.fill(1,e,c,1," ",0xFFFFFF,f)
local D=pcall(g.withContext,i,c,n,function()
g.fill(1,e,c,1," ",0xFFFFFF,j)end)
if D then a.eq("the forwarded draw really landed",c,h(j))
g.fill(1,e,c,1," ",0xFFFFFF,f)
a.eq("a repaint after a forwarded draw is not skipped",c,h(f))else
a.skip("withContext","display.withContext not callable here")end;local A,w=0x000000,0x00AAFF;local E,B=0xFFFFFF,0x000000;local x=string.rep("r",c)
local y,C=p(w),p(B)
if y==C then
a.skip("selection row","highlight and normal quantize to the same palette entry here")else d.set(1,e,x,A,w)if d.endFrame then pcall(d.endFrame)end
a.eq("a highlighted row paints across the full width",c,h(y))d.set(1,e,x,E,B)if d.endFrame then pcall(d.endFrame)end
a.eq("un-highlighting the row clears every cell",c,h(C))d.set(1,e,x,A,w)if d.endFrame then pcall(d.endFrame)end
a.eq("re-highlighting it covers every cell again",c,h(y))end;local v=nil
if m then local G,F=pcall(k.displayProxy,m)if G and type(F)=="table"and
F.fill then v=F end end
if v then d.fill(1,e,c,1," ",0xFFFFFF,f)
if d.endFrame then pcall(d.endFrame)end;v.fill(1,e,c,1," ",0xFFFFFF,j)
if v.endFrame then pcall(v.endFrame)end
a.eq("a second proxy's fill reaches the glass",c,h(j))d.fill(1,e,c,1," ",0xFFFFFF,f)
if d.endFrame then pcall(d.endFrame)end
a.eq("the first proxy repaints after the second wrote",c,h(f))else
a.ok("a second proxy can be built for seat "..tostring(m),false)end else
a.skip("seat proxy","no active seat proxy exposed on this build")end;s(e,t)end