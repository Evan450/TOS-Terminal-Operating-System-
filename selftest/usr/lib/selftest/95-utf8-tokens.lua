local b="utf8 tokens"
return
function(a)
if not(a.cfg and a.cfg.screen)then return
a.skip(b,"it draws: add screen=true to selftest.on")end;local n,g=pcall(require,"shell.syntax")if
not n or type(g)~="table"or type(g.tokenize)~="function"then
return a.skip(b,
"shell.syntax unavailable: "..tostring(g))end
local o,c=pcall(require,"kernel.display")
local d=o and type(c)=="table"and c.getGpu and c.getGpu()if not d or not d.get then
return a.skip(b,"no GPU, or gpu.get unavailable")end
local p,e=pcall(require,"kernel.screen")
local h=p and type(e)=="table"and e.displayProxy and e.displayProxy(1)
if not h or type(h.set)~="function"then return
a.skip(b,"no kernel.screen display proxy before seat init")end;local j="local café = naïve -- ok"local k=g.tokenize(j)local l=true;for u,t in ipairs(k)do if
utf8.len(t.text)==nil then l=false end end
a.ok("every token is whole UTF-8",l)local i,q=d.getResolution()local f=math.max(2,q-6)local m={}
for t=1,i do
local u,v,w,x=pcall(d.get,t,f)m[t]=u and{ch=v,fg=w,bg=x}or nil end
local r,s=pcall(function()c.fill(1,f,i,1," ",0xFFFFFF,0x000000)
local w="[\0-\127\194-\255][\128-\191]*"local v=1;for y,x in ipairs(k)do h.set(v,f,x.text,0xFFFFFF,0x000000)
local y,z=x.text:gsub(w,"")v=v+z end;local t,u=0,nil
for y,x in
utf8.codes(j)do t=t+1;local A,z=pcall(d.get,t,f)if not
(A and z==utf8.char(x))and not u then
u=string.format("column %d: want %q, got %q",t,utf8.char(x),tostring(z))end end
a.ok("tokens painted one at a time read back as the line ("..
(u or("all "..t.." cells"))..")",u==nil)end)for t=1,i do local u=m[t]
if u then pcall(c.set,t,f,u.ch or" ",u.fg,u.bg)end end;if e.invalidateAll then
pcall(e.invalidateAll)end
a.skip("editor column model","draw.lua still advances by bytes (TODO: THE EDITOR COUNTS BYTES WHERE THE SCREEN COUNTS CHARACTERS)")if not r then error(s,0)end end