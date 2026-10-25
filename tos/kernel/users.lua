
local aL,as,aM,aF,aN,aG,aB,au="/public","Insufficient privileges","Invalid username or password","Persist failed: ","User '","User not found","number","string"local aq=require("computer")
local aC=require("kernel.serialize")local ak={}local aj={GUEST=0,USER=1,ADMIN=2,ROOT=3}local al={}local aH="/etc/users.dat"
local bp="/var/run/session"local av="/etc/elevate.dat"local ap={}local ao=nil;local an=nil;local am=nil;local ai=nil;local ar=nil;local aO=5
local aP=true;local aw=3600;local aQ=6;local function aI(a)
if type(a)~=au or#a<aQ then return false,
"Password must be at least "..aQ.." characters"end;return true end
local aR={[aj.GUEST]=true,[aj.USER]=true,[aj.ADMIN]=true,[aj.ROOT]=true}local function aD(a,b)
return
type(a)=="table"and type(a.tier)==aB and type(b)==aB and a.tier>b end
local function ax(a,b)
if a and not a.isKernel and not
a.isLogin then return tonumber(a.tier)or 0 end
return type(b)=="table"and tonumber(b.tier)or 0 end
local function ay(a)return type(a)=="table"and a.isLogin==true end;local aS=3;local bd=5;local aT=300
local function aU(a)a=tonumber(a)or 0;if a<aS then return 0 end;local b=bd*
(2^ (a-aS))if b>aT then b=aT end;return b end;local function az()
return(os.time and os.time())or aq.uptime()end
local function aV()return
(_G._TOS and tonumber(_G._TOS.bootCount))or 0 end;local function aW()return{boot=aV(),at=aq.uptime()}end
local function aX(a)
local b=aq.uptime()if type(a)=="table"and a.boot==aV()then local c=tonumber(a.at)if
c and c<=b then return b-c end end
return b end
local function at()
if not an then
if ai then ai.error("users","saveDB: fs not initialized")end;return false,"FS not initialized"end;local c,a=pcall(aC.encode,al)
if not c then if ai then
ai.error("users","saveDB: serialize failed: "..tostring(a))end;return false,
"serialize failed: "..tostring(a)end
local d,b=(an.writeFileAtomic or an.writeFile)(aH,a)if not d then if ai then
ai.error("users","saveDB: write failed: "..tostring(b))end
return false,tostring(b or"write failed")end;return true end
local function be()if not an then return false,"FS not initialized"end;if
not an.exists(aH)then al={}return true end;local a,c=an.readFile(aH)
if not a then return false,c end;local b,d=aC.decode(a)if not b then return false,d end;al=b;return true end
local function aJ()if not an or not an.exists(av)then return nil end
local b=an.readFile(av)if type(b)~=au or b==""then return nil end
local a=aC.decode(b)if type(a)~="table"or type(a.hash)~=au or
type(a.salt)~=au then return nil end
if
a.cap~=aj.ADMIN and a.cap~=aj.ROOT then a.cap=aj.ADMIN end;return a end
function ak.setElevation(c,b,a)local d=c or(ao and ap[ao])
if not d or(d.tier or 0)<
aj.ROOT then return false,"Only root can configure elevation"end;local f,g=aI(b)if not f then return false,g end;if a~=aj.ADMIN and a~=aj.ROOT then return
false,"cap must be admin or root"end;local h=
aJ()~=nil;local e=am.salt(16)
local i={hash=am.hashPassword(b,e),salt=e,cap=a}local j=aC.encode(i)
local k,l=(an.writeFileAtomic or an.writeFile)(av,j)
if not k then return false,tostring(l or"write failed")end;if ai then
ai.warn("auth","Elevation password "..
(h and"updated"or"configured").." (cap tier "..a..
") by "..tostring(d.user))end;return true end
function ak.clearElevation(a)local b=a or(ao and ap[ao])
if not b or(b.tier or 0)<
aj.ROOT then return false,"Only root can disable elevation"end
if an and an.exists(av)then pcall(an.remove,av)end;if ai then
ai.warn("auth","Elevation disabled by "..tostring(b.user))end;return true end
function ak.elevationInfo()local a=aJ()if not a then return{configured=false}end;return
{configured=true,cap=a.cap}end
function ak.elevate(a,b)local c=a or(ao and ap[ao])local e=aJ()
local d=c and
type(c.user)==au and al[c.user]or nil;local f=d and aU(d.elevFailed)or 0
if f>0 then
local m=aX(d.elevFailedAt)
if m<f then if ai then
ai.warn("auth",string.format("Elevation throttled for '%s' (cooldown %ds)",tostring(c.user),f))end;return nil,
string.format("Too many failed attempts; try again in %ds",math.ceil(
f-math.max(m,0)))end end;local g="elevate-timing-dummy"local k=(e and e.salt)or g;local h=
(e and e.hash)or
(am and am.hashPassword and am.hashPassword("x",g))
local i=false;if am and am.verifyPassword and h then
i=am.verifyPassword(b or"",k,h)end
if not c then return nil,"Not logged in"end
if(c.tier or 0)<aj.USER then return nil,"Guests cannot elevate"end;if not e then return nil,"Elevation is not configured"end
if not i then if d then d.elevFailed=(
tonumber(d.elevFailed)or 0)+1
d.elevFailedAt=aW()at()end;if ai then
ai.warn("auth","Failed elevation attempt by "..
tostring(c.user))end
return nil,"Incorrect elevation password"end;if d and(d.elevFailed or d.elevFailedAt)then d.elevFailed,d.elevFailedAt=
nil,nil;at()end;local j=math.max(
c.tier or 0,e.cap)
local l={user=c.user,tier=j,realTier=c.realTier or c.tier,home=c.home,displayName=c.displayName or
c.user,loginTime=c.loginTime,lastActivity=aq.uptime(),elevated=true,elevatedFrom=c.tier or 0,elevatedCap=e.cap}if ai then
ai.warn("auth",aN..tostring(c.user).."' elevated to tier "..j)end;return l end
function ak.registerSession(a)
if type(a)~="table"or not a.user then return nil end;local b=am.token()ap[b]=a;return b end
local function bf(b,a)
for d,c in pairs(ap)do
if
type(c)=="table"and c.user==b and not c.isGuest then c.realTier=a
if c.passwordChangeOnly then elseif c.elevated then
if a<aj.USER then c.tier=aj.GUEST else c.tier=math.max(a,
tonumber(c.elevatedCap)or a)end else c.tier=a end end end end
local function aY(a)local b={}for d,c in pairs(ap)do
if type(c)=="table"and c.user==a then b[#b+1]=d end end
for d,c in ipairs(b)do local e=ap[c]ap[c]=nil;if c==ao then
ao=nil end;e.tier,e.revoked=aj.GUEST,true end;return#b end
function ak.init(a)an=a.fs;am=a.crypto;ai=a.log;ar=a.config
if ar then
local e=ar.get and ar.get("maxAttempts")if type(e)==aB and e>0 then aO=e end
local f=ar.get and ar.get("autoLockout")if f~=nil then aP=f~=false end
local d=ar.get and ar.get("sessionTimeout")
if type(d)==aB and d>0 then aw=d elseif d==0 then aw=math.huge end end;if am then am.init()end;local b,c=be()
if not b then if ai then
ai.warn("users","Could not load user DB: "..tostring(c))end;al={}end;if not al["root"]then ak.createFirstBoot()end
if

ar and ar.get and ar.get("guestAccess")and not al["guest"]then ak.createGuestAccount()end
if not an.exists(aL)then an.makeDirectory(aL)end
if not an.exists("/home")then an.makeDirectory("/home")end
if ai then local d=0;for e in pairs(al)do d=d+1 end
ai.info("users","User system initialized ("..d.." accounts)")
ai.info("users","Crypto: "..
(am.hasHardware()and"Hardware (data card)"or"Software"))end;return true end
function ak.createFirstBoot()local a=am.salt(16)local b=am.hashPassword("root",a)
al["root"]={tier=aj.ROOT,salt=a,hash=b,created=az(),lastLogin=0,locked=false,failedAttempts=0,home="/root",displayName="System Administrator",firstBoot=true}if an and not an.exists("/root")then
an.makeDirectory("/root")end;at()if ai then
ai.warn("users","First boot: root account created with default password")
ai.warn("users","CHANGE THE ROOT PASSWORD IMMEDIATELY!")end end
function ak.createGuestAccount()
al["guest"]={tier=aj.GUEST,salt="",hash="",created=az(),lastLogin=0,locked=false,failedAttempts=0,home=aL,displayName="Guest",isGuest=true}at()
if ai then ai.info("users","Guest account created")end end;function ak.guestEnabled()return
ar and ar.get and ar.get("guestAccess")==true end
function ak.guestLogin()
if not
ak.guestEnabled()then return nil,"Guest access is disabled"end
if not al["guest"]then ak.createGuestAccount()end;local a=al["guest"]
if a.locked then return nil,"Guest account is locked"end;a.lastLogin=az()at()local b=am.token()
ap[b]={user="guest",tier=aj.GUEST,home=a.home,displayName="Guest",loginTime=aq.uptime(),lastActivity=aq.uptime(),firstBoot=false,isGuest=true}ao=b;if ai then ai.info("auth","Guest login")end;return b end
function ak.create(b,a,d,c)local e=ak.currentSession()if ay(e)then return false,as end;if e and
not e.isKernel and not e.isLogin then b=e.user;if e.tier<aj.ADMIN then
return false,as end end;if
not b then return false,"Creator username is required"end
local g=al[b]if not g then return false,"Creator not found"end;local i=
(
e and not e.isKernel and not e.isLogin)and(e.tier or 0)or g.tier;if i<
aj.ADMIN then return false,as end;if not a or#a<2 or#a>20 then return false,
"Username must be 2-20 characters"end
if
a:match("[^%w_%-]")then return false,"Username can only contain letters, numbers, _ and -"end;if al[a]then return false,"Username already exists"end
local j=a:lower()
for p in pairs(al)do if type(p)==au and p:lower()==j then
return false,"Username already exists"end end;local k,l=aI(d)if not k then return false,l end;c=c or aj.USER;if not aR[c]then return false,
"Invalid tier"end
if c>=aj.ROOT and
(not b or b~="root")then return false,"Only root can create root-level accounts"end;local h=am.salt(16)local m=am.hashPassword(d,h)local f="/home/"..a
al[a]={tier=c,salt=h,hash=m,created=az(),lastLogin=0,locked=false,failedAttempts=0,home=f,displayName=a}if not an.exists(f)then an.makeDirectory(f)end
local n,o=at()
if not n then al[a]=nil;return false,aF..tostring(o)end;if ai then
ai.info("users",string.format("User '%s' created (tier %d) by %s",a,c,b or"system"))end;return true end
function ak.delete(b,a)local c=ak.currentSession()if ay(c)then return false,as end;if c and
not c.isKernel and not c.isLogin then b=c.user;if c.tier<aj.ADMIN then
return false,as end end
local d=al[b]local e=ax(c,d)if not d or e<aj.ADMIN then return false,as end;if
a=="root"then return false,"Cannot delete root account"end;if
not al[a]then return false,aG end;if aD(al[a],e)then
return false,"Cannot delete an account that outranks you"end;aY(a)local f=al[a]al[a]=nil
local g,h=at()if not g then al[a]=f;return false,aF..tostring(h)end;if ai then
ai.info("users",string.format("User '%s' deleted by %s",a,b))end;return true end
local function bg(b,a,c,d,e)
if type(a)~=au or a==""or a=="/"then return nil end
if not
(an and an.exists and an.exists(a.."/.keychain.vault"))then return nil end
if not c then return
"'"..tostring(b)..
"' has a keychain; a reset cannot re-key it, ".."so it still opens with their OLD password."end;local g=_G._TOS and _G._TOS.keychain
local h,f=false,"keychain module unavailable"if g and g.rekey then
local j,i,k=pcall(g.rekey,d,e,ak.sessionFor(b))if j then h,f=i,k else f=i end end;if
h then return nil end;if ai then
ai.warn("users","Keychain re-key failed for '"..
tostring(b).."': "..tostring(f))end;return
"Your keychain could not be re-keyed ("..
tostring(f).."); it still opens with your OLD password."end
function ak.changePassword(a,b,d,c)local e=al[b]if not e then return false,aG end
local f=ak.currentSession()
if f and not f.isKernel and not f.isLogin then a=f.user end;if ay(f)and a~=b then return false,as end;local g=al[a]
if a~=b then local p=ax(f,g)if not g or p<
aj.ADMIN then return false,as end
if aD(e,p)then return false,
"Cannot change the password of an account that outranks you"end else local p=am.verifyPassword(d,e.salt,e.hash)if not p then return false,
"Current password is incorrect"end end;local i,j=aI(c)if not i then return false,j end;local k,l,m=e.salt,e.hash,e.firstBoot
local h=am.salt(16)e.salt=h;e.hash=am.hashPassword(c,h)e.firstBoot=nil;local n,o=at()if not n then
e.salt,e.hash,e.firstBoot=k,l,m;return false,aF..tostring(o)end;if ai then
ai.info("users",string.format("Password changed for '%s' by %s",b,a))end
return true,bg(b,e.home,a==b,d,c)end
local function aZ(a)local b=0;for d,c in pairs(al)do
if
d~=a and type(c.tier)==aB and c.tier>=aj.ADMIN and not c.locked then b=b+1 end end;return b end
function ak.setTier(c,b,a)local d=ak.currentSession()if ay(d)then return false,as end;if d and not
d.isKernel and not d.isLogin then c=d.user;if d.tier<aj.ADMIN then
return false,as end end
local g=al[c]if not g then return false,as end
local f=
(d and not d.isKernel and not d.isLogin)and(d.tier or 0)or g.tier;if f<aj.ADMIN then return false,as end;if b=="root"then
return false,"Cannot change root tier"end
if not aR[a]then return false,"Invalid tier"end;local e=al[b]if not e then return false,aG end
if aD(e,f)then return false,
"Cannot change the tier of an account that outranks you"end
if a>=aj.ROOT and f<aj.ROOT then return false,"Only root can grant root access"end
if e.tier>=aj.ADMIN and a<aj.ADMIN and aZ(b)==0 then return
false,"Refusing to demote the last administrator"end;local h=e.tier;e.tier=a;local i,j=at()
if not i then e.tier=h;return false,aF..tostring(j)end;bf(b,a)if ai then
ai.info("users",string.format("User '%s' tier set to %d by %s",b,a,c))end;return true end
function ak.setLocked(c,a,b)local e=ak.currentSession()if ay(e)then return false,as end;if e and not
e.isKernel and not e.isLogin then c=e.user;if e.tier<aj.ADMIN then
return false,as end end
local f=al[c]local g=ax(e,f)if not f or g<aj.ADMIN then return false,as end
local d=al[a]if not d then return false,aG end;if aD(d,g)then
return false,"Cannot lock or unlock an account that outranks you"end;if
b and type(d.tier)==aB and
d.tier>=aj.ADMIN and not d.locked and aZ(a)==0 then
return false,"Refusing to lock the last usable administrator"end
local h,i,j=d.locked,d.failedAttempts,d.lastFailedAt;d.locked=b;d.failedAttempts=0;d.lastFailedAt=nil;local k,l=at()
if not k then
d.locked,d.failedAttempts,d.lastFailedAt=h,i,j;return false,aF..tostring(l)end
if b then local m=aY(a)if m>0 and ai then
ai.warn("auth",string.format("Locked '%s': ended %d live session(s)",a,m))end end;return true end;local aK="0123456789abcdef"local aE=nil
local function a_()if aE then return aE end;if am and am.hashPassword then
aE=am.hashPassword("dummy-password-for-timing-only",aK)end;return aE end
function ak.login(a,b,c)c=c or{}local e=c.setCurrent;if e==nil then e=true end;local d=al[a]
if not d then
local j=a_()if j and am and am.verifyPassword then
am.verifyPassword(b or"",aK,j)end;if ai then
ai.warn("auth","Login attempt for unknown user: "..tostring(a))end;return nil,aM end;local f=aU(d.failedAttempts)
if f>0 then local j=aX(d.lastFailedAt)
if j<f then
local k=a_()if k and am and am.verifyPassword then
am.verifyPassword(b or"",aK,k)end;if ai then
ai.warn("auth",string.format("Login throttled for '%s' (cooldown %ds)",a,f))end;return nil,aM end end;local h,i=am.verifyPassword(b,d.salt,d.hash)
if not h then d.failedAttempts=(
d.failedAttempts or 0)+1
d.lastFailedAt=aW()if ai then
ai.warn("auth",string.format("Failed login for '%s' (attempt %d)",a,d.failedAttempts))end
if
aP and d.failedAttempts>=aO and a~="root"then d.locked=true;at()
if ai then ai.error("auth","Account '"..
a.."' auto-locked!")end;return nil,aM end;at()return nil,aM end
if d.locked then if ai then
ai.warn("auth","Login on locked account (correct password): "..a)end
return nil,"Account is locked. Contact an administrator."end;d.failedAttempts=0;d.lastFailedAt=nil;d.lastLogin=az()
if i then local j=am.salt(16)
d.salt=j;d.hash=am.hashPassword(b,j)if ai then
ai.info("auth","Rehashed legacy credentials for '"..a.."'")end end;at()local ax=d.tier;if d.firstBoot then ax=aj.GUEST end;local g=am.token()
ap[g]={user=a,tier=ax,realTier=d.tier,home=d.home,displayName=
d.displayName or a,loginTime=aq.uptime(),lastActivity=aq.uptime(),firstBoot=d.firstBoot or false,passwordChangeOnly=d.firstBoot or false}if e~=false then ao=g end
if ai then
if d.firstBoot then
ai.info("auth",aN..
a.."' authenticated (firstBoot — restricted token)")else
ai.info("auth",aN..a.."' logged in (tier "..d.tier..")")end end;return g end
function ak.promoteAfterFirstBoot(a)local b=ap[a]if not b then return false,"Unknown token"end
if not
b.passwordChangeOnly then return false,"Session is not first-boot"end;local c=al[b.user]if not c then return false,aG end;if c.firstBoot then return false,
"First-boot password still required"end
b.tier=b.realTier or c.tier;b.passwordChangeOnly=nil;b.firstBoot=nil;return true end
function ak.logout(a)a=a or ao
if a and ap[a]then local b=ap[a].user;ap[a]=nil;if a==ao then ao=nil end
if
ai then ai.info("auth",aN..b.."' logged out")end;return true end;return false end
function ak.currentSession()local b,a=pcall(require,"kernel.process")
if
b and a and a.currentSession then local c=a.currentSession()
if c then if
c.lastActivity and c.lastActivity~=math.huge then c.lastActivity=aq.uptime()end
local d=
a.currentToken and a.currentToken()or nil;return c,d end end
if _G._TOS and _G._TOS.bootSession then return _G._TOS.bootSession,nil end
if ao and ap[ao]then local c=ap[ao]local d=aq.uptime()
if
(d- (c.lastActivity or 0))>aw then if ai then
ai.info("auth","Session expired for '"..c.user.."' (idle timeout)")end;ap[ao]=nil;ao=nil;return nil end;c.lastActivity=d;return c,ao end;return nil end
function ak.getSession(a)local b=ap[a]
if b then local c=aq.uptime()
if
(c- (b.lastActivity or 0))>aw then if ai then
ai.info("auth","Session expired for '"..b.user.."' (idle timeout)")end;ap[a]=nil;if a==ao then ao=nil end
return nil end end;return b end
function ak.sweepSessions()local b=aq.uptime()local a={}for d,c in pairs(ap)do
if
(b- (c.lastActivity or 0))>aw then a[#a+1]={token=d,user=c.user}end end;for d,c in ipairs(a)do if ai then
ai.info("auth",
"Sweeping expired session for '"..c.user.."'")end;ap[c.token]=nil
if c.token==ao then ao=nil end end end
local bh={user="_kernel_",tier=aj.ROOT,home="/",displayName="Kernel",isKernel=true,loginTime=0,lastActivity=math.huge}function ak.kernelSession()return bh end
function ak.loginSession(a)
return
{user="_login_",tier=aj.GUEST,home="/",displayName="Login (seat "..
tostring(a or"?")..")",isLogin=true,display=a,loginTime=0,lastActivity=math.huge}end
function ak.sessionFor(a)if type(a)~=au then return nil end;local b=al[a]
if not b then return nil end;return
{user=a,tier=b.tier,home=b.home,displayName=b.displayName or a,loginTime=aq.uptime(),lastActivity=math.huge,isService=true}end
function ak.createSession(a)local b
if type(a)==au then b=a elseif type(a)=="table"then b=
type(a.name)==au and a.name or nil end;if not b then return nil end;local c=al[b]if not c then return nil end;return
{user=b,tier=c.tier,home=c.home,displayName=c.displayName or b,loginTime=aq.uptime(),lastActivity=math.huge,isService=true}end
local bi={["/etc/motd"]=true,["/etc/hostname"]=true,["/etc/profile"]=true,["/etc/tos.cfg"]=true}
local bj={["/etc/users.dat"]=true,["/etc/shadow"]=true,["/var/shadow"]=true}local bk={["/etc/selftest.on"]=true}
local bl={["/etc/elevate.dat"]=true,["/etc/trust.dat"]=true,["/etc/entropy"]=true,["/etc/cluster-manager.cfg"]=true}
local bm={"/var/log","/var/crash","/var/swap","/var/pkg/secrets","/var/lib/mesh"}local bn="%.tos%-tmp$"
local function ba(a)if
not a:find("[%u\128-\255]")and
not a:find("[%. ]/")and not a:find("[%. ]$")then return a end
local b=a:gsub("\226\132\170","k"):gsub("\196\176","i"):lower()
b=(b.."/"):gsub("[%. ]+/","/"):gsub("//+","/")if#b>1 then b=b:sub(1,-2)end;return b end;ak.pathKey=ba;local function aA(b,a)
return b==a or b:sub(1,#a+1)==a.."/"end
local bo={"/tos","/etc","/var","/usr"}
local function bb(a,b,c,d)if c=="r"and bi[b]then return true end;local e=(b:gsub(bn,""))
if
bj[e]then
if c=="r"then return a.tier>=aj.ADMIN,"Shadow file (admin required)"end;return a.tier>=aj.ROOT,"Shadow file (root required)"end;if c=="w"and bk[e]then
return a.tier>=aj.ROOT,"Grants kernel authority (root required)"end
if c=="r"then if bl[e]then return a.tier>=aj.ADMIN,
"Secret-bearing file (admin required)"end;for i,h in
ipairs(bm)do
if aA(b,h)then return a.tier>=aj.ADMIN,"Admin-only area (admin required)"end end end;local f=b:match("^/var/mail/([^/]+)")
if f then
if
d~=f and a.tier<aj.ADMIN then return false,"Access denied: not your mailbox"end
if c=="w"then return a.tier>=aj.ADMIN,"System path (admin required)"end;return true end;for i,h in ipairs(bo)do
if aA(b,h)then if c=="w"then
return a.tier>=aj.ADMIN,"System path (admin required)"end;return true end end;if aA(b,aL)then
if
c=="w"then return a.tier>=aj.USER,"Write requires user account"end;return true end;if aA(b,"/tmp")then
return true end;local g=b:match("^/home/([^/]+)")if g then
if g==d then return true end;if a.tier>=aj.ADMIN then return true end
return false,"Access denied: not your home directory"end
if
aA(b,"/root")then return a.tier>=aj.ROOT,"Root access required"end
if c=="w"then return a.tier>=aj.ADMIN,"Admin privileges required"end;return a.tier>=aj.USER,"User account required"end
local function bc(b,a,c)if not b then return false,"Not logged in"end
if a==nil or a==""then a="/"elseif
type(a)~=au then return false,"Invalid path"elseif an and an.normalize then a=an.normalize(a)elseif
a:find("\0",1,true)then a=nil else a=a:gsub("\\","/")if a:sub(1,1)~="/"then a="/"..a end
local g={}for h in a:gmatch("[^/]+")do
if h==".."then g[#g]=nil elseif h~="."then g[#g+1]=h end end
a="/"..table.concat(g,"/")end;if not a then return false,"Invalid path"end
if b.tier>=aj.ROOT then return true end;local d,e=bb(b,a,c,b.user)if not d then return false,e end;local f=ba(a)
if f~=a then
local g=b.user
d,e=bb(b,f,c,type(g)==au and g:lower()or nil)if not d then return false,e end end;return true end;function ak.canAccessAs(a,b,c)return bc(a,b,c)end;function ak.canAccess(a,b)return
bc(ak.currentSession(),a,b)end
function ak.list(a)
local e=ak.currentSession()local c=(e and e.tier)or aj.GUEST;local d=a or c
if d>c then d=c end;a=d;local b={}
for g,f in pairs(al)do
local h={username=g,tier=f.tier,displayName=f.displayName or g,locked=f.locked or false}if a>=aj.ADMIN then h.created=f.created;h.lastLogin=f.lastLogin
h.failedAttempts=f.failedAttempts;h.home=f.home end
b[#b+1]=h end
table.sort(b,function(f,g)if f.tier~=g.tier then return f.tier>g.tier end;return f.username<
g.username end)return b end
function ak.getUser(a)local c=al[a]if not c then return nil end;local b={}
for d,e in pairs(c)do b[d]=e end;b.name=a;b.salt=nil;b.hash=nil;return b end;function ak.exists(a)return al[a]~=nil end;ak.TIER=aj;return ak