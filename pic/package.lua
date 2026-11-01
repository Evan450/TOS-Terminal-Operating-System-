return {
hashes = {
["/usr/modules/pic/convert.lua"] = "a255c4e7acb0a2983302b8e7f16895517ffd4e5799235302d3c16b1ccf436187",
["/usr/modules/pic/init.lua"] = "7d562a86d71bc07cbea0310c0141be35d186bcafcdcf5992f75122b8bc89fd63",
["/usr/modules/pic/ocif.lua"] = "f71a4d41924f1df595b19bdb79eb02ccea6cf2e3a6a72b3086775755f0b3d0f7",
["/usr/modules/pic/png.lua"] = "1e0c44a5ad48e52b7c6abba42465c84dd4db4085845440e107a8f3360375430c",
},
name = "pic",
version = "1.0.1",
kind = "command",
category = "productivity",
description = "Picture viewer: MineOS .pic and PNG on any GPU, from disk or a URL, and PNG to .pic.",
author = "Strata Systems",
files = {
"/usr/modules/pic/init.lua",
"/usr/modules/pic/ocif.lua",
"/usr/modules/pic/png.lua",
"/usr/modules/pic/convert.lua",
},
fullscreen = true,
background = "freeze",
commands = { pic = "/usr/modules/pic/init.lua" },
handles = {
{ ext = { "pic" }, as = "native" },
{ ext = { "png" }, as = "native" },
},
capabilities = { "fs.read", "fs.write", "component", "internet" },
requires = {},
}
