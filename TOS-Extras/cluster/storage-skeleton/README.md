# cluster-storage — the cluster's scratch store (Storage Node)

A Storage Node holds the data the Master would otherwise have to push through
a 6 KB packet: when a job's task list for one Manager is too big to send
inline, the Master writes it here under `job-<id>/tasks/assignment-<n>`, sends
the Manager a pointer, and releases the key when the job finishes. The design
is [storage-spec-draft.md](../storage-spec-draft.md); the wire format is
§4.5 of [cluster-protocol-spec-draft.md](../cluster-protocol-spec-draft.md).

**What 1.0.0 is:** one node over its own disk (the spec's §9 step 3, which it
calls "shippable alone"). **What it is not:** the distributed pool (steps 4+),
`inputs_ref`, or `result_sink = "public"`. Nothing in the Master needs a node —
with none configured, or one that is full or unreachable, jobs fall back to
inline payloads, so a missing scratch tier costs a bigger packet, never a
failed job.

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

Run from the `TOS-Extras` root: `lua cluster/storage-skeleton/test_storage_wire.lua`, and so on.
`TOS-Dev/usr/lib/tests/test_cluster_storaged_shim.lua` runs the shim under the real `rc.lua`.

## Setting one up

1. Install it on a box that has a **wired modem or a Tier-2 wireless card**. The node holds
   three ports open: the kernel's own, 2101 (writes) and 2100 (reads). A Tier-1 wireless
   card holds one, so opening ours would evict TOS's; the daemon logs
   `could not open ports ... (a Tier-1 wireless card holds only one)` and an error saying
   nothing can reach the node, and starts anyway in case there is a second NIC.
2. `pkg install cluster-storage`. It pulls in `cluster-manager`, because that package ships
   `cluster.protocol` (see the manifest for why this is a bandage and not an answer).
3. Edit `/etc/cluster-storage.cfg`: put the **Master's modem address** in `master`, and any
   Manager allowed to write its own `domain-<id>/` scratch in `managers`. An address that is
   not listed is refused as `unknown_writer`, by design — the namespace rules turn entirely on
   who is writing, so believing a peer's own claim would leave no isolation.
4. `service start cluster-storaged`, then on the Master set `storage_node_address` to this
   node's modem address in `/etc/cluster-master.cfg` and restart `clusterd`.

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
- **`STORE_LIST_RES.keys` carries rows** (`{ key, size, expires_at }`), not bare names. Nothing
  consumes it yet; mind that if something starts to.
