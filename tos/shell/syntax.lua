local e="string"local d={}
local f={["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,["end"]=true,["false"]=true,["for"]=true,["function"]=true,["goto"]=true,["if"]=true,["in"]=true,["local"]=true,["nil"]=true,["not"]=true,["or"]=true,["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,["until"]=true,["while"]=true}
function d.tokenize(a)local c={}local h=2048;local i=nil
if#a>h then i=a:sub(h+1)a=a:sub(1,h)end;local b=1;local g=#a
while b<=g do local j=a:sub(b,b)
if
j=="-"and a:sub(b+1,b+1)=="-"then c[#c+1]={type="comment",text=a:sub(b)}break elseif j=='"'then local k=b+1
while k<=g do
local l=a:sub(k,k)if l=="\\"then k=k+2 elseif l=='"'then k=k+1;break else k=k+1 end end;c[#c+1]={type=e,text=a:sub(b,k-1)}b=k;goto next elseif j=="'"then local k=b+1
while k<=g do
local l=a:sub(k,k)if l=="\\"then k=k+2 elseif l=="'"then k=k+1;break else k=k+1 end end;c[#c+1]={type=e,text=a:sub(b,k-1)}b=k;goto next elseif j=="["and
(
a:sub(b+1,b+1)=="["or a:sub(b+1,b+1)=="=")then local k=a:match("^%[(=*)%[",b)
if k then
local m="]"..k.."]"local l=a:find(m,b+2+#k,true)if l then l=l+#m else l=g+1 end;c[#c+1]={type=e,text=a:sub(b,
l-1)}b=l;goto next end;c[#c+1]={type="op",text=j}b=b+1;goto next elseif j:match("%d")or
(j=="."and b+1 <=g and a:sub(
b+1,b+1):match("%d"))then local k=b
if
a:sub(k,k+1):lower()=="0x"then k=k+2
while k<=g and a:sub(k,k):match("[%da-fA-F]")do k=k+1 end else
while k<=g and a:sub(k,k):match("[%d.]")do k=k+1 end
if k<=g and a:sub(k,k):match("[eE]")then k=k+1;if k<=g and
a:sub(k,k):match("[%+%-]")then k=k+1 end;while k<=g and
a:sub(k,k):match("%d")do k=k+1 end end end;c[#c+1]={type="number",text=a:sub(b,k-1)}b=k;goto next elseif
j:match("[%a_]")then local k=b+1
while k<=g and a:sub(k,k):match("[%w_]")do k=k+1 end;local l=a:sub(b,k-1)local m=f[l]and"keyword"or"ident"
c[#c+1]={type=m,text=l}b=k;goto next elseif j:match("%s")then local k=b+1;while
k<=g and a:sub(k,k):match("%s")do k=k+1 end
c[#c+1]={type="space",text=a:sub(b,k-1)}b=k;goto next elseif j:byte()>=0x80 then local k=b+1;while k<=g do local l=a:byte(k)
if l<0x80 or l>0xBF then break end;k=k+1 end
c[#c+1]={type="ident",text=a:sub(b,k-1)}b=k;goto next else c[#c+1]={type="op",text=j}b=b+1;goto next end;b=b+1;::next::end;if i then c[#c+1]={type="ident",text=i}end;return c end
function d.tokenColor(b,a)
if b=="keyword"then return a.syn_keyword or a.title end;if b==e then return a.syn_string or a.highlight end;if b==
"comment"then return a.syn_comment or a.dim end;if
b=="number"then return a.syn_number or a.warning end;if
b=="ident"then return a.fg end;if b=="op"then return a.dim or a.fg end
return a.fg end;return d