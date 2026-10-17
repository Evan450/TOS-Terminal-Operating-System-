local K=require("computer")local A={}
local B={DEBUG=0,INFO=1,WARN=2,ERROR=3,FATAL=4}local P={[0]="DBG",[1]="INF",[2]="WRN",[3]="ERR",[4]="FTL"}
local T={[0]=0x666666,[1]=0xAAAAAA,[2]=0xFFFF00,[3]=0xFF6600,[4]=0xFF0000}local E=64;local F={}local D=0;local L=B.INFO;local H=0;local M=nil;local Q=false;local O=B.INFO;local I=nil
function A.init(a)
a=a or{}M=a.earlyPrint;I=a.bootProgress;Q=a.verbose or false;if
type(a.earlyMinLevel)=="number"then O=a.earlyMinLevel end;if Q or
O<=B.DEBUG then L=B.DEBUG else L=B.INFO end;if
K.totalMemory()<131072 then E=16 elseif K.totalMemory()<262144 then E=32 end end;function A.setLevel(a)
if type(a)=="string"then a=B[a:upper()]or B.INFO end;L=a end;local N={}
function A.setSourceLevel(b,a)
local d,c=pcall(require,"kernel.users")
if d and c and c.currentSession then local e=c.currentSession()if
e and not e.isKernel and
(e.tier or 0)< (c.TIER and c.TIER.ADMIN or 2)then
return false,"admin required to change source-level filtering"end end;if a==nil then N[b]=nil;return true end;if type(a)=="string"then a=B[a:upper()]or
B.INFO end;N[b]=a;return true end
local U={auth=true,users=true,repl=true,crypto=true,trust=true,securefs=true}
local function V(a,b)if not a then return false end;local c=a.tier or 0;local d=3;local e=2;local f=1
if c>=d then return true end;if c>=e then return true end;if c<f then return false end;if U[b]then return false end;return
true end
local function R(a)a=tostring(a)return
(a:gsub("[%c]",function(b)local c=string.byte(b)if c==9 then return b end;return
string.format("\\x%02x",c)end))end
local function J(a,b,c)local f=N[b]or L;if a<f then return end
local d={time=K.uptime(),level=a,source=R(b or"kernel"),msg=R(c)}D=D+1;local e=((D-1)%E)+1;if F[e]then H=H+1 end;F[e]=d;if
M and not I and a>=O then local g=string.format("[%s] ",P[a]or"???")
M(g..d.msg,T[a])end;if I and a>=B.INFO then
pcall(I,d.msg,a)end end;function A.debug(a,b)J(B.DEBUG,a,b)end
function A.info(a,b)J(B.INFO,a,b)end;function A.warn(a,b)J(B.WARN,a,b)end
function A.error(a,b)J(B.ERROR,a,b)end;function A.fatal(a,b)J(B.FATAL,a,b)end
function A.recent(a,b)
a=math.min(a or 20,E,D)local c={}if H>0 then
c[#c+1]={time=K.uptime(),level=B.WARN,source="log",msg="["..H.." entries lost since last read]"}H=0 end;local d=D-a+1;if d<1 then
d=1 end;for e=d,D do local f=((e-1)%E)+1
if F[f]then if
b and not V(b,F[f].source)then else c[#c+1]=F[f]end end end;return c end
function A.getSourceLevels()local a={}for b,c in pairs(N)do a[b]=c end;return a end
function A.format(a)return
string.format("[%7.1f][%s][%s] %s",a.time,P[a.level]or"???",a.source,a.msg)end;function A.detachEarlyPrint()M=nil;I=nil end;local z=nil;local C=nil;local S=16384;local G=0
function A.attachFile(b,c,a)
z=b;C=c;if a and tonumber(a.rotateBytes)then
S=tonumber(a.rotateBytes)end;G=0 end;function A.detachFile()z=nil;C=nil;G=0 end
local function W()if not z or not C then return end
if not
z.exists or not z.size or not z.rename then return end;if not z.exists(C)then return end;local b=z.size(C)or 0
if b<S then return end;local a=C..".1"
if z.exists(a)and z.remove then pcall(z.remove,a)end;pcall(z.rename,C,a)end
function A.flush()
if not z or not C then return false,"no log file attached"end;if D<=G then return true,"nothing to flush"end;W()local c=G+1
local d=D-E+1;if c<d then c=d end;local a={}for e=c,D do local f=((e-1)%E)+1;if F[f]then
a[#a+1]=A.format(F[f])end end;if#a==0 then G=D;return true,
"no entries in window"end;a[#a+1]=""
local b=table.concat(a,"\n")
if z.appendFile then local e,f=z.appendFile(C,b)if not e then return false,f end elseif z.open then
local e,g=z.open(C,"a")
if not e then return false,g or"open(append) failed"end;local f
if z.write then f=z.write(e,b)elseif e.write then f=e:write(b)end;if z.close then z.close(e)elseif e.close then e:close()end;if f==false then return false,
"append write failed"end elseif z.writeFile then local e=
z.readFile and z.readFile(C)or""
local f,g=z.writeFile(C,(e or"")..b)if not f then return false,g end else
return false,"fs supports neither appendFile, open, nor writeFile"end;G=D;return true end;local X=A.fatal
function A.fatal(a,b)X(a,b)if z and C then pcall(A.flush)end end;A.LEVELS=B;return A