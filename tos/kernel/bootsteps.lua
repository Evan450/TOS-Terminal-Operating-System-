local f,g,h="Starting networking","Starting background services","number"local e={}
e.STAGES={{"Scanning hardware","Scanning hardware"},{"Initializing filesystem","Mounting filesystems"},{"Boot disk","Mounting filesystems"},{"Loading configuration","Loading configuration"},{"Starting event","Starting event system"},{"Starting process","Starting process manager"},{"Initializing display","Initializing display"},{"Crypto","Initializing cryptography"},{"User system","Loading users and security"},{"Security","Loading users and security"},{"Theme manager","Loading themes"},{"Trust manager",f},{"Network",f},{"transfer",f},{"Remote shell",f},{"Loading:",g},{"Service started",g},{"Startup services",g},{"Cron","Starting scheduler"},{"Package manager","Loading package manager"},{"OpenOS compat","Loading OpenOS compatibility layer"},{"Audio feedback","Enabling audio feedback"},{"Boot complete","Boot complete"}}
do local b,a={},0;for d,c in ipairs(e.STAGES)do
if not b[c[2]]then b[c[2]]=true;a=a+1 end end;e.STAGE_COUNT=a end
function e.stageFor(a)a=tostring(a or"")for c,b in ipairs(e.STAGES)do
if a:find(b[1],1,true)then return b[2]end end;return nil end
function e.next(a,b)local c=e.stageFor(b)if c and c~=a then return c end;return nil end
function e.splashGeometry(b,a,c)b=(type(b)==h and b>0)and math.floor(b)or
50
a=
(type(a)==h and a>0)and math.floor(a)or 16
c=(type(c)==h)and math.floor(c)or 1;local i=math.max(10,math.min(40,b-6))
local j=math.max(1,math.floor((b-
(i+2))/2)+1)local d=c+1;if a-d<3 then d=c end
d=math.max(1,math.min(a-1,d))return d,i,j,math.max(0,math.min(3,a-d))end
function e.splashFits(a,b,c)local d,j,i=e.splashGeometry(a,b,c)return
(i>=1)and(i+j+1 <=a)and(d>=1)and(d<=b)end;return e