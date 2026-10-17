local d={}
local function f(a)return not a:find("[\128-\255]")end;d.isAscii=f
local function e(a,b)local c=a:byte(b)if not c then return 0,false end
if c<0x80 then return 1,true end
local g=(c>=0xC2 and c<=0xDF)and 2 or
(c>=0xE0 and c<=0xEF)and 3 or
(c>=0xF0 and c<=0xF4)and 4 or 1;if g==1 then return 1,false end
for h=1,g-1 do local i=a:byte(b+h)if
not i or i<0x80 or i>0xBF then return 1,false end end;return g,true end;d.unitAt=e
function d.units(a)local c,g={},{}local b,h=1,#a
while b<=h do local i,j=e(a,b)c[#c+1]=b;g[#g+1]=j and a:sub(b,
b+i-1)or"?"b=b+i end;return c,g end;function d.cells(a)if f(a)then return#a end;local c,b,g=0,1,#a
while b<=g do b=b+ (e(a,b))c=c+1 end;return c end
function d.cellOf(b,a)
if a<=1 then return 1 end;if f(b)then return a end;local c,g,h=1,1,#b
while g<a and g<=h do g=g+ (e(b,g))c=c+1 end;if a>h+1 then c=c+ (a- (h+1))end;return c end
function d.colOf(a,b)if b<=1 then return 1 end
if f(a)then return math.min(b,#a+1)end;local g,i,h=1,#a,1;while h<b and g<=i do g=g+ (e(a,g))h=h+1 end
return g end;function d.nextCol(a,b)if b>#a then return#a+1 end;local c=e(a,b)
return b+math.max(1,c)end
function d.prevCol(a,b)if b<=1 then return 1 end;if f(a)then return
b-1 end;local c,g,h=1,1,#a
while c<b and c<=h do g=c;c=c+ (e(a,c))end;return g end
function d.slice(a,b,c)if b<1 then b=1 end;if c<b then return""end;if f(a)then return a:sub(b,c)end;local i,g,j,h={},1,
#a,1
while g<=j and h<=c do local k,l=e(a,g)if h>=b then i[#i+1]=
l and a:sub(g,g+k-1)or"?"end;g=g+k;h=h+1 end;return table.concat(i)end;return d