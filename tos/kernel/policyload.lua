local d
local e=setmetatable({},{__index=function()return true end})
local function f()
return
{closed=true,MODULE_PREFIXES={},MODULE_NAMES={},BLOCKED_MODULES=e,BASE_COMPONENTS={},GATED_COMPONENTS={},SERVICE_PORTS=e,PKG_RUN_CAPS={},SERVICE_DEFAULT_CAPS={},SERVICE_CAPS={},KERNEL_REQUIRE_ALLOW={},KERNEL_SERVICES={},isAdmin=function(a)
return type(a)=="table"and a.isKernel==true end}end
return
function(a)if d then return d end;local h,b=pcall(require,"kernel.policy")if h and
type(b)=="table"then d=b;return d end;d=f()
local g="SECURITY POLICY DID NOT LOAD ("..tostring(a)..
"): "..
tostring(b)..". Everything non-kernel is denied until it is repaired."local c=package.loaded["kernel.log"]if
type(c)=="table"and c.error then pcall(c.error,"policy",g)end
_G._TOS_POLICY_FAILURE=g;return d end