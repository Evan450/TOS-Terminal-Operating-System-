local c,d="internet","string"
return
function(a)local h,b=pcall(require,"kernel.internet")if not
h or type(b)~="table"then
return a.skip(c,"kernel.internet unavailable")end;local f=b.status()a.ok("status() returns a table",
type(f)=="table")
if
type(f)=="table"and not f.present then
a.ok("no card -> a real reason is given, not a bare false",
type(f.reason)==d and#f.reason>0)
a.ok("no card -> available() agrees",b.available()==false)local l,n,m=pcall(b.get,"http://example.invalid/probe")
a.ok("get() with no card does not throw",l)
if l then a.eq("...and returns no body",nil,n)a.ok("...with a reason",
type(m)==d and#m>0)end else
a.skip("no-card path","a real internet card is present on this machine")end;local i,e=pcall(require,"kernel.config")if not
(i and e and e.get and e.set)then
return a.skip("kill switch","kernel.config unavailable")end;local g=e.get(c)
local j,k=pcall(function()
e.set(c,false)
a.ok("isEnabled() honours the switch turned off",b.isEnabled()==false)
a.ok("...and available() agrees",b.available()==false)local l=b.status()
if l.present then
a.ok("switched off -> the reason names the switch, not the card",
type(l.reason)==d and
l.reason:find("disabled on this machine",1,true)~=nil)end;e.set(c,true)
a.ok("isEnabled() flips back on",b.isEnabled()==true)end)e.set(c,g)
a.eq("config left exactly as found",g,e.get(c))if not j then
a.ok("kill-switch check: "..tostring(k),false)end end