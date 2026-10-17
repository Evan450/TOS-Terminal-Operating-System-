local k="string"local l=require("component")local i={}
local function h(a,b,...)local c={...}local d=type(b)for f,e in
ipairs(c)do if d==e then return end end
error("bad argument #"..a..
" ("..
table.concat(c," or ").." expected, got "..d..")",3)end
local function m()local a=l.list and l.list("internet")()if not a then
return nil end;local b,c=pcall(l.proxy,a)if not b then return nil end;return c end
local function n()local c,a=pcall(require,"kernel.process")if
c and a and a.yieldCooperative then a.yieldCooperative()return end
local d,b=pcall(require,"kernel.event")if d and b and b.pull then pcall(b.pull,0)end end
function i.request(b,a,c,d)h(1,b,k)h(2,a,k,"table","nil")h(3,c,"table","nil")
h(4,d,k,"nil")local g=m()
if not g then error("no primary internet card found",2)end;local e
if type(a)==k then e=a elseif type(a)=="table"then for p,q in pairs(a)do
e=e and(e.."&")or""
e=e..tostring(p).."="..tostring(q)end end;local f,o=g.request(b,e,c,d)if not f then
error(tostring(o or"request failed"),2)end
return
setmetatable({close=setmetatable({},{__call=function()return f.close()end,__tostring=function()return
"function() -- closes the connection"end})},{__call=function()
while
true do local p,q=f.read()
if not p then pcall(function()f.close()end)if
q then error(q,2)end;return nil elseif#p>0 then return p end;n()end end,__index=f})end;local j={}
function j:close()if self.socket then
pcall(function()self.socket.close()end)self.socket=nil end end;function j:seek()return nil,"bad file descriptor"end;function j:read(a)if
not self.socket then return nil,"connection is closed"end;return
self.socket.read(a)end
function j:write(a)if not
self.socket then return nil,"connection is closed"end
while#a>0 do
local b,c=self.socket.write(a)if not b then return nil,c end;a=string.sub(a,b+1)end;return true end
function i.socket(a,b)h(1,a,k)h(2,b,"number","nil")local c=m()if not c then
return nil,"no primary internet card found"end;if not c.connect then
return nil,"internet card has no TCP support"end
local e=b and(a..":"..b)or a;local d,f=c.connect(e)if not d then return nil,f end;return
setmetatable({inet=c,socket=d},{__index=j,__metatable="socketstream"})end
function i.open(a,b)local d,e=i.socket(a,b)if not d then return nil,e end
local f,c=pcall(require,"buffer")
if not f or not c or not c.new then return nil,"buffer library unavailable"end;return c.new("rwb",d)end;return i