
return
function(a)local e=component.list("keyboard")()if not e then return
a.skip("keyboard","no keyboard on this machine")end
local f,d=pcall(component.methods,e)
if f and type(d)=="table"then
a.ok("the keyboard component has no isKeyDown method (H-03's premise)",d.isKeyDown==nil)else
a.skip("keyboard methods","component.methods failed: "..tostring(d))end;local g,b=pcall(require,"compat.keyboard")
if
not g or type(b)~="table"then return
a.skip("compat.keyboard","does not load here: "..tostring(b))end
local function c(j,k,...)local l,m=pcall(k,...)
a.ok(j..
" returns a boolean and does not raise".. (l and""or
(" (raised: "..tostring(m)..")")),l and type(m)=="boolean")end
c("isKeyDown(scancode)",b.isKeyDown,b.keys.c or 46)c("isKeyDown(\"c\")",b.isKeyDown,"c")
c("isControlDown()",b.isControlDown)c("isAltDown()",b.isAltDown)
c("isShiftDown()",b.isShiftDown)local h,i=pcall(b.isControlDown)
a.ok("no key reads as held during boot",h and i==false)end