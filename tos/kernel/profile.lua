local q,C="string","^[%w_%-]+$"local u={}local t=nil;local s=nil;local z=nil;local w=nil;local v=nil;local x=nil
local D=".profile.cfg"local y=8192;local E=16;local F=48
function u.init(a)t=a.securefs;s=a.users;z=a.theme;w=a.env;v=a.log;x=a.serialize or
require("kernel.serialize")end
local function A(a)if not a or a.isKernel then return nil end;if
not a.home or a.home==""or a.home=="/"then return nil end;return
a.home.."/"..D end;local function r()
return{name="default",theme=nil,env={},startup={},cwd=nil,prompt=nil,landing=nil,lang=nil,aliases={}}end
local function B(a)local b=r()if type(a)~=
"table"then return b end
if
type(a.name)==q and#a.name<=32 and a.name:match(C)then b.name=a.name end;if
type(a.theme)==q and#a.theme<=32 and a.theme:match(C)then b.theme=a.theme end
if
type(a.env)=="table"then local c=0
for d,e in pairs(a.env)do
if
type(d)==q and type(e)==q and#d<=32 and#
e<=1024 and d:match("^[%w_]+$")then b.env[d]=e;c=c+1;if c>=32 then break end end end end
if type(a.startup)=="table"then
for d,c in ipairs(a.startup)do if d>E then break end;if type(c)==q and#c<=
200 then if not c:find("[\n\r]")then
b.startup[#b.startup+1]=c end end end end
if type(a.cwd)==q and#a.cwd<=256 then b.cwd=a.cwd end
if type(a.prompt)==q and#a.prompt<=200 then b.prompt=a.prompt end;if
a.landing=="desktop"or a.landing=="shell"or a.landing=="tiles"or a.landing=="files"then
b.landing=a.landing end
if
type(a.aliases)=="table"then local c=0
for d,e in pairs(a.aliases)do
if
type(d)==q and type(e)==q and#d<=32 and#e<=200 and d:match(C)and not
e:find("[\n\r]")then
b.aliases[d:lower()]=e;c=c+1;if c>=F then break end end end end
if type(a.lang)==q then local d,c=pcall(require,"kernel.i18n")
local e=(d and c and
c.validCode)and c.validCode(a.lang)or(
#a.lang>=2 and#a.lang<=8 and
a.lang:match("^%l%l[%l%d_%-]*$")~=nil)if e then b.lang=a.lang end end;return b end
function u.load(a)
a=a or(s and s.currentSession())or nil;if not a then return r(),false end;local c=A(a)
if not c or not t then return r(),false end;if not t.exists(c,a)then return r(),false end
local b=t.readFile(c,a)if not b then return r(),false end
if#b>y then if v then
v.warn("profile","Profile file too large for "..a.user.." ("..#b..
" bytes); using defaults")end;return r(),false end;local e,d=pcall(x.decode,b,{maxBytes=y})
if
not e or type(d)~="table"then if v then
v.warn("profile","Corrupt profile for "..a.user.."; using defaults")end;return r(),false end;return B(d),true end
function u.save(b,a)
a=a or(s and s.currentSession())or nil;if not a then return false,"no session"end;local c=A(a)if not c then return false,
"no profile path (guest or no home)"end;if not t then return false,
"securefs not available"end;local e=B(b or{})
local d=x.encode(e)
if#d>y then return false,"profile too large after sanitization"end;return t.writeFile(c,d,a)end
function u.apply(a,b)b=b or{}local d=
b.session or(s and s.currentSession())or nil;if not a then a=r()end;local c=z or(_G._TOS and
_G._TOS.theme)
if c and c.apply and
a.theme then
local e=c.hasSavedTheme and c.hasSavedTheme(d)or false;if not e then pcall(c.apply,a.theme)end end
if a.lang and a.lang~=""then local e=_G._TOS and _G._TOS.i18n;if
e and e.setLanguage then pcall(e.setLanguage,a.lang)end end
if w and w.write then local e;local g,h=pcall(require,"kernel.process")
if g then e=h end
local f=e and e.current and e.current()or nil
if f and f.env then for i,j in pairs(a.env or{})do f.env[i]=j end end end;return a.startup or{},a end;return u