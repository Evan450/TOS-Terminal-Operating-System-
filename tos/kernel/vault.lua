local r="string"local p={}local o=require("kernel.crypto")local s="TVAULT1\0"
local q="TVAULT2\0"local w=q;local x=8+4+2+16+16+4+64;local function t(a)return
string.char(a&0xFF,(a>>8)&0xFF)end;local function u(a)
return string.char(a&0xFF,(a>>8)&0xFF,(
a>>16)&0xFF,(a>>24)&0xFF)end;local function A(b,a)return b:byte(a)|
(b:byte(a+1)<<8),a+2 end;local function B(b,a)
return
b:byte(a)| (b:byte(
a+1)<<8)| (b:byte(a+2)<<16)| (b:byte(a+3)<<24),a+4 end
local function v(a)
if#a>=4 then return a:sub(1,4)end;return a..string.rep("\0",4-#a)end
local function y(a,b)local d=o.hashPassword(a,b)
local e,e,c=d:find("^v%d+%$%d+%$(%x+)$")c=c or d;return c:sub(1,32)end;local function z(a)local b=o.hmac(a,"tos.vault.enc.v2")
local c=o.hmac(a,"tos.vault.mac.v2")return b,c end
function p.encrypt(c,a,b)b=b or{}if
type(c)~=r or type(a)~=r then
return nil,"vault.encrypt: plaintext and passphrase must be strings"end;if#a<1 then
return nil,"passphrase must be non-empty"end
if b.requireStrong and not
(o.hasHardware and o.hasHardware())then return nil,

"vault.encrypt: strong encryption required but no data card present ".."(refusing to protect secrets with the XOR fallback)"end;local f=o.salt(16)
local g=o._makeIv16 and o._makeIv16()or string.rep("\0",16)local j=y(a,f)local k,l=z(j)local d,e=o.encrypt(c,k)if not d then
return nil,"encryption failed"end
if e=="aes"then g=d:sub(1,16)d=d:sub(17)elseif e=="xor"then else return nil,
"unknown algo: "..tostring(e)end;local h=0;local m=v(e)..t(h)..f..g..u(#d)..d
local n=o.hmac(l,m)
local i=w..v(e)..t(h)..f..g..u(#d)..n..d;return i,{algo=e,ctLen=#d,blobLen=#i}end
function p.decrypt(a,b)if type(a)~=r or type(b)~=r then
return nil,"vault.decrypt: blob and passphrase must be strings"end;if#a<x then
return nil,"blob too short"end;local l=a:sub(1,8)local f;if l==q then f=true elseif l==s then f=false else
return nil,"not a TOS vault blob"end;local c=8+1;local d=a:sub(c,c+3)
c=c+4;d=d:gsub("\0+$","")local m;m,c=A(a,c)local n=a:sub(c,c+15)c=c+16;local C=a:sub(c,c+
15)c=c+16;local e;e,c=B(a,c)local D=a:sub(c,c+63)c=c+64;if c+e-
1 >#a then return nil,"blob truncated"end
local g=a:sub(c,c+e-1)local h=y(b,n)local i,j;if f then i,j=z(h)else i,j=h,h end;local E=v(d)..
t(m)..n..C..u(e)..g;local F=o.hmac(j,E)
if not o.ctEquals(F,D)then return nil,
"MAC mismatch (wrong passphrase, or blob tampered with)  [E-305 ERR_VAULT_UNLOCK]"end;local G=(d=="aes")and(C..g)or g
local k=o.decrypt(G,i,d)if not k then return nil,"decryption failed (corrupt blob)"end;return
k,{algo=d,ctLen=e,plaintextLen=#k}end
function p.isEncrypted(a)if type(a)~=r or#a<8 then return false end
local b=a:sub(1,8)return b==q or b==s end;p.MAGIC=w;p.MAGIC_V1=s;p.MAGIC_V2=q;p.HEADER_LEN=x;return p