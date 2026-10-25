local an,ah,ae="formula","number","string"local Y={}Y.MAX_COLS=26*3;Y.MAX_ROWS=512
Y.MAX_DEPTH=32;Y.DEFAULT_WIDTH=9;Y.MIN_WIDTH,Y.MAX_WIDTH=1,60;local function Z(a)return{e=a}end
local function aa(a)return
type(a)=="table"and a.e~=nil end;Y.err,Y.isErr=Z,aa;Y.E_CYCLE="#CYCLE!"Y.E_DIV="#DIV/0!"Y.E_NAME="#NAME?"
Y.E_REF="#REF!"Y.E_VALUE="#VALUE!"Y.E_SYNTAX="#SYNTAX!"Y.E_DEPTH="#DEPTH!"Y.E_NA="#N/A"
Y.E_ERR="#ERR!"
function Y.colName(a)if type(a)~=ah or a<1 then return"?"end;local b=""while a>0 do
local c=(a-1)%26;b=string.char(65+c)..b
a=math.floor((a-1)/26)end;return b end
function Y.colIndex(a)if type(a)~=ae or a==""then return nil end;a=a:upper()
local b=0;for c=1,#a do local d=a:byte(c)if d<65 or d>90 then return nil end
b=b*26+ (d-64)end;return b end
function Y.parseRef(a)if type(a)~=ae then return nil end
local f,e,g,h=a:match("^(%$?)(%a+)(%$?)(%d+)$")if not e then return nil end;local d=Y.colIndex(e)local b=tonumber(h)if
not d or not b or b<1 then return nil end;if
d>Y.MAX_COLS or b>Y.MAX_ROWS then return nil end;return d,b,f=="$",g=="$"end;function Y.refName(a,b,c,d)
return(c and"$"or"")..Y.colName(a)..
(d and"$"or"")..tostring(b)end
function Y.parseRange(a)
if type(a)~=ae then return nil end;a=a:gsub("%s","")
local c,d=a:match("^([%$%w]+)%.%.([%$%w]+)$")
if not c then c,d=a:match("^([%$%w]+)[:%.]([%$%w]+)$")end;if not c then c,d=a,a end;local e,g=Y.parseRef(c)local f,h=Y.parseRef(d)if
not e or not f then return nil end;return math.min(e,f),math.min(g,h),math.max(e,f),
math.max(g,h)end
function Y.rangeName(a,b,c,d)local e=Y.refName(a,b)
if a==c and b==d then return e..".."..e end;return e..".."..Y.refName(c,d)end;local function ai(a,b)return a..":"..b end;Y._key=ai
function Y.unkey(a)
local b,c=a:match("^(%d+):(%d+)$")return tonumber(b),tonumber(c)end
function Y.new()return
{cells={},fmt={},colw={},names={},gfmt="G",gwidth=Y.DEFAULT_WIDTH,gprefix="'",recalc="auto",graph={},print={},sort={},cols=8,rows=20}end
function Y.set(a,b,c,d)if b<1 or c<1 or b>Y.MAX_COLS or c>Y.MAX_ROWS then
return a end;local e=ai(b,c)
if d==nil or d==""then
a.cells[e]=nil else a.cells[e]=tostring(d)if b>a.cols then a.cols=b end;if c>a.rows then
a.rows=c end end;return a end;function Y.raw(a,b,c)return a.cells[ai(b,c)]or""end
function Y.width(a,b)return
a.colw[b]or a.gwidth or Y.DEFAULT_WIDTH end
function Y.cellFmt(a,b,c)return a.fmt[ai(b,c)]or a.gfmt or"G"end;local ao={["'"]="L",['"']="R",["^"]="C",["\\"]="REP"}
Y.PREFIX_ALIGN=ao
function Y.classify(a)if a==nil or a==""then return"empty"end;local b=a:sub(1,1)
local c=ao[b]if c then return"label",a:sub(2),c end
if b=="="then return an,a:sub(2)end;local d=tonumber(a)
if d and a:find("^[%d%.%-%+]")then return ah,d end
if

