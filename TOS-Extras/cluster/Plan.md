# Master skeleton — file layout

> **Scope:** this file documents ONLY the `master-skeleton/` layout (the
> Master side of the cluster add-on). It does not cover `manager-skeleton/`
> (`usr/lib/cluster-manager.lua`, `usr/bin/cluster-manager.lua`,
> `usr/lib/cluster/protocol.lua`, `usr/lib/cluster/worker.lua`) or
> `openos/cluster-worker.lua`. For the wire protocol between all three
> (Master, Manager, Worker) see
> [cluster-protocol-spec-draft.md](cluster-protocol-spec-draft.md); for the
> Manager/Worker implementation itself, read the `manager-skeleton/` and
> `openos/` source directly — there is no separate design doc for those yet.

This directory mirrors the target install layout on the Master machine.
Files under `master-skeleton/` map to paths on the TOS filesystem as follows:

```
master-skeleton/                          →   TOS filesystem
├── clusterd.lua                          →   /usr/lib/clusterd.lua
├── cluster.lua                           →   /usr/bin/cluster.lua  (the CLI)
├── etc/
│   ├── rc.d/
│   │   └── clusterd.lua                  →   /etc/rc.d/clusterd.lua
│   └── cluster-master.cfg                →   /etc/cluster-master.cfg
└── lib/
    └── cluster/
        ├── state.lua                     →   /usr/lib/cluster/state.lua
        ├── scheduler.lua                 →   /usr/lib/cluster/scheduler.lua
        ├── jobs.lua                      →   /usr/lib/cluster/jobs.lua
        ├── net.lua                       →   /usr/lib/cluster/net.lua
        └── api.lua                       →   /usr/lib/cluster/api.lua
```

## Module dependencies

```
clusterd.lua
  ├── cluster.state         (state store)
  ├── cluster.scheduler     (pure function; no state)
  ├── cluster.jobs          (owns job/assignment lifecycle)
  ├── cluster.net           (registers net.on handlers)
  └── cluster.api           (exposes public API to the CLI)

cluster.lua (CLI)
  └── cluster.api           (only dependency; all domain logic behind the API)

cluster.net ─┬─► cluster.state       (updates on packet receipt)
             └─► cluster.jobs        (delivers results, acks)

cluster.scheduler            (stateless; called with state as argument)

cluster.jobs ─┬─► cluster.state
              └─► cluster.net        (for sendAssignment, sendCancel)

cluster.api ─┬─► cluster.state
             ├─► cluster.scheduler
             └─► cluster.jobs
```

## Read order for review

1. **`clusterd.lua`** — see the service lifecycle (start/stop) and the
   set of timer/event handlers. Everything else fills in the bodies.
2. **`lib/cluster/state.lua`** — the data shape. Most downstream
   questions ("where does X live?", "is Y persisted?") are answered here.
3. **`lib/cluster/scheduler.lua`** — the scheduling rules. Small file,
   high leverage on correctness.
4. **`lib/cluster/api.lua`** — the CLI↔daemon contract.
5. **`cluster.lua`** — the user-facing surface; thin dispatch layer.
6. **`lib/cluster/net.lua`** and **`lib/cluster/jobs.lua`** — these carry
   the most intricate logic (relay unwrap/re-wrap, retry/timeout/reassembly
   policy); read them last but read them fully — see "Current status" below,
   they're implemented, not placeholders.

## Current status

This skeleton is no longer skeletal — read order above still applies, but
every file it names has a real implementation.

**Built:**

- **`clusterd.lua`** — full service lifecycle (start/stop), config
  load/merge with defaults, `/var/cluster` bootstrapping, recurring timers
  (heartbeat sweep, scheduler tick, status snapshot), and real packet
  handlers for register (with protocol version negotiation), heartbeat,
  result, result-chunk, assign-ack, status-res, and relay-fail. Also wires
  up the pairing subsystem (CLUSTER-6, see below).
- **`lib/cluster/state.lua`** — in-memory state store with write-through
  persistence (atomic tmp+rename), a cooperative lock (`withLock`) for
  CLI↔daemon consistency, full manager/job/assignment CRUD, and an event
  ring buffer for `cluster log`.
- **`lib/cluster/scheduler.lua`** — real weighted scoring (free capacity,
  manager state, storage-preference match, fullness penalty, queue-depth
  penalty, error-rate penalty), compute-bound soft-cap enforcement (§9.1,
  2× margin), and deterministic tie-breaking. Exposes an `_internal` table
  for unit testing.
- **`lib/cluster/jobs.lua`** — job→assignment splitting (size-based
  chunking), dispatch, retry-policy-aware result and timeout handling,
  Manager-offline reassignment, multi-chunk result reassembly, and job
  finalization. Also exposes an `_internal` table for unit testing.
- **`lib/cluster/net.lua`** — send/receive plumbing for every `CLUSTER_*`
  message type, plus `RELAY_FORWARD` unwrap on inbound and reply-side
  re-wrap using a remembered return path (Master-side relay handling;
  see the protocol spec §1.3 for the Manager-side gap).
- **`lib/cluster/api.lua`** — the full CLI↔daemon contract (status,
  managers, jobs, storage, submit, cancel, retry, drain, undrain, forget,
  config, pairing).
