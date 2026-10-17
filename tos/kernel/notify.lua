local i={}i.MIN_SOURCE_GAP=10;i.MIN_GAP=3;i.MAX_QUEUE=8;i.DEFAULT_TTL=120
i.MAX_TTL=3600;i.MAX_TITLE=40;i.MAX_MESSAGE=400;i.MAX_BUTTONS=4
local p={info=true,warn=true,danger=true,error=true,install=true,general=true}local j={}local k=0;local m={}local n={}
local function l(a)if a then return a end
local c,b=pcall(require,"computer")if c and b and b.uptime then return b.uptime()end;return 0 end
local function o()local a=_G._TOS or{}
if a.logObj and a.logObj.info then return a.logObj end;local c,b=pcall(require,"kernel.log")
if c and b and b.info then return b end end
function i.sanitize(a)
if type(a)~="table"then return nil,"spec must be a table"end;local e=a.message or a.body;if type(e)~="string"or e==""then return nil,
"a notice needs a message"end
local c=tostring(a.from or"?"):sub(1,24)if c==""then c="?"end;local b={}if type(a.buttons)=="table"then
for g,f in ipairs(a.buttons)do if
type(f)=="string"and f~=""and#b<i.MAX_BUTTONS then
b[#b+1]=f:sub(1,16)end end end;if#b==
0 then b={"OK"}end
local d=tonumber(a.ttl)or i.DEFAULT_TTL;if d<=0 or d>i.MAX_TTL then d=i.DEFAULT_TTL end
return
{from=c,title=tostring(a.title or c):sub(1,i.MAX_TITLE),message=e:sub(1,i.MAX_MESSAGE),buttons=b,style=p[
a.style or""]and a.style or"info",ttl=d}end
function i.post(a,b)local c,g=i.sanitize(a)if not c then return nil,g end;local d=l(b)local f=o()if f then
f.info("notify",
"["..c.from.."] "..c.message)end;if#j>=i.MAX_QUEUE then
return nil,"too many notices already waiting"end;local e=m[c.from]
if e and
(d-e)<i.MIN_SOURCE_GAP then return nil,
string.format("%s posted %.0fs ago (min gap %ds)",c.from,d-e,i.MIN_SOURCE_GAP)end;k=k+1;c.seq=k;c.id=k;c.at=d;m[c.from]=d;j[#j+1]=c;return c.id end;function i.highWater()return k end
function i.pending(a,b)a=tonumber(a)or 0;local e=l(b)
local c,d={},a
for g,f in ipairs(j)do if f.seq>d then d=f.seq end;if
f.seq>a and(e-f.at)<=f.ttl then c[#c+1]=f end end;return c,d end
function i.nextToShow(a,b,c)local d=l(c)
if type(a)~="table"or#a==0 then return nil,"nothing pending"end
if b and(d-b)<i.MIN_GAP then return nil,
string.format("quiet window (%.0fs of %ds left)",i.MIN_GAP- (d-b),i.MIN_GAP)end
for f,e in ipairs(a)do if(d-e.at)<=e.ttl then return e end end;return nil,"everything pending has expired"end
function i.settle(a,b)
for c,d in ipairs(j)do if d.id==a then table.remove(j,c)
n[a]=tonumber(b)or 1;return true end end;return false end;function i.result(a)return n[a]end
function i.sweep(a)local c=l(a)local b=0
for d=#j,1,-1 do if(c-j[d].at)>
j[d].ttl then table.remove(j,d)b=b+1 end end;if b>0 then local d=o()if d then
d.info("notify",b.." notice(s) expired unseen")end end
return b end;function i.depth()return#j end;function i._reset()j,k,m,n={},0,{},{}end;return i