# Storage Spec (Draft v0.1)

> **Scope:** the Public storage tier — the Storage Node that [cluster-protocol-spec-draft.md](cluster-protocol-spec-draft.md) §4.5–§5 designs but nothing implements, plus a distributed fallback built from network-attached JBOD members, plus the TOS-level remote-share primitive both of them stand on. Extends the protocol spec's trust topology (§1), port layout (§2) and namespace rules (§4.6). Nothing here is implemented; every section is design.
>
> **Relationship to the existing spec:** §4.5's `STORE_PUT` / `STORE_LEASE_EXTEND` / `STORE_RELEASE` wire format is taken as given and is not redesigned. What this document adds is *who answers those messages*, and how the answer can come from a pool of ordinary cluster nodes rather than one dedicated box.

---

## 0. The idea, and the one thing that makes it hard

`kernel/jbod.lua` pools N filesystem components into one mountable proxy. Reads search every member; writes land on whichever member already holds the file, else the emptiest one. Losing a member loses only that member's files.

The load-bearing observation is that **`jbod.makePool(members)` is fully duck-typed.** It never calls `component.proxy`, never consults the component list, and never assumes a member is local. A member is any table carrying `exists / isDirectory / size / lastModified / list / makeDirectory / open / read / write / close / seek / remove / rename / spaceTotal / spaceUsed / isReadOnly / address`. Supply a member whose methods happen to travel over the mesh and the pool works unmodified.

So one new primitive — a remote filesystem proxy, `netfs` — unlocks both halves of the idea: a cluster whose nodes collectively provide Public storage, and a general TOS "share this directory" facility. That part of the design is genuinely as clean as it sounds.

**What is not clean is placement.** JBOD's write rule is "the member that already holds this file, else the emptiest." Rule one is a call to `exists()` on every member. On a local pool a disk is either there or provably gone. On a network pool a member is routinely *neither* — it is a machine that is rebooting, and `exists()` cannot answer. Whatever the proxy returns for an unreachable member is wrong in one direction or the other:

- **Return an error** and one node rebooting takes the whole pool down for writes.
- **Return `false`** and the write lands on a different member. The absent node returns holding its own copy of the same key, `proxy.open(rel, "r")` returns whichever member sits earlier in the array, and the pool now silently serves one of two divergent files depending on array order.

This is not a corner case; it is the steady state of a pool made of Minecraft computers. **Everything below is shaped by refusing to let liveness decide placement.** §5 is the core of the document; the rest is scaffolding around it.

---

## 1. Two back ends, one contract

Do not build "the Storage Node" and "the distributed pool" as two systems. Build one `STORE_*` surface with two implementations, so no caller ever branches on which is deployed.

```
              STORE_PUT / STORE_LEASE_EXTEND / STORE_RELEASE   (§4.5, unchanged)
              PUB GET / LIST on port 2100                      (§3.2, already implemented)
                                    │
              ┌─────────────────────┴─────────────────────┐
              │                                           │
      Dedicated Storage Node                    Distributed pool
      one box, one disk tree,                   coordinator + N contributed
      authoritative, simple                     members over netfs
      PRIMARY                                   FALLBACK
```

Both must honour §4.6 namespaces, §5 TTL and lease semantics, and the `PUB` read protocol identically. A Worker doing `PUB GET job-104/tasks/assignment-17` cannot tell which is answering, and that is the requirement.

The dedicated node stays **primary** because it is dramatically simpler: one machine, one key table, no placement problem, no partial availability. The distributed pool exists for the estate that has not built a dedicated box yet — which today is every estate, since no Storage Node module exists at all.

---

## 2. `netfs` — the remote filesystem proxy

A TOS-level primitive, not a cluster one. It belongs in `TOS-Dev/tos/kernel/netfs.lua` and is consumed by the cluster, not owned by it.

### 2.1 Shape

`netfs.attach(host_addr, share_name)` returns a filesystem-component-shaped proxy backed by the mesh. It is exactly what `jbod.makePool` wants, and exactly what `kernel.fs.mount` wants, which is why one primitive serves both use cases.

### 2.2 Wire operations

**Implemented as two message types, not nine.** The draft listed a type per operation; the build uses one `NETFS_REQ` / `NETFS_RES` pair with an `op` field, multiplexed behind a single handler. The reason is security rather than tidiness: the arm check, the TRUSTED check, `verifyPeer` and the vague-denial rule are written **once** in `netfs.handleRequest`, and an operation added later cannot forget one of them. Nine handlers would be nine places to get it right. This also mirrors the `PUB` read protocol (§3.2), which multiplexes on `op` for the same reason.

