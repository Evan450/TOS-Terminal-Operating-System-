
return
function(a)local f,b=pcall(require,"kernel.audio")
if
not f or type(b)~="table"or type(b.isEnabled)~="function"then return
a.skip("audio","kernel.audio unavailable")end;if not b.isEnabled()then
return a.skip("audio","audio is turned off on this machine")end;local e=computer.uptime;local function c(j,...)local k=e()
j(...)return e()-k end;local g=b.getVolume()local d=b._resetCooldown or
function()end
local h,i=pcall(function()
local j=c(computer.beep,440,0.3)
a.ok(string.format("computer.beep(440, 0.3) holds the machine (%.2f s)",j),j>=0.2)b.setVolume(1.0)d()local k=c(b.chat)local l=c(b.chat)
a.ok(string.format("a repeat chat() inside the cooldown is skipped (%.2f s, then %.2f s)",k,l),
k>=0.1 and l<0.05)b.setVolume(0.1)d()local m=c(b.notify)
a.ok(string.format("notify() at volume 0.1 still plays (%.2f s)",m),
m>=0.04)end)b.setVolume(g)d()if not h then error(i,0)end end