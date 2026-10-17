local h={}local function g(a,b)local d,c=pcall(a.readSector,b)if d and type(c)=="string"then
return c end end
local function f(a,b)
a=tostring(
a or""):gsub("\0.*$",""):gsub("%c","?"):gsub("%s+$","")if#a>b then a=a:sub(1,b)end;return a end
local function i(a,b,c)local d,e=string.packsize(b),{}
for k=d+1,#a-d+1,d do
local m,n,o,p,q,r=pcall(string.unpack,b,a,k)local l=m and c(n,o,p,q,r)if l then e[#e+1]=l end end;return e end
local function j(b,a)if#a==0 then return b..", with no partitions"end;local c={}for d=1,math.min(
#a,3)do c[d]=a[d]end
return("%s: %d partition%s (%s%s)"):format(b,
#a,#a==1 and""or"s",table.concat(c,", "),
#a>3 and(", +".. (#a-3))or"")end
function h.probe(a)if
type(a)~="table"or type(a.readSector)~="function"then
return{kind="unreadable",text="nothing TOS can read as a raw drive"}end
local b=g(a,1)if not b then
return{kind="unreadable",text="a first sector that cannot be read"}end
if b:sub(1,4)=="TBFS"then return
{kind="tbfs",text="a TBFS volume (TOS's own filesystem)"}end
if#b>=32 and b:sub(9,16)=="OSDI\170\170\85\85"then
local e=i(b,"<I4I4c8I3c13",function(m,m,k,m,l)if not
k:find("[^\0]")then return nil end;local o=f(l,12)
return o~=""and o or f(k,8)end)
return{kind="osdi",text=j("an OSDI partition table",e),count=#e}end
if b:sub(1,4)=="\27SFS"then
local e=#b>=35 and f(b:sub(17,35),19)or""
return{kind="simplefs",text="a SimpleFS filesystem"..
(e~=""and(' labelled "'..e..'"')or"")}end;local d=g(a,2)if d and d:sub(1,8)=="\27[OCGPTm"then return
{kind="ocgpt",text="an OCGPT partition table"}end
local c
do local l,k=pcall(a.getCapacity)local m,e=pcall(a.getSectorSize)if

l and m and type(k)=="number"and type(e)=="number"and e>0 then local o=math.floor(k/e)
if o>2 then c=g(a,o)end end end
if c and#c>=32 and c:sub(21,24)=="mtpt"then
local e=i(c,">c20c4I4I4",function(k)local l=f(k,12)return
l~=""and l or nil end)
return{kind="mtpt",text=j("an MTPT partition table",e),count=#e}end
if#b>=512 and b:sub(511,512)=="\85\170"then return
{kind="mbr",text="an MS-DOS boot record (MBR or FAT)"}end
if not b:find("[^\0]")and
(not c or not c:find("[^\0]"))then return
{kind="blank",text="nothing in its first and last sectors (it looks blank)"}end
return{kind="unknown",text="data in a format TOS does not recognise"}end;return h