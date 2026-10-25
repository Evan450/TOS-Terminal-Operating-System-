local g,h="^%s*(.-)%s*$","string"local e={}
local function f()
local a=package.loaded["kernel.process"]if a and type(a.inProcess)=="function"then
return a.inProcess()end
return
(coroutine.isyieldable and coroutine.isyieldable())and true or false end
function e.create()local i={}local a=1;local b=0;local d=false;local l=64*1024;local c=0;local function j()return a>b end
local function k()if a>b then return
nil end;local q=i[a]i[a]=nil;a=a+1;if type(q)==h then
c=math.max(0,c-#q)end;if a>b then a=1;b=0 end;return q end
local function m(q)b=b+1;i[b]=q;if type(q)==h then c=c+#q end end
local function n(q)a=a-1;i[a]=q;if type(q)==h then c=c+#q end end
local o={read=function(q,r)
while j()and not d do if f()then coroutine.yield()else return nil end end;return k()end,readLine=function(q)local r={}
while true do
while
j()and not d do if f()then coroutine.yield()else
if#r>0 then return table.concat(r)end;return nil end end
if j()then if#r>0 then return table.concat(r)end;return nil end;local s=k()local t=s:find("\n",1,true)if t then r[#r+1]=s:sub(1,t-1)if t<#s then n(s:sub(
t+1))end;return table.concat(r)else
r[#r+1]=s end end end,close=function(q)
d=true end}
local p={write=function(r,q)if d then return false end;local t=tostring(q)
if c+#t>l then return false,"pipe full"end;m(t)return true end,close=function(q)
d=true end}return o,p end
function e.parse(a)local c={}local b={}local d=false;local j=nil
for l=1,#a do local m=a:sub(l,l)
if d then b[#b+1]=m
if m==j then d=false end elseif m=='"'or m=="'"then d=true;j=m;b[#b+1]=m elseif m=="|"then
c[#c+1]=table.concat(b)b={}else b[#b+1]=m end end;if#b>0 then c[#c+1]=table.concat(b)end
local function k(l)local n,o=false,nil
local m=1
while m<=#l do local p=l:sub(m,m)
if n then if p==o then n=false end;m=m+1 elseif p=='"'or p=="'"then n=true
o=p;m=m+1 elseif p=="\\"and m<#l then m=m+2 elseif p==">"and l:sub(m+1,m+1)==">"then return m,
">>"elseif p==">"then return m,">"elseif p=="<"then return m,"<"else m=m+1 end end;return nil end;local i={}
for l,m in ipairs(c)do local n=m;local o=nil;local p=nil
while true do local s,q=k(n)if not s then break end
local v=n:sub(1,s-1)local t=n:sub(s+#q):match(g)or""local r=
t:match("^(%S+)")or""
local u=t:sub(#r+1):match(g)or""
if q==">>"then o={type="file",path=r,append=true}elseif q==">"then
o={type="file",path=r,append=false}elseif q=="<"then p={type="file",path=r}end;n=v.. (u~=""and(" "..u)or"")end;if l>1 and not p then p={type="pipe",index=l-1}end;if
l<#c and not o then o={type="pipe",index=l+1}end
i[#i+1]={cmd=n:match(g),stdin=p,stdout=o}end;return i end;return e