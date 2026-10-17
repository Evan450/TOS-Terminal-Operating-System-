local d="closed"local c={}
function c.new(a,b)
local e={mode=a or"r",stream=b,readBuf="",closed=false}
function e:read(f)if self.closed then return nil,d end;f=f or"*l"
if f=="*a"or f=="a"then
local g={self.readBuf}self.readBuf=""while true do local h=self.stream:read(4096)
if not h then break end;g[#g+1]=h end
return table.concat(g)elseif f=="*l"or f=="l"then
while true do
local g=self.readBuf:find("\n",1,true)if g then local i=self.readBuf:sub(1,g-1)
self.readBuf=self.readBuf:sub(g+1)return i end
local h=self.stream:read(4096)if not h then
if#self.readBuf>0 then local i=self.readBuf;self.readBuf=""return i end;return nil end
self.readBuf=self.readBuf..h end elseif f=="*n"or f=="n"then
while true do
local g=self.readBuf:match("^%s*(.*)")
if g and#g>0 then local j=g:sub(1,1)
if not j:match("[%d%+%-%.eE]")then return nil end
local i=self.readBuf:match("^%s*([%+%-]?%d[%d%.eE%+%-]*)")
if i then local k=tonumber(i)if k then
local o,n=self.readBuf:find("^%s*[%+%-]?%d[%d%.eE%+%-]*")self.readBuf=self.readBuf:sub((n or 0)+1)
return k end
local m,l=self.readBuf:find("^%s*[%+%-]?%d[%d%.eE%+%-]*")self.readBuf=self.readBuf:sub((l or 0)+1)
return nil end;if#g>64 then self.readBuf=g;return nil end end;local h=self.stream:read(256)if not h then return nil end;self.readBuf=
self.readBuf..h end elseif type(f)=="number"then local g=f
while#self.readBuf<g do local i=self.stream:read(g-
#self.readBuf)if not i then break end;self.readBuf=
self.readBuf..i end;if#self.readBuf==0 then return nil end
local h=self.readBuf:sub(1,g)self.readBuf=self.readBuf:sub(g+1)return h end end
function e:write(...)if self.closed then return nil,d end
for f=1,select("#",...)do
local g=tostring(select(f,...))self.stream:write(g)end;return self end
function e:lines()return function()return self:read("*l")end end
function e:close()if self.closed then return nil,d end;self.closed=true;if self.stream.close then
self.stream:close()end;return true end
function e:seek(f,g)if self.stream.seek then self.readBuf=""
return self.stream:seek(f,g)end;return nil,"not seekable"end;function e:flush()return self end;return e end;return c