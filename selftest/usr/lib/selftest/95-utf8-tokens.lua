local d,c="function","utf8 tokens"
return
function(a)if
not(a.cfg and a.cfg.screen)then
return a.skip(c,"it draws: add screen=true to selftest.on")end
local q,k=pcall(require,"shell.syntax")if
not q or type(k)~="table"or type(k.tokenize)~=d then
return a.skip(c,"shell.syntax unavailable: "..tostring(k))end
local r,f=pcall(require,"kernel.display")
local b=r and type(f)=="table"and f.getGpu and f.getGpu()if not b or not b.get then
return a.skip(c,"no GPU, or gpu.get unavailable")end
local s,g=pcall(require,"kernel.screen")
local l=s and type(g)=="table"and g.displayProxy and g.displayProxy(1)
if not l or type(l.set)~=d then return
a.skip(c,"no kernel.screen display proxy before seat init")end;local h="local café = naïve -- ok"local n=k.tokenize(h)local o=true;for B,A in ipairs(n)do if
utf8.len(A.text)==nil then o=false end end
a.ok("every token is whole UTF-8",o)local e,i=b.getResolution()local j=math.max(2,i-6)local p={}
for A=1,e do
local B,C,D,E=pcall(b.get,A,j)p[A]=B and{ch=C,fg=D,bg=E}or nil end
local t,u=pcall(function()f.fill(1,j,e,1," ",0xFFFFFF,0x000000)
local D="[\0-\127\194-\255][\128-\191]*"local C=1;for F,E in ipairs(n)do l.set(C,j,E.text,0xFFFFFF,0x000000)
local F,G=E.text:gsub(D,"")C=C+G end;local A,B=0,nil
for F,E in
utf8.codes(h)do A=A+1;local H,G=pcall(b.get,A,j)if not
(H and G==utf8.char(E))and not B then
B=string.format("column %d: want %q, got %q",A,utf8.char(E),tostring(G))end end
a.ok("tokens painted one at a time read back as the line ("..
(B or("all "..A.." cells"))..")",B==nil)end)for A=1,e do local B=p[A]
if B then pcall(f.set,A,j,B.ch or" ",B.fg,B.bg)end end;if g.invalidateAll then
pcall(g.invalidateAll)end;if not t then error(u,0)end
local v,m=pcall(require,"shell.panels.draw")
if not
(v and type(m)=="table"and type(m.editTab)==d)then return
a.skip("editor column model","shell.panels.draw unavailable: "..tostring(m))end
local w=setmetatable({fg=0xFFFFFF,bg=0x000000,sel_fg=0x000000,sel_bg=0xFFFFFF},{__index=function()return 0x808080 end})
local x={type="edit",lines={h},curRow=1,curCol=#h+1,viewTop=1,viewLeft=1,label="selftest"}
local y,z=pcall(function()f.fill(1,1,e,i," ",0xFFFFFF,0x000000)
m.editTab({D=l,T=w,W=e,H=i,tier=1,padW=string.rep(" ",e)},x)local A
for B=1,i do local C={}
for F=1,e do local H,G=pcall(b.get,F,B)C[F]=
(H and type(G)=="string")and G or" "end;local D=table.concat(C)local E=D:find(h,1,true)
if E then A={y=B,x=
utf8.len(D:sub(1,E-1))+1}break end end
a.ok("the editor draws the line whole, one character per cell",A~=nil)
if A then local B=A.x+utf8.len(h)local E,E,E,C=pcall(b.get,B,A.y)
local E,E,E,D=pcall(b.get,B-1,A.y)
a.ok(string.format("the cursor is the cell after the line's last character (cell %d)",B),
C~=nil and C~=D)end end)f.fill(1,1,e,i," ",0xFFFFFF,0x000000)if g.invalidateAll then
pcall(g.invalidateAll)end;if not y then error(z,0)end end