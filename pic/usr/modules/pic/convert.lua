local g=require("pic.ocif")local k=require("pic.png")local h={}
local i=math.floor
h.T2_PALETTE={0xFFFFFF,0xFFCC33,0xCC66CC,0x6699FF,0xFFFF33,0x33CC33,0xFF6699,0x333333,0xCCCCCC,0x336699,0x9933CC,0x333399,0x663300,0x336600,0xFF3333,0x000000}
function h.quantizer(a,b)local d=g.to8;if a>=8 then
return function(e,f,m)local n=d(e,f,m)local o,p,q=g.rgb(g.PALETTE[n])
return n,o,p,q end end;if a<=1 then
local e=d(255,255,255)
return function(f,m,n)
if f*0.299+m*0.587+n*0.114 >=128 then return e,255,255,255 end;return 0,0,0,0 end end
local c={}for e,f in ipairs(b or h.T2_PALETTE)do local m,n,o=g.rgb(f)
c[e]={m,n,o,d(m,n,o)}end
return
function(e,f,m)local n,o=c[1],math.huge;for p=1,#c do local q=c[p]
local r=(e-
q[1])^2+ (f-q[2])^2+ (m-q[3])^2;if r<o then n,o=q,r end end;return n[4],n[1],
n[2],n[3]end end
function h.targetSize(a,b,c,d)local e=math.min(1,c/a,(d*2)/b)
local f=math.max(1,i(a*e+0.5))local m=math.max(1,i(b*e+0.5))return f,m end;local l=3
local function j(a,b)local c={}
for d=1,b do local f=(d-1)*a/b
local e=math.min(l,math.max(1,i(a/b+0.5)))
for m=0,e-1 do
local n=i(f+ (m+0.5)* (a/b)/e)+1;c[#c+1]={math.min(a,n),d}end end;return c end
function h.fromPNG(b,a)a=a or{}local B,C=a.maxW or 160,a.maxH or 50
local D=h.quantizer(a.depth or 8,a.palette)local E=a.dither~=false;local q,c,e;local r={}local s={}local t=g.builder(1,1)
local u,v=string.char(t:symbol(g.UPPER)),string.char(t:symbol(" "))local f,m,n,o={},{},{},{}local w,x,y={},{},{}local p=nil;local function z()
for H=1,c do f[H],m[H],n[H],o[H]=0,0,0,0 end end
local function A(H)local M={}local I,J,K={},{},{}for Q=0,c+1 do
I[Q],J[Q],K[Q]=0,0,0 end;local P=(H%2 ==1)local N,O,L=1,c,1
if not P then N,O,L=c,1,-1 end
for Q=N,O,L do local U=o[Q]if U==0 then U=1 end;local R,S,T=f[Q]/U+ (w[Q]or 0),m[Q]/U+ (x[Q]or 0),
n[Q]/U+ (y[Q]or 0)
if R<0 then R=0 elseif R>255 then R=255 end;if S<0 then S=0 elseif S>255 then S=255 end;if T<0 then T=0 elseif T>255 then T=255 end
local V,W,X,Y=D(R,S,T)M[Q]=V
if E then local aa,ab,ac=R-W,S-X,T-Y;local Z=Q+L
if Z>=1 and Z<=c then
local ad=o[Z]>0 and o[Z]or 1;f[Z]=f[Z]+aa*7/16*ad;m[Z]=m[Z]+ab*7/16*ad;n[Z]=
n[Z]+ac*7/16*ad end;local _=Q-L;I[_]=I[_]+aa*3/16;J[_]=J[_]+ab*3/16;K[_]=K[_]+ac*3/
16;I[Q]=I[Q]+aa*5/16
J[Q]=J[Q]+ab*5/16;K[Q]=K[Q]+ac*5/16;I[Z]=I[Z]+aa/16;J[Z]=J[Z]+ab/16;K[Z]=
K[Z]+ac/16 end end;w,x,y=I,J,K
if H%2 ==1 then p=M else s[H/2]=g.pixelRow(p,M,c,u,v)p=nil end;z()end;local d=0
local F,G=k.read(b,function(H,I)c,e=h.targetSize(H,I,B,C)q=j(H,c)for K,J in ipairs(j(I,e))do
r[J[1]]=J[2]end;z()return r end,function(H,I)
local J=r[H]while d+1 <J do d=d+1;A(d)end
for K=1,#q do local N=q[K]local O,P,Q,M=I(N[1])local L=N[2]f[L]=f[L]+O*
M/255;m[L]=m[L]+P*M/255
n[L]=n[L]+Q*M/255;o[L]=o[L]+1 end end,a.progress)if not F then return nil,G end;while d<e do d=d+1;A(d)end
if e%2 ==1 then local H={}
for I=1,c do H[I]=0 end;s[(e+1)/2]=g.pixelRow(p,H,c,u,v)end;return{w=c,h=math.ceil(e/2),syms=t.syms,rows=s,lost=0}end;return h