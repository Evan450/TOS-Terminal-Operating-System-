local ag,ah,ai,aj="Log passphrase","Menu passphrase","passwd","tape truncated"
local ak=require("component")local ac=require("computer")local U="TAUTH2\0"local al="TAUTH1\0"local Q=64;local V=200
local ad=8192
local function ae(a)if
type(crypto)=="table"and crypto.hmac and crypto.ctEquals then return crypto end
a("crypto capability unavailable — reinstall tape-authenticator.",0xFF0000)return nil end
local function W(a)if
type(vault)=="table"and vault.encrypt and vault.decrypt then return vault end
a("vault capability unavailable — reinstall tape-authenticator.",0xFF0000)return nil end
local function am(a)local b=ae(a)if not b then return nil end;if not b.secret then
a("machine secret unavailable (kernel too old?).",0xFF0000)return nil end;local c,d=b.secret()
if
not c then
a("Cannot access the key secret: "..tostring(d),0xFF0000)
a("(minting and verifying keycards is an admin action)",0xAAAAAA)return nil end;return c end;local function as()local a=ak.list("tape_drive")()
if a then return ak.proxy(a)end;return nil end
local function X(a)local b=as()if not b then
a("No tape drive found.",0xFF0000)return nil end;if not b.isReady()then
a("No tape inserted.",0xFF6600)return nil end;return b end
local function P(b,a)if a<=0 then return""end;local d,c={},a
while c>0 do
local f,e=pcall(b.read,math.min(ad,c))if not f or not e or#e==0 then break end;d[#d+1]=e;c=c-#e end;return table.concat(d)end
local function af(a,b)a.stop()
a.seek(- (a.getSize()or 0))local c=0
while c<#b do local d=b:sub(c+1,c+ad)local e,f=pcall(a.write,d)if not e then
return false,
"write failed at "..c..": "..tostring(f)end;c=c+#d;if(c/ad)%8 ==0 then
ac.pullSignal(0)end end;pcall(a.write,string.rep("\0",16))a.stop()a.seek(
- (a.getSize()or 0))return true end
local function an(a)return string.char(a&0xFF,(a>>8)&0xFF)end;local function Y(a)return
string.char(a&0xFF,(a>>8)&0xFF,(a>>16)&0xFF,(a>>24)&0xFF)end
local function ao(b,a)return
b:byte(a)| (b:byte(a+1)<<8),a+2 end
local function R(b,a)return
b:byte(a)| (b:byte(a+1)<<8)|
(b:byte(a+2)<<16)| (b:byte(a+3)<<24),a+4 end
local function at(a)
if not a or#a<7+4+2+Q then return nil,"tape unreadable or too short"end;local g=a:sub(1,7)local f;if g==U then f=2 elseif g==al then f=1 else
return nil,"not a tape-auth keycard (bad magic)"end;local b=8;local h;h,b=R(a,b)local e
e,b=ao(a,b)if e>V then return nil,"label length implausible"end;if
b+e+Q-1 >#a then return nil,aj end;local k=a:sub(b,b+e-1)b=b+e
local l=a:sub(1,b-1)local m=a:sub(b,b+Q-1)b=b+Q;local c,i=0,""local d,j=0,""
if f==2 then
if b+3 <=#a then c,b=R(a,b)if c>0 then if
b+c-1 >#a then return nil,"log region truncated"end
i=a:sub(b,b+c-1)b=b+c end
if b+3 <=#a then d,b=R(a,b)if d>0 then if b+d-
1 >#a then return nil,"menu region truncated"end
j=a:sub(b,b+d-1)b=b+d end end end end
return{version=f,label=k,issuedAt=h,body=l,mac=m,logLen=c,logBlob=i,menuLen=d,menuBlob=j}end;local function Z(c,d,b,a)local e=c..d..Y(#b)..b
if a and#a>0 then e=e..Y(#a)..a end;return e end
local function _(a)
local e=a.getSize()or 0;a.stop()a.seek(-e)local f=P(a,7)local d;if f==U then d=2 elseif f==al then d=1 else
return nil,"not a tape-auth keycard (bad magic)"end;local g=P(a,4)local h=P(a,2)if#g<4 or
#h<2 then return nil,aj end;local n=R(g,1)local i=ao(h,1)if i>V then return nil,
"label length implausible"end;local j=P(a,i)
if#j<i then return nil,aj end;local m=P(a,Q)if#m<Q then return nil,aj end;local o=f..g..h..j;local b,k,c,l=0,"",0,""
if
d==2 then local p=P(a,4)
if#p==4 then b=R(p,1)
if b>e then return nil,"log length implausible"end
if b>0 then k=P(a,b)if#k<b then return nil,"log region truncated"end end;local q=P(a,4)
if#q==4 then c=R(q,1)
if c>e then return nil,"menu length implausible"end
if c>0 then l=P(a,c)if#l<c then return nil,"menu region truncated"end end end end end
return{version=d,label=j,issuedAt=n,body=o,mac=m,logLen=b,logBlob=k,menuLen=c,menuBlob=l}end
local function O(a,b,c)local e=X(a)if not e then return nil end;local d,f=_(e)if not d then
a(tostring(f),0xFF0000)return nil end
if b then if d.version~=2 then
a("This is a TAUTH1 (identity-only) tape; re-run `tape-auth init` to upgrade.",0xFF6600)return nil end
local g=#d.body+
Q+4+ (d.logLen or 0)+4+
(d.menuLen or 0)+ (c or 0)if g> (e.getSize()or 0)then
a("Tape too small for that change.",0xFF0000)return nil end end;return e,d end;local function ap(a)local b={}
for c in(a or""):gmatch("[^\n]+")do b[#b+1]=c end;return b end
local function S(a,c,b)local d=W(b)
if not d then return nil end;if a.logLen==0 or a.logBlob==""then return{}end;if not
d.isEncrypted(a.logBlob)then
b("Log region is corrupt (not a vault blob).",0xFF0000)return nil end
local e,f=d.decrypt(a.logBlob,c)if not e then
b("Cannot decrypt log: "..tostring(f),0xFF0000)return nil end;return ap(e)end
local function aa(c,b,d,e,a)local f=W(a)if not f then return false end;local g=""
if#d>0 then
local k,l=f.encrypt(table.concat(d,"\n"),e)if not k then
a("encrypt failed: "..tostring(l),0xFF0000)return false end;g=k end;local h=Z(b.body,b.mac,g,b.menuBlob)if
#h> (c.getSize()or 0)then a("Tape too small for the updated log.",0xFF0000)
return false end;local i,j=af(c,h)if not i then
a(tostring(j),0xFF0000)return false end;return true end
local function T(a,c,b)local d=W(b)if not d then return nil end;if a.menuLen==0 or a.menuBlob==""then
return{}end;if not d.isEncrypted(a.menuBlob)then
b("Menu region is corrupt (not a vault blob).",0xFF0000)return nil end
local e,f=d.decrypt(a.menuBlob,c)if not e then
b("Cannot decrypt menu: "..tostring(f),0xFF0000)return nil end;return ap(e)end
local function ab(c,b,d,e,a)local f=W(a)if not f then return false end;local g=""
if#d>0 then
local k,l=f.encrypt(table.concat(d,"\n"),e)if not k then
a("encrypt failed: "..tostring(l),0xFF0000)return false end;g=k end;local h=Z(b.body,b.mac,b.logBlob,g)if
#h> (c.getSize()or 0)then a("Tape too small for the updated menu.",0xFF0000)return
false end;local i,j=af(c,h)if not i then
a(tostring(j),0xFF0000)return false end;return true end
local function aq(a,b)local e,d=pcall(require,"compat.term")
if
not e or type(d)~="table"or type(d.read)~="function"then
a("Cannot ask here (no terminal): type the passphrase in place of -.",0xFF6600)return nil end;a(b.." (not echoed):",0xAAAAAA)
local f,c=pcall(d.read,nil,false,nil,"*")c=
(f and type(c)=="string")and c:gsub("[\r\n]+$","")or nil;if not c or c==""then
a("Cancelled.",0xAAAAAA)return nil end;return c end
local function N(a,b,c,d)if b~="-"then return b end;local e=aq(a,c)if not e or not d then return e end
local f=aq(a,"Again, to confirm")
if f~=e then if f then
a("The two did not match; nothing was changed.",0xFF6600)end;return nil end;return e end
local function ar(a,...)
for b=1,select("#",...)do local c=select(b,...)
if c~=nil and c~="-"then
a("Note: a typed passphrase stays in command history.",0x555555)
a("Put - in its place to be asked for it instead.",0x555555)return end end end
local function au(b,a)local d=b[2]if not d then a("Usage: tape-auth init <label>",0xAAAAAA)
return end;if#d>V then
a("Label too long (max "..V..").",0xFF0000)return end;local e=X(a)if not e then return end;local g=am(a)if
not g then return end;local h=ae(a)local c=_(e)
if c and((c.logLen or 0)>0 or
(c.menuLen or 0)>0)then
local m=((
c.logLen or 0)>0)and"a personal log"or"a personal menu"if
(c.logLen or 0)>0 and(c.menuLen or 0)>0 then m="a personal log and menu"end
a(
"Tape already holds a keycard WITH "..m..".",0xFF6600)
a("`tape-auth log clear` / `tape-auth menu clear <passphrase>` first, or use a fresh tape.",0xAAAAAA)return end;local i=math.floor(ac.uptime())
local f=U..Y(i)..an(#d)..d;local j=h.hmac(g,f)local k,l=af(e,Z(f,j,""))if not k then
a(tostring(l),0xFF0000)return end
a(("Keycard initialized: label=%s (%d bytes identity, log empty)"):format(d,
#f+Q+4),0x00FF00)
a("Add private notes with: tape-auth log add - <text>",0xAAAAAA)
a("(- asks for the passphrase, so it stays out of your history)",0xAAAAAA)end
local function av(b,a)local d=X(a)if not d then return false end;local e=am(a)if not e then return false end
local f=ae(a)local c,g=_(d)
if not c then a(tostring(g),0xFF0000)return false end;local h=f.hmac(e,c.body)if not f.ctEquals(h,c.mac)then
a("INVALID: MAC mismatch — tape is not a valid key.",0xFF0000)return false end
a(("VALID: label=%s issuedAt=%d%s"):format(c.label,c.issuedAt,
c.version==1 and"  (TAUTH1 legacy card)"or""),0x00FF00)return true,c.label end
local function aw(b,a)local f=X(a)if not f then return end;local c,h=_(f)if not c then
a(tostring(h),0xFF6600)return end
local e=
(
type(crypto)=="table"and crypto.hmac and crypto.ctEquals)and crypto or nil;local d=nil
if e and e.secret then local i,j=pcall(e.secret)if i then d=j end end
local g=d and e.ctEquals(e.hmac(d,c.body),c.mac)
a(("Keycard (TAUTH%d%s): label=%s issuedAt=%d"):format(c.version,
d and(g and", VALID"or", INVALID")or", unverified",c.label,c.issuedAt),
d and(g and 0x00FF00 or 0xFF0000)or 0xFFFF55)
if c.version==2 then
if c.logLen>0 then
a(("Personal log: %d bytes (encrypted)"):format(c.logLen),0xAAAAAA)else a("Personal log: empty",0xAAAAAA)end
if(c.menuLen or 0)>0 then
a(("Personal menu: %d bytes (encrypted)"):format(c.menuLen),0xAAAAAA)else a("Personal menu: empty",0xAAAAAA)end else
a("No log region (legacy card; `tape-auth init` to upgrade).",0xAAAAAA)end;if not d then
a("Run `tape-auth verify` (admin) to authenticate it.",0x555555)end end
local function ax(b,a)local d=b[2]local c=b[3]if not d or not c then
a("Usage: tape-auth log <add|list|remove|clear|passwd> <passphrase|-> [...]",0xAAAAAA)return end;ar(a,c,
d==ai and b[4]or nil)
if d=="add"then
local e=table.concat(b," ",4)if#e==0 then
a("Usage: tape-auth log add <passphrase|-> <text>",0xAAAAAA)return end;e=e:gsub("[\r\n]"," ")local h,g=O(a,true,
#e+96)if not h then return end
c=N(a,c,ag,g.logLen==0)if not c then return end;local f=S(g,c,a)if not f then return end
f[#f+1]=("[t%d] %s"):format(math.floor(ac.uptime()),e)if aa(h,g,f,c,a)then
a(("Logged entry #%d."):format(#f),0x00FF00)end elseif d=="list"then local g,e=O(a,false)
if not g then return end;if e.version~=2 or e.logLen==0 then a("Log is empty.",0xAAAAAA)
return end;c=N(a,c,ag)if not c then return end
local f=S(e,c,a)if not f then return end
a(("Personal log — %s (%d entries)"):format(e.label,
#f),0xFFFF55)for h,i in ipairs(f)do
a(("  %2d. %s"):format(h,i),0xFFFFFF)end elseif d=="remove"or d=="rm"then
local e=tonumber(b[4])if not e then
a("Usage: tape-auth log remove <passphrase|-> <entry#>",0xAAAAAA)return end;local g,h=O(a,true)
if not g then return end;c=N(a,c,ag)if not c then return end;local f=S(h,c,a)if not f then return end
if not f[e]then a(
"No entry #"..e..".",0xFF6600)return end;local i=table.remove(f,e)if aa(g,h,f,c,a)then
a("Removed: "..i,0x00FF00)end elseif d=="clear"then local f,e=O(a,true)if not f then return end
if
e.logLen>0 then c=N(a,c,ag)if not c or not S(e,c,a)then return end end;if aa(f,e,{},c,a)then a("Log cleared.",0x00FF00)end elseif d==
ai then local e=b[4]if not e then
a("Usage: tape-auth log passwd <old|-> <new|->",0xAAAAAA)return end;local f,g=O(a,true)
if not f then return end;c=N(a,c,"Current log passphrase")if not c then return end
local h=S(g,c,a)if not h then return end;e=N(a,e,"New log passphrase",true)
if not e then return end
if aa(f,g,h,e,a)then a("Log passphrase changed.",0x00FF00)end else
a("Unknown: tape-auth log "..tostring(d),0xFF6600)end end
local function ay(b,a)local d=b[2]local c=b[3]if not d or not c then
a("Usage: tape-auth menu <add|list|remove|passwd|clear> <passphrase|-> [...]",0xAAAAAA)return end;ar(a,c,
d==ai and b[4]or nil)
if d=="add"then
local h=table.concat(b," ",4)local e,f=h:match("^(.-)%s+%-%-%s+(.+)$")if not e then
e,f=h:match("^(.-)%s*|%s*(.+)$")end
if not e or#e==0 or not f then
a("Usage: tape-auth menu add <pass> <Label> -- <command>",0xAAAAAA)
a("  e.g. tape-auth menu add hunter2 Reactor status -- doctor",0xAAAAAA)
if#h>0 then
a("Note: an unquoted | is a shell PIPE — it never reaches this",0xFFAA00)
a("command. Use -- , or quote it: \""..h.." | <command>\"",0xFFAA00)end;return end;e=e:gsub("[\r\n|]"," ")f=f:gsub("[\r\n]"," ")
local j,i=O(a,true,#e+#f+96)if not j then return end
local k=(i.menuLen==0 or i.menuBlob=="")c=N(a,c,ah,k)if not c then return end;local g=T(i,c,a)if not g then return end;g[#g+1]=e..
"|"..f
if ab(j,i,g,c,a)then
a(("Added menu item #%d."):format(#g),0x00FF00)
if k then
a("This tape had no menu, so the passphrase you just used is now",0xFFAA00)
a("ITS passphrase. Anyone holding the tape can try it: don't",0xFFAA00)
a("reuse your login password. Change it with 'menu passwd'.",0xFFAA00)end end elseif d==ai then local e=b[4]if not e then
a("Usage: tape-auth menu passwd <old|-> <new|->",0xAAAAAA)return end;local g,f=O(a,true)
if not g then return end
if f.menuLen==0 or f.menuBlob==""then
a("This tape has no menu yet — its passphrase is set by the first",0xAAAAAA)a("'menu add'.",0xAAAAAA)return end;c=N(a,c,"Current menu passphrase")if not c then return end
local h=T(f,c,a)if not h then return end;e=N(a,e,"New menu passphrase",true)
if not e then return end
if ab(g,f,h,e,a)then a("Menu passphrase changed.",0x00FF00)end elseif d=="list"then local g,e=O(a,false)if not g then return end;if e.menuLen==0 then
a("Tape menu is empty.",0xAAAAAA)return end;c=N(a,c,ah)if not c then return end
local f=T(e,c,a)if not f then return end
a(("Tape menu — %s (%d items)"):format(e.label,#f),0xFFFF55)for j,h in ipairs(f)do local i,k=h:match("^(.-)|(.+)$")
a(("  %2d. %-18s %s"):format(j,
i or h,k or""),0xFFFFFF)end elseif
d=="remove"or d=="rm"then local e=tonumber(b[4])if not e then
a("Usage: tape-auth menu remove <pass|-> <#>",0xAAAAAA)return end;local g,h=O(a,true)
if not g then return end;c=N(a,c,ah)if not c then return end;local f=T(h,c,a)if not f then return end
if not f[e]then a(
"No menu item #"..e..".",0xFF6600)return end;local i=table.remove(f,e)if ab(g,h,f,c,a)then
a("Removed: "..i,0x00FF00)end elseif d=="clear"then local f,e=O(a,true)if not f then return end
if
e.menuLen>0 then c=N(a,c,ah)if not c or not T(e,c,a)then return end end
if ab(f,e,{},c,a)then a("Tape menu cleared.",0x00FF00)end else
a("Unknown: tape-auth menu "..tostring(d),0xFF6600)end end
return
{commands={["tape-auth"]=function(b,a)a=a or print;local c=b[1]
if c=="init"or c=="write"then return au(b,a)elseif
c=="verify"then return av(b,a)elseif c=="info"then return aw(b,a)elseif c=="log"then return ax(b,a)elseif c=="menu"then return ay(b,a)else
a("=== Tape Authenticator ===",0xFFFF00)
a("A tape as a keycard + private notebook.",0xAAAAAA)a("",0xFFFFFF)
a("  tape-auth init <label>     Bless the tape as a keycard (admin)",0xFFFFFF)
a("  tape-auth verify           Authenticate the inserted tape (admin)",0xFFFFFF)
a("  tape-auth info             Identify the card (no secret needed)",0xFFFFFF)a("",0xFFFFFF)
a(" Personal log (operator-passphrase encrypted, lives on the card):",0x00FF00)
a("  tape-auth log add <pass> <text>      Append an entry",0xFFFFFF)
a("  tape-auth log list <pass>            Show all entries",0xFFFFFF)
a("  tape-auth log remove <pass> <n>      Delete entry n",0xFFFFFF)
a("  tape-auth log clear <pass>           Wipe the log",0xFFFFFF)
a("  tape-auth log passwd <old> <new>     Change the passphrase",0xFFFFFF)a("",0xFFFFFF)
a(" Personal menu (your own toolbox, travels on the card):",0x00FF00)
a("  tape-auth menu add <pass> <Label> -- <cmd> Add a menu item",0xFFFFFF)
a("  tape-auth menu list <pass>                Show items",0xFFFFFF)
a("  tape-auth menu remove <pass> <n>          Delete item n",0xFFFFFF)
a("  tape-auth menu passwd <old> <new>         Change the passphrase",0xFFFFFF)
a("  tape-auth menu clear <pass>               Wipe the menu",0xFFFFFF)
a("  (-- separates label from command; an unquoted | is a pipe)",0xAAAAAA)
a("  Any <pass> can be - : it is asked for, not echoed, and not",0xAAAAAA)
a("  left in your command history. A new one is asked twice.",0xAAAAAA)a("  Then open it with:  tape-menu",0xAAAAAA)end end},_format={parseImage=at,buildImage=Z,makeBody=function(a,b)return
U..Y(b or 0)..an(#a)..a end}}