# Browser + Fetch Proxy Spec (Draft v0.1)

> **Scope:** a text-mode web browser package, the TOS-to-TOS fetch proxy that lets a machine without an internet card borrow one that has it, and the shared page cache that falls out of having both. Extends the cluster protocol spec's trust topology (§1) and reuses the storage tier's namespace and TTL model where it fits. Nothing here is implemented; every section is design.
>
> **Starting point:** `TOS-Dev/TODO.txt`, the deferred `[*]` OPERATOR IDEA of 2026-08-04. Its three conclusions are taken as settled and not re-argued: the browser is a **package** declaring `internet` + `fullscreen` and never ships in the base image; **HTML→text layout is the work**, not the fetch; and `kernel.internet`'s size caps want raising **per-call, never globally**, because a page is bigger than 64 K.

---

## 0. Three features, one mechanism

The operator idea is really three things that share a single piece of plumbing:

1. **A browser** on a machine that has an internet card. Local fetch, local render.
2. **A browser on a machine that has no card**, borrowing a peer's. This is the interesting one.
3. **Reading pages nobody can currently fetch**, because some machine on the network fetched them earlier and kept them.

(2) and (3) are the same service seen from different sides: a peer that will fetch on your behalf, and a peer that will serve what it already fetched. So there is one new daemon, `webproxyd`, and the browser is a client that may or may not have a local card.

```
  browser (no card) ──WEB_FETCH──▶ webproxyd (has card) ──▶ internet
        │                              │
        │                              └──▶ page cache  (what it fetched)
        └──WEB_CACHE_GET────────────────────▶ same cache, no card needed
```

---

## 1. The problem this design exists to solve

**A fetch proxy is a confused deputy.** Box A asks box B to fetch a URL. B's internet card makes the request, so it happens with *B's* network identity, *B's* allowlist, *B's* rate limits and *B's* memory. Every reason B was trusted with an internet card is now being spent on a decision A made.

This codebase has already reached the right answer twice, and the shape should be recognisable:

| Subsystem | The asker proposes | The holder decides |
|---|---|---|
| `ai-operator` | a verb + scalars | `ai-exec`'s whitelist (§4) |
| `netfs` | a share + a path | the host's export ACL and `_confine` |
| **`webproxyd`** | **a URL** | **the proxy's own allowlist** |

And the TODO already states the principle in the OPPM master-list entry, in a different context: adopting a list of hosts you did not write down "is exactly what the allowlist exists to prevent — it needs an operator-facing *add all of these?* step, not a silent federation."

So the rule for this design: **a fetch request is a request, never an instruction.** `webproxyd` fetches what its own operator has allowed, and A's URL is matched against that. If it is not allowed, A is refused — not asked to confirm, not allowed to widen it.

---

## 2. Trust: fetching and reading are different acts

The operator's instinct was "Trusted computers only". That is right for *fetching* and probably wrong for *reading the cache*, and the storage tier already has the split to copy.

Protocol spec §2.2 puts Public storage **reads** on an unauthenticated port and **writes** on a trust-gated one, on the grounds that reads are cheap and writes are what the namespace rules protect. The same reasoning applies here, and for a sharper reason: a fetch **spends someone else's resource and network identity**, whereas a cache read hands over bytes that machine already chose to store.

| Operation | Trust required | Why |
|---|---|---|
| `WEB_FETCH` — "go and get this" | **TRUSTED** + `verifyPeer` | Spends B's card, B's memory, B's reputation with the far host |
| `WEB_CACHE_GET` — "give me what you have" | operator's choice, default **KNOWN** | Serves bytes already fetched and already stored; no egress, no new authority |
| `WEB_CACHE_LIST` | same as `WEB_CACHE_GET` | |

BLOCKED peers get nothing at either tier — that is the trust manager's existing floor and this design adds no exception to it.

**Making the cache readable at UNKNOWN is the "open intranet" configuration** the operator described. It should be a single setting with an honest name (`cache_read_trust = "unknown"`), because an operator choosing it is choosing to serve their downloads to anyone in radio range, and that deserves to be a decision rather than a default.

---

## 3. `webproxyd` — the fetch side

### 3.1 The allowlist is the security boundary

`/etc/webproxy.cfg`, operator-written, never peer-writable:

```lua
return {
  enabled     = false,             -- fail closed, armed by the rc service
  allow_hosts = {                  -- exact host or *.suffix; NO regex
    "openprograms.github.io",
    "*.wikipedia.org",
  },
  max_page      = 262144,          -- 256 K ceiling on a single fetch
  max_per_min   = 6,               -- per requesting peer
  cache_ttl     = 86400,           -- how long a fetched page stays servable
  cache_read_trust = "known",      -- "trusted" | "known" | "unknown"
  allow_schemes = { "http", "https" },
}
```

