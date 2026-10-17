local g={}local j=16*1024;local k=512;local h={}
local function i(a)if a~=nil then return a end
local b=_G._TOS and _G._TOS.kernel;if b and b.getDisplayIdx then local d,c=pcall(b.getDisplayIdx)
if d and c then return c end end;return 0 end
local function l(a)local b,d={},false;local c=0
local function e(f)if#b>=k then d=true;return false end
f=tostring(f or""):gsub("[\r\n]","")
if c+#f>j then local m=j-c;if m>0 then b[#b+1]=f:sub(1,m)end;d=true;return false end;b[#b+1]=f;c=c+#f+1;return true end
if type(a)=="string"then local f=1
while true do local m=a:find("\n",f,true)if not m then
e(a:sub(f))break end;if not e(a:sub(f,m-1))then break end;f=m+1 end elseif type(a)=="table"then for m,f in ipairs(a)do if not e(f)then break end end else return nil,
false end;return b,d end
function g.set(a,b)local c,e=l(a)
if not c then return false,"clipboard takes a string or a list of lines"end;if#c==0 then c={""}end;local d=0;for m,f in ipairs(c)do d=d+#f+1 end
h[i(b)]={lines=c,bytes=d,truncated=e}return true,e end;function g.get(a)local b=h[i(a)]if not b then return nil end;local c={}
for d,e in ipairs(b.lines)do c[d]=e end;return c end
function g.text(a)
local b=h[i(a)]if not b then return nil end;return table.concat(b.lines,"\n")end
function g.line(a)local b=h[i(a)]if not b then return nil end
if#b.lines==1 then return b.lines[1]end;return table.concat(b.lines," ")end
function g.isEmpty(a)local b=h[i(a)]return b==nil or
(#b.lines==1 and b.lines[1]=="")end;function g.count(a)local b=h[i(a)]if not b or g.isEmpty(a)then return 0 end;return
#b.lines end
function g.describe(a)local b=h[i(a)]if not
b or g.isEmpty(a)then return"empty"end;local d=#b.lines
local c=
(d==1)and(#b.lines[1].." chars")or(d.." lines \194\183 "..
b.bytes.." bytes")
if b.truncated then c=c.." (truncated at the clipboard cap)"end;return c end;function g.clear(a)h[i(a)]=nil;return true end
function g.clearAll()h={}return true end;g.MAX_BYTES=j;g.MAX_LINES=k;return g