local Z,J,L,F="ed25519","invalid","pkgsign","string"local B={}local N="/etc/pkg_trust.cfg"
local T=4096;local U=8192;local V=64*1024;local C,H,D;function B.init(a)a=a or{}C=a.fs;H=a.serialize;D=a.log;return C~=nil and
H~=nil end;local function I(a,b)
return type(a)==F and#a==
b and a:match("^%x+$")~=nil end
local function K(a)return
(a:gsub("%x%x",function(b)return
string.char(tonumber(b,16))end))end
local function O(a)return
(a:gsub(".",function(b)return string.format("%02x",b:byte())end))end;B.hexToBin=K;B.binToHex=O
function B.fingerprint(a)
if not I(a,64)then return"(invalid key)"end;local d,b=pcall(require,"kernel.crypto")local c
if d and b and b.hash then
c=b.hash(K(a))else local g,f=pcall(require,"kernel.sha256")if not(g and f)then
return a:sub(1,16)end;c=f.hex(K(a))end
local e=tostring(c):sub(1,16):upper()return
(e:gsub("(....)","%1 "):gsub("%s+$",""))end;local E,P=nil,false;local W={tofu=true,trusted=true,off=true}local function _()return
{requireSignature=false,keys={},discovered="tofu"}end
local function G()
if P then return E end;P=true;E=_()if not C or not C.exists or not C.exists(N)then
return E end;local b=C.readFile(N)
if
not b or#b==0 or#b>U then if D then
D.warn(L,"trust store unreadable or oversized — NO publisher keys are in force")end;E.discovered="off"return E end;local c,a=pcall(H.decode,b,{maxBytes=U})
if
not c or type(a)~="table"then if D then
D.warn(L,"trust store did not decode — NO publisher keys are in force")end;E.discovered="off"return E end
if a.discovered~=nil then
if W[a.discovered]then E.discovered=a.discovered else E.discovered="off"if D then
D.warn(L,"unknown 'discovered' setting; reading it as off")end end end
if a.requireSignature==true then E.requireSignature=true end
if type(a.keys)=="table"then
for d,e in pairs(a.keys)do
if type(d)==F and#d<=48 and
d:match("^[%w%-_%.]+$")and I(e,64)then
E.keys[d]=e:lower()elseif D then
D.warn(L,"ignoring malformed trust entry '"..tostring(d).."'")end end end;return E end;function B.reloadTrust()P=false;E=nil;return G()end
function B.listKeys()local b=G()local a={}
for d,c in
pairs(b.keys)do a[#a+1]={label=d,key=c,fingerprint=B.fingerprint(c)}end
table.sort(a,function(c,d)return c.label<d.label end)return a end
function B.requiresSignature()return G().requireSignature==true end
function B.labelForKey(a)if not I(a,64)then return nil end;a=a:lower()local b=G()for c,d in
pairs(b.keys)do if d==a then return c end end;return nil end
local function M(a)
if not C or not C.writeFile then return false,"no filesystem"end
local b=H.encode({requireSignature=a.requireSignature==true,keys=a.keys,discovered=a.discovered})local c,d=C.writeFile(N,b)if not c then
return false,tostring(d or"write failed")end;return true end
function B.addKey(a,b)if type(a)~=F or not a:match("^[%w%-_%.]+$")or
#a>48 then
return false,"label must be 1-48 chars of letters, digits, - _ ."end
if not I(b,64)then return
false,"public key must be 64 hexadecimal characters (32 bytes)"end;b=b:lower()local c=G()if c.keys[a]and c.keys[a]~=b then
return false,"'"..a..
"' already names a different key — remove it first"end
local d=B.labelForKey(b)if d and d~=a then
return false,"that key is already trusted as '"..d.."'"end;c.keys[a]=b;local e,f=M(c)if not e then
c.keys[a]=nil;return false,f end;if D then
D.info(L,"trusted publisher key '"..a..
"' "..B.fingerprint(b))end;return true end
function B.removeKey(a)local b=G()if not b.keys[a]then return false,
"no trusted key named '"..tostring(a).."'"end
local c=b.keys[a]b.keys[a]=nil;local d,e=M(b)
if not d then b.keys[a]=c;return false,e end;if D then
D.info(L,"removed publisher key '"..a.."'")end;return true end
function B.setRequireSignature(a)local b=G()b.requireSignature=a and true or false;return M(b)end
function B.discoveredPolicy()return G().discovered or"off"end
function B.setDiscoveredPolicy(a)
if not W[a]then return false,"must be tofu, trusted or off"end;local b=G()b.discovered=a;return M(b)end
function B.sigPathFor(a)if type(a)~=F then return nil end
local b=a:match("^(.*)%.[%w]+$")if not b then return a..".sig"end;return b..".sig"end
function B.readSig(a)if not C or not C.exists or not C.exists(a)then return nil,
"no signature file"end
local c=C.readFile(a)
if not c or#c==0 then return nil,"signature file is empty"end
if#c>T then return nil,"signature file is implausibly large"end;local d,b=pcall(H.decode,c,{maxBytes=T})
if
not d or type(b)~="table"then return nil,"signature file did not decode"end
if b.alg~=nil and b.alg~=Z then return nil,
"unsupported signature algorithm '"..tostring(b.alg).."'"end
if not I(b.key,64)then return nil,"signature names no valid public key"end
if not I(b.sig,128)then return nil,"signature value is malformed"end
return
{alg=Z,key=b.key:lower(),sig=b.sig:lower(),signer=
type(b.signer)==F and b.signer:sub(1,48)or nil,covers=
type(b.covers)==F and b.covers:sub(1,64)or nil}end;local aa={trusted=true,unknown=true}
function B.verifyManifest(b,a)local d={state="unsigned"}if not C then
d.reason="no filesystem"return d end;local e=B.sigPathFor(b)if not e or
not C.exists(e)then
d.reason="no signature file alongside "..tostring(b)return d end;local c,h=B.readSig(e)if not
c then return{state=J,reason=h}end;if type(a)~=F then
a=C.readFile(b)end
if not a then return
{state=J,reason="cannot read the manifest the signature covers"}end;if#a>V then
return{state=J,reason="manifest is implausibly large to be signed"}end;if c.covers then local l=b:match("[^/]+$")
if l and
c.covers~=l then return
{state=J,reason="signature covers '"..c.covers.."', not "..l}end end
local i,f=pcall(require,"kernel.ed25519")
if not i or not f or not f.verify then return
{state=J,reason="signature present but ed25519 support is unavailable"}end;local j,k=f.verify(a,K(c.sig),K(c.key))
if not j then return
{state=J,key=c.key,signer=c.signer,fingerprint=B.fingerprint(c.key),reason=
k or"signature does not verify"}end;local g=B.labelForKey(c.key)return
{state=g and"trusted"or"unknown",key=c.key,fingerprint=B.fingerprint(c.key),label=g,signer=c.signer}end
function B.isVerified(a)return a~=nil and aa[a.state]==true end
function B.describe(a)if not a then return{"Signature: not checked"}end
local b={}
if a.state=="trusted"then b[#b+1]="Signature: VALID, from trusted publisher '"..
tostring(a.label).."'"b[#b+
1]="  key "..tostring(a.fingerprint)elseif a.state==
"unknown"then
b[#b+1]="Signature: VALID, but this key is NOT in your trust store."b[#b+1]="  key "..tostring(a.fingerprint)if
a.signer then
b[#b+1]="  the disk calls this publisher \""..a.signer.."\" (its own word, not proof)"end
b[#b+1]=
"  Trust it with:  pkg trust add <yourname> "..tostring(a.key)elseif a.state==J then
b[#b+1]="Signature: DOES NOT VERIFY — "..tostring(a.reason)b[#b+1]="  This is tampering or corruption, not a missing signature."else b[#b+
1]="Signature: none. This package is unsigned."
b[#b+1]="  Hashes prove the disk is intact, never who wrote it."b[#b+1]="  Your admin privilege is what is authorising this install."end;return b end
function B.signManifest(a,c,b)b=b or{}if type(c)~=F or#c~=32 then
return nil,"signing key must be 32 raw bytes"end
if not C or not C.exists(a)then return nil,
"no manifest at "..tostring(a)end;local e=C.readFile(a)
if not e then return nil,"cannot read "..a end;if#e>V then return nil,"manifest is too large to sign"end
local j,d=pcall(require,"kernel.ed25519")
if not j or not d or not d.sign then return nil,"ed25519 support unavailable"end;local f=d.publickey(c)
if not f then return nil,"cannot derive the public key"end;local i=d.sign(e,c,f)if not i then return nil,"signing failed"end
local g={v=1,alg=Z,key=O(f),sig=O(i),covers=a:match("[^/]+$")}if type(b.signer)==F and b.signer~=""then
g.signer=b.signer:sub(1,48)end;local h=B.sigPathFor(a)
local k,l=C.writeFile(h,H.encode(g))if not k then
return nil,"cannot write "..h..": "..tostring(l)end;return g.key,h end;local X="TOS-pkg-signing-key-v2"local Y=4096;local Q=20;local R=10
B.KDF_DOMAIN,B.KDF_ROUNDS=X,Y;B.KDF_MIN_PASS,B.KDF_MIN_UNIQUE=Q,R;local S
do
local b,a=pcall(require,"kernel.process")
if b and type(a)=="table"and
type(a.yieldCooperative)=="function"then S=a.yieldCooperative else S=function()end end end
function B.normalizeLabel(a)if type(a)~=F then return nil end
local b=a:gsub("^%s+",""):gsub("%s+$",""):lower()if b==""then return nil end;return b end
function B.seedFromPassphrase(a,b)local f=B.normalizeLabel(b)
if not f then return nil,

"a publisher label is required: it salts the key, so the same ".."passphrase under a different label is a different identity"end
if type(a)~=F or#a<Q then return nil,
"signing passphrase must be at least "..Q..
" characters (it IS the private key; generate it, do not invent it)"end;local g,c={},0
for j=1,#a do local i=a:sub(j,j)if not g[i]then g[i]=true;c=c+1 end end;if c<R then
return nil,"signing passphrase uses only "..
c.." distinct characters; ".."need "..
R..". Generate one rather than composing it."end
local h,d=pcall(require,"kernel.sha512")if not h or not d then return nil,"sha512 unavailable"end;local e=d.raw(X.."\0"..f..
"\0"..a)for j=1,Y do e=d.raw(e)if j%
256 ==0 then S()end end;return e:sub(1,32)end;return B