b=="+"or b=="@"or b=="("or b=="-"or b=="#"or b=="."or b:find("%d")or b=="$"then return an,a end;return"label",a,nil end;local aI={["<="]=true,[">="]=true,["<>"]=true}
local aJ={["+"]=true,["-"]=true,["*"]=true,["/"]=true,["%"]=true,["^"]=true,["="]=true,["<"]=true,[">"]=true,["&"]=true}local aK={["#AND#"]=true,["#OR#"]=true,["#NOT#"]=true}
local function aw(b,a)
local c=b:match("^%$?%a+%$?%d+",a)if not c then return nil end;local d=b:sub(a+#c,a+#c)if d:match("[%w_]")then
return nil end;if not Y.parseRef(c)then return nil end;return c end
function Y.tokenize(a)local c,b,d={},1,#a
while b<=d do local e=a:sub(b,b)
if e==" "or e=="\t"then b=b+1 elseif e=='"'then
local g,f={},b+1
while f<=d do local h=a:sub(f,f)if h=='"'then
if a:sub(f+1,f+1)=='"'then g[#g+1]='"'f=f+2 else break end else g[#g+1]=h;f=f+1 end end;if f>d then return nil,Y.E_SYNTAX end
c[#c+1]={t="str",v=table.concat(g)}b=f+1 elseif e:match("%d")or
(e=="."and a:sub(b+1,b+1):match("%d"))then
local f=a:match("^%d*%.?%d+",b)or a:match("^%d+",b)local g=a:match("^[eE][%+%-]?%d+",b+#f)if g then f=f..g end
c[#c+1]={t="num",v=tonumber(f)}b=b+#f elseif e=="#"then local f=a:match("^#%a+#",b)
if f and aK[f:upper()]then
c[#c+1]={t="op",v=f:upper()}b=b+#f elseif a:sub(b,b+4):upper()=="#REF!"then
c[#c+1]={t="err",v=Y.E_REF}b=b+5 else return nil,Y.E_SYNTAX end elseif e=="$"or e:match("%a")then local f=aw(a,b)
if f then local g=b+#f;local h=0
if
a:sub(g,g+1)==".."then h=2 elseif a:sub(g,g)==":"or a:sub(g,g)=="."then h=1 end;local i=h>0 and aw(a,g+h)or nil
if i then local j,k,n,o=Y.parseRef(f)
local l,m,p,q=Y.parseRef(i)c[#c+1]={t="range",c1=j,r1=k,c2=l,r2=m}b=g+h+#i elseif h==1 and
a:sub(g,g)==":"then return nil,Y.E_REF else local j,k=Y.parseRef(f)
c[#c+1]={t="ref",c=j,r=k}b=g end elseif e=="$"then return nil,Y.E_SYNTAX else local g=a:match("^%a[%w_]*",b)
c[#c+1]={t="name",v=g:upper()}b=b+#g end elseif e=="@"then local f=a:match("^@(%a[%w_]*)",b)
if not f then return nil,Y.E_SYNTAX end;c[#c+1]={t="name",v=f:upper(),at=true}b=b+1+#f else
local f=a:sub(b,b+1)
if aI[f]then c[#c+1]={t="op",v=f}b=b+2 elseif aJ[e]then c[#c+1]={t="op",v=e}b=b+1 elseif
e=="("or e==")"or e==","then c[#c+1]={t=e}b=b+1 else return nil,Y.E_SYNTAX end end end;return c end
local function aL(a)local b={toks=a,i=1}function b:peek()return self.toks[self.i]end;function b:next()
local c=self.toks[self.i]self.i=self.i+1;return c end
function b:accept(d,c)
local e=self:peek()if e and e.t==d and(c==nil or e.v==c)then
return self:next()end end;return b end;local ap
local function ax(a)local b=a:next()if not b then return nil,Y.E_SYNTAX end;if b.t=="num"then return
{k="num",v=b.v}end
if b.t=="str"then return{k="str",v=b.v}end;if b.t=="err"then return{k="err",v=b.v}end;if b.t=="ref"then return
{k="ref",c=b.c,r=b.r}end;if b.t=="range"then return
{k="range",c1=b.c1,r1=b.r1,c2=b.c2,r2=b.r2}end;if b.t=="("then
local c,d=ap(a)if not c then return nil,d end
if not a:accept(")")then return nil,Y.E_SYNTAX end;return c end
if
b.t=="name"then
if a:accept("(")then local c={}
if not a:accept(")")then
while true do local d,f=ap(a)
if not d then return nil,f end;c[#c+1]=d
if a:accept(",")then elseif a:accept(")")then break else return nil,Y.E_SYNTAX end end end;return{k="call",name=b.v,args=c}end;if b.at then return{k="call",name=b.v,args={}}end;if b.v=="TRUE"then return
{k="num",v=1}end
if b.v=="FALSE"then return{k="num",v=0}end;return{k="name",v=b.v}end
if b.t=="op"and(b.v=="-"or b.v=="+")then local c,d=ax(a)if not c then return
nil,d end;return{k="unary",op=b.v,a=c}end;return nil,Y.E_SYNTAX end
local function ay(a)local b,d=ax(a)if not b then return nil,d end;local c=a:peek()
if c and c.t=="op"and
c.v=="^"then a:next()local e,f=ay(a)if not e then return nil,f end;return
{k="bin",op="^",a=b,b=e}end;return b end
local function az(a)local b=a:peek()if
b and b.t=="op"and(b.v=="-"or b.v=="+")then a:next()local c,d=az(a)if not c then return nil,d end
return{k="unary",op=b.v,a=c}end
return ay(a)end
local function aq(a,c,b)local d,f=b(a)if not d then return nil,f end
while true do local e=a:peek()if e and e.t=="op"and
c[e.v]then a:next()local g,h=b(a)if not g then return nil,h end
d={k="bin",op=e.v,a=d,b=g}else return d end end end;local aM={["*"]=true,["/"]=true,["%"]=true}
local aN={["+"]=true,["-"]=true}
local aO={["="]=true,["<>"]=true,["<"]=true,[">"]=true,["<="]=true,[">="]=true}local aP={["#AND#"]=true,["#OR#"]=true,["&"]=true}local function aQ(a)
return aq(a,aM,az)end;local function aR(a)return aq(a,aN,aQ)end;local function aS(a)
return aq(a,aO,aR)end
local function aA(a)local b=a:peek()
if
b and b.t=="op"and b.v=="#NOT#"then a:next()local c,d=aA(a)if not c then return nil,d end;return{k="not",a=c}end;return aS(a)end;ap=function(a)return aq(a,aP,aA)end
function Y.parse(a)
local b,f=Y.tokenize(a)if not b then return nil,f end;if#b==0 then return nil,Y.E_SYNTAX end
local c=aL(b)local d,g=ap(c)if not d then return nil,g end
if c:peek()then return nil,Y.E_SYNTAX end;return d end
local function ab(a)if type(a)==ah then return a end
if type(a)=="boolean"then return a and 1 or 0 end
if type(a)==ae then if a==""then return 0 end;return tonumber(a)end;if a==nil then return 0 end;return nil end;Y.toNum=ab
local function af(a)if a==nil then return""end
if type(a)==ah then
if a==math.floor(a)and
math.abs(a)<1e15 then return string.format("%d",a)end;return tostring(a)end;return tostring(a)end;Y.toStr=af
local function al(a,b)
if a.k=="range"then return math.min(a.c1,a.c2),math.min(a.r1,a.r2),
math.max(a.c1,a.c2),math.max(a.r1,a.r2)end;if a.k=="name"and b.names then local c=b.names[a.v]
if c then return c[1],c[2],c[3],c[4]end end;return nil end;Y.rangeOf=al
local function aj(a,b,c)local d={}
for f,e in ipairs(b)do local g,h,i,j=al(e,a)
if g then
for k=g,i do
for l=h,j do local m=a.get(k,l)
if aa(m)then return nil,m end;local o=ab(m)if o~=nil and not(m==nil or m=="")and
type(m)~=ae then d[#d+1]=o end end end else local k=c(e)if aa(k)then return nil,k end;local l=ab(k)if l==nil then
return nil,Z(Y.E_VALUE)end;d[#d+1]=l end end;return d end;local _={}
local function aB(c,d,b,a)
_[c]=function(e,f,g)local h,j=aj(e,f,g)if not h then return j end;if#h==0 then
return a and a(b,0)or b end;local i=b;for l,k in ipairs(h)do i=d(i,k)end;return
a and a(i,#h)or i end end;aB("SUM",function(c,d)return c+d end,0)
aB("AVERAGE",function(c,d)
return c+d end,0,function(b,a)if a==0 then return Z(Y.E_DIV)end;return b/a end)_.AVG=function(...)return _.AVERAGE(...)end
_.MIN=function(a,b,c)
local d,g=aj(a,b,c)if not d then return g end;if#d==0 then return 0 end;local f=d[1]
for h,e in ipairs(d)do if e<f then f=e end end;return f end
_.MAX=function(a,b,c)local d,g=aj(a,b,c)if not d then return g end;if#d==0 then return 0 end;local f=d[1]for h,e in
ipairs(d)do if e>f then f=e end end;return f end
_.COUNT=function(a,b,c)local d,f=aj(a,b,c)if not d then return f end;return#d end
local function aC(a,b,c)local d,h=aj(a,b,c)if not d then return nil,h end
if#d==0 then return nil,Z(Y.E_DIV)end;local f=0;for j,e in ipairs(d)do f=f+e end;local i=f/#d;local g=0;for j,e in ipairs(d)do
g=g+ (e-i)^2 end;return g/#d end
_.VAR=function(a,b,c)local d,f=aC(a,b,c)return d or f end
_.STD=function(a,b,c)local d,f=aC(a,b,c)return d and math.sqrt(d)or f end
local function ac(a,b)
_[a]=function(e,c,d)if#c~=1 then return Z(Y.E_VALUE)end;local f=d(c[1])
if aa(f)then return f end;local g=ab(f)if g==nil then return Z(Y.E_VALUE)end;return b(g)end end;ac("ABS",math.abs)
ac("SQRT",function(a)if a<0 then return Z(Y.E_VALUE)end;return
math.sqrt(a)end)ac("FLOOR",math.floor)ac("CEIL",math.ceil)_.CEILING=function(...)return
_.CEIL(...)end;ac("INT",function(a)
return math.floor(a)end)
ac("EXP",math.exp)
ac("LN",function(a)if a<=0 then return Z(Y.E_VALUE)end;return math.log(a)end)
ac("LOG",function(a)if a<=0 then return Z(Y.E_VALUE)end;return math.log(a,10)end)ac("SIN",math.sin)ac("COS",math.cos)
ac("TAN",math.tan)
ac("ASIN",function(a)if a<-1 or a>1 then return Z(Y.E_VALUE)end
return math.asin(a)end)
ac("ACOS",function(a)if a<-1 or a>1 then return Z(Y.E_VALUE)end
return math.acos(a)end)ac("ATAN",math.atan)
local function ak(d,a,c,b)
if#a~=b then return nil,Z(Y.E_VALUE)end;local e={}
for f=1,b do local g=c(a[f])if aa(g)then return nil,g end;local h=ab(g)if h==nil then return nil,
Z(Y.E_VALUE)end;e[f]=h end;return e end
_.PI=function(b,a)if#a~=0 then return Z(Y.E_VALUE)end;return math.pi end
_.ATAN2=function(a,b,c)local d,f=ak(a,b,c,2)if not d then return f end;if d[1]==0 and d[2]==0 then return
Z(Y.E_DIV)end;return math.atan(d[2],d[1])end
_.ROUND=function(c,a,b)if#a<1 or#a>2 then return Z(Y.E_VALUE)end;local d=b(a[1])if
aa(d)then return d end;local f=ab(d)if f==nil then return Z(Y.E_VALUE)end
local g=0
if a[2]then local j=b(a[2])if aa(j)then return j end;g=ab(j)or 0 end;local h=10^g;local e=f*h;local i=(e>=0)and math.floor(e+0.5)or
math.ceil(e-0.5)return i/h end
_.POWER=function(a,b,c)local d,f=ak(a,b,c,2)if not d then return f end;return d[1]^d[2]end
_.MOD=function(a,b,c)local d,f=ak(a,b,c,2)if not d then return f end
if d[2]==0 then return Z(Y.E_DIV)end;return d[1]%d[2]end
_.PMT=function(a,b,c)local d,i=ak(a,b,c,3)if not d then return i end;local h,f,g=d[1],d[2],d[3]if g<=0 then return
Z(Y.E_VALUE)end;if f==0 then return h/g end;return h*f/
(1- (1+f)^-g)end
_.PV=function(a,b,c)local d,i=ak(a,b,c,3)if not d then return i end;local g,f,h=d[1],d[2],d[3]
if f==0 then return g*h end;return g* (1- (1+f)^-h)/f end
_.FV=function(a,b,c)local d,i=ak(a,b,c,3)if not d then return i end;local g,f,h=d[1],d[2],d[3]
if f==0 then return g*h end;return g* ((1+f)^h-1)/f end
_.NPV=function(c,a,b)if#a<2 then return Z(Y.E_VALUE)end;local g=ab(b(a[1]))if g==nil then return
Z(Y.E_VALUE)end;local d={}for e=2,#a do d[#d+1]=a[e]end
local h,i=aj(c,d,b)if not h then return i end;local f=0
for e,j in ipairs(h)do f=f+j/ (1+g)^e end;return f end
_.IF=function(c,a,b)if#a<2 or#a>3 then return Z(Y.E_VALUE)end;local d=b(a[1])if
aa(d)then return d end;local e;if type(d)=="boolean"then e=d else local f=ab(d)
e=(f~=nil and f~=0)end;if e then return b(a[2])end;if a[3]then
return b(a[3])end;return 0 end
_.AND=function(c,a,b)for e,d in ipairs(a)do local f=b(d)if aa(f)then return f end;local g=ab(f)
if g==nil or g==0 then return 0 end end;return 1 end
_.OR=function(c,a,b)for e,d in ipairs(a)do local f=b(d)if aa(f)then return f end;local g=ab(f)
if g~=nil and g~=0 then return 1 end end;return 0 end
_.NOT=function(c,a,b)if#a~=1 then return Z(Y.E_VALUE)end;local d=b(a[1])
if aa(d)then return d end;local e=ab(d)return(e==nil or e==0)and 1 or 0 end
_.TRUE=function(b,a)if#a~=0 then return Z(Y.E_VALUE)end;return 1 end
_.FALSE=function(b,a)if#a~=0 then return Z(Y.E_VALUE)end;return 0 end;_.NA=function(a,b)return Z(Y.E_NA)end
_.ERR=function(a,b)return Z(Y.E_ERR)end;local function ar(a,b)
_[a]=function(e,c,d)if#c~=1 then return Z(Y.E_VALUE)end;return
b(d(c[1]))and 1 or 0 end end
ar("ISERR",function(a)return aa(a)end)
ar("ISNA",function(a)return aa(a)and a.e==Y.E_NA end)
ar("ISNUMBER",function(a)return type(a)==ah or a==nil end)
ar("ISSTRING",function(a)return type(a)==ae end)
_.CHOOSE=function(c,a,b)if#a<2 then return Z(Y.E_VALUE)end;local d=ab(b(a[1]))if d==nil then return
Z(Y.E_VALUE)end;d=math.floor(d)if d<0 or d>#a-2 then return
Z(Y.E_VALUE)end;return b(a[d+2])end
local function aD(a)
return
function(b,c,d)if#c~=3 then return Z(Y.E_VALUE)end;local h=d(c[1])
if aa(h)then return h end;local e,g,j,k=al(c[2],b)if not e then return Z(Y.E_VALUE)end
local f=ab(d(c[3]))if f==nil then return Z(Y.E_VALUE)end;f=math.floor(f)local l=a and
(k-g+1)or(j-e+1)
local m=a and(j-e)or(k-g)if f<0 or f>m then return Z(Y.E_REF)end;local i
for n=0,l-1 do local p,q=a and e or(e+n),a and
(g+n)or g;local o=b.get(p,q)
if type(h)==ae then
if
type(o)==ae and o:lower()==h:lower()then i=n;break end else local r=type(o)==ah and o or nil;if r~=nil then
if r<=ab(h)then i=n else break end end end end;if not i then return Z(Y.E_NA)end
if a then return b.get(e+f,g+i)end;return b.get(e+i,g+f)end end;_.VLOOKUP=aD(true)_.HLOOKUP=aD(false)local function ad(d,a,b,c)local e=b(a[c])
if aa(e)then return nil,e end;return af(e)end;local function ag(d,a,b,c)local e=b(a[c])if aa(e)then
return nil,e end;local f=ab(e)if f==nil then return nil,Z(Y.E_VALUE)end;return
f end
_.LEN=function(b,a,c)if
#a~=1 then return Z(Y.E_VALUE)end;local d,f=ad(b,a,c,1)return
d and#d or f end;_.LENGTH=function(...)return _.LEN(...)end
_.UPPER=function(b,a,c)if#a~=1 then return
Z(Y.E_VALUE)end;local d,f=ad(b,a,c,1)
return d and d:upper()or f end
_.LOWER=function(b,a,c)if#a~=1 then return Z(Y.E_VALUE)end;local d,f=ad(b,a,c,1)return
d and d:lower()or f end
_.PROPER=function(b,a,c)if#a~=1 then return Z(Y.E_VALUE)end;local d,f=ad(b,a,c,1)
if not d then return f end;return
(d:lower():gsub("(%a)(%a*)",function(e,g)return e:upper()..g end))end
_.TRIM=function(b,a,c)if#a~=1 then return Z(Y.E_VALUE)end;local d,f=ad(b,a,c,1)
if not d then return f end;return
(d:gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," "))end
_.LEFT=function(b,a,c)if#a~=2 then return Z(Y.E_VALUE)end;local f,g=ad(b,a,c,1)
if not f then return g end;local d,h=ag(b,a,c,2)if not d then return h end
if d<0 then return Z(Y.E_VALUE)end;return f:sub(1,math.floor(d))end
_.RIGHT=function(b,a,c)if#a~=2 then return Z(Y.E_VALUE)end;local f,g=ad(b,a,c,1)
if not f then return g end;local d,h=ag(b,a,c,2)if not d then return h end
if d<0 then return Z(Y.E_VALUE)end;d=math.floor(d)if d==0 then return""end;return f:sub(-d)end
_.MID=function(b,a,c)if#a~=3 then return Z(Y.E_VALUE)end;local g,h=ad(b,a,c,1)
if not g then return h end;local d,i=ag(b,a,c,2)if not d then return i end;local f,j=ag(b,a,c,3)
if not f then return j end;if d<0 or f<0 then return Z(Y.E_VALUE)end;d=math.floor(d)return g:sub(
d+1,d+math.floor(f))end
_.FIND=function(b,a,c)if#a<2 or#a>3 then return Z(Y.E_VALUE)end
local d,i=ad(b,a,c,1)if not d then return i end;local f,j=ad(b,a,c,2)if not f then return j end;local g=0
if a[3]then
local e,k=ag(b,a,c,3)if not e then return k end;g=math.floor(e)end;local h=f:find(d,g+1,true)if not h then return Z(Y.E_VALUE)end
return h-1 end
_.EXACT=function(b,a,c)if#a~=2 then return Z(Y.E_VALUE)end;local d,g=ad(b,a,c,1)
if not d then return g end;local f,h=ad(b,a,c,2)if not f then return h end;return d==f and 1 or 0 end
_.REPEAT=function(b,a,c)if#a~=2 then return Z(Y.E_VALUE)end;local f,g=ad(b,a,c,1)
if not f then return g end;local d,h=ag(b,a,c,2)if not d then return h end;if d<0 or#f*d>512 then
return Z(Y.E_VALUE)end;return f:rep(math.floor(d))end
_.STRING=function(b,a,c)if#a~=2 then return Z(Y.E_VALUE)end;local g,h=ag(b,a,c,1)
if not g then return h end;local f,i=ag(b,a,c,2)if not f then return i end
f=math.max(0,math.min(15,math.floor(f)))return string.format("%."..f.."f",g)end
_.VALUE=function(b,a,c)if#a~=1 then return Z(Y.E_VALUE)end;local d,g=ad(b,a,c,1)
if not d then return g end
local f=tonumber((d:gsub("^%s+",""):gsub("%s+$","")))if f==nil then return Z(Y.E_VALUE)end;return f end
_.CONCAT=function(a,b,c)local d={}
for f,e in ipairs(b)do local g,h,i,j=al(e,a)
if g then
for k=g,i do for l=h,j do local m=a.get(k,l)
if aa(m)then return m end;d[#d+1]=af(m)end end else local k=c(e)if aa(k)then return k end;d[#d+1]=af(k)end end;return table.concat(d)end;Y.FUNCS=_
function Y.evalAst(a,b,c)c=(c or 0)+1
if c>Y.MAX_DEPTH then return Z(Y.E_DEPTH)end;local function e(f)return Y.evalAst(f,b,c)end;local d=a.k;if
d=="num"or d=="str"then return a.v end;if d=="err"then return Z(a.v)end;if d=="ref"then return
b.get(a.c,a.r)end
if d=="range"then return Z(Y.E_VALUE)end
if d=="name"then local f,g,h,i=al(a,b)if not f then return Z(Y.E_NAME)end;if
f==h and g==i then return b.get(f,g)end;return Z(Y.E_VALUE)end
if d=="unary"then local f=e(a.a)if aa(f)then return f end;if
a.op=="+"and type(f)==ae then return f end;local g=ab(f)
if g==nil then return Z(Y.E_VALUE)end;return(a.op=="-")and-g or g end
if d=="not"then local f=e(a.a)if aa(f)then return f end;local g=ab(f)return
(g==nil or g==0)and 1 or 0 end;if d=="call"then local g=_[a.name]if not g then return Z(Y.E_NAME)end;return
g(b,a.args,e)end
if d=="bin"then
local i,j=e(a.a),e(a.b)if aa(i)then return i end;if aa(j)then return j end;local f=a.op;if f=="&"then
return af(i)..af(j)end
if f=="="or f=="<>"then local l,m=ab(i),ab(j)local k;if
l~=nil and m~=nil then k=(l==m)else k=(af(i)==af(j))end;if f=="="then return
k and 1 or 0 end;return k and 0 or 1 end;local h,g=ab(i),ab(j)
if h==nil or g==nil then return Z(Y.E_VALUE)end
if f=="#AND#"then return(h~=0 and g~=0)and 1 or 0 end
if f=="#OR#"then return(h~=0 or g~=0)and 1 or 0 end;if f=="+"then return h+g end;if f=="-"then return h-g end
if f=="*"then return h*g end
if f=="/"then if g==0 then return Z(Y.E_DIV)end;return h/g end
if f=="%"then if g==0 then return Z(Y.E_DIV)end;return h%g end;if f=="^"then return h^g end
if f=="<"then return(h<g)and 1 or 0 end;if f==">"then return(h>g)and 1 or 0 end;if f=="<="then return
(h<=g)and 1 or 0 end
if f==">="then return(h>=g)and 1 or 0 end;return Z(Y.E_SYNTAX)end;return Z(Y.E_SYNTAX)end
function Y.evaluator(a)local b,d={},{}local c={names=a.names}
function c.get(e,f)local g=ai(e,f)if b[g]~=nil then local l=b[g]if l==
"\0nil"then return nil end;return l end;if d[g]then return
Z(Y.E_CYCLE)end;local i=a.cells[g]
if i==nil or i==""then return nil end;local h;local k,j=Y.classify(i)
if k==an then d[g]=true;local l,m=Y.parse(j)if not l then
h=Z(m or Y.E_SYNTAX)else h=Y.evalAst(l,c,0)end;d[g]=nil elseif k==ah then h=j else h=j end;b[g]=(h==nil)and"\0nil"or h;return h end;c.values=b;return c end
function Y.display(e,a,b,c,d)local f=a.get(b,c)if f==nil then return""end;if aa(f)then return f.e end
if
type(f)==ah then if f~=f then return"#NAN!"end;if
f==math.huge or f==-math.huge then return"#INF!"end
if f==math.floor(f)and
math.abs(f)<1e15 then return string.format("%d",f)end
return string.format("%.".. (d or 4).."g",f)end;return tostring(f)end
Y.FORMATS={G="General",F="Fixed",S="Scientific",C="Currency",[","]="Comma",P="Percent",["+"]="+/-",T="Text",H="Hidden"}
local function aT(a)local c=a:sub(1,1)=="-"if c then a=a:sub(2)end
local b=a:reverse():gsub("(%d%d%d)","%1,"):reverse()if b:sub(1,1)==","then b=b:sub(2)end;return
(c and"-"or"")..b end
local function as(a,b)local d=10^b;local e=math.abs(a)*d
local c=math.floor(e+0.5)/d;if a<0 then c=-c end;return string.format("%."..b.."f",c)end
function Y.formatNumber(a,c,b)c=c or"G"
local e,f=c:sub(1,1),tonumber(c:sub(2))or 2;local d
if a~=a then d="#NAN!"elseif a==math.huge or a==-math.huge then d="#INF!"elseif e=="F"then
d=as(a,f)elseif e=="S"then d=string.format("%."..f.."E",a)elseif
e=="C"or e==","then
local g,h=as(math.abs(a),f):match("^(%d+)(.*)$")d=aT(g)..h;if e=="C"then d="$"..d end
if a<0 then d="("..d..")"end elseif e=="P"then d=as(a*100,f).."%"elseif e=="+"then
local g=math.floor(math.abs(a))
if g==0 then d="."else d=string.rep(a<0 and"-"or"+",g)end else
if a==math.floor(a)and math.abs(a)<1e15 then
d=string.format("%d",a)else d=string.format("%.10g",a)end
if b and#d>b then for g=9,1,-1 do local h=string.format("%."..g.."g",a)if#h<=b then d=h
break end;d=h end end end;if b and#d>b then return string.rep("*",b),true end;return d end
function Y.cellText(b,f,d,e,a)a=a or Y.width(b,d)local g=b.cells[ai(d,e)]if
g==nil or g==""then return"","L"end;local j=Y.cellFmt(b,d,e)
if j=="H"then return"","L"end;local k,h,i=Y.classify(g)
if k=="label"then
if i=="REP"then if h==""then return"","L"end;local l=h:rep(math.ceil(
a/#h)+1)return l:sub(1,a),"L"end;i=i or ao[b.gprefix or"'"]or"L"return h,i end;if j=="T"and k==an then return g,"L"end;local c=f.get(d,e)if c==nil then
return"","L"end;if aa(c)then return c.e,"R"end;if type(c)==ah then return
(Y.formatNumber(c,j,a)),"R"end;return tostring(c),"L"end
local function at(a)return
(a:gsub("\\","\\\\"):gsub("\t","\\t"):gsub("\n","\\n"):gsub("\r",""))end
local function au(a)local c,b={},1
while b<=#a do local d=a:sub(b,b)
if d=="\\"then local e=a:sub(b+1,b+1)if e=="t"then
c[#c+1]="\t"b=b+2 elseif e=="n"then c[#c+1]="\n"b=b+2 elseif e=="\\"then c[#c+1]="\\"b=b+2 else c[#c+1]=d
b=b+1 end else
c[#c+1]=d;b=b+1 end end;return table.concat(c)end
local function am(a,b)local c={}for d in pairs(a)do c[#c+1]=d end;table.sort(c,b)return c end
local function aE(c,d)local e,a=Y.unkey(c)local f,b=Y.unkey(d)if a~=b then return a<b end;return e<f end;Y.GRAPH_KEYS={"type","x","a","b","c","title1","title2"}local function aF(a)return
Y.parseRange(a)~=nil end;local function aG(a)
return Y.parseRef(a)~=nil end;local function aH(a)return#a<=120 end
Y.SETTINGS={print={range=aF,header=aH,footer=aH,formulas=function(a)return
a=="1"or a=="0"end},sort={range=aF,k1=aG,k2=aG,o1=function(a)return a=="A"or
a=="D"end,o2=function(a)return a=="A"or a=="D"end}}
function Y.serialize(a)local b={"TOSCALC2"}for d,c in ipairs(am(a.cells,aE))do local e,f=Y.unkey(c)
b[
#b+1]=Y.refName(e,f).."\t"..at(a.cells[c])end;if
(a.gfmt or"G")~="G"then b[#b+1]="#gfmt "..a.gfmt end;if(a.gwidth or
Y.DEFAULT_WIDTH)~=Y.DEFAULT_WIDTH then b[#b+1]="#gwidth "..
a.gwidth end
if
(a.gprefix or"'")~="'"then b[#b+1]="#prefix "..a.gprefix end;if a.recalc=="manual"then b[#b+1]="#recalc manual"end;for e,d in
ipairs(am(a.colw))do
b[#b+1]="#width "..Y.colName(d).." "..a.colw[d]end;for d,c in ipairs(am(a.fmt,aE))do
local e,f=Y.unkey(c)
b[#b+1]="#fmt "..Y.refName(e,f).." "..a.fmt[c]end
for d,c in ipairs(am(a.names))do
local e=a.names[c]b[#b+1]="#name "..
c.." "..Y.rangeName(e[1],e[2],e[3],e[4])end
for d,c in ipairs(Y.GRAPH_KEYS)do local e=a.graph and a.graph[c]if
e~=nil and e~=""then
b[#b+1]="#graph "..c.." "..at(tostring(e))end end
for d,c in ipairs({"print","sort"})do local e=a[c]or{}
for d,f in
ipairs(am(Y.SETTINGS[c]))do local g=e[f]if g~=nil and g~=""and g~=false then if g==true then g="1"end
b[#b+1]=
"#"..c.." "..f.." "..at(tostring(g))end end end;return table.concat(b,"\n")end;local function aU(a)local b=Y.classify(a)
if b==an and a:sub(1,1)~="="then return"'"..a end;return a end
local function av(a)if type(a)~=ae then
return false end;local b,c=a:sub(1,1),a:sub(2)if
b=="G"or b=="+"or b=="T"or b=="H"then return c==""end
if
b=="F"or b=="S"or b=="C"or b==","or b=="P"then
local e=tonumber(c)return
e~=nil and e>=0 and e<=15 and e==math.floor(e)end;return false end;Y.validFmt=av
function Y.deserialize(a)local b=Y.new()if type(a)~=ae then return b end;local e=true
local c=0;local d=true
local function f(g)local j,l=g:match("^(%$?%a+%$?%d+)\t(.*)$")local h,k;if j then
h,k=Y.parseRef(j)end;if not h then return false end;local i=au(l)if d then i=aU(i)end
Y.set(b,h,k,i)return true end
for g in(a.."\n"):gmatch("(.-)\r?\n")do
if e then e=false;if g=="TOSCALC2"then d=false elseif
g~="TOSCALC1"then f(g)end elseif g:sub(1,1)=="#"and not d then
local i,h,k=g:match("^#(%a+) (%S+) ?(.*)$")local j=false
if i=="gfmt"and av(h)then b.gfmt=h;j=true elseif
i=="gwidth"and tonumber(h)then
b.gwidth=math.max(Y.MIN_WIDTH,math.min(Y.MAX_WIDTH,math.floor(tonumber(h))))j=true elseif i=="prefix"and ao[h]and h~="\\"then b.gprefix=h;j=true elseif
i=="recalc"and(h=="manual"or h=="auto")then b.recalc=h
j=true elseif i=="width"and Y.colIndex(h)and tonumber(k)then
local l=Y.colIndex(h)if l<=Y.MAX_COLS then
b.colw[l]=math.max(Y.MIN_WIDTH,math.min(Y.MAX_WIDTH,math.floor(tonumber(k))))j=true end elseif
i=="fmt"and av(k)then local l,m=Y.parseRef(h)if l then b.fmt[ai(l,m)]=k;j=true end elseif
i==
"name"and h:match("^%a[%w_]*$")and not Y.parseRef(h)then local l,m,n,o=Y.parseRange(k)if l then b.names[h:upper()]={l,m,n,o}
j=true end elseif i=="graph"then for m,l in ipairs(Y.GRAPH_KEYS)do if l==h then
b.graph[l]=au(k)j=true end end elseif(i=="print"or i==
"sort")and Y.SETTINGS[i][h]then
local l=au(k)
if Y.SETTINGS[i][h](l)then if i=="print"and h=="formulas"then
l=(l=="1")end;b[i][h]=l;j=true end end;if not j then c=c+1 end elseif g~=""then if not f(g)then c=c+1 end end end;b.skipped=c;return b end
function Y.toCSV(a,b)local c={}
for d=1,a.rows do local e={}for f=1,a.cols do local g=Y.display(a,b,f,d)if g:find('[,"\n]')then g='"'..
g:gsub('"','""')..'"'end
e[#e+1]=g end;while
#e>0 and e[#e]==""do e[#e]=nil end;c[#c+1]=table.concat(e,",")end;while#c>0 and c[#c]==""do c[#c]=nil end
return table.concat(c,"\n")end
function Y.fromCSV(d,a,b,c)b,c=b or 1,c or 1;local h=0;local i=c;local e,m=1,#a;local g,f,j={},{},false;local function k()
g[#g+1]=table.concat(f)f={}end
local function l()k()
for o,n in ipairs(g)do if n~=""then local p=Y.classify(n)if p==an or
n:sub(1,1)=="="then n="'"..n end
Y.set(d,b+o-1,i,n)h=h+1 end end;g={}i=i+1 end
while e<=m do local n=a:sub(e,e)
if j then
if n=='"'then if a:sub(e+1,e+1)=='"'then f[#f+1]='"'e=e+1 else
j=false end else f[#f+1]=n end elseif n=='"'then j=true elseif n==","then k()elseif n=="\n"then l()elseif n~="\r"then f[#f+1]=n end;e=e+1 end;if#f>0 or#g>0 then l()end;return h end;return Y