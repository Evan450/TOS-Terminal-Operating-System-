local b={}
function b.trim(a)return(a:match("^%s*(.-)%s*$"))end
function b.wrap(c,a)a=a or 80;local d={}
for e in c:gmatch("[^\n]*")do
if e==""then d[#d+1]=""else local f=""for g in
e:gmatch("%S+")do
if f==""then f=g elseif#f+1+#g<=a then f=f.." "..g else d[#d+1]=f;f=g end end;d[#d+1]=f end end;return d end;function b.padRight(a,c)local d=#a;if d>=c then return a end
return a..string.rep(" ",c-d)end
function b.padLeft(a,c)local d=#a
if d>=c then return a end;return string.rep(" ",c-d)..a end
function b.detab(c,a)a=a or 8;local e=0;local d={}
for f=1,#c do local g=c:sub(f,f)
if g=="\t"then local h=a- (e%a)
d[#d+1]=string.rep(" ",h)e=e+h elseif g=="\n"then d[#d+1]=g;e=0 else d[#d+1]=g;e=e+1 end end;return table.concat(d)end
function b.tokenize(a)local d={}local c=1;local e=#a
while c<=e do local g=a:match("^%s+",c)if g then c=c+#g end;if c>e then
break end;local f=a:sub(c,c)
if f=='"'or f=="'"then local i=f;c=c+1;local h={}while c<=e do
local j=a:sub(c,c)
if j=="\\"and c<e then c=c+1;h[#h+1]=a:sub(c,c)elseif j==i then break else h[#h+1]=j end;c=c+1 end
d[#d+1]=table.concat(h)c=c+1 else local h=a:match("^[^%s'\"]+",c)
if h then d[#d+1]=h;c=c+#h else c=c+1 end end end;return d end;return b