Five rules, each with a reason:

1. **Empty `allow_hosts` serves nothing.** A proxy with no allowlist is a misconfiguration, and the safe reading of a missing rule is "no" — the same call `netfs._accessOk` makes for an empty `allow`.
2. **Host matching is exact or one leading `*.` suffix.** No regex, no substring. `evil-wikipedia.org` must not match `*.wikipedia.org`, and a substring check is exactly how it would.
3. **The URL is parsed and re-rendered before use**, never passed through as the peer sent it. Userinfo (`http://allowed.com@evil.com/`) is the classic bypass and it is defeated by parsing rather than by matching harder.
4. **No redirect following across the allowlist.** A 302 to a non-allowed host is a refusal, not a follow — otherwise the allowlist only constrains the *first* hop.
5. **Fail closed, armed by the rc service**, exactly as `20-netfsd.lua` and `20-fileshare.lua` are: a handler registered at boot keeps answering forever, so "service stop" has to actually disarm the backend.

### 3.2 Size is the proxy's problem, not the asker's

The TODO's note that "a page is bigger than 64 K" gets worse under proxying: B spends B's memory on a page A wanted. So the cap is enforced **on B, before the body is read**, the way `transfer.lua` checks file size before reading it — reading into RAM and *then* declining is a memory-exhaustion vector on a 2 MB machine.

The reply is chunked to A rather than buffered whole, reusing the shape `netfs` already uses for reads: ~4 KB per message inside the 8192-byte ceiling, with the client reassembling. A `WEB_FETCH` for a 256 K page is 64 messages, not one impossible one.

### 3.3 Rate limiting exists to protect the far host, not us

`max_per_min` per peer is not really about B's CPU. It is about not turning a room full of Minecraft computers into a small denial-of-service against a real website, whose operator did not agree to any of this. That is worth stating in the config comment so nobody "optimises" it away.

---

## 4. The cache

### 4.1 What it is

Every page `webproxyd` fetches is stored, keyed by canonical URL, with the TTL from the config. That store serves three purposes at once: it makes repeat reads free, it makes a page readable by machines that were never allowed to fetch, and it makes a page readable when *no* machine can currently reach the internet.

### 4.2 Where it lives

Two options, and the answer depends on whether a cluster exists:

- **Standalone:** a local directory on the proxy, swept on a timer. Simple, no dependencies.
- **On a cluster:** this is exactly `cluster.store` — keys, TTL, leases, eviction, a sweep, and an already-built `PUB` read path that an OpenOS worker can speak in twenty lines. A new namespace `web/<host>/<path-hash>` slots into §4.6 alongside `job-`, `domain-` and `shared/`.

**Recommendation: build the standalone one, shaped so the cluster one is a back end swap.** That is the same "one surface, two back ends" call the storage spec makes in its §1, and for the same reason — no caller should branch on which is deployed.

### 4.3 Only the fetcher writes

A cache entry may be created **only** by the proxy that performed the fetch. A peer can never hand B a page and ask it to store it.

This is the cache-poisoning defence and it is not optional. Without it, any TRUSTED peer can put a chosen document at a chosen URL in a store that every other machine reads — a far better attack than anything the fetch path offers, because it persists and it is served with the proxy's credibility.

### 4.4 Staleness is shown, not hidden

Every cache hit carries the fetch timestamp, and the browser displays it. A page served from a three-day-old cache is fine; a page served from a three-day-old cache while the reader believes it is live is not. The status line says `cached 3d ago` and that is the whole mechanism.

---

## 5. Message types

Two types, one `op` field — the same call `netfs` made, for the same reason: the arm check, the trust check, `verifyPeer` and the rate limit are written **once**, and an operation added later cannot forget one of them.

```lua
WEB_REQ  -- { op, req_id, ... }
WEB_RES  -- { req_id, ..., err }

op = "fetch"      -- { url }              → { status, mime, total_chunks, fetched_at }
op = "chunk"      -- { req_id, idx }      → { data, eof }
op = "cache_get"  -- { url }              → { status, mime, total_chunks, fetched_at, stale }
op = "cache_list" -- { prefix, limit }    → { entries, truncated }
op = "status"     -- { }                  → { has_card, allow_count, cache_entries }
```

