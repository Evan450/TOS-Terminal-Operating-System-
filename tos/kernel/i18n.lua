local s="string"local q={}local r,t,B,w;local z="/usr/lang"local A=64*1024;local C=64;local D=512;local E=2048
local u=nil;local x=nil;local v=nil;local y={}function q.validCode(a)
return type(a)==s and#a>=2 and#a<=8 and
a:match("^%l%l[%l%d_%-]*$")~=nil end;local function F(a)return
z.."/"..a..".lang"end
function q.init(a)a=a or{}r=a.fs;t=a.log;B=a.serialize or
require("kernel.serialize")w=a.config;local b=w and w.get and
w.get("language")
if
type(b)==s and b~=""and b~="en"then local c,d=q.setLanguage(b)if not c and t then
t.warn("i18n","System language '"..tostring(b).."' not applied: "..
tostring(d))end end end
function q.loadCatalog(a)
if not q.validCode(a)then return nil,"invalid language code"end;if not r then return nil,"i18n not initialized"end;local c=F(a)if not
r.exists(c)then return nil,"no catalog at "..c end
local e=r.readFile(c)if not e then return nil,"cannot read "..c end
if#e>A then return nil,"catalog too large (>"..A..
" bytes)"end;local g,b=pcall(B.decode,e,{maxBytes=A})
if
not g or type(b)~="table"then return nil,"corrupt catalog (parse failed)"end
if type(b.strings)~="table"then return nil,"corrupt catalog (no strings table)"end;local f,d={},0
for i,j in pairs(b.strings)do if
type(i)==s and type(j)==s and#i>0 and#i<=C and#j<=D then f[i]=j;d=d+1
if d>=E then break end end end
local h=(type(b.meta)=="table")and b.meta or{}return{meta=h,strings=f,count=d}end
function q.setLanguage(a)
if a==nil or a==""or a=="en"then u,x,v=nil,nil,nil;return true end;local b,c=q.loadCatalog(a)if not b then return false,c end
u,x,v=a,b.strings,b.meta;if t then
t.info("i18n","Language set: "..
a.." ("..tostring(b.count).." strings)")end;return true end;function q.language()return u or"en"end
function q.languageName()
if not u then return"English"end;return
(v and type(v.name)==s and v.name)or u end
function q.available()
local a={{code="en",name="English (built-in)"}}
if not r or not r.exists or not r.exists(z)then return a end;local d,b=pcall(r.list,z)if not d or not b then return a end;local c={}
if type(b)==
"table"then c=b elseif type(b)=="function"then for e in b do c[#c+1]=e end end;table.sort(c)
for f,e in ipairs(c)do local g=e:match("^(.+)%.lang$")
if g and
q.validCode(g)then local i=g;local j,h=pcall(q.loadCatalog,g)if j and h and
type(h.meta.name)==s then i=h.meta.name end
a[#a+1]={code=g,name=i}end end;return a end
function q.t(a,b,...)
if type(a)==s and type(b)==s then y[a]=y[a]or b end
local c=(x and type(a)==s and x[a])or b or a;if select("#",...)==0 then return c end
local d,e=pcall(string.format,c,...)if d then return e end
local f,g=pcall(string.format,b or tostring(a),...)if f then return g end;return b or tostring(a)end
function q.keysSeen()local a={}for c in pairs(y)do a[#a+1]=c end;table.sort(a)local b={}for d,c in
ipairs(a)do b[#b+1]={key=c,default=y[c]}end;return b end;return q