# web — a text-mode browser

Reads a page with this machine's own internet card: no JavaScript, no CSS, no images, no tables-as-layout, no forms. Headings, paragraphs, lists, links and `<pre>` blocks cover most documentation and nearly all plain articles, which is what anyone is realistically reading from inside Minecraft. HTML → readable text is the actual feature; the fetch is the easy 10%.

This is steps 1-2 of [`../browser-spec-draft.md`](../browser-spec-draft.md)'s build order: the pure renderer and the local browser, with no fetch proxy, no shared cache, and no cross-machine trust decision anywhere in it. Steps 3-5 (`webproxyd`, the cache, a cluster back end for the cache) are a separate, not-yet-built piece — see [`../README.md`](../README.md).

## Install

As admin, with the Optional Utilities disk inserted: `pkg install web`. Needs an internet card on this machine; there is no borrowing a peer's yet.

## Use

```
web example.com
web http://example.com/some/page.html
```

A bare host gets `http://` assumed. Inside:

| Key | Does |
|---|---|
| Up / Down | scroll one line |
| PgUp / PgDn | scroll one screen |
| Home / End | jump to the top / bottom |
| Left / Right | scroll sideways — for a `<pre>` block wider than the screen, which never wraps |
| a digit, then Enter | follow the numbered link `[N]` |
| `o` | open a new URL |
| `b` | back to the previous page |
| F10 or Ctrl+Q | quit |

Every link in the text gets a bracketed ordinal (`[12]`) inline and is listed again at the bottom under "References:" with its full URL, so you always know where a number actually goes before you follow it.

## What it is not

- **Not a fetch proxy.** A machine with no internet card, or whose card is disabled, simply cannot browse with this package alone — there is no asking a peer to fetch on your behalf yet. `web <url>` says so plainly (`no internet card: ...`) rather than hanging or guessing.
- **Not a cache.** Nothing fetched is kept; load the same page twice and it is fetched twice.
- **Not a way around the capability system.** This package declares `internet`; a machine with no card and no proxy cannot browse no matter how it's configured.

## Files

| Installed at | What it is |
|---|---|
| `/usr/modules/web/init.lua` | the program: fetching, drawing, keys |
| `/usr/modules/web/render.lua` | `render(html, width) -> { lines, links }` — pure, no network, no screen, no filesystem |

Asks for `internet` (the fetch) and `component` (the screen). No `fs.read`/`fs.write` — nothing in this package touches the disk. When backgrounded it freezes: a rendered page is static, so nothing should keep running while you're not looking at it.

## Tests

From `TOS-Extras/`:

- `lua web/browser/test_web.lua` — the renderer against fixture HTML: entities, wrapping, headings, lists, links (including the bug a link near the end of a long paragraph used to trigger — its "text" was the whole paragraph, not just the anchor), `<pre>`, and tolerance for malformed markup.
- `lua web/browser/test_web_ui.lua` — the real screen, driven like an operator would: opening a URL, following a link, going back, scrolling, and the no-capability / no-card / fetch-failure paths.