```lua
-- NETFS_REQ payload: { op, share, req_id, ... }   NETFS_RES: { req_id, ... , err }
op = "space"   -- { share }                     → { total, used, read_only }
op = "stat"    -- { share, path }               → { exists, is_dir, size, mtime }
op = "list"    -- { share, path }               → { entries, truncated }
op = "open"    -- { share, path, mode }         → { handle_id }
op = "read"    -- { handle_id, n }              → { data, eof }
op = "write"   -- { handle_id, data }           → { ok, written }
op = "close"   -- { handle_id }                 → { ok }          (idempotent)
op = "seek"    -- { handle_id, whence, offset } → { pos }
op = "mkdir"   -- { share, path }               → { ok }
op = "remove"  -- { share, path }               → { ok }
op = "rename"  -- { share, path, to }           → { ok }
```

`rename` **is** present, contrary to the draft's note. A share lives on one host, so a rename inside it is a local rename and costs nothing. What §4.3 refuses is *cross-member* rename in a pool, which is a different operation. Both ends of the path are confined — checking only the source would let a rename write anywhere on the host.

### 2.3 Handles cost round trips, so buffer

`jbod.proxy.open` returns *the member's own handle* and later calls `handle:read(n)` on it. A naive netfs handle is therefore one network round trip per read call, and OC's per-tick call budget is the scarcest resource in the estate — the AI-operator spec (§1.2) already refuses to put a poll loop on the Master for this reason.

So netfs handles buffer:

- **Read:** fetch in blocks of ~4 KB (comfortably inside the 8192-byte message cap once framing is subtracted), serve `read(n)` from the buffer, refill on exhaustion. A whole-file read of a typical task list becomes one round trip, not forty.
- **Write:** accumulate and flush at the block boundary and on `close`. This means **a write is not durable until `close` returns**, which must be documented rather than discovered.

### 2.4 Capacity is cached, never polled

`jbod.pickWriteMember` calls `spaceTotal()` *and* `spaceUsed()` on every member on **every write**. Across a remote pool that is 2N round trips per file. Unacceptable.

netfs caches `NETFS_SPACE` and refreshes it on a slow interval (30 s), so `spaceTotal()`/`spaceUsed()` are local reads of a cached value. Capacity accurate to 30 s is entirely sufficient for "which member is emptiest," and §5 removes free-space from the placement decision for the cluster back end anyway.

---

## 3. Making JBOD network-tolerant

**Prerequisite, discovered while scoping this and now fixed:** `jbod.lua`'s handle forwarding was broken for every real member. `proxy.open` returned the member's handle bare and `proxy.read` forwarded with `handle:read(n)` — but members are OpenComputers filesystem components (`admin.lua` builds pools from `component.proxy(addr)`), whose `open` returns an *opaque* handle read via `member.read(handle, n)`. Since `kernel/fs.lua` calls `proxy.read(h, n)` on a mounted proxy, every read and write through a mounted pool errored. The unit test missed it because its fake member returned a method-bearing table, which no component does. Pool handles now carry their owning member, `test_jbod.lua`'s fake implements the real contract, and the routing is pinned — including the case where two members hold the same path, which is what makes routing load-bearing rather than cosmetic.

With that corrected, `jbod.lua` still needs a fault-tolerance pass before it can hold remote members. Today only `list`, `makeDirectory` and `remove` wrap member calls in `pcall`; `exists`, `open`, `size`, `lastModified`, `spaceTotal` and `spaceUsed` propagate. One unreachable member currently throws out of the mount.

The change is **not** "wrap everything in pcall." That converts unreachable into not-found, which is precisely the ambiguity §0 identifies as fatal. Instead:

1. **Members gain a liveness state** — `up`, `down`, `unknown` — maintained by netfs from its own traffic, not by the pool.
2. **Reads tolerate `down` members** and are answered from `up` ones, because a read that finds the file has found it.
3. **A read that finds nothing, with any member `down`, returns a distinguishable "incomplete" result** rather than a flat "not found." The caller may retry or degrade; it must not conclude absence.
4. **Writes never place based on a liveness-dependent `exists()` sweep.** See §5.
5. **`spaceTotal`/`spaceUsed` skip `down` members** and the pool reports its member count and how many are reachable, so `df` tells the truth about a degraded pool instead of quietly shrinking.

Point 3 is the one most likely to be dropped as fussy. It should not be: "I could not find it" and "I could not look" differ by exactly the bug in §0.

---