- **`lib/cluster/pair.lua`** — a complete HMAC/PBKDF trust-pairing
  subsystem (CLUSTER-6): pairing-code generation, a 5-minute window, and
  `CLUSTER_PAIR_INIT`/`CLUSTER_PAIR_CONFIRM` handling.
- **`cluster.lua`** (CLI) — every subcommand listed in §0.5.5 of the
  protocol spec is implemented, including `cluster pair` and a `watch` TUI
  that's a real auto-refreshing dashboard (managers/jobs/events panels,
  `--interval`/`--events` flags, `q` to quit) — not a stub.

**Still missing / genuinely out of scope here:**

- **Public storage / Storage Node integration.** `state.lua` carries a
  `storage_node` config stub (address/capacity/used/last_seen) but there's
  no `STORE_PUT`/`STORE_LEASE_EXTEND`/`STORE_RELEASE` handling anywhere,
  and no Storage Node module exists in the repo yet (see the protocol
  spec's storage section for the "NOT YET IMPLEMENTED" note).
  **Now designed and largely built.** The Storage Node ships in
  `storage-skeleton/`, and the Master uses it: `lib/cluster/store_client.lua`
  speaks `STORE_PUT`/`STORE_RELEASE`, `jobs.lua` spills oversized task
  slices to `job-<id>/tasks/assignment-<n>` and sends a pointer, and
  `finalizeJob` releases those keys — which is also the job-completion
  signal §5.1's eviction tier 2 needs. `inputs_ref` and
  `result_sink="public"` are still dead fields; see
  [storage-spec-draft.md](storage-spec-draft.md) §9 step 5 for why each
  needs its own change. Design in [storage-spec-draft.md](storage-spec-draft.md): one
  `STORE_*` surface with two back ends — a dedicated node (primary) and a
  distributed pool built from contributed node storage over a new `netfs`
  remote-filesystem proxy (fallback). `jbod.makePool` turns out to be
  fully duck-typed, so a remote member plugs into it unmodified; the catch
  is that JBOD's liveness-dependent write placement diverges on a network
  pool, so the cluster back end derives placement from the §4.6 namespace
  instead. Build order and current progress are §9 there.
- **Dedicated unit tests for state/scheduler/jobs.** Mostly covered now.
  `TOS-Dev/usr/lib/tests/test_cluster_storage_pref.lua` covers the
  storage-preference path end to end — register payload → `state.lua`
  Manager record → heartbeat merge → `scheduler.pickDomain` selection and
  scoring — using the `_internal` table `scheduler.lua` exposes for exactly
  this. `TOS-Dev/usr/lib/tests/test_cluster_jobs.lua` (207 checks) now
  covers `jobs.lua`: splitting, the §4.3 assignment shape, queue ordering,
  dispatch and its rollback, all three retry policies, timeouts,
  Manager-offline redistribution, multi-chunk reassembly and buffer
  sweeping, and finalization. It drives the real `jobs.lua` against the
  real `state.lua` (uninitialized, so in-memory) with a stub net. Writing
  it turned up three shipped bugs, all now fixed and pinned:
  - **`assigned_to` was never cleared on requeue.** All five call sites
    passed `{ assigned_to = nil }`, which in Lua is an *empty table* — the
    key is never created, so `setAssignmentState`'s `pairs()` walk never
    visits it. Pending assignments kept naming the Manager they had just
    been taken off, which is the `MGR` column in `cluster jobs`. Fixed by
    a `state.CLEAR` sentinel that means "delete this key."
  - **A failed send burned a retry attempt.** `dispatch` incremented
    `attempts` before `sendAssignment` and rolled back only the state, so
    a packet that never left the Master spent the job's §8.2
    redistribution budget — two unreachable-Manager sends exhausted a
    `once` job before any Manager had seen it.
  - **Late results overwrote settled assignments.** `onResult` noticed the
    stale case, logged "don't retransition," then retransitioned anyway. A
    duplicate `failed` after a `completed` (§8.6, partition heal) rewrote
    the record *and* ran the retry path, parking the assignment back in
    `pending` inside an already-finalized job — where `pendingAssignments`
    skips it forever, so it could never be dispatched and the job could
    never re-finalize. Now first-writer-wins, with an
    `assignment_result_duplicate` event.

  Still untested: `net.lua`'s relay unwrap/re-wrap and `api.lua`.
  (Separately, `build/test_build_disk.lua` and `build/test_manifests.lua`
  test the packaging/manifest pipeline — a different layer, not this
  domain logic.)
- ~~**A written error-handling convention.**~~ Written, as
  [error-conventions.md](error-conventions.md): the two return shapes
  (`ok, err` and `value, err`), the rule that absence is not failure, the
  three conditions that throw instead of returning, and the ruling that
  `err` is a stable snake_case code with optional detail behind a colon.
  **The code does not conform yet** — §7 of that document is a site-by-site
  audit. `scheduler.lua` and the Manager's `protocol.lua` already do it
  right and are where the convention was taken from; `api.lua`, `state.lua`
  and `jobs.lua` carry ~35 prose strings that need a code prefix.
