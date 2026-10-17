local c={}
local function d()local b,a=pcall(require,"kernel.process")
if not b or
type(a)~="table"or not a.current then return nil end;local e,f=pcall(a.current)if not e then return nil end;return f end
function c.info(a)local b=type(a)if b~="nil"and b~="number"and b~="thread"then
error(
"bad argument #1 (thread, number or nil expected, got "..b..")",2)end;local e=d()if not e then
return nil end
return{path=e.progPath,command=e.name,env=nil,data={vars={}}}end;function c.running(a)local b=c.info(a)if b then return b.path,b.env,b.command end
return nil end
function c._forProgram(a,b)local e=nil;if

type(a)=="string"and a:find("/",1,true)and not a:find("^prog:")then e=a end;local f={}
function f.info(g)local h=c.info(g)if not h then
return nil end;h.path=e or h.path;h.env=b;if e then h.command=e end;return h end;function f.running(g)local h=f.info(g)if h then return h.path,h.env,h.command end
return nil end;return f end;return c