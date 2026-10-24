local g={}local j=nil
local function k()if j==nil then local a,b=pcall(require,"kernel.ustr")j=(a and b)or
false end;return j or nil end;local function h(a,b)local c=k()if c then return c.fit(a,b)end;return
tostring(a or""):sub(1,b)end
local function i(a)local b=k()if b then return
b.width(a)end;return#tostring(a or"")end
function g.tileGrid(b,a)a=a or{}local e=math.max(6,a.tileW or 14)
local m=math.max(3,a.tileH or 4)local c=a.gapX or 2;local f=a.gapY or 1
local d=math.max(1,math.floor((b.w+c)/ (e+c)))
local n=math.max(1,math.floor((b.h+f)/ (m+f)))local o=d*e+ (d-1)*c;local p=b.x+
math.max(0,math.floor((b.w-o)/2))return
{cols=d,rows=n,perPage=d*n,tileW=e,tileH=m,gapX=c,gapY=f,ox=p,oy=b.y}end
function g.tileRect(a,b)
if type(b)~="number"or b<1 or b>a.perPage then return nil end;local d=b-1;local e=d%a.cols;local f=math.floor(d/a.cols)return
{x=a.ox+e*
(a.tileW+a.gapX),y=a.oy+f* (a.tileH+a.gapY),w=a.tileW,h=a.tileH}end
function g.tileHit(a,b,c)for d=1,a.perPage do local e=g.tileRect(a,d)
if e and b>=e.x and b<e.x+e.w and c>=
e.y and c<e.y+e.h then return d end end;return nil end
function g.cycle(a,b,c)if type(a)~="table"or#a==0 then return b end;local d=0;for e,f in
ipairs(a)do if f==b then d=e;break end end;if d==0 then return a[1]end;d=d+
(c or 1)if d>#a then d=1 elseif d<1 then d=#a end;return a[d]end
local l={lua="♦",txt="≡",md="≡",log="≡",man="¶",cfg="§",conf="§",json="§",dat="▓",tcz="▓",bak="▓",bin="▓"}
function g.fileGlyph(a,b)
if b then return(a=="..")and"«"or"■"end
local c=type(a)=="string"and a:match("%.(%w+)$")or nil;return(c and l[c:lower()])or"·"end
function g.drawTile(d,b,a,c)c=c or{}
local e=c.selected and(b.sel_bg or b.highlight)or(
b.panel_bg or b.bg)
local n=c.selected and(b.sel_fg or b.bg)or(
c.dim and(b.dim or b.fg)or b.fg)
local m=c.selected and(b.highlight or b.title)or(b.border or b.dim or
b.fg)local f=a.w-2
d.set(a.x,a.y,"┌"..string.rep("─",f).."┐",m,e)for s=1,a.h-2 do
d.set(a.x,a.y+s,"│"..string.rep(" ",f).."│",m,e)end
d.set(a.x,a.y+a.h-1,"└"..
string.rep("─",f).."┘",m,e)local o=a.y+a.h-3;local q=a.y+a.h-2;if o>a.y then
d.set(a.x+math.floor(a.w/2),o,
c.glyph or"•",c.selected and n or(b.title or b.fg),e)end
local p=h(tostring(c.label or""),f)
local r=math.max(0,math.floor((f-i(p))/2))d.set(a.x+1+r,q,p,n,e)end
function g.railText(a,b)local d,e={},{}local c=1;local function f(m)
if m>0 then d[#d+1]=string.rep("─",m)c=c+m end end
for n,m in ipairs(b or{})do local q=m.label~=nil;local o=tostring(
m.label or m.text or"")local p=i(o)if m.at and
m.at>c then f(m.at-c)end;if c==1 then f(1)end;local r=p+
(q and 4 or 2)
if c+r-1 >a then local s=a-c- (q and 4 or 2)if s<
1 then break end;o=h(o,s)p=i(o)r=p+ (q and 4 or 2)end
if q then d[#d+1]="┤ "..o.." ├"
e[#e+1]={s=c+2,e=c+1+p,label=o}else d[#d+1]=" "..o.." "e[#e+1]={s=c+1,e=c+p,label=o}end;c=c+r end;f(a-c+1)return table.concat(d),e end
function g.drawRail(c,b,d,e,f,a)a=a or{}local o,m=g.railText(e,f)local n=a.bg or b.bg;c.set(1,d,o,
a.fg or b.dim or b.fg,n)
local p=a.labelFg or b.fg;for r,q in ipairs(m)do c.set(q.s,d,q.label,p,n)end;return m end
function g.drawRampBar(c,d,e,a,n,m,f,b)
f=f or d.statusbar_fg or d.bar_fg or d.fg
b=b or d.statusbar_bg or d.bar_bg or d.bg;local o=d.dim or f;c.set(1,e,"▓▒░",o,b)if a>6 then
c.set(a-2,e,"░▒▓",o,b)end
local s=h(tostring(n or""),math.max(0,a-9))local p=i(s)local t=3;if p>0 then c.set(5,e," "..s.." ",f,b)t=5+p+1
c.set(4,e,"░",o,b)end
local q=(a>6)and(a-2)or(a+1)
if m and#m>0 then local v=" "..m.." "local u=a-3-#v;if u>5+p+2 then
c.set(u,e,v,f,b)local w=u+#v
if w<=a-3 then c.fill(w,e,a-2-w,1,"░",o,b)end;q=u end end;local r=t+1;if r<=q-1 then c.fill(r,e,q-r,1,"░",o,b)end end
function g.tabChips(b,c,a)a=a or 10;local d={}
for f,e in ipairs(b or{})do
local m=tostring(e.label or"?")m=h(m,a)local n="idle"if f==c then n="active"elseif e.live or
(e.type=="edit"and e.modified)then n="busy"end
local o=
(n=="busy")and("["..m.."]")or(" "..m.." ")d[#d+1]={text=o,state=n,idx=f}end;return d end
function g.chipSpans(c,b,a)a=a or 1;local d={}for o,p in ipairs(c or{})do d[o]=p end;local n=#d;local function f(o)local p=0
for q,r in
ipairs(o)do p=p+i(r.text)+ (q>1 and 1 or 0)end;return p end
while#d>1 and
f(d)> (b-a+1)do if d[1].state=="active"then table.remove(d,2)else
table.remove(d,1)end end;if#d==1 and f(d)> (b-a+1)then return{},n end;local m={}local e=
b-f(d)+1;for p,o in ipairs(d)do if p>1 then e=e+1 end;local q=i(o.text)
m[#m+1]={s=e,e=e+q-1,idx=o.idx,text=o.text,state=o.state}e=e+q end
return m,n-#d end
function g.fitChips(c,d,a,b)local e,f
for n,m in ipairs({10,8,6,5})do local o=g.tabChips(c,d,m)
e,f=g.chipSpans(o,a,b)if f==0 then return e end
if m==5 then local p="«"..f
e,f=g.chipSpans(o,a,b+#p+3)p="«"..f;local q=
((e[1]and e[1].s)or(a-#p+1))-#p-1;if q>=b then
table.insert(e,1,{s=q,e=q+#p-1,idx=0,text=p,state="more"})end;return e end end;return e or{}end
function g.menuSpans(a)local c,b={},2
for d,e in ipairs(a or{})do
local f=" "..tostring(e.label or"").." "c[#c+1]={s=b,e=b+#f-1,idx=d,text=f}b=b+#f+1 end;return c end
function g.drawBar(f,d,m,e,n,a,b,c)b=b or d.bar_fg or d.fg
c=c or d.bar_bg or d.bg;f.fill(1,m,e,1," ",b,c)
if n and#n>0 then f.set(1,m,h(n,e),b,c)end;if a and#a>0 and#a<e then f.set(e-#a,m,a,b,c)end end
function g.drawSettingRow(d,a,e,c,f,b,m)
local n=m and(a.sel_bg or a.highlight)or a.bg;local o=m and(a.sel_fg or a.bg)or a.fg
d.fill(c,e,f,1," ",o,n)
if b.kind=="header"then
d.set(c,e,h(tostring(b.label or""),f),a.title or a.fg,a.bg)elseif b.kind=="info"then
d.set(c+1,e,h(tostring(b.text or""),f-1),a.dim or a.fg,a.bg)elseif b.kind=="toggle"then local p=b.value and"[x] "or"[ ] "
d.set(c+1,e,h(p..tostring(
b.label or""),f-1),o,n)elseif b.kind=="choice"then
d.set(c+1,e,h(tostring(b.label or""),f-1),o,n)
local p="« "..tostring(b.value or"").." »"local q=c+f-#p-1;if q>c+1 then
d.set(q,e,p,m and o or(a.highlight or a.fg),n)end elseif b.kind=="button"then
d.set(c+1,e,h("[ "..
tostring(b.label or"").." ]",f-1),o,n)end end
function g.rowSelectable(a)return a and
(a.kind=="toggle"or a.kind=="choice"or a.kind=="button")end;function g.nextSelectable(a,b,c)local d=b
repeat d=d+c;if d<1 or d>#a then return b end until g.rowSelectable(a[d])return d end;function g.firstSelectable(a)for b,c in
ipairs(a)do if g.rowSelectable(c)then return b end end
return nil end;return g