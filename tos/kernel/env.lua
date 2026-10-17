local c={}
local d={PATH="/usr/bin:/bin:/tos/shell",HOME="/",SHELL="/tos/shell/init.lua",TERM="tos",TOS_VERSION=_G._TOS and _G._TOS.version or"1.5.0"}
function c.get(a)if a and a.env then return a.env end;return d end;function c.read(a,b)
if a and a.env and a.env[b]~=nil then return a.env[b]end;return d[b]end
function c.write(a,b,e)
if not a then return false end;if not a.env then a.env={}end;a.env[b]=e;return true end
function c.inherit(a)local b={}for e,f in pairs(d)do b[e]=f end;if a and a.env then
for e,f in pairs(a.env)do b[e]=f end end;return b end
function c.setDefault(a,b)local f,e=pcall(require,"kernel.users")
if
f and e and e.currentSession then local g=e.currentSession()
if
g and not g.isKernel and g.tier< (
e.TIER and e.TIER.ADMIN or 2)then return false,"env.setDefault requires admin tier"end end;d[a]=b;return true end
function c.list(a)local b={}for e,f in pairs(d)do b[e]=f end;if a and a.env then
for e,f in pairs(a.env)do b[e]=f end end;return b end;return c