return {
hashes = {
["/usr/modules/web/init.lua"] = "84120734b0cbcd6804a9ec942c3f9d3c009018b6895756d71a7b657cf7974d18",
["/usr/modules/web/render.lua"] = "d7698033a0187d2a0611c3d6f304ac7d496d3789afae8b7fc6d487bc07d3c779",
},
name = "web",
version = "1.0.1",
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
