local d=require("component")local c={}
c.TIER_NAMES={[0]="present (unknown tier)",[1]="T1 (hashing / base64 / deflate)",[2]="T2 (AES + random + T1)",[3]="T3 (ECC + AES + T1)"}
function c.capsOf(a,b)local f=nil
if b then local h,g=pcall(d.methods,b)
if h and type(g)=="table"then
f={}for i,j in pairs(g)do
if type(i)=="string"then f[i]=true elseif type(j)=="string"then f[j]=true end end end end;local function e(g)if f then return f[g]==true end;return
type(a)=="table"and a[g]~=nil end;if not f and type(a)~=
"table"then return{}end
return
{hash=e("sha256")or e("md5"),sha256=e("sha256"),base64=
e("encode64")or e("decode64"),crc32=e("crc32"),deflate=e("deflate")and e("inflate"),aes=
e("encrypt")and e("decrypt"),random=e("random"),ecc=
e("generateKeyPair")or e("ecdsa")or e("ecdh")}end
function c.tierOf(a)a=a or{}if a.ecc then return 3 end;if a.aes or a.random then return 2 end
if
a.hash or a.deflate or a.base64 or a.crc32 then return 1 end;return 0 end
function c.detect()local a={present=false,addr=nil,proxy=nil,caps={},tier=0}
local b=pcall(function()
for e in
d.list("data")do local g,f=pcall(d.proxy,e)
if g and f then a.present=true;a.addr=e;a.proxy=f
a.caps=c.capsOf(f,e)a.tier=c.tierOf(a.caps)return end end end)
if not b then a={present=false,addr=nil,proxy=nil,caps={},tier=0}end
a.name=c.TIER_NAMES[a.tier]or c.TIER_NAMES[0]return a end;return c