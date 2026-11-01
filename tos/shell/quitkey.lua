local f={}local g={}
local function i()local a=package.loaded["kernel.users"]local b=
a and a.currentSession and a.currentSession()return
b and b.user or""end
local function j(a)local c,b=pcall(require,"kernel.fs")if
not c or type(b)~="table"or not b.exists then return false end;if
b.exists("/etc/keys.cfg")then return true end;if a==""then return false end;local d=
a=="root"and"/root"or("/home/"..a)return
b.exists(d.."/.keys.cfg")==true end
local function h()local b=package.loaded["shell.keys"]if b then return b end;local a=i()if g[a]==
nil then g[a]=j(a)end;if g[a]then
local c,d=pcall(require,"shell.keys")if c then return d end end end
function f.is(a,b,c)local d=h()if d then return d.isQuit(a,b,c)end;return a==17 end
function f.hint()local a=h()return a and a.quitHint()or"^Q"end;return f