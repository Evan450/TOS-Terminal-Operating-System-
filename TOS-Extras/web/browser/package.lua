-- Optional Utilities — web: a text-mode browser for TOS.
--
-- browser-spec-draft.md's build order, steps 1-2 only: the pure HTML
-- renderer (render.lua, §6) and the local browser (init.lua) -- one
-- machine, its own internet card, no fetch proxy. The spec's later
-- steps (webproxyd, the cache, a cluster back end for the cache, §9
-- steps 3-5) are NOT in this package: they depend on open trust
-- decisions (§10 -- proxy discovery, cache-read defaults, the
-- canonical URL key, whether the proxy strips anything) that are not
-- this package's to make alone, and the spec itself calls steps 1-2
-- out as the half with "no security surface at all" and "useful on
-- its own" -- which is exactly why they shipped first.
--
-- render(html, width) is pure and unit-tested off-box against fixture
-- HTML (test_web.lua, §6.3 — "touches no network, no screen, no
-- filesystem"). init.lua is fetching, drawing and keys; its own
-- seam with the engine is driven the same way calc/write's UI tests
-- drive theirs (test_web_ui.lua): a fake GPU, a scripted keyboard, a
-- fake `internet` capability.
--
-- `internet` is the only capability with any real weight here, and it
-- is exactly as much as the spec's own non-goal list promises: this
-- package can read what ITS OWN card reaches, never anyone else's
-- (that borrowing is the proxy, not built yet), and it declares no
-- `fs.write` at all -- there is no cache in this package to write to.
return {
  name        = "web",
  version     = "1.0.1",
  kind        = "command",
  category    = "network",
  description = "Text-mode browser: headings, paragraphs, lists, links and <pre>, read with this machine's own internet card.",
  author      = "Strata Systems",
  files       = {
    "/usr/modules/web/init.lua",
    "/usr/modules/web/render.lua",
  },
  -- Full-screen program: the shell hands it the seat as its own
  -- process, so Ctrl+B can push it to the background and Ctrl+T
  -- brings it back instead of it owning the terminal until it exits.
  fullscreen  = true,
  -- Background policy (freeze): a rendered page is static once it's on
  -- screen -- no timer, no in-flight recalculation, nothing that should
  -- keep running while the operator isn't looking at it.
  background  = "freeze",

  commands     = { web = "/usr/modules/web/init.lua" },
  capabilities = { "internet", "component" },
  requires    = {},
}
