
local function t()return
(_G._TOS and _G._TOS.securefs)or require("kernel.securefs")end;local p=require("compat.buffer")local q=require("compat.term")
local l={}
local function u(a,b)local c={}local d=b:find("r")~=nil
local e=b:find("[wa]")~=nil;if d then function c:read(f)return a:read(f)end end;if e then function c:write(f)return
a:write(f)end end
function c:close()return a:close()end
function c:seek(f,g)if a.seek then return a:seek(f,g)end;return nil,"not seekable"end;return p.new(b,c)end
function l.open(b,a)a=a or"r"local c,d=t().open(b,a)if not c then return nil,
d or("cannot open "..b)end;return u(c,a)end;local function r()local a={}function a:write(b)q.write(b,true)end;function a:close()end;return
p.new("w",a)end
local function v()local a={}function a:read()
local b=q.read()if b then return b.."\n"end;return nil end;function a:close()
end;return p.new("r",a)end;l.stdout=r()l.stderr=r()l.stdin=v()
local n={input=l.stdin,output=l.stdout}local s=setmetatable({},{__mode="k"})
local function m()
local d,b=pcall(require,"kernel.process")if
not d or type(b)~="table"or type(b.current)~="function"then return n end;local e,c=pcall(b.current)if not e or
type(c)~="table"then return n end;local a=s[c]if not a then
a={input=n.input,output=n.output}s[c]=a end;return a end
local function o(a)if not a then return end;if
a==l.stdin or a==l.stdout or a==l.stderr then return end
if type(a)=="table"and
type(a.close)=="function"then pcall(a.close,a)end end
function l.input(a)local b=m()
if a then
if type(a)=="string"then local c,d=l.open(a,"r")
if not c then error(d,2)end;o(b.input)b.input=c else if a~=b.input then o(b.input)end;b.input=a end end;return b.input end
function l.output(a)local b=m()
if a then
if type(a)=="string"then local c,d=l.open(a,"w")
if not c then error(d,2)end;o(b.output)b.output=c else if a~=b.output then o(b.output)end
b.output=a end end;return b.output end;function l.read(...)local a=m()return a.input:read(...)end;function l.write(...)
local a=m()return a.output:write(...)end
function l.lines(a)
local b=m()
if a then local c,f=l.open(a,"r")if not c then error(f,2)end;local d=false
local g=setmetatable({},{__gc=function()if not d then pcall(function()
c:close()end)d=true end end})
local e=function()if d then return nil end;local j,i=pcall(c.read,c,"*l")
if not j or i==nil then pcall(function()
c:close()end)d=true;return nil end;return i end;local h={iter=e,guard=g}return function()local i=h;return e()end else return
b.input:lines()end end;function l.close(a)local b=m()
if a then return a:close()else return b.output:close()end end;function l.flush()local a=m()if a.output.flush then
a.output:flush()end end;function l.tmpfile()return nil,
"tmpfile not supported"end
function l.type(a)
if type(a)~="table"then return nil end;if a.closed then return"closed file"end
if a.read or a.write then return"file"end;return nil end;function l.popen()return nil,"popen not supported"end;return l