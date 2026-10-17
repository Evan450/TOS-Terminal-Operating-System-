local C,R,K,L,M="remote","string"," bytes)","/public","/public/"
local E=require("computer")local A={}local I="remote_exec"local F="remote_res"local S=30;local H=8192;local N=32*1024;local T=1e6
local O=1e5;local z=nil;local B=nil;local G=nil;local y=nil;local U=nil;local J=false;function A.setEnabled(a)
J=a and true or false end;function A.isEnabled()return J end;local function P()
return
type(debug)=="table"and type(debug.sethook)=="function"end
function A.stepBudgetAvailable()return P()end;local Q=false
local function V()if Q or P()then return end;Q=true
if y and y.warn then
y.warn(C,
"debug.sethook is unavailable here (OpenComputers does "..
"not expose it): remote commands run with NO step or memory budget. ".."Trust + challenge-response and the OC watchdog are the only limits.")end end;local D=nil
function A.init(a)z=a.net;B=a.fs;G=a.trust;y=a.log;U=a.event
D=require("kernel.net.protocol")if z then
z.on(I,function(b,c)A.handleExec(b,c)end)end;if y then
y.info(C,"Remote shell module initialized")end;return true end
function A.execute(a,b)if not z then return nil,"Network not available"end;if not D then return nil,
"Protocol not loaded"end;local g=G.getLevel(a)if g<
G.LEVEL.TRUSTED then return nil,"Peer is not TRUSTED"end;if z.verifyPeer then
local k,l=z.verifyPeer(a)
if not k then return nil,"Peer verification failed: "..tostring(l)end end;if not b or b==""then return
nil,"No command specified"end;if type(b)~=R then return nil,
"Command must be a string"end;if#b>H then return nil,
"Command too large (max "..H..K end;local c=false;local d=nil;local e=nil
local f={{type=F,id=z.onceFrom(F,a,function(k)local l=
k.payload or{}
d=type(l.output)==R and l.output or""
e=type(l.exitCode)=="number"and l.exitCode or 0;c=true end)}}local h=D.makePacket(I,{cmd=b},{to=a})local i,j=z.send(a,h)
if not i then
z.offAll(f)return nil,"Send failed: "..tostring(j)end;if y then
y.info(C,"Sent command to "..a:sub(1,8).."...: "..b:sub(1,40))end
z.waitFor(function()return c end,S)z.offAll(f)
if not c then return nil,"Timeout waiting for response"end;return d,e end
function A.handleExec(b,a)if not z or not D then return end;if not J then return end
local l=G.getLevel(a)
if l<G.LEVEL.TRUSTED then if y then
y.warn(C,"Remote exec denied from non-trusted peer: "..a:sub(1,8).."...")end;return end
if z.verifyPeer then local r,s=z.verifyPeer(a)
if not r then if y then
y.warn(C,"Refusing remote exec from "..a:sub(1,8)..": "..
tostring(s))end;return end end;local m=b.payload or{}local d=m.cmd
if type(d)~=R or d==""then
local r=D.makePacket(F,{output="Error: no command provided",exitCode=1},{to=a})z.send(a,r)return end
if#d>H then if y then
y.warn(C,"Oversized remote cmd from "..a:sub(1,8).."... ("..#d..K)end
local r=D.makePacket(F,{output="Error: command too large (max "..H..K,exitCode=1},{to=a})z.send(a,r)return end
if E.freeMemory and E.freeMemory()<N then if y then
y.warn(C,"Refusing remote exec: low memory")end
local r=D.makePacket(F,{output="Error: host low on memory, retry later",exitCode=1},{to=a})z.send(a,r)return end;if y then
y.info(C,"Executing remote command from "..a:sub(1,8).."...: "..d:sub(1,60))end;local c={}local f=0;local g=5120;local function i(s,r)local t={}for u,w in
pairs(s)do if not(r and r[u])then t[u]=w end end
return t end
local j={print=function(...)if f>=g then return end;local s={}
for u=1,select("#",...)
do s[#s+1]=tostring((select(u,...)))end;local r=table.concat(s,"\t")local t=g-f;if#r>t then
r=r:sub(1,math.max(0,t))end;f=f+#r+1;c[#c+1]=r end,tostring=tostring,tonumber=tonumber,type=type,pairs=pairs,ipairs=ipairs,select=select,pcall=pcall,xpcall=xpcall,error=error,assert=assert,unpack=
table.unpack or unpack,table=i(table),string=i(string,{dump=true}),math=i(math),os={clock=os.clock,time=os.time,date=os.date},computer={uptime=E.uptime,freeMemory=E.freeMemory,totalMemory=E.totalMemory}}
if B then
j.fs={exists=function(r)r=B.normalize(r)
if r==L or r:sub(1,8)==M then return B.exists(r)end;return false end,list=function(r)
r=B.normalize(r)if r==L or r:sub(1,8)==M then return B.list(r)end
return{}end,isDirectory=function(r)r=B.normalize(r)if r==L or
r:sub(1,8)==M then return B.isDirectory(r)end;return
false end,readFile=function(r)
r=B.normalize(r)
if r==L or r:sub(1,8)==M then return B.readFile(r)end;return nil,"Access denied: only /public/ is accessible remotely"end}end;local k,n=load(d,"=remote","t",j)local h=0
if not k then
c[#c+1]="Load error: "..tostring(n)h=1 else local r,u,v=nil,nil,nil;local w=false;local s=0;local t=false;V()
if debug and debug.sethook then
if
debug.gethook then local Z,_,aa,ab=pcall(debug.gethook)if Z then r,u,v=_,aa,ab end end;local X
X=function()
if t then error("remote exec: step budget exceeded",0)end;if E.freeMemory and E.freeMemory()<N then t=true
pcall(debug.sethook,X,"",1)
error("remote exec: aborted (host low on memory)",0)end;s=s+O;if s>=T then
t=true;pcall(debug.sethook,X,"",1)
error("remote exec: step budget exceeded",0)end end;local Y=pcall(debug.sethook,X,"",O)if Y then w=true end end;local x,W=pcall(k)
if w then if r then pcall(debug.sethook,r,u or"",v or 0)else
pcall(debug.sethook)end end
if not x then c[#c+1]="Runtime error: "..tostring(W)h=1 end end;local e=table.concat(c,"\n")if#e>g then
e=e:sub(1,g).."\n... (output truncated)"end;if y then
y.info(C,"Command finished (exit="..h..", output="..#e..K)end
local o=D.makePacket(F,{output=e,exitCode=h},{to=a})local p,q=z.send(a,o)if not p and y then
y.warn(C,"Failed to send result: "..tostring(q))end end;A.TYPE_EXEC=I;A.TYPE_RES=F
do local a=rawget(_G,"_TOS")
if
a and a.net and not z then
local b=pcall(A.init,{net=a.net,fs=a.fs,trust=a.net.getTrust and a.net.getTrust()or nil,log=a.logObj,event=a.event})if
b and a.net.getServiceArm and a.net.getServiceArm("rshd")then A.setEnabled(true)end end end;return A