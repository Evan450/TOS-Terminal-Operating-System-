local b={}
function b.builder(a)local c=nil
local function d()if c==nil then local e,f=pcall(require,"kernel.sandbox")c=
e and f or false end;return c or nil end
return
function(e)e=e or{}local f=d()
if not f then
local function h(j)local k={}for l,m in pairs(j)do k[l]=m end;return k end
local i={assert=assert,error=error,pcall=pcall,xpcall=xpcall,type=type,tostring=tostring,tonumber=tonumber,pairs=pairs,ipairs=ipairs,next=next,select=select,setmetatable=setmetatable,math=h(math),string=h(string),table=h(table),print=e.stdout or print}i._G=i;return i end
local g={["fs.read"]=true,["fs.write"]=true,["compat.io"]=true}if e.caps then for h,i in pairs(e.caps)do g[h]=i end end
return
f.build{name=
e.name or"shell:program",pkgName=e.pkgName,cwd=a.cwd,session=
(a.U and a.U.currentSession and a.U.currentSession())or nil,caps=g,stdout=e.stdout}end end;return b