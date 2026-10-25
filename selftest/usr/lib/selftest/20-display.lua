
return
function(a)
if not(a.cfg and a.cfg.screen)then return
a.skip("display colour cache","screen checks are opt-in: add screen=true to selftest.on")end;local h,b=pcall(require,"kernel.display")
if
not h or type(b)~="table"then return a.skip("display","kernel.display unavailable")end;local c=b.getGpu and b.getGpu()
if
not c or not c.getBackground then return a.skip("display","no GPU bound on this machine")end;local d,g=c.getResolution()local e=0x336699;local f=g;local function i(m)local n={}
for o=1,d do
local p,q,r,s=pcall(c.get,o,m)n[o]=p and{ch=q,fg=r,bg=s}or nil end;return n end
local function j(m,n)for q=1,d do
local r=n[q]
if r then pcall(b.set,q,m,r.ch or" ",r.fg,r.bg)end end
local p,o=pcall(require,"kernel.screen")
if p and o and o.invalidateAll then pcall(o.invalidateAll)end end;local k=i(f)b.fill(1,f,d,1," ",0xFFFFFF,e)
a.eq("hardware is at the fill colour",e,c.getBackground())b.scrollUp(g-1,g)b.fill(1,f,d,1," ",0xFFFFFF,e)
a.eq("same colour still reaches the hardware after a scroll",e,c.getBackground())local l=c.getBackground()b.fill(1,f,d,1," ",0xFFFFFF,e)
a.eq("a repeated colour leaves the hardware where it was",l,c.getBackground())j(f,k)end