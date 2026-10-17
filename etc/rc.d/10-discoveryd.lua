local h=120;local g=false;local f=nil
local function i()local a=_G._TOS and _G._TOS.net
if not a then return end;local b=nil
pcall(function()b=require("kernel.event")end)if not b then return end;g=true;pcall(a.discover)
f=b.interval(h,function()if not g then return end
pcall(a.discover)end,"discoveryd")end;local function j()g=false
if f then local b,a=pcall(require,"kernel.event")if b and a.cancelTimer then
a.cancelTimer(f)end;f=nil end end;return
{start=i,stop=j,deps={},restart=true,caps={net=true},needs="net",user="_kernel_"}