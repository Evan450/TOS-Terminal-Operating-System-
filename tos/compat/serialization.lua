local c=require("kernel.serialize")local d={}
function d.serialize(a,b)if b then
local e=c.encode(a)if e:sub(1,7)=="return "then e=e:sub(8)end;return e else
return c.compact(a)end end
function d.unserialize(a)
if type(a)~="string"then return nil,"unserialize: expected string"end;local e,b,f=pcall(c.decode,a)
if not e then return nil,tostring(b)end;return b,f end;return d