## 4. What JBOD should not be asked to do remotely

### 4.1 Cross-member rename

`proxy.rename` across members reads the entire source file into a Lua table of 4 KB chunks, concatenates, and writes it to the destination. On a Master with ~3.6 MB apparent RAM (protocol spec §0.5.1), that is a memory spike proportional to file size; across the network it is also two full transfers with no atomicity and no rollback if the second half fails.

Remote pools should **refuse cross-member rename** and return `cross_member_rename_unsupported`. Same-member rename forwards to the member and is fine.

### 4.2 Directories that exist on several members

`makeDirectory` deliberately creates the directory on *every* writable member so later writes always have a parent. Across a network that is N round trips per mkdir, and a `down` member silently misses it, so a later write to that member fails on a missing parent. Remote pools create the directory lazily on the member actually being written to.

### 4.3 Being the authoritative cluster store

Covered next, and it is the main architectural claim of this document.

---

## 5. Placement: why the cluster back end is not "JBOD over the network"

JBOD's placement heuristic — already-holds-it, else emptiest — is right for a box with four disks in it and wrong for an authoritative distributed store, for the reason in §0. The fix is not a better heuristic. It is to **stop discovering placement and start deciding it.**

And the protocol spec has already done that work, in a section written for another purpose entirely. §4.6:

| Namespace | Who can write | Lifecycle |
|---|---|---|
| `job-<id>/...` | Master, or the Manager assigned that job | auto-delete when job completes |
| `domain-<id>/...` | only the owning Manager | auto-delete when Manager offline > 5 min |
| `shared/...` | only the Master | manual only |

**The namespace already names the owner and the lifetime.** Placement can be derived from the key, with no polling, no liveness check, and no index lookup:

- **`domain-<id>/…` lives on the Manager owning that domain.** Zero coordination — the writer and the store are the same machine, so `STORE_PUT` to your own scratch never leaves the box. And the availability semantics come out exactly right for free: §4.6 already says this namespace is swept when that Manager has been offline five minutes, so "that Manager is down, therefore its scratch is unreachable" is the *specified* behaviour rather than a degradation.

- **`shared/…` is Master-written, rare, and small.** Replicate to every member on write. Reads are then satisfiable from any reachable member, which is what you want for the one namespace that holds cluster-wide configuration.

- **`job-<id>/…` is the hard one, and the spec says why.** §4.6's stated rationale is that assignment task lists live here specifically so that "if a Manager dies mid-assignment, the task list survives and Master can redistribute to a replacement Manager without copying." Placing it on the assigned Manager would destroy the only reason the namespace exists.

  So `job-<id>/` needs placement that is independent of both liveness and job assignment. Use **rendezvous hashing (HRW)**: for key *k*, pick the member maximising `hash(k, member_id)`. It is deterministic, needs no index, and — unlike `hash(k) % N` — adding or removing a member remaps only the keys that belonged to it, not all of them. Write to the top **two** members by that ranking.

**Replication factor 2 on `job-<id>/` only** is the price of §4.6's promise, and it should be paid consciously. Task lists fit in a single packet, so the storage cost is trivial; the cost is a second write round trip on the assignment path. Everything else in the store is unreplicated.

### 5.1 What this buys

Placement becomes a pure function of the key. A write never asks "who has this?" and so never has to interpret silence. A read knows precisely which member(s) should hold a key, so "member is down" and "key does not exist" are distinguishable without heuristics — which is the §0 hazard closed at the root rather than patched.

### 5.2 What it costs

A member joining or leaving remaps its share of `job-<id>/` keys. Because those keys are TTL-bounded (§5, default 1 h) and job-scoped, **the design does not migrate them** — it lets them expire and be rewritten. A rebalance path is the kind of machinery that looks essential on a whiteboard and rots untested in a Minecraft cluster.

---

## 6. Trust and exports

netfs is a generalisation of something that already exists, and should inherit its posture rather than invent one. `kernel/net/transfer.lua` already serves files to TRUSTED peers over `FILE_REQ`/`FILE_RES`, and `usr/bin/share` is its client. What netfs adds is *named exports with ACLs* in place of transfer.lua's single hardcoded `/public/`, plus handles, block reads and writes — transfer.lua is whole-file, read-only, and caps at 6144 bytes.

The five properties transfer.lua already establishes are **requirements, not suggestions**, because a weaker netfs would be a way around them:

