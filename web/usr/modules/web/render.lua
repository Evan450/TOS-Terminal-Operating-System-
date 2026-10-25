local n={}
local s={amp="&",lt="<",gt=">",quot="\"",apos="'",nbsp=" ",mdash="-",ndash="-",minus="-",hellip="...",copy="(c)",reg="(R)",trade="(TM)",lsquo="'",rsquo="'",ldquo="\"",rdquo="\"",sbquo="'",bdquo="\"",laquo="<<",raquo=">>",middot="*",bull="*",deg=" deg",plusmn="+/-",times="x",divide="/",frac12="1/2",frac14="1/4",frac34="3/4"}
function n.decodeEntities(a)
a=a:gsub("&#x(%x+);",function(b)local c=tonumber(b,16)if c and c>=32 and c<127 then return
string.char(c)end
return c and"?"or"&#x"..b..";"end)
a=a:gsub("&#(%d+);",function(b)local c=tonumber(b)if c and c>=32 and c<127 then
return string.char(c)end;return c and"?"or"&#"..b..";"end)
a=a:gsub("&(%a+);",function(b)local c=s[b:lower()]if c then return c end;return"?"end)return a end
local function t(a)local b={}local c,d=1,#a
while c<=d do local e=a:find("<",c)if not e then
b[#b+1]={type="text",text=a:sub(c)}break end;if e>c then
b[#b+1]={type="text",text=a:sub(c,e-1)}end
if a:sub(e,e+3)=="<!--"then
local f=a:find("%-%->",e+4)c=f and(f+3)or(d+1)elseif a:sub(e,e+1)=="<!"then
local f=a:find(">",e+1)c=f and(f+1)or(d+1)else local f=a:find(">",e+1)
if not f then
b[#b+1]={type="text",text=a:sub(e)}c=d+1 else local g=a:sub(e+1,f-1)local h=g:sub(1,1)=="/"
if h then g=g:sub(2)end;local i=g:sub(-1)=="/"if i then g=g:sub(1,-2)end
local j=g:match("^%s*([%a][%w%-]*)")if j then
b[#b+1]={type="tag",name=j:lower(),closing=h,selfclose=i,raw=g}end;c=f+1 end end end;return b end
local function p(b,a)local d=b:lower()local c=d:find(a,1,true)
while c do local e=b:sub(c-1,c-1)local f=d:sub(c+#a,
c+#a)
if(c==1 or e:match("[%s\"']"))and
f~="-"then local g=b:sub(c+#a)
local h=g:match("^%s*=%s*\"([^\"]*)\"")or
g:match("^%s*=%s*'([^']*)'")or g:match("^%s*=%s*([^%s>]+)")if h then return h end end;c=d:find(a,c+1,true)end;return nil end;n._attrOf=p
local u={script=true,style=true,head=true,title=true,table=true,form=true,select=true,noscript=true}
local q={p=true,div=true,section=true,article=true,header=true,footer=true,nav=true,blockquote=true,h1=true,h2=true,h3=true,h4=true,h5=true,h6=true}
local v={br=true,hr=true,img=true,input=true,meta=true,link=true,area=true,base=true,col=true,embed=true,source=true,track=true,wbr=true}
local function w()
return
{blocks={},links={},buf={},kind="p",skip=nil,skipDepth=0,inPre=false,preLines=nil,preLine=nil,linkStack={},curLinkUrl=nil,listStack={},liDepth=0}end
local function o(a)local b=table.concat(a.buf)b=b:gsub("%s+"," ")
b=b:gsub(" ?\1 ?","\n")b=b:gsub("^%s+",""):gsub("%s+$","")
if b~=""then
local c=nil
if a.kind=="li"then local d=a.listStack[#a.listStack]if
d and d.kind=="ol"then d.n=d.n+1;c=d.n..". "else c="- "end
c=string.rep("  ",math.max(0,
#a.listStack-1))..c end;a.blocks[#a.blocks+1]={kind=a.kind,text=b,prefix=c}end;a.buf={}end
local function r(a)if a.preLine then
a.preLines[#a.preLines+1]=table.concat(a.preLine)a.preLine=nil end;if a.preLines and
#a.preLines>0 then
a.blocks[#a.blocks+1]={kind="pre",lines=a.preLines}end;a.preLines=nil;a.inPre=false end
local function x(a,b)local c=b.name
if a.skip then if c==a.skip and not b.selfclose then
a.skipDepth=a.skipDepth+1 end;return end
if u[c]and not b.selfclose then a.skip=c;a.skipDepth=1;return end
if v[c]or b.selfclose then
if c=="br"then if a.inPre then if a.preLine then
a.preLines[#a.preLines+1]=table.concat(a.preLine)end;a.preLine={}else
a.buf[#a.buf+1]="\1"end end;return end
if c=="pre"then o(a)a.inPre=true;a.preLines,a.preLine={},{}return end;if c=="ul"or c=="ol"then o(a)
a.listStack[#a.listStack+1]={kind=c,n=0}return end
if c=="li"then o(a)a.kind="li"return end
if c=="a"then local d=p(b.raw,"href")
if
d and d~=""and not d:match("^#")and not d:match("^javascript:")then
a.curLinkUrl=d;a.linkBufStart=#a.buf+1 end;return end
if q[c]then o(a)a.kind=c:match("^h%d$")and c or"p"return end end
local function y(a,b)local c=b.name
if a.skip then if c==a.skip then a.skipDepth=a.skipDepth-1;if a.skipDepth<=0 then
a.skip=nil end end;return end;if c=="pre"then r(a)return end
if c=="a"then
if a.curLinkUrl then
local e=a.linkBufStart or(#a.buf+1)
local d=table.concat(a.buf,"",e):gsub("^%s+",""):gsub("%s+$","")
a.links[#a.links+1]={url=a.curLinkUrl,text=d~=""and d or a.curLinkUrl}
a.buf[#a.buf+1]=string.format(" [%d] ",#a.links)a.curLinkUrl=nil;a.linkBufStart=nil end;return end;if c=="li"then o(a)a.kind="p"return end;if c=="ul"or c=="ol"then
if
#a.listStack>0 then a.listStack[#a.listStack]=nil end;return end
if q[c]then o(a)a.kind="p"end end
local function z(a,b)if a.skip then return end;b=n.decodeEntities(b)
if a.inPre then for c=1,#b do local d=b:sub(c,c)
if
d=="\n"then
a.preLines[#a.preLines+1]=table.concat(a.preLine)a.preLine={}else a.preLine[#a.preLine+1]=d end end else a.buf[
#a.buf+1]=b end end
function n.toBlocks(a)local b=w()for d,c in ipairs(t(a))do
if c.type=="text"then z(b,c.text)elseif c.closing then y(b,c)else x(b,c)end end
if b.inPre then r(b)else o(b)end;return b.blocks,b.links end
function n.wrapText(b,a)a=math.max(1,a)local c={}
for d in(b.."\n"):gmatch("(.-)\n")do
if d==""then
c[#c+1]=""else local e=""
for f in d:gmatch("%S+")do
local g=(e=="")and f or(e.." "..f)
if#g<=a then e=g else if e~=""then c[#c+1]=e end;e=f;while#e>a do c[#c+1]=e:sub(1,a)
e=e:sub(a+1)end end end;c[#c+1]=e end end;return c end
function n.render(a,b)a=type(a)=="string"and a or""b=math.max(10,math.floor(
tonumber(b)or 80))local e=b-1
local f,d=n.toBlocks(a)local c={}local g=nil
for i,h in ipairs(f)do
local j=h.kind and h.kind:match("^h%d$")~=nil;if j and#c>0 then c[#c+1]=""end
if h.kind=="pre"then
if#c>0 then c[#c+1]=""end;for i,k in ipairs(h.lines)do c[#c+1]=k end;c[#c+1]=""else
local k=h.prefix or""local l=n.wrapText(h.text,math.max(1,e-#k))for A,m in ipairs(l)do
c[#
c+1]=(A==1)and(k..m)or(string.rep(" ",#k)..m)end;if j then c[#c+1]=""end end;g=h.kind end;while#c>0 and c[#c]==""do c[#c]=nil end
if#d>0 then c[#c+1]=""
c[#c+1]="References:"
for j,h in ipairs(d)do for k,i in
ipairs(n.wrapText(string.format("[%d] %s -- %s",j,h.text,h.url),e))do c[#c+1]=i end end end;return{lines=c,links=d}end;return n