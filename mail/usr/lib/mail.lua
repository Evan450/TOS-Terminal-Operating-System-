local w="string"local m={}m._VERSION="1.0.1"local n=require("kernel.net")
local q=require("kernel.fs")local u=require("kernel.serialize")local r
do
local b,a=pcall(require,"kernel.log")if b and a and a.info then r=a else
r={info=function()end,warn=function()end,error=function()end}end end;m.MAX_BODY=4096;m.MAX_SUBJECT=120;m.MAX_BOX=200
function m.senderName(a)
if type(a)~="table"then return"?"end
if type(a.fromUser)==w and a.fromUser~=""then return a.fromUser end
return(tostring(a.from or"?")):sub(1,8)end
function m.formatTs(a)if type(a)~="number"then return"--:--:--"end
a=math.max(0,a)local b=math.floor(a/3600)
local c=math.floor((a%3600)/60)local d=math.floor(a%60)
return string.format("%02d:%02d:%02d",b,c,d)end
function m.inboxRow(a,c,b)
local e=(type(a)=="table"and a.read)and" "or"*"local f=m.senderName(a):sub(1,12)
local g=
(type(a)=="table"and
a.subject~=""and a.subject)or"(no subject)"
local h=m.formatTs(type(a)=="table"and a.ts or nil)local d=string.format(" %s %2d %s %-12s  %s",e,c,h,f,g)b=b or
60;if#d>b then d=d:sub(1,b-1).."~"end;return d end
function m.resolveRecipient(a,b)if not a or a==""then return nil end
local e,c=a:match("^([^@]+)@(.+)$")c=c or a;local d=c;if c=="*"then d="*"elseif b then d=b(c)or c end;return d,e end;local o={}o.__index=o;function m.newMailbox(a,b)
return setmetatable({store=a,path=b,_cache=nil},o)end
function o:load()
if self._cache then return self._cache end;local a={}
if self.store.exists(self.path)then
local b=self.store.read(self.path)
if b and#b>0 then
local d,c=pcall(u.decode,b,{maxBytes=256*1024})if d and type(c)=="table"then a=c end end end;self._cache=a;return a end;function o:save()local a=u.encode(self._cache or{})return
self.store.write(self.path,a)end
function o:add(a)
local b=self:load()for d,c in ipairs(b)do if c.id==a.id then return false end end
a.read=false;b[#b+1]=a;while#b>m.MAX_BOX do table.remove(b,1)end
self:save()return true end;function o:list()return self:load()end;function o:get(a)
return self:load()[a]end
function o:unread()local a=0;for c,b in ipairs(self:load())do
if not b.read then a=a+1 end end;return a end;function o:markRead(a)local b=self:get(a)if not b then return false end;b.read=true
self:save()return true end;function o:delete(a)
local b=self:load()if not b[a]then return false end;table.remove(b,a)
self:save()return true end
local function t(a)
a=(
type(a)==w and a~="")and a or"_node"a=a:gsub("[^%w%._%-]","_")local b="/var/mail/"..a
return
m.newMailbox({exists=function(c)return
q.exists(c)end,read=function(c)return q.readFile(c)end,write=function(c,e)if
not q.exists(b)then pcall(q.makeDirectory,b)end
return q.writeFile(c,e)end},
b.."/inbox.dat")end;m._mailboxFor=t
local function x()local c,b=pcall(require,"kernel.users")if not
(c and b and b.currentSession)then return nil,3,true end
local a=b.currentSession()if not a then return nil,0,false end
return a.user,a.tier or 0,a.isKernel or false end;local p={}p.__index=p
function p:rows()local a={}for b,c in ipairs(self.own:list())do
a[#a+1]={box=self.own,i=b,m=c}end;for c,b in
ipairs(self.machine:list())do
if self.all or b.to=="*"then a[#a+1]={box=self.machine,i=c,m=b}end end;return a end;function p:list()local a={}for c,b in ipairs(self:rows())do a[#a+1]=b.m end
return a end;function p:get(a)
local b=self:rows()[a]return b and b.m or nil end
function p:unread()local a=0;for c,b in
ipairs(self:rows())do if not b.m.read then a=a+1 end end;return a end;function p:markRead(a)local b=self:rows()[a]return
b~=nil and b.box:markRead(b.i)end
function p:delete(a)
local b=self:rows()[a]if
not b or(b.box==self.machine and not self.all)then return false end;return b.box:delete(b.i)end
function m.inboxBox(a)
a=(type(a)==w and a~="")and a or"_node"local b,d,e=x()
if
not(e or d>=2 or(b~=nil and b==a))then return nil,
"access denied: inbox '"..tostring(a).."' is owner-or-admin only (you are "..
tostring(b or"nobody")..")"end;local c=t(a)if a=="_node"or b~=a then return c end
local f=setmetatable({own=c,machine=t("_node"),all=e or d>=2},p)local g=#f:rows()>#c:list()return g and f or c end
function m.inbox(a)local b,c=m.inboxBox(a)if not b then return nil,c end;return b:list()end;function m.available()
return n.meshAvailable and n.meshAvailable()or false end
function m.send(a)a=a or{}
return
n.meshSend({svc="mail",to=a.to,user=a.user,fromUser=a.fromUser,payload={subject=tostring(
a.subject or""):sub(1,m.MAX_SUBJECT),body=tostring(a.body or""):sub(1,m.MAX_BODY)},allowPlaintext=
a.allowPlaintext or(a.to=="*")or nil})end;function m.pending()
return n.meshPending and n.meshPending()or 0 end;function m.tick()
if n.meshTick then pcall(n.meshTick)end end;local s=false
local function v(a)local b=a.payload
local e={id=a.id,from=a.from,fromUser=a.fromUser,to=a.to,user=a.user,subject=(b and
b.subject)or"(unreadable)",body=(b and b.body)or"",ts=a.ts,sealed=a.sealed,readable=a.readable,how=a.how}local c=t(a.user)local d=c and c:add(e)if d then
r.info("mail","Mail delivered to "..

tostring(a.user or"_node").." from "..tostring(a.from):sub(1,8))end;return
d and true or false end;m._onMeshMail=v
function m.start()if s then return true end
if
not(n.meshOn and n.meshAvailable and
n.meshAvailable())then return false,"mesh transport not available (no network?)"end;n.meshOn("mail",v)s=true
r.info("mail","Mail service up (mesh kind 'mail' registered)")return true end
function m.stop()if not s then return true end
if n.meshOff then n.meshOff("mail")end;s=false;r.info("mail","Mail service stopped")return true end;function m.running()return s end;return m