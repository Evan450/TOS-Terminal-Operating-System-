local c={}local d=nil
do local b,a=pcall(require,"unicode")if
b and type(a)=="table"and a.len and a.sub then d=a end end
function c.len(a)a=tostring(a or"")if d then local e,b=pcall(d.len,a)
if e and b then return b end end;return#a end
function c.width(a)a=tostring(a or"")if d and d.wlen then local e,b=pcall(d.wlen,a)if e and b then
return b end end;return c.len(a)end
function c.sub(a,b,e)a=tostring(a or"")if d then local g,f=pcall(d.sub,a,b,e)
if g and f then return f end end;return a:sub(b,e)end
function c.fit(a,b)a=tostring(a or"")
b=math.max(0,math.floor(b or 0))if c.width(a)<=b then return a end;if b==0 then return""end
if d and d.wtrunc then local i,h=pcall(d.wtrunc,a,
b+1)if i and h then return h end end;local g,e,f={},0,0;for h=1,c.len(a)do local i=c.sub(a,h,h)local j=c.width(i)
if e+j>b then break end;f=f+1;g[f]=i;e=e+j end;return
table.concat(g)end;function c.padR(a,b)a=c.fit(a,b)
return a..string.rep(" ",b-c.width(a))end
function c.padL(a,b)a=c.fit(a,b)return string.rep(" ",b-
c.width(a))..a end;function c.centerOffset(a,b)return
math.max(0,math.floor((b-c.width(a))/2))end;return c