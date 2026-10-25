local h="string"local g={}g._VERSION="1.0.0"g.MAX_LINES=20;g.MAX_WIDTH=164
local j={[32]=3,[33]=1,[34]=3,[39]=1,[40]=3,[41]=3,[42]=3,[44]=1,[46]=1,[58]=1,[59]=1,[60]=4,[62]=4,[64]=6,[73]=3,[91]=3,[93]=3,[96]=2,[102]=4,[105]=1,[107]=4,[108]=2,[116]=3,[123]=3,[124]=1,[125]=3,[126]=6}local k=5
local function i(a)local b={}
if utf8 and utf8.codes then
local c=pcall(function()
for e,d in utf8.codes(a)do b[#b+1]=d end end)if c then return b end;b={}end;for c=1,#a do b[c]=a:byte(c)end;return b end
function g.width(a)if type(a)~=h then return 0 end;local b=0;for e,d in ipairs(i(a))do
b=b+ (j[d]or k)end;return b end
function g.charCount(a)if type(a)~=h then return 0 end;return#i(a)end
function g.sanitize(a,b)if type(a)~=h then return""end;b=b or{}
local c=tonumber(b.tabWidth)or 4
a=a:gsub("\t",string.rep(" ",math.max(1,math.min(16,c))))a=a:gsub("[%z\1-\31\127]","")if b.strip then
a=a:gsub("\194\167.","")end;return a end
function g.lines(a)if type(a)~=h then return{}end
a=a:gsub("\r\n","\n"):gsub("\r","\n")local b={}
for c in(a.."\n"):gmatch("(.-)\n")do b[#b+1]=c end;if#b>0 and b[#b]==""then table.remove(b)end;return b end
function g.wrap(c,a,b)b=b or g.width;a=tonumber(a)or g.MAX_WIDTH;if
type(c)~=h then return{""}end;if c==""then return{""}end;if a<=0 then return{c}end
local d,e={},""
local function f(m)local n=""
for p,o in ipairs(i(m))do
local q=
(utf8 and utf8.char)and utf8.char(o)or string.char(o%256)
if b(n..q)>a and n~=""then d[#d+1]=n;n=q else n=n..q end end;return n end
for m in c:gmatch("%S+")do local n=(e=="")and m or(e.." "..m)
if
b(n)<=a then e=n else if e~=""then d[#d+1]=e;e=""end;if b(m)>a then e=f(m)else e=m end end end;if e~=""then d[#d+1]=e end;if#d==0 then d[#d+1]=""end;return d end;local l={left=true,center=true}
function g.align(b)if b==nil then return"left"end;if
type(b)~=h then return nil,"alignment must be a string"end
local a=b:lower()if l[a]then return a end
return nil,"unknown alignment '"..b.."' (left, center)"end
function g.paginate(b,a)a=tonumber(a)or g.MAX_LINES;if a<1 then a=1 end;local d,c={},{}
for f,e in ipairs(
b or{})do c[#c+1]=e;if#c>=a then d[#d+1]=c;c={}end end;if#c>0 or#d==0 then d[#d+1]=c end;return d end
function g.layout(b,a)a=a or{}local m=a.measure or g.width
local n=tonumber(a.maxWidth)or g.MAX_WIDTH;local o=tonumber(a.perPage)or g.MAX_LINES
local f,p=g.align(a.align)if not f then return nil,p end;local q=a.color;local r=a.pageBreak or"\f"
local s=a.wrap~=false;local d,c={},{}local function e()if#c>0 then d[#d+1]=c;c={}end end
for u,t in
ipairs(g.lines(b))do
if t==r then e()else local v=g.sanitize(t,a)
local w=s and g.wrap(v,n,m)or{v}
for u,x in ipairs(w)do c[#c+1]={text=x,color=q,align=f}if#c>=o then e()end end end end;e()if#d==0 then d[1]={}end;return d end
function g.cost(b,a)
a=math.max(1,math.floor(tonumber(a)or 1))local c,d=0,0;for f,e in ipairs(b or{})do
for f,m in ipairs(e)do if type(m)=="table"and m.color~=nil then d=
d+1 else c=c+1 end end end;return{paper=# (b or{})*a,black=
c*a,color=d*a}end;return g