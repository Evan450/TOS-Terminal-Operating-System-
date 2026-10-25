local d="number"local c={}c.VERSION="0.2.0"
c.PARAMS={{key="N",label="POWER",field="flux",unit="",full=10000,limit="fluxScram",step=4},{key="T",label="CORE TEMP",field="temp",unit="C",full=1000,limit="tempScram",step=1},{key="X",label="STEAM",field="steam",unit="%",full=100,step=0.01},{key="K",label="ROD DEPTH",field="rodDepth",unit="%",full=100,step=0.01},{key="G",label="COOLANT",field="water",unit="%",full=100,limit="waterMin",invert=true,step=0.01}}
function c.param(a)if type(a)~="string"then return nil end;a=a:upper()for e,b in
ipairs(c.PARAMS)do if b.key==a then return b end end;return nil end
function c.paramKeys()local a={}for b,e in ipairs(c.PARAMS)do a[b]=e.key end;return a end
c.BANDS={{0.00,0x0080FF,"cold"},{0.40,0x00FF00,"normal"},{0.70,0xFFFF00,"high"},{0.85,0xFF8000,"warn"},{1.00,0xFF0000,"alarm"}}c.COLOR_MISSING=0x666666
function c.fractionOf(a,b,e)
if type(a)~=d or a~=a then return nil end;if not b then return nil end;local g=b.full;if
b.limit and e and type(e[b.limit])==d then g=e[b.limit]end
if b.invert then local f=b.full or 100;if
not g or g>=f then g=f*0.1 end;if a>=f then return 0 end;if a<=g then return 1 end;return(
f-a)/ (f-g)end;if not g or g<=0 then return nil end;local h=a/g;if h<0 then h=0 end;if h>1 then h=1 end
return h end
function c.bandOf(a,b,e)local g=c.fractionOf(a,b,e)
if g==nil then return c.COLOR_MISSING,"missing"end;local h,i=c.BANDS[1][2],c.BANDS[1][3]for j,f in ipairs(c.BANDS)do if g>=f[1]then
h,i=f[2],f[3]end end;return h,i end
function c.cellText(a)if type(a)~=d or a~=a then return"----"end
if a>-999.5 and
a<9999.5 then
return string.format("%4d",math.floor(a+0.5))elseif a>-99500 and a<999500 then
return string.format("%3.0fk",a/1000)elseif a>=999500 and a<999500000 then
return string.format("%3.0fM",a/1000000)end;return a<0 and"-BIG"or"+BIG"end
function c.isChannel(b,e,a)a=a or{}local f,g=a.w or 15,a.h or 15;if
b<1 or e<1 or b>f or e>g then return false end;if a.mask then
return a.mask[b..","..e]==true end
if a.shape=="circle"then local j,k=(f+1)/2,(g+1)/2
local l,m=f/2,g/2;local h,i=(b-j)/l,(e-k)/m;return(h*h+i*i)<=1.0 end;return true end;function c.channelCount(a)a=a or{}local b=0;for e=1,a.h or 15 do for f=1,a.w or 15 do
if c.isChannel(f,e,a)then b=b+1 end end end
return b end
c.RAIL_PREF=22;c.RAIL_MIN=10;c.CELL_MAX=5;c.CELL_MIN=2
function c.layout(a,e,b)b=b or{}
local i,g=b.w or 15,b.h or 15;local f={gridW=i,gridH=g}f.headerH=2;f.footerH=2
local k=f.headerH+1+g+1+f.footerH
if e<k then return
{ok=false,why=string.format("screen is %d rows; a %dx%d core map needs %d",e,i,g,k)}end;f.rulerW=#tostring(g)local function l(m,n)return f.rulerW+1+i*n+
(m>0 and(1+m)or 0)end;local j,h
for m=c.CELL_MAX,c.CELL_MIN,
-1 do for o,n in ipairs({c.RAIL_PREF,c.RAIL_MIN,0})do
if l(n,m)<=a then j,h=n,m;break end end;if h then break end end
if not h then return
{ok=false,why=string.format("screen is %d columns; a %dx%d core map needs %d",a,i,g,l(0,c.CELL_MIN))}end;f.ok=true;f.W,f.H=a,e;f.railW=j;f.cellW=h;f.numeric=(h>=5)
f.rulerY=f.headerH+1;f.mapY=f.rulerY+1;f.mapX=f.rulerW+2
f.railX=(j>0)and(a-j+1)or nil;f.statusY=f.mapY+g+1;return f end
function c.cellPos(a,b,e,f)if not(a and a.ok)then return nil end;if f and
not c.isChannel(b,e,f)then return nil end;if
b<1 or e<1 or b>a.gridW or e>a.gridH then return nil end;return a.mapX+ (b-1)*
a.cellW,a.mapY+ (e-1)end
function c.cellAt(a,e,f,b)if not(a and a.ok)then return nil end;local g=f-a.mapY;if g<0 or
g>=a.gridH then return nil end;local h=e-a.mapX;if h<0 then return nil end;local i=math.floor(
h/a.cellW)+1
if i>a.gridW then return nil end
if a.cellW>4 and(h%a.cellW)>=4 then return nil end;local j=g+1
if b and not c.isChannel(i,j,b)then return nil end;return i,j end
function c.railRows(a,b)local e={}if not
(a and a.ok and a.railW and a.railW>0)then return e end
local f=a.railW>=c.RAIL_PREF
for h,g in ipairs(c.PARAMS)do local i;if f then i=g.key.."  "..g.label else
i=g.key.." "..g.label:sub(1,math.max(1,
a.railW-2))end
e[#e+1]={key=g.key,text=i,param=g,selected=(g.key==b)}end;return e end
function c.readout(b,e,a,f)local g={}local h=e or b or{}
for j,i in ipairs(c.PARAMS)do local k=h[i.field]
local m,n=c.bandOf(k,i,f)local l;if type(k)~=d then l="----"elseif math.abs(k)>=1000 then l=c.cellText(k)else
l=string.format("%.1f",k)end
g[#g+1]={key=i.key,text=i.key.." "..
l.. (
i.unit~=""and(" "..i.unit)or""),band=n,color=m,selected=(a~=nil and i.key==a.key)}end;return g end
function c.legend(a,b)local f={}local e=a and a.full;if a and a.limit and b and
type(b[a.limit])==d then e=b[a.limit]end
for h,g in
ipairs(c.BANDS)do local i;if a and e then
if a.invert then local j=a.full or 100;i=j-g[1]* (j-e)else i=g[1]*e end end
f[#f+1]={name=g[3],color=g[2],at=i}end;return f end;return c