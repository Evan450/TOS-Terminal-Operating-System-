# cluster-storage — the cluster's scratch store (Storage Node)

A Storage Node holds the data the Master would otherwise have to push through
a 6 KB packet: when a job's task list for one Manager is too big to send
inline, the Master writes it here under `job-<id>/tasks/assignment-<n>`, sends
the Manager a pointer, and releases the key when the job finishes. The design
is [storage-spec-draft.md](../storage-spec-draft.md); the wire format is
§4.5 of [cluster-protocol-spec-draft.md](../cluster-protocol-spec-draft.md).

**What it is:** one node over its own disk (the spec's §9 step 3), or one member of a
**storage pool** (§9 step 4, built 2026-11-07, 1.1.0 here and cluster-master 1.2.0). In a
pool the Master places every key itself, so a node never knows it is in one; see
[A pool](#a-pool) below. **What it is not:** `inputs_ref` or `result_sink = "public"`,
which are still dead. Nothing in the Master needs a node — with none configured, or one
that is full or unreachable, jobs fall back to inline payloads, so a missing scratch tier
costs a bigger packet, never a failed job.

## What's here

| Path | What it is |
|---|---|
| `package.lua` | the `cluster-storage` package (`kind="service"`, installed DISABLED) |
| `usr/lib/cluster/store.lua` | the on-disk key store: leases, TTL, eviction, an atomic index. Decides nothing about who may write. |
| `usr/lib/cluster-storaged.lua` | the daemon: both listeners, the sweep, the §4.6 namespace gate |
| `etc/cluster-storage.cfg` | operator config. Writers are **declared here**, never learned from the wire |
| `etc/rc.d/cluster-storaged.lua` | the service shim |
| `test_store.lua` | the key store (67) |
| `test_storaged.lua` | the daemon's handlers against the real protocol modules (36) |
| `test_storage_wire.lua` | the Master's real client talking to the real daemon over a modelled radio (34) |
| `test_storage_pool.lua` | a pool of three on the same radio: placement, two replicas, majority, versions, repair, LIST (74) |

Run from the `TOS-Extras` root: `lua cluster/storage-skeleton/test_storage_wire.lua`, and so on.
`TOS-Dev/usr/lib/tests/test_cluster_storaged_shim.lua` runs the shim under the real `rc.lua`.

## Setting one up

1. Install it on a box that has a **wired modem or a Tier-2 wireless card**. The node holds
   three ports open: the kernel's own, 2101 (writes) and 2100 (reads). A Tier-1 wireless
   card holds one, so opening ours would evict TOS's; the daemon logs
   `could not open ports ... (a Tier-1 wireless card holds only one)` and an error saying
   nothing can reach the node, and starts anyway in case there is a second NIC.
2. `pkg install cluster-storage`. It pulls in `cluster-manager`, because that package ships
   `cluster.protocol` (see the manifest for why this is a bandage and not an answer). A Manager
   beside its own node reads tasks straight from the store, since no modem can send to itself.
3. Edit `/etc/cluster-storage.cfg`: put the **Master's modem address** in `master`, and any
   Manager allowed to write its own `domain-<id>/` scratch in `managers`. An address that is
   not listed is refused as `unknown_writer`, by design — the namespace rules turn entirely on
   who is writing, so believing a peer's own claim would leave no isolation.
4. `service start cluster-storaged`, then on the Master set `storage_node_address` to this
   node's modem address in `/etc/cluster-master.cfg` and restart `clusterd`. `lsdev --full` on
   the node shows that address. The Master and the node must trust each other (`net trust`
   on both), because writes are TOS traffic at TRUSTED.

## A pool

Several nodes can share the Public tier. Set each one up as above, then on the Master list
them instead of naming one node:

```lua
-- /etc/cluster-master.cfg
storage_pool = { "<node-a address>", "<node-b address>", "<node-c address>" },
```

Where a key lives is a function of the key and that list (`cluster/placement.lua` on the
Master), the answers the operator approved in the spec's §10:

| Key | Goes to | Stands when |
|---|---|---|
| `job-<id>/...` (task lists) | the top two members by rendezvous hash | **both** have it. One copy is less safe than the inline payload it would replace, so a short write is released and the job stays inline. |
| `shared/...` | every member | a majority have it. Each write is versioned (counter, Master's address); a node refuses an older version, and the Master's repair sweep (`storage_repair_interval`, 120 s) brings the rest up. |
| anything else | the top member by hash | it has it |

There is no coordinator: no member is ever asked "do you have it?", so a member that is
rebooting cannot steer a write somewhere else (the spec's §0). A Manager is told both of a
task list's members and reads the second when the first refuses or is silent. Each member
issues its own lease and the Master releases each one where it was issued. A LIST asks
every member and names any that did not answer rather than returning a short list as if it
were whole. Adding a member changes where new keys go, and only the ones it now ranks
for. Nothing is migrated: a key already written stays where it is, the assignment names
its members, and job keys end with their job.

Each member's `/etc/cluster-storage.cfg` names the same Master, and the Master trusts each
member, as for one node. A Manager running a node on its own box reports that node's free
space in its heartbeat.

## Things worth knowing before you change anything here

- **A modem delivers only to a port the destination holds open.** The daemon opens 2101 and
  2100 on every modem at start and closes them at stop. It originally opened neither: the
  Master's writes (sent to 2101) and every Worker's reads (sent to 2100) were addressed to
  closed ports and silently discarded, while the Master quietly fell back to inline payloads —
  so nothing ever looked broken. The tests had hidden it by faking a delivery the radio would
  not make, which is why `test_storage_wire.lua` models the air instead.
- **Replies go out on the node's default port, not 2101.** The Master opens only its own
  listen port, so a reply addressed to 2101 would never arrive. kernel.net ignores the port
  on inbound TOS traffic and dispatches on packet type, so the requester hears it wherever it
  lands.
- **The read plane is raw and unauthenticated on purpose** (§2.2): everything in Public is
  readable by everyone, and an OpenOS Worker must be able to ask in ~20 lines. Replies are a
  bare serialized table sent out of the modem that heard the question — kernel.net has no
  raw send, and there is no TOS packet to build. A frame that is not a well-formed `PUB`
  request is dropped in silence so the port is no error oracle.
- **Eviction tier 2 needs the Master.** A node cannot know a job finished; the signal is the
  Master's `STORE_RELEASE` at finalize. Guessing by age here would delete live task lists.
- **`STORE_LIST_RES.keys` carries rows** (`{ key, size, expires_at, version }`), not bare
  names. The Master's pool LIST and repair sweep read them, so a change here is a change to
  both.