`status` exists so a browser can tell "no proxy will serve me" from "the proxy is there and said no", which is the distinction an operator needs to debug their own network and the one a bare timeout destroys.

---

## 6. The browser

### 6.1 Where the work actually is

The TODO is right and it is worth restating: **the fetch is 10% of this.** HTML → readable text on 80×25 is the feature.

Deliberate non-goals, listed so nobody treats them as gaps: no JavaScript, no CSS, no images, no tables-as-layout, no forms in v1. A renderer that handles headings, paragraphs, lists, links, `<pre>`, and character entities covers most documentation and nearly all plain articles, which is what anyone is realistically reading from inside Minecraft.

### 6.2 Layout on 80×25

- Wrap at the viewport width, minus a one-column gutter for the link marker.
- Links get a bracketed ordinal (`[12]`) and a numbered footer list; following a link is `12` + Enter, not a mouse hunt.
- `<pre>` does not wrap — it scrolls sideways, because wrapping code is worse than clipping it.
- Entities (`&amp;`, `&#8212;`, …) decode to the closest thing the T1/T2 font actually has, which for an em-dash is `-`. A glyph that renders as a blank box is worse than an honest ASCII substitute.

### 6.3 The renderer is a pure function, so it is testable

`render(html, width) -> { lines, links }` touches no network, no screen and no filesystem. That is the whole reason to draw the boundary there: the hard, fiddly, regression-prone half of this feature can be unit-tested off-box against fixture documents, on the same harness everything else in the tree uses.

---

## 7. Failure semantics

| Failure | Behaviour |
|---|---|
| No local card, no proxy answers | "No internet card and no proxy reachable" — say both, since the fix differs |
| Proxy reachable, host not allowed | `host_not_allowed: <host>`; the browser shows the proxy's address so the operator knows *whose* allowlist to edit |
| Proxy has no card | `no_internet_card` from `status`, not a timeout |
| Page over `max_page` | Refused before the body is read, with the limit named |
| Far host down | The proxy's HTTP error is passed through, not flattened to "failed" |
| Fetch fails, cache has it | Serve the cached copy, clearly marked stale — this is the offline-reading case working as designed |
| Proxy stops mid-transfer | Chunks are idempotent by `(req_id, idx)`; the client retries the missing index |

---

## 8. What this is not

- **Not a shared browsing session.** Two machines reading the same page do not see each other.
- **Not an anonymiser.** Every fetch is attributable to the proxy, and the proxy logs which peer asked. An operator running a proxy is accountable for its traffic and should be able to see it.
- **Not a way around the capability system.** A browser package declares `internet`; a machine with no card and no allowed proxy simply cannot browse, and no configuration inside the browser changes that.

---

## 9. Build order

1. **`render(html, width)`** — pure, off-box, fixture-tested. It is the actual work and it needs nothing else to exist.
2. **The local browser** — `internet` + `fullscreen` package over §6, one machine, no proxy. Useful on its own.
3. **`webproxyd` fetch path** — allowlist, size cap, rate limit, chunked reply, fail-closed arming.
4. **The cache** — standalone store behind an interface, plus stale marking.
5. **Cluster back end for the cache** — the `web/` namespace in `cluster.store`.

Steps 1 and 2 are shippable alone and are worth doing first for a reason beyond dependency order: they are the half with no security surface at all, so they can be built quickly and reviewed lightly, which leaves attention for step 3, where every mistake is someone else's problem.

---

## 10. Open questions

1. **Does the browser auto-discover a proxy, or is one configured?** Auto-discovery is the convenience, and the cluster README already refuses that pattern for the Master on the grounds that whoever answers first becomes your gateway. A proxy is a strictly worse thing to accept from a stranger. Leaning: configured, with `web proxy list` showing TRUSTED peers that answer `status`.
2. **Should `cache_read_trust = "unknown"` require a second confirmation?** It is the setting that turns a private cache into a public one, and the difference is invisible from the machine's own screen.
3. **Is per-call cap raising enough for `kernel.internet`?** The TODO's instinct was per-call rather than global. A proxy makes the caller and the payer different machines, which may argue for a *proxy-specific* cap that is not the same as the local browser's.
4. **What is the canonical URL key?** Query strings, fragments and trailing slashes all decide whether two requests share a cache entry. Fragments clearly drop; query strings clearly stay; the rest needs a rule written down before anything caches.
5. **Does the proxy strip anything from the response?** Serving raw HTML to a peer means the *renderer* is the thing parsing untrusted input, on every machine rather than one. Rendering proxy-side would centralise that risk but hard-codes a width.
