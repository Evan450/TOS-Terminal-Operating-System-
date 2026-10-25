local u="string"local l={}l._VERSION="1.0.0"local m=require("kernel.net")
local o=require("kernel.fs")local s=require("kernel.serialize")local p
do
local b,a=pcall(require,"kernel.log")if b and a and a.info then p=a else
p={info=function()end,warn=function()end,error=function()end}end end;l.MAX_BODY=4096;l.MAX_SUBJECT=120;l.MAX_BOX=200
function l.senderName(a)
if type(a)~="table"then return"?"end
if type(a.fromUser)==u and a.fromUser~=""then return a.fromUser end
return(tostring(a.from or"?")):sub(1,8)end
function l.formatTs(a)if type(a)~="number"then return"--:--:--"end
a=math.max(0,a)local b=math.floor(a/3600)
local c=math.floor((a%3600)/60)local d=math.floor(a%60)
return string.format("%02d:%02d:%02d",b,c,d)end
function l.inboxRow(a,c,b)
local e=(type(a)=="table"and a.read)and" "or"*"local f=l.senderName(a):sub(1,12)
local g=
(type(a)=="table"and
a.subject~=""and a.subject)or"(no subject)"
local h=l.formatTs(type(a)=="table"and a.ts or nil)local d=string.format(" %s %2d %s %-12s  %s",e,c,h,f,g)b=b or
60;if#d>b then d=d:sub(1,b-1).."~"end;return d end
function l.resolveRecipient(a,b)if not a or a==""then return nil end
local e,c=a:match("^([^@]+)@(.+)$")c=c or a;local d=c;if c=="*"then d="*"elseif b then d=b(c)or c end;return d,e end;local n={}n.__index=n;function l.newMailbox(a,b)
return setmetatable({store=a,path=b,_cache=nil},n)end
function n:load()
if self._cache then return self._cache end;local a={}
if self.store.exists(self.path)then
local b=self.store.read(self.path)
if b and#b>0 then
local d,c=pcall(s.decode,b,{maxBytes=256*1024})if d and type(c)=="table"then a=c end end end;self._cache=a;return a end;function n:save()local a=s.encode(self._cache or{})return
self.store.write(self.path,a)end
function n:add(a)
local b=self:load()for d,c in ipairs(b)do if c.id==a.id then return false end end
a.read=false;b[#b+1]=a;while#b>l.MAX_BOX do table.remove(b,1)end
self:save()return true end;function n:list()return self:load()end;function n:get(a)
return self:load()[a]end
function n:unread()local a=0;for c,b in ipairs(self:load())do
if not b.read then a=a+1 end end;return a end;function n:markRead(a)local b=self:get(a)if not b then return false end;b.read=true
self:save()return true end;function n:delete(a)
local b=self:load()if not b[a]then return false end;table.remove(b,a)
self:save()return true end
local function r(a)
a=(
type(a)==u and a~="")and a or"_node"a=a:gsub("[^%w%._%-]","_")local b="/var/mail/"..a
return
l.newMailbox({exists=function(c)return
o.exists(c)end,read=function(c)return o.readFile(c)end,write=function(c,e)if
not o.exists(b)then pcall(o.makeDirectory,b)end
return o.writeFile(c,e)end},
b.."/inbox.dat")end;l._mailboxFor=r
local function v()local c,b=pcall(require,"kernel.users")if not
(c and b and b.currentSession)then return nil,3,true end
local a=b.currentSession()if not a then return nil,0,false end
return a.user,a.tier or 0,a.isKernel or false end
function l.inboxBox(a)
a=(type(a)==u and a~="")and a or"_node"local b,c,d=v()
if
not(d or c>=2 or(b~=nil and b==a))then return nil,
"access denied: inbox '"..tostring(a).."' is owner-or-admin only (you are "..
tostring(b or"nobody")..")"end;return r(a)end
function l.inbox(a)local b,c=l.inboxBox(a)if not b then return nil,c end;return b:list()end;function l.available()
return m.meshAvailable and m.meshAvailable()or false end
function l.send(a)a=a or{}
return
m.meshSend({svc="mail",to=a.to,user=a.user,fromUser=a.fromUser,payload={subject=tostring(
a.subject or""):sub(1,l.MAX_SUBJECT),body=tostring(a.body or""):sub(1,l.MAX_BODY)},allowPlaintext=
a.allowPlaintext or(a.to=="*")or nil})end;function l.pending()
return m.meshPending and m.meshPending()or 0 end;function l.tick()
if m.meshTick then pcall(m.meshTick)end end;local q=false
local function t(a)local b=a.payload
local e={id=a.id,from=a.from,fromUser=a.fromUser,to=a.to,user=a.user,subject=(b and
b.subject)or"(unreadable)",body=(b and b.body)or"",ts=a.ts,sealed=a.sealed,readable=a.readable,how=a.how}local c=r(a.user)local d=c and c:add(e)if d then
p.info("mail","Mail delivered to "..

tostring(a.user or"_node").." from "..tostring(a.from):sub(1,8))end;return
d and true or false end;l._onMeshMail=t
function l.start()if q then return true end
if
not(m.meshOn and m.meshAvailable and
m.meshAvailable())then return false,"mesh transport not available (no network?)"end;m.meshOn("mail",t)q=true
p.info("mail","Mail service up (mesh kind 'mail' registered)")return true end
function l.stop()if not q then return true end
if m.meshOff then m.meshOff("mail")end;q=false;p.info("mail","Mail service stopped")return true end;function l.running()return q end;return l