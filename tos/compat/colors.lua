
local b={white=0,orange=1,magenta=2,lightblue=3,yellow=4,lime=5,pink=6,gray=7,silver=8,cyan=9,purple=10,blue=11,brown=12,green=13,red=14,black=15}
do local a={}for c in pairs(b)do a[#a+1]=c end;for d,c in ipairs(a)do local e=b[c]
if b[e]==nil then b[e]=c end end end;return b