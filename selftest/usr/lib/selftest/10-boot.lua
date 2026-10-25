
return
function(a)local b=_G._TOS
a.ok("_TOS global exists",type(b)=="table")if type(b)~="table"then return end
a.ok("filesystem is up",type(b.fs)=="table")
a.ok("log is up",type(b.log)=="function"or type(b.log)=="table")local c=computer.freeMemory()
a.ok("free memory > 32K after boot ("..
math.floor(c/1024).."K)",c>32*1024)local e,d=pcall(require,"component")
if e and d then local f=false;for g in d.list("gpu")do f=true
break end
if f then local g,h=pcall(require,"kernel.screen")
a.ok("screen module loaded",
g and type(h)=="table")else a.skip("seat binding","no GPU on this machine")end end
a.ok("uptime is positive",computer.uptime()>0)end