local l="string"local i={}local m=16;local n=8192
local function j(b,a,c)local d=type(b)
if d=="nil"or d=="boolean"or
d=="number"or d==l then return b end;if d~="table"then
error("a "..d.." cannot cross ipc",0)end;if c>=m then
error("too deep to cross ipc",0)end;if a.seen[b]then
error("a cycle cannot cross ipc",0)end;a.seen[b]=true;local e={}
for f,g in next,b do a.nodes=a.nodes+1
if
a.nodes>n then error("too large to cross ipc",0)end;local o=type(f)
if o~=l and o~="number"and o~="boolean"then error("a "..o..
" key cannot cross ipc",0)end;e[f]=j(g,a,c+1)end;a.seen[b]=nil;return e end
local function k(...)local c={seen={},nodes=0}local a=select("#",...)local b={n=a}for d=1,a do
b[d]=j((select(d,...)),c,0)end;return b end;local h={}
function i.register(a,b,c)if
type(a)~=l or not a:match("^[%l%d][%l%d%-]*$")then return false,"bad endpoint name"end
if
type(b)~="function"then return false,"handler must be a function"end;local d=h[a]if d and d.owner~=c then
return false,"endpoint '"..a..
"' is held by "..tostring(d.owner)end;h[a]={handler=b,owner=c}
return true end;function i.unregister(a,b)local c=h[a]if not c or c.owner~=b then return false end
h[a]=nil;return true end
function i.call(b,a,...)local f=h[b]if
not f then return nil,"not running"end;local g,d=pcall(k,...)
if not g then return nil,d end
local o={user=type(a)=="table"and a.user or nil,tier=type(a)=="table"and
tonumber(a.tier)or 0}
local c=table.pack(pcall(f.handler,o,table.unpack(d,1,d.n)))if not c[1]then return nil,tostring(c[2])end
local p,e=pcall(k,table.unpack(c,2,c.n))if not p then return nil,e end;return table.unpack(e,1,e.n)end;return i