# web — text-mode browser and the TOS-to-TOS fetch proxy

`browser-spec-draft.md` is the design for a text-mode web browser
package plus the fetch proxy that lets a TOS box *without* an internet
card borrow one that has it, and the page cache that turns a network of
TOS machines into a small shared archive.

**Steps 1-2 of the spec's build order are built: [`browser/`](browser/README.md),
the `web` package** — the pure HTML-to-text renderer and a local
browser, one machine, its own internet card, no proxy. The spec itself
calls these two out as the half with no security surface at all,
"useful on its own", and worth building first for exactly that reason.

**Steps 3-5 are still design only.** `webproxyd` (the fetch side), the
page cache, and a cluster back end for that cache all depend on §10's
open questions — does the browser auto-discover a proxy or is one
configured, should an "open to anyone" cache read setting need a second
confirmation, is per-call cap raising enough for `kernel.internet`, what
the canonical URL key is, and whether the proxy strips anything from
what it serves. Those are trust decisions for the operator, not code,
and nothing past step 2 should be built before they're answered.

The browser is its own package (`internet` + `component` capabilities,
`fullscreen = true`), never part of the base image — see the deferred
"text-mode WEB BROWSER" idea of 2026-08-04 in `ROADMAP.md`.
