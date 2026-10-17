local q=require("computer")local m={}local r=true;local t=1.0;local v=0.05
local function n(b,a)
if not r then return end;a=a*t;if a<v then a=v end;pcall(q.beep,b,a)end;local w=0.05;local s=nil
local function p()if s==nil then local c,b=pcall(require,"kernel.process")
s=
(c and
type(b)=="table"and type(b.pause)=="function")and b or false end;if s and
s.pause(w)then return end;local a=q.uptime()+w
while q.uptime()<a do end end;local x=1.0;local u={}local function o(a)local b=q.uptime()local c=u[a]
if c and b-c<x and b>=c then return false end;u[a]=b;return true end
function m.success()if
not o("success")then return end;n(1000,0.1)end;function m.confirm()if not o("confirm")then return end;n(800,0.08)p()
n(1200,0.1)end;function m.error()
if not o("error")then return end;n(300,0.3)end;function m.critical()n(400,0.15)p()
n(400,0.15)p()n(400,0.15)end
function m.warning()if not o("warning")then
return end;n(500,0.1)p()n(500,0.1)end
function m.notify()if not o("notify")then return end;n(1200,0.06)end;function m.shutdown()if not o("shutdown")then return end;n(800,0.12)p()
n(400,0.15)end;function m.boot()
if not o("boot")then return end;n(1000,0.15)end;function m.bootComplete()if
not o("bootComplete")then return end;n(800,0.08)p()n(1000,0.08)p()
n(1200,0.1)end
function m.chat()if not o("chat")then
return end;n(1000,0.05)p()n(1400,0.08)end
function m.tick()if not o("tick")then return end;n(600,0.02)end;function m.setEnabled(a)r=a~=false end;function m.isEnabled()return r end
function m.setVolume(a)t=math.max(0.1,math.min(2.0,
tonumber(a)or 1.0))end;function m.getVolume()return t end;function m._resetCooldown()u={}end;m.COOLDOWN=x
function m.init(a)if a then
local b=a.get("audio")if b~=nil then r=b~=false end;local c=a.get("audioVolume")if c then
m.setVolume(c)end end end;return m