1. **Fail-closed arm switch tied to the rc service.** `transfer.setEnabled` defaults to `false` and is flipped by the fileshare service's `start`/`stop`, precisely so that deleting the service actually stops the serving. netfs needs the same, or "stop sharing" becomes advisory.
2. **TRUSTED level required**, checked on every request.
3. **`net.verifyPeer` challenge-response** before honouring anything. The threat is a *relocated trusted modem*: the address is still trusted, but the bytes now come from an attacker. The 60 s verification cache makes this affordable per-request.
4. **Size checked before read.** transfer.lua rejects oversize files *before* reading them, because reading into RAM and then declining is a memory-exhaustion vector on a machine with ~3.6 MB.
5. **Denial reasons are deliberately vague.** transfer.lua returns "Insufficient trust level" for a failed verification rather than the true reason, so an attacker cannot map which peers a host shares a secret with. netfs error codes are operator-facing on the *client*; the wire denial stays uninformative.

On top of that, an export is an explicit, named, ACL'd decision — never "whoever asks."

```lua
-- /etc/netfs-exports.cfg, operator-written
return {
  { name = "pool",  path = "/mnt/shared", allow = { "<addr>" }, mode = "rw" },
  { name = "media", path = "/home/media", allow = { "*paired*" }, mode = "ro" },
}
```

Four rules, each with a reason:

1. **Exports are opt-in per directory.** A host with no config file shares nothing and needs no defensive code.
2. **`allow` lists addresses or `*paired*`** (anything through the existing `CLUSTER_PAIR_INIT`/`CONFIRM` flow, §3.1.1). No new bootstrap mechanism and no discovery broadcast — the cluster README already refuses "who's out there?" on the grounds that whoever answers first becomes your gateway, and a filesystem is a worse thing to hand to a stranger than a route.
3. **The host's securefs ACLs still apply, evaluated as the requesting user.** The manual is explicit that JBOD is a transport and securefs mediates the mount point — but that is the *client's* securefs. If the host does not also evaluate its own, mounting a share is a privilege escalation: a USER-tier account on box A reading a root-owned file on box B.
4. **`mode = "ro"` is enforced host-side**, not by the client declining to send writes.

A `netfs` capability gates the client half, so a package manifest that does not request it cannot mount anything — consistent with how `internet` and `peripheral.*` are already handled.

---

## 7. The general TOS share

Everything above the cluster layer falls out of §2 and §6 with no further machinery:

```
mount netfs://<host>/media /mnt/media
```

This is the Windows-folder-share analogy from the original idea, and it earns the comparison including the drawback: **when the host is offline the mount is empty, and files vanish from a directory listing without being deleted.** That is worth stating in the manual in those words, because a user who does not expect it will conclude the files were lost.

Pooling remote shares with `jbod create` also works, and here plain JBOD placement is acceptable *provided* the pool is documented as single-writer or read-mostly. The §0 divergence hazard is real but bounded: two machines writing the same path in the same pool while a member is offline is a scenario a person can be told to avoid, and it is not the cluster's authoritative store. **The cluster back end does not use this path** — §5 is not optional there.

---

## 8. Failure semantics

| Failure | Dedicated node | Distributed pool |
|---|---|---|
| Store unreachable | Public tier unavailable; §8.3 already covers it | Only the affected members' keys are unavailable |
| One member offline | n/a | `domain-<id>/` for that node gone (per §4.6, correct); `job-<id>/` served by its replica; `shared/` from any member |
| Two members offline | n/a | A `job-<id>/` key with both replicas down is unavailable; Master falls back to inline transfer (§8.3) |
| Host offline mid-write | Write fails, no lease issued | Write fails on that member; caller retries and HRW picks the same member, so retry is idempotent |
| Member returns with stale keys | n/a | Keys past `expires_at` are swept on the 60 s sweep; §5's "expiry is best-effort" already permits this |

The last row is where a lesser design leaks: because placement is a pure function of the key, a returning member holds only keys it was always supposed to hold. It cannot hold a *rival copy* of a key that was written elsewhere in its absence, which is exactly the divergence §0 warned about — and the reason that hazard does not appear in this table.

---

## 9. Build order

1. ~~**`netfs` + exports.**~~ **Built** — `tos/kernel/netfs.lua`, `etc/rc.d/20-netfsd.lua`, `NETFS_REQ`/`NETFS_RES`, and `usr/lib/tests/test_netfs.lua` (72 checks, driving the real client proxy against the real server dispatcher over an in-process loopback). Confinement, fail-closed arming, read-only enforcement and per-peer handle scoping are each mutation-tested — the suite was verified to fail when those four are individually broken, because a security test that cannot fail is decoration. **Not yet built: an operator command.** netfs is reachable from Lua and mountable via `kernel.fs.mount`, but there is no `netfs mount` verb, so it is a library feature until one exists.
2. **JBOD network-tolerance pass** (§3), with a test that pins "member down" as distinguishable from "file absent" — the §0 regression, written before the code that could reintroduce it.
3. ~~**The `STORE_*` server surface**, against local disk only.~~ **Built** — `storage-skeleton/`: `usr/lib/cluster/store.lua` (keys, leases, TTL, §5.1 eviction, an atomic index), `usr/lib/cluster-storaged.lua` (writes on 2101, the §3.2 `PUB` read plane on 2100, the 60 s sweep), plus config, rc service and package manifest. Tests: `test_cluster_store.lua` (92 checks) and `test_cluster_storaged.lua` (28). This closes the protocol spec's largest "NOT YET IMPLEMENTED" block.

   Two things worth carrying forward. **`store.lua` does not decide who may write where** — §4.6 is `cluster.protocol.canWrite`, shared with the Manager rather than copied, so the two cannot drift; the daemon composes identity→ACL→storage and `test_cluster_storaged.lua` tests that join directly, because if it is wrong there is nothing behind it. And **writer identities are operator-declared** in `cluster-storage.cfg`, never self-declared on the wire: the namespace rules turn entirely on who the writer claims to be, so believing the claim would leave no isolation at all.

   Not implemented, and recorded rather than skipped: §5.1's eviction tier 2 ("keys in `job-<id>/` where the job has completed"). A Storage Node cannot know a job finished. The signal has to be a `STORE_RELEASE` from the Master at finalize time; guessing by age here would delete live task lists out from under a running job.
4. **The distributed back end** behind the same surface: namespace-derived placement, HRW for `job-<id>/`, replication factor 2.
5. ~~**Master-side integration.**~~ **Partly built** — `tasks_ref` is live. `master-skeleton/lib/cluster/store_client.lua` speaks §4.5's `STORE_PUT`/`STORE_RELEASE` to the configured node, and `jobs.splitIntoAssignments` now spills any slice whose serialized form exceeds 4 KB to `job-<id>/tasks/assignment-<n>`, sending a pointer instead of the payload (design principle 5). `finalizeJob` releases those keys.

   That release is worth naming: it is the signal §5.1's eviction **tier 2** needs and a Storage Node cannot generate for itself. §9 step 3 above recorded tier 2 as unimplementable from inside the node; this is the other half, and it closes that gap.

   Everything degrades to the current behaviour. No `storage_node_address` configured, a node that is full, unreachable, or refuses the write — each falls back to inline, because a missing scratch tier must cost a bigger packet, never a failed job. `test_cluster_jobs.lua` §16 pins all four paths plus the release, and was mutation-tested: spilling regardless of size fails 3 assertions, skipping the release fails 1, and leaving a dangling ref after a failed write fails 1.

   **Still dead: `inputs_ref` and `result_sink="public"`.** Inputs are job-wide rather than per-slice, so they want a different key and a different lifetime. The `public` result sink needs the *Manager* to write its result and return a ref, which is Manager-side work this commit does not touch.

Steps 1–3 are each shippable alone. Step 3 delivers the specified feature; step 4 delivers the idea.

---

## 10. Open questions

1. **Does the distributed pool need a coordinator at all?** §5 is deliberately coordinator-free — placement is a pure function, so any node can compute it. That is a strong property and worth defending, but it means no single node can answer "what keys exist?" without asking everyone. `PUB LIST` over a distributed pool is therefore a scatter-gather. Acceptable, or is `LIST` common enough to want an index?
2. **Should `shared/` replication be all-members or a quorum?** All-members is simplest and the namespace is tiny, but it makes every `shared/` write as slow as the slowest node.
3. **Does a Manager contributing storage advertise capacity in its heartbeat?** It already declares `storage_type` (including `"jbod"`) and `external_capacity` at registration (§4.1), so the field exists. Reusing it would let the scheduler's existing `storage_preference` matching see pool membership for free.
4. **What happens to an in-flight lease when its member leaves the pool?** Leases are held per key; if placement moves, the lease_id must survive or every holder must re-`PUT`. Leaning: leases are member-local and a departed member's leases simply expire.
5. **Is `netfs` TRUSTED-only, or should read-only exports be allowed to PAIRED-but-untrusted peers?** The cluster's Workers are the awkward case — they do not speak TOS protocol at all (§3.2 exists for exactly that reason), so they would reach a distributed pool through the `PUB` port, not netfs.
