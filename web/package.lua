return {
hashes = {
["/usr/modules/web/init.lua"] = "7bdaf84ab809d93e3b77f8b68fc36e8261e8df75f45e8fff4b2fd5cacd27d3de",
["/usr/modules/web/render.lua"] = "d7698033a0187d2a0611c3d6f304ac7d496d3789afae8b7fc6d487bc07d3c779",
},
name = "web",
version = "1.0.0",
kind = "command",
category = "network",
description = "Text-mode browser: headings, paragraphs, lists, links and <pre>, read with this machine's own internet card.",
author = "Strata Systems",
files = {
"/usr/modules/web/init.lua",
"/usr/modules/web/render.lua",
},
fullscreen = true,
background = "freeze",
commands = { web = "/usr/modules/web/init.lua" },
capabilities = { "internet", "component" },
requires = {},
}
