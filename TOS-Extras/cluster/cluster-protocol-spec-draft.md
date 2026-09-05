# Cluster Protocol Spec (Draft v0.1)

Companion to the architecture draft. This document defines the wire protocol, trust topology, state machines, and failure semantics for the Master → Manager → Worker cluster with optional Public storage.

**Status:** Draft. Open questions are marked `❓`. Assumptions I've made without asking are marked `⚠️` — flag any you disagree with.

---

## 0. Design principles

These principles govern every decision downstream. When two reasonable options exist, pick the one that better satisfies these.

1. **Automation over operator ritual.** This is Minecraft — operators will forget the cluster exists until it breaks. Any recovery path that requires manual intervention is a future outage. Workers must re-register after reboot with no human involvement. Managers must self-heal after transient outages. Storage must self-garbage-collect. The only operations that legitimately require an operator are the ones that can't be automated without compromising security: first-time trust establishment and destructive changes.

2. **Hierarchical authority, not mesh coordination.** The Master is the single source of truth for scheduling and cluster state. Managers coordinate work only through the Master. Peer-to-peer Manager communication is strictly limited to what's needed for message delivery (relay routing and relay-peer health). No broader gossip without a concrete, designed use case.

3. **Schedule on declared capability, not physical shape.** The Master treats a domain as the capabilities it advertises. Physical layout (M3/M4/M8, rack count, relay topology) is an implementation detail below the scheduling layer.

4. **Fail loudly at the right layer.** Workers fail → Manager notices and requeues. Managers fail → Master notices and redistributes. Master fails → cluster halts gracefully, existing work finishes. No failure is silent; no recovery is the wrong layer's problem.

5. **Data movement prefers pointers over payloads.** When Public storage is available, large data travels by reference. The 6 KB packet ceiling is never routed around with heroic chunking when a scratch tier exists.

---

## 0.5 The Master machine

The Master is the single control-plane node for the cluster. One Master per cluster; no HA in v1.

### 0.5.1 Hardware profile

| Component | Tier / spec | Why |
|---|---|---|
| CPU | T3 | Scheduler and encryption are CPU-sensitive |
| RAM | T3.5 (2× T3 sticks, ~3.6 MB apparent) | Holds full cluster state + job queues + working memory |
| HDD | T3 (4 MB) | Persistent cluster state — Master restarts MUST NOT lose registered Managers |
| GPU + Screen + Keyboard | T3 | Operator console lives here |
| Modems | ≥1 wired, optionally wireless | TOS multi-NIC broadcast supports multiple modems natively |
| Data card | T2+ | Every TRUSTED-level packet is encrypted; Master is the most encryption-heavy node |
| Internet card | optional, not v1 | Future HTTP status endpoint |

Lower specs are possible but not recommended. The scheduler working set scales linearly with `# Managers × # active jobs`, and memory is cheap relative to the debugging cost of running out.

### 0.5.2 Software layout

The Master runs TOS with the cluster software structured as **cooperative services**, not a monolith. This uses TOS's existing `/etc/rc.d/` startup model, cooperative scheduler, and multi-seat support.

| Component | Role | Lifecycle |
|---|---|---|
| `clusterd` | Core daemon: net listener, state store, scheduler, job router | Background service, started by `/etc/rc.d/clusterd.lua` on boot |
| `cluster` CLI | Operator commands (`cluster status`, `cluster submit`, etc.) | Foreground, invoked from shell; talks to `clusterd` via in-process API |
| `cluster-ui` (optional) | TUI dashboard (panels-style tree view of domains, real-time stats) | Foreground, invoked from shell; separate process from CLI |
| TOS net stack | Packet I/O, trust, encryption | TOS kernel (already present) |

### 0.5.3 Daemon ↔ CLI communication

Two complementary mechanisms:

**1. In-process API (hot path, writes and reads that need consistency).** The CLI `require`s the cluster module, which exposes a public API (`cluster.submit(...)`, `cluster.status()`, `cluster.drain(domain_id)`, etc.). Because TOS is cooperatively scheduled, the daemon and CLI share address space within the process; the API functions take a logical lock (a busy flag with yield-until-clear), mutate state, and release. This is the pattern TOS already uses for things like `service start` / `service stop`.

**2. Status snapshot file (read-only inspection, lag-tolerant).** The daemon writes `/var/cluster/status.dat` every 2 seconds with a serialized state snapshot. External readers — remote shells via `rsh`, secondary screens, monitoring scripts — read this file without needing to enter the daemon's process. Stale by up to 2s, which is fine for dashboards and bad for operational commands (those use the API).

### 0.5.4 State model

The Master holds the following in memory, persisted to `/var/cluster/state.dat` on every meaningful change and at clean shutdown:

```lua
cluster.state = {
  managers = {
    -- keyed by Manager modem address
    ["<addr>"] = {
      hostname = "mgr-alpha",
      domain_id = 3,
      profile = "M8",
      worker_count = 8,
      storage = { external_type = "raid", external_capacity = 524288 },
      master_path = "direct",          -- "direct" | "via"
      relay_peer = nil,                -- set if master_path == "via"
      state = "active",                -- active | degraded | draining | offline
      last_heartbeat = <uptime>,
      last_snapshot = { ... },          -- most recent heartbeat payload
      registered_at = <uptime>,
      cluster_protocol = "1.0",
    },
  },
  domain_id_counter = 4,                -- next domain_id to assign

  storage_node = {                      -- nil if no public tier configured
    address = "<addr>",
    capacity = 1048576,
    used = 45000,
    last_seen = <uptime>,
  },

  jobs = {
    [104] = {
      submitted_by = "root",
      submitted_at = <uptime>,
      state = "running",                -- pending | running | completing | done | failed
      compute_profile = "mixed",
      retry_policy = "safe",
      assignments = {
        [17] = {
          domain_id = 3,
          state = "running",            -- pending | running | completed | failed | lost
          dispatched_at = <uptime>,
          deadline = <uptime + 300>,
          result = nil,
          attempts = 1,
        },
      },
      result_sink = "public",           -- "public" | "inline"
    },
  },
  job_id_counter = 105,
  assignment_id_counter = 18,

  -- Runtime-only (not persisted)
  compute_bound_in_flight = 2,          -- for §9.1 soft-cap enforcement
  events = { ... },                     -- ring buffer of recent events, for `cluster log`
}
```

**Persistence strategy:** write-through on mutation, not journaled. This is Minecraft, not a bank; the Master going down and losing the last 500ms of mutations is acceptable. What's NOT acceptable is losing the fact that a Manager exists, so persistence happens synchronously on registration/deregistration/job submission/assignment state changes. Heartbeat updates are in-memory only and rebuilt from the next round of heartbeats after restart.

### 0.5.5 Operator CLI surface

v1 commands, grouped by purpose:

**Inspection (read-only):**
- `cluster status` — one-screen summary: `# Managers by state`, `# jobs active`, storage node status
- `cluster managers` — table of all Managers
- `cluster managers <id>` — detail view (full last heartbeat)
- `cluster jobs` — table of active + recent jobs
- `cluster jobs <id>` — detail view: all assignments, progress, results
- `cluster storage` — public storage tier status

**Job management:**
- `cluster submit <file>` — submit a job from a Lua job-definition file
- `cluster cancel <job_id>`
- `cluster retry <job_id>`

**Manager management:**
- `cluster drain <domain_id>` — mark Manager draining (no new work)
- `cluster undrain <domain_id>`
- `cluster forget <domain_id>` — remove an offline Manager

**Live monitoring:**
- `cluster watch` — TUI dashboard, auto-refreshing

**Operator config:**
- `cluster config` — view/edit Master config (`host_thread_budget`, encryption, etc.)

Each is a thin wrapper around the in-process daemon API. Access tier: `ADMIN` for read commands, `ROOT` for mutating commands (submit, cancel, drain, forget, config).

### 0.5.6 Master failure posture

Per §8.4: Master failure halts scheduling but doesn't kill in-flight work. Managers continue existing assignments and buffer results. On Master restart, state loads from `/var/cluster/state.dat`, Managers re-register (they notice the Master is absent via missed ack to their heartbeats and begin re-announcing), and buffered results flow in. This is the single biggest reason the state file exists — not recovery from Master hardware failure (replace the machine), but tolerance of Master reboots.

---

## 1. Trust topology

The cluster uses an **asymmetric, hierarchical trust graph**. Not everyone trusts everyone — trust follows the control hierarchy.

### 1.1 Trust edges

| Edge | Trust level | Direction | Why |
|---|---|---|---|
| Master ↔ Manager | TRUSTED | bidirectional | Control plane; encrypted, authenticated |
| Master ↔ Storage Node | TRUSTED | bidirectional | Master needs to coordinate storage lifecycle |
| Manager ↔ Storage Node | TRUSTED | bidirectional | Manager writes scratch, reads scratch |
| Manager ↔ configured-relay-peer | TRUSTED | bidirectional | Relay routing + relay-peer health only |
| Manager → own Workers | *out-of-band* | downward | Workers are OpenOS, don't speak TOS protocol |
| Worker → Storage Node (reads) | *unauthenticated* | upward only | Public reads are by definition public |
| Master ↔ Worker | **forbidden** | — | Workers don't know the wider cluster |
| Manager ↔ non-relay Manager | **forbidden** | — | Coordination goes through Master, not laterally |
| Worker ↔ other Workers | **forbidden** | — | No lateral worker comms |

### 1.2 Trust bootstrap

**Master ↔ Manager**: manual first-time pairing through a dedicated code-based handshake — `CLUSTER_PAIR_INIT` / `CLUSTER_PAIR_CONFIRM` (see §3.1.1) — not TOS's generic `TRUST_REQ`/`TRUST_ACK` flow. The operator runs `cluster pair start` on the Master, which opens a 5-minute window and displays a 24-character pairing code; typing that code into `cluster-manager pair <master-addr> <code>` on each Manager derives a shared secret via PBKDF and HMACs the handshake, after which both sides hold each other at TRUSTED. Trust persists after that.

**Manager ↔ Storage Node**: same as Master ↔ Manager. Operator accepts once per pair.

**Manager → Workers**: no TOS trust. Workers are identified by modem address within the Manager's domain. The Manager maintains a per-domain worker list (MAC address → worker ID). New workers register with their Manager over a known port; the Manager either auto-accepts (if in bootstrap mode) or prompts the operator.

⚠️ **Assumption:** Manager bootstrap mode is a time-limited flag (3 minutes after the operator enables it) that auto-accepts any Worker that registers. After the window, new Workers are rejected until the operator re-enables it. This is a compromise between "manually accept each Worker" (tedious) and "always auto-accept" (unsafe).

### 1.3 Relay routing

Not every Manager can reach the Master directly — modem range is finite, wired topologies have physical paths, and large clusters naturally span distances. The spec supports **single-hop and multi-hop relay** via other Managers.

**Path types per Manager:**

- `direct` — this Manager can reach Master itself.
- `via: <peer_address>` — Master-bound traffic is forwarded through this peer (which may itself be `direct` or `via` another peer).

**Forwarding rules:**

1. A Manager with `via` path wraps every Master-bound packet in a `RELAY_FORWARD` envelope, addressed to its relay peer.
2. The inner packet is **already encrypted end-to-end** with the sender's Master secret. Relay peers cannot read contents; they can only forward or drop.
3. Each hop decrements the envelope TTL (default 3). TTL 0 → drop + send `RELAY_FAIL` back.
4. Each hop appends itself to the `path` field. If a Manager sees itself already in `path`, it's a loop — drop + send `RELAY_FAIL`.
5. Reply path is source-routed: the inner packet carries the reverse path, so Master's reply follows the same chain back without Master maintaining routing state.

**What this does NOT mean:** Managers cannot use relay peers for work coordination, data sharing, or scheduling decisions. The relay channel carries exactly two message types (see §3.1): `RELAY_FORWARD` (opaque forwarding) and `PEER_STATUS` (liveness check between relay pairs only). General Manager-to-Manager communication remains forbidden.

**Trust implication:** a Manager must TRUST its relay peer. TRUSTED is required because relay peers decide whether to forward your traffic. They can't read or forge it (end-to-end encryption, Master-signed), but they can drop it. This is acceptable because you, the operator, chose that peer as your gateway.

**v1 configuration:** `master_path` is set in each Manager's local config file (`/etc/cluster.cfg` or similar). Format:

```lua
return {
  master_path = "via",               -- "direct" | "via"
  relay_peer  = "<modem-address>",   -- required if master_path == "via"
}
```

Managers with `direct` paths ignore `relay_peer`. Changes to this config take effect on restart.

⚠️ **Implementation status: relay is currently Master-side-only / half-built, not the full bidirectional scheme described above.** `manager-skeleton/usr/lib/cluster-manager.lua` always sends directly to `master_address` — it never checks a `master_path`/`relay_peer` config, never loads `/etc/cluster.cfg`, and never wraps outbound packets in `RELAY_FORWARD`. (`manager-skeleton/usr/lib/cluster/protocol.lua` *does* implement `/etc/cluster.cfg` loading and relay-envelope processing per the spec above, but nothing in `cluster-manager.lua` calls it yet.) On the Master side, `master-skeleton/lib/cluster/net.lua` correctly unwraps inbound `RELAY_FORWARD` and re-wraps replies using a remembered return path (§4.7's anti-amplification backstops included) — so a relay peer terminating *at* the Master works, but no Manager can currently *originate* relay-routed traffic. Treat everything above as the target design, not current behavior, until Manager-side origination lands.

**v2 direction (not yet designed):** Master-managed auto-discovery. Managers probe nearby peers on startup, report reachability to the Master, and Master computes and pushes routes. Adds message types `RELAY_PROBE` and `RELAY_ROUTE_UPDATE`. See §10.

---

## 2. Channel and port layout

OpenComputers modems are promiscuous within radio range. Port allocation matters because two domains sharing a port will see each other's worker traffic.

### 2.1 Reserved ports

| Port | Purpose | Protocol | Trust required |
|---|---|---|---|
| `2000` | Cluster control plane (Master ↔ Manager ↔ Storage Node) | TOS protocol | TRUSTED |
| `2001 + domain_id` | Manager ↔ Worker traffic within a domain | Raw OC modem, custom framing | none (domain-isolated by port) |
| `2100` | Public storage **reads** | Lightweight non-TOS | none |
| `2101` | Public storage **writes** | TOS protocol | TRUSTED |
| `2000` broadcast | Discovery (`PING`/`PONG`) | TOS protocol | UNKNOWN+ |

❓ **Open:** should `domain_id` be assigned by the Master during registration, or self-chosen by Managers? Master-assigned is safer (no collisions) but requires the Manager to know its ID before opening its Worker port. Chicken-and-egg; I'd lean toward Master-assigned with the Manager using a temporary bootstrap port until it registers.

### 2.2 Why separate read and write ports for storage

- Reads are unauthenticated and handled by a simple request/response loop that doesn't need TOS's trust gate. Serving them on 2100 keeps the read path cheap and means Workers (OpenOS) can hit it with 20 lines of code.
- Writes go through full TOS protocol on 2101 — authenticated, trust-level-gated, optionally encrypted.

---

## 3. Message type extensions

All cluster messages extend `protocol.TYPE`. This requires a TOS protocol version bump.

⚠️ **Assumption:** we extend `protocol.TYPE` rather than wrapping everything in `MSG`. Rationale: type-level validation at the packet gate is valuable, and we're already modifying TOS to support the cluster use case.

### 3.1 New message types

```lua
-- Cluster control plane (Master ↔ Manager)
CLUSTER_REGISTER       -- Manager introduces itself to Master
CLUSTER_REGISTER_ACK   -- Master accepts registration, returns domain_id
CLUSTER_HEARTBEAT      -- Manager status snapshot (periodic)
CLUSTER_ASSIGN         -- Master sends an assignment to a Manager
CLUSTER_ASSIGN_ACK     -- Manager accepts (or rejects) the assignment
CLUSTER_RESULT         -- Manager returns the assignment result
CLUSTER_RESULT_CHUNK   -- One chunk of a multi-chunk result
CLUSTER_CANCEL         -- Master cancels an in-flight assignment
CLUSTER_DRAIN          -- Master asks Manager to stop taking new work
CLUSTER_STATUS_REQ     -- Master queries a Manager out-of-band
CLUSTER_STATUS_RES     -- Manager's reply

-- Trust bootstrap / pairing (Master ↔ Manager, pre-registration)
CLUSTER_PAIR_INIT      -- Manager presents a code-derived HMAC to Master
CLUSTER_PAIR_CONFIRM   -- Master confirms with its own HMAC; both sides TRUSTED

-- Relay routing (Manager ↔ Manager, strictly limited)
RELAY_FORWARD          -- Wrapped Master-bound packet, forwarded by relay peer
RELAY_FAIL             -- TTL exceeded, loop detected, or destination unreachable
PEER_STATUS            -- Relay-peer liveness (heartbeat between configured relay pairs)

-- Public storage (Manager ↔ Storage Node, TOS-protocol path)
STORE_PUT              -- Write key → value
STORE_PUT_ACK          -- Write succeeded, returns lease_id + expiry
STORE_PUT_CHUNK        -- Chunked write (for values > 6KB)
STORE_LEASE_EXTEND     -- Renew TTL on a key
STORE_RELEASE          -- Delete early (revoke lease)
STORE_LIST             -- List keys under a namespace prefix
STORE_ERROR            -- Storage-specific error
```

### 3.1.1 Pairing flow (trust bootstrap)

Implemented in `master-skeleton/lib/cluster/pair.lua` (Master side) and
`manager-skeleton/usr/lib/cluster-manager.lua`'s `mgr.pair()` (Manager
side). Solves the chicken-and-egg problem of "Master and Manager need a
shared secret to talk securely, but they need a secure channel to exchange
the secret" with an out-of-band, operator-relayed code:

1. Operator runs `cluster pair start` on the Master. Master generates a
   24-character high-entropy code (restricted alphabet, ambiguous
   characters like `0`/`O`/`I`/`1` excluded) and opens a 5-minute pairing
   window.
2. Operator types the code into `cluster-manager pair <master-addr> <code>`
   on each Manager. The Manager derives `secret = PBKDF(code,
   "tos-cluster-pair-v1")` (via `kernel.crypto.hashPassword`, domain-
   separated from other TOS secret derivations), sets the Master to
   TRUSTED in its *local* trust DB immediately, then sends
   `CLUSTER_PAIR_INIT` carrying `HMAC(secret, master_addr || timestamp)`.
3. Master verifies the pairing window is open, the peer hasn't already
   paired this window (one-shot per address), and the HMAC matches its own
   derived secret. On success it sets the Manager to TRUSTED with that
   secret and replies with `CLUSTER_PAIR_CONFIRM` carrying its own HMAC.
4. Manager verifies the confirm and considers pairing complete. If the
   confirm is lost in transit, the Manager's local trust DB is already
   correct — the operator can verify with `net trust list` and doesn't need
   to redo the handshake.

After pairing, the normal `CLUSTER_REGISTER` → `CLUSTER_REGISTER_ACK`
handshake takes over with encrypted + MACed transport. CLI surface:
`cluster pair start|status|close` (Master), `cluster-manager pair <addr>
<code>` (Manager). No replay protection beyond per-window freshness is
needed — a captured init from one pairing window can't replay into a
different window because the code (and therefore the derived secret) is
unique per window.

### 3.2 Lightweight read protocol (Worker → Storage Node on 2100)

Workers don't speak TOS protocol. Reads use a minimal framing:

```
Request:  {magic="PUB", op="GET",  key="<namespace>/<name>", req_id=<n>}
Response: {magic="PUB", op="RES",  key="...", req_id=<n>, data=<string|nil>, chunk=<idx>, total=<n>, err=<string|nil>}
Request:  {magic="PUB", op="LIST", prefix="<namespace>/", req_id=<n>}
Response: {magic="PUB", op="LIST_RES", keys={...}, req_id=<n>, err=<nil>}
```

Serialized the same way as TOS packets (kernel.serialize) but without the TOS packet envelope. Storage Node rejects anything without `magic="PUB"` on port 2100. Max message size still 8192 bytes.

### 3.3 Encryption policy

TOS encrypts all TRUSTED-level traffic by default. The cluster protocol allows **selective opt-out** for a small, deliberately-restricted set of message types where the entire payload schema is provably free of job-derived or operator-sensitive content.

**Plaintext-eligible message types** (default: still encrypted, but `enc_opt_out=true` allowed):

| Message type | Why eligible | Schema lock |
|---|---|---|
| `PEER_STATUS` | Pure relay-health metrics; no job content possible | Payload limited to `state`, `master_reachable`, `relay_hops`, `load`. **MUST NOT** be extended with any job/user-derived field. |
| `CLUSTER_HEARTBEAT` | Liveness and capacity metrics; aggregate counters only | Payload limited to fields in §4.2. **MUST NOT** be extended with `current_job_*`, error message strings, exception traces, task content, or any other job-derived data. New fields require encryption review. |

**All other message types are encrypted, no exceptions in v1.**

**Important:** the schema lock is the safety mechanism. Adding a field to a plaintext-eligible message that contains job-derived data (even indirectly — error messages, job IDs paired with content, etc.) violates the contract and reintroduces the leak this discipline is designed to prevent. Any change to these schemas requires a documented review.

**Configuration:** v1 defaults to encryption-on for everything. A future config option will allow per-message-type opt-out for the eligible types above:

```lua
-- Future /etc/cluster.cfg field
encryption = {
  -- Opt out of encryption for performance; only valid for plaintext-eligible types
  plaintext_types = { "PEER_STATUS", "CLUSTER_HEARTBEAT" },
}
```

**Relay envelope special case:** `RELAY_FORWARD` is **inherently mixed** — the outer envelope (`dest`, `path`, `ttl`, `inner_type`) is plaintext because relay peers need to read it for routing. The `inner` field is end-to-end encrypted with the sender's Master secret. This is by design, not an oversight: relay peers are dumb forwarders that cannot decrypt what they carry.

**v1 implementation note:** ship with everything encrypted. Add the opt-out config and benchmark first, then enable selectively if measurements justify it. The schema locks exist *now* so that future opt-out is safe.

### 3.4 Version negotiation

The cluster protocol has its own version, separate from TOS's `protocol.VERSION`. This decouples cluster evolution from TOS releases — you can ship cluster v1.1 without bumping TOS's protocol version, and vice versa.

**Format:** `cluster.PROTOCOL_VERSION = "MAJOR.MINOR"` (e.g., `"1.0"`, `"1.2"`, `"2.0"`).

**Compatibility rule:**

| Master version | Manager version | Result |
|---|---|---|
| Same MAJOR, any MINOR | (either direction) | Compatible. Newer side ignores fields it doesn't recognize. Older side cannot use new features. |
| Different MAJOR | (either direction) | Incompatible. Master rejects with `accepted=false, reason="version_mismatch"`. |

**Forward compatibility:** parsers must silently ignore unknown payload fields. Unknown *message types* are still rejected at the TOS protocol layer (as today). This means new fields are safe to add within a major version; new message types require a minor version bump that older nodes can't use but won't crash on.

**Negotiation flow:**

1. Manager sends `CLUSTER_REGISTER` including `cluster_protocol = "X.Y"`.
2. Master compares to its own `cluster.PROTOCOL_VERSION` and `min_supported_protocol`.
3. If compatible: Master replies with `accepted=true` plus its own version info.
4. If incompatible: Master replies with `accepted=false, reason="version_mismatch"`, including its `master_protocol` and `min_supported_protocol` so the operator/Manager log can show what's needed.
5. Rejected Manager logs the mismatch and stops attempting registration. Operator must update one side or the other.

**Why no auto-upgrade:** OpenComputers has no mechanism for remote software updates. The operator reflashes machines manually. So "fail loudly with a clear error" is the only honest behavior.

**Relationship to TOS protocol version:** TOS's `protocol.VERSION` (currently `1`) governs the packet envelope format (magic bytes, validation, encryption framing). Cluster protocol version governs payload schemas and message-type semantics on top of that envelope. A future TOS protocol version bump (e.g., new envelope format) is independent of a cluster protocol version bump (e.g., new heartbeat fields).

**v1 starting point:** `cluster.PROTOCOL_VERSION = "1.0"`, `min_supported_protocol = "1.0"`.

### 3.5 Worker-side wire format (Manager ↔ Worker, port `2001 + domain_id`)

Implemented (this is no longer an open question — see §11). Manager side:
`manager-skeleton/usr/lib/cluster/worker.lua`. OpenOS side:
`openos/cluster-worker.lua`.

**Framing:** plain Lua table literals, encoded with `kernel.serialize` on
the Manager (TOS) and stock `serialization.serialize` on the Worker
(OpenOS) — both produce the same on-wire representation, so no shared
library is needed. Every frame carries `magic = "WRK"`. Max frame size
8192 bytes; task output is separately capped (5120 bytes in the OpenOS
worker's constants).

**Worker → Manager ops:**

```lua
{ magic="WRK", op="REGISTER", hostname=<s>, capabilities=<t> }
{ magic="WRK", op="RESULT",   task_id=<n>, status=<s>, output=<s>, err=<s|nil> }
{ magic="WRK", op="PROGRESS", task_id=<n>, progress=<0..1>, msg=<s> }
{ magic="WRK", op="PONG",     time=<n> }
```

**Manager → Worker ops:**

```lua
{ magic="WRK", op="REGISTER_ACK", worker_id=<n>, accepted=<b>, reason=<s|nil> }
{ magic="WRK", op="TASK",         task_id=<n>, code=<s>, inputs=<t>, timeout=<n> }
{ magic="WRK", op="CANCEL",       task_id=<n> }
{ magic="WRK", op="PING",         time=<n> }
```

**Authentication (#SEC H21/H2/CR-3):** every frame carries `nonce` and
`mac` fields. `mac = HMAC-SHA256(shared_secret, canonicalFrame(frame))`,
where `canonicalFrame` sorts keys and length-prefixes every scalar so both
sides agree on the byte sequence to MAC despite Lua's non-deterministic
`pairs()` order — the MAC covers the *whole* frame (not just
`op||task_id||nonce`), so payload/result fields can't be tampered with
past the check. The shared secret is configured on both sides
(`worker_bridge_secret` in `/etc/cluster-manager.cfg`, `shared_secret` in
`/etc/cluster-worker.cfg`; 16+ bytes) and must match exactly. Receivers
keep a bounded ring buffer of accepted nonces (`seenNonces`) and silently
drop frames with a missing/malformed nonce, a bad MAC, or a replayed
nonce.

**Bootstrap:** new Worker addresses are only accepted during a
configurable bootstrap window after Manager start (`worker_bridge_bootstrap`
in `/etc/cluster-manager.cfg`, default 180s, matching the Worker
bootstrap window in §1.2/§7). After the window closes, only
already-registered Worker addresses are serviced — this mirrors §1.2's
Manager→Worker bootstrap-mode design, applied at the Manager↔Worker-bridge
layer.

**Lifecycle:** matches §6.2 (Worker lifecycle). A Worker that misses its
task deadline yields a synthetic `"timeout"` result on the Manager side so
an assignment never hangs on a dead Worker.

---

## 4. Payload schemas

All payloads are Lua tables. The 6 KB effective limit (8192 − TOS envelope − encryption overhead) governs what fits in one packet. Anything larger must be chunked or written to Public storage and referenced.

### 4.1 Manager registration

```lua
-- CLUSTER_REGISTER (Manager → Master)
{
  hostname      = "mgr-alpha",
  profile       = "M8",          -- "M3" | "M4" | "M8" | custom
  worker_count  = 8,
  storage       = {
    external_type     = "raid",  -- "raid" | "tape" | "floppy" | "drive" | "none"
    external_capacity = 524288,  -- bytes
  },
  has_console   = true,
  compute_capable = true,           -- is the Manager itself available for opportunistic compute
  cluster_protocol = "1.0",         -- cluster protocol version (see §3.4)
  software_version = "1.0.0",       -- this Manager's build version
}

-- CLUSTER_REGISTER_ACK (Master → Manager)
{
  accepted   = true,                -- false = rejected, see reason
  reason     = nil,                 -- "version_mismatch" | "trust_required" | "duplicate_hostname" | nil
  domain_id  = 3,                   -- assigned by Master (only if accepted)
  worker_port = 2004,               -- 2001 + domain_id
  heartbeat_interval = 5,           -- seconds
  master_protocol = "1.0",          -- Master's cluster protocol version
  min_supported_protocol = "1.0",   -- minimum protocol version Master accepts
}
```

### 4.2 Heartbeat

Must fit comfortably in one packet. Target: <1 KB.

```lua
-- CLUSTER_HEARTBEAT (Manager → Master, every 5s)
{
  domain_id       = 3,
  state           = "active",     -- "active" | "degraded" | "draining"
  workers_total   = 8,
  workers_active  = 7,            -- responsive to heartbeats
  workers_busy    = 5,            -- currently executing a task
  queue_depth     = 12,
  assignments_running = {17, 18}, -- assignment_ids
  compute_capable = true,         -- false = opportunistic rule is currently off
  storage_used    = 0.34,         -- 0.0–1.0 of external capacity
  external_type   = "raid",       -- declared storage type; omitted if none
  errors_last_min = 0,
  uptime          = 12847,
}
```

**Schema-lock review — `external_type`.** §3.3 locks this payload and requires
a documented review for new fields. `external_type` passes: it is a static
hardware capability declared in `/etc/cluster-manager.cfg` (`storage_type`),
identical on every heartbeat, and carries no job-derived, operator-sensitive,
or content-bearing data — it is the same class of fact as `workers_total`. It
is present so a Manager that gains or loses external storage converges without
a re-register; the Master folds it into the Manager record that §9's
storage-preference matching reads. It must NOT be extended into a
per-job storage descriptor — that would be job-derived and would break the lock.

### 4.3 Assignment

```lua
-- CLUSTER_ASSIGN (Master → Manager)
{
  assignment_id = 17,
  job_id        = 104,
  priority      = 5,              -- 0 (low) – 9 (urgent)
  deadline      = 1700001234,     -- unix time, 0 = no deadline
  retry_policy  = "safe",         -- "safe" (idempotent) | "once" | "none"
  compute_profile = "mixed",      -- "compute_bound" | "io_bound" | "mixed" (default)
                                  -- see §9.1 for scheduling implications
  
  -- Tasks: either inline (if small) or a reference to Public storage
  tasks_inline  = { ... },        -- list of task descriptors, if fits
  tasks_ref     = nil,            -- OR "public://job-104/tasks/assignment-17"
  
  -- Inputs: same pattern
  inputs_inline = { ... },
  inputs_ref    = nil,
  
  -- Result handling
  result_sink   = "inline",       -- "inline" (chunk back over wire)
                                  -- | "public" (write result to Public, return ref)
  result_prefix = "public://job-104/results/",  -- if sink="public"
}
```

`tasks_ref` / `inputs_ref` are the escape hatch for large assignments: Master writes them to Public storage first, sends a pointer, Manager fetches.

### 4.4 Result

```lua
-- CLUSTER_RESULT (Manager → Master, single-packet case)
{
  assignment_id = 17,
  status        = "ok",            -- "ok" | "partial" | "failed" | "cancelled"
  output_inline = { ... },         -- if fits
  output_ref    = nil,             -- OR "public://job-104/results/17"
  errors        = {},              -- per-task errors, if any
  stats         = {
    tasks_total   = 40,
    tasks_ok      = 39,
    tasks_failed  = 1,
    duration_ms   = 4821,
  },
}

-- CLUSTER_RESULT_CHUNK (Manager → Master, for >6KB inline results)
{
  assignment_id = 17,
  chunk_idx     = 2,
  chunk_total   = 5,
  data          = "<serialized fragment>",
  final_stats   = nil,             -- set on last chunk only
}
```

⚠️ **Assumption:** chunked inline results are supported but discouraged. If a Manager produces >6 KB of output it should prefer writing to Public (when Public exists) and returning a pointer. Chunking is the fallback when Public isn't available.

> ⚠️ **PARTLY IMPLEMENTED (was: not at all).** A Storage Node now exists —
> `storage-skeleton/` implements §4.5's operations, §4.6's namespace
> enforcement (via the Manager's own `canWrite`, shared not copied), §5's
> TTL and lease semantics, and §5.1's eviction minus tier 2, which needs a
> job-completion signal the node cannot have. What is still design-only is
> the *distributed* back end and any Master-side use of `tasks_ref` /
> `inputs_ref` / `result_sink="public"`, which remain dead fields in
> `jobs.lua`. See
> [storage-spec-draft.md](storage-spec-draft.md) for who is meant to
> *answer* these messages — a dedicated Storage Node, or a distributed
> pool of contributed node storage — and note that §4.6's namespace table
> below turns out to double as the distributed back end's placement rule. There is no Storage Node module anywhere
> under `TOS-Extras/cluster/` (only `master-skeleton/`, `manager-skeleton/`,
> `openos/`, and `installer/` exist). `master-skeleton/lib/cluster/state.lua`
> carries an unvalidated `storage_node` config stub (address/capacity/used/
> last_seen) and nothing else; `manager-skeleton/usr/lib/cluster/protocol.lua`
> implements the read side only (`pubGet`, `pubList`, `validatePubRequest` —
> §3.2's lightweight GET/LIST protocol). `STORE_PUT`, `STORE_LEASE_EXTEND`,
> `STORE_RELEASE`, and the write path in general do not exist yet.

### 4.5 Public storage operations

```lua
-- STORE_PUT (Manager → Storage Node)
{
  key      = "domain-3/scratch/partial-17",  -- must be under writer's namespace
  data     = "<serialized value>",            -- ≤ ~5 KB
  ttl      = 3600,                            -- seconds; 0 = use default
  overwrite = false,                          -- false = fail if exists
}

-- STORE_PUT_ACK (Storage Node → Manager)
{
  key       = "domain-3/scratch/partial-17",
  lease_id  = "a3f9b1",                       -- opaque, needed for extend/release
  expires_at = 1700004834,                    -- unix time
  size_bytes = 4821,
}

-- STORE_LEASE_EXTEND (Manager → Storage Node)
{
  key       = "domain-3/scratch/partial-17",
  lease_id  = "a3f9b1",
  extend_by = 3600,                           -- seconds to add from now
}

-- STORE_RELEASE (Manager → Storage Node)
{
  key       = "domain-3/scratch/partial-17",
  lease_id  = "a3f9b1",                       -- must match; prevents accidental deletes
}
```

### 4.6 Namespace rules

Keys have the form `<namespace>/<path>`:

| Namespace | Who can write | Who can read | Lifecycle |
|---|---|---|---|
| `job-<id>/...` | Master, or Manager currently assigned work for job | everyone | auto-delete when job completes |
| `domain-<id>/...` | only the owning Manager | everyone | auto-delete when Manager goes offline > 5 min |
| `shared/...` | only the Master | everyone | manual only |

Writes to a namespace you don't own return `STORE_ERROR` with `reason="namespace_denied"`.

**Convention for assignment task lists and results:** Master always writes assignment task lists and collected results to `job-<id>/` rather than `domain-<id>/`. This decouples assignment storage from Manager liveness — if a Manager dies mid-assignment, the task list survives in `job-<id>/` and Master can redistribute to a replacement Manager without copying. Concretely:

- `job-<id>/tasks/assignment-<n>` — task list for assignment N (written by Master)
- `job-<id>/results/assignment-<n>` — collected result (written by Master after Manager returns it)
- `domain-<id>/scratch/...` — Manager's own intermediate scratch, never assignments or final results

This means even successful single-attempt assignments leave their task list in Public for the job's duration. Cost is small (task lists fit in a single packet) and the benefit (free redistribution on failure) is worth it.

### 4.7 Relay envelope and peer status

```lua
-- RELAY_FORWARD (Manager A → relay peer B)
{
  dest       = "<master-addr>",       -- final destination
  path       = {"<A-addr>"},          -- hops traversed (sender first)
  ttl        = 3,                     -- decrement at each hop
  inner      = "<serialized packet>", -- end-to-end encrypted for dest
  inner_type = "CLUSTER_HEARTBEAT",   -- hint for relay logging; NOT authoritative
}

-- On each hop B:
--   if self in path        → drop + RELAY_FAIL (loop)
--   if ttl <= 0            → drop + RELAY_FAIL (exceeded)
--   if dest unreachable    → RELAY_FAIL
--   else: append self to path, decrement ttl, forward toward dest

-- RELAY_FAIL (reverse path → original sender)
{
  reason     = "loop",                -- "loop" | "ttl_exceeded" | "unreachable" | "peer_down"
  failed_at  = "<addr-that-failed>",
  original_dest = "<master-addr>",
  original_inner_type = "CLUSTER_HEARTBEAT",
}

-- PEER_STATUS (between configured relay pairs, every 10s)
{
  state          = "active",          -- "active" | "degraded" | "draining"
  master_reachable = true,            -- can this peer currently reach Master?
  relay_hops     = 0,                 -- 0 if direct, else # of hops to Master
  load           = 0.3,               -- 0.0–1.0, relay forwarding load
}
```

**Reply routing:** when Master replies to a relay-originated packet, it reads `path` from the original `RELAY_FORWARD` and uses its reverse as the return path. Master does not keep routing state; each reply is independently source-routed. If the return path is broken, the reply is lost — the Manager's normal timeout/retry handles it.

**Anti-amplification backstops (#SEC H-18):** implemented in `manager-skeleton/usr/lib/cluster/protocol.lua`. On the forwarding path (not on delivery to self), every relayed envelope is checked against two backstops before being forwarded: a **dedup window** — a payload already forwarded within `cluster.TIMING.RELAY_SEEN_TTL` (30s) is dropped as `"duplicate"` regardless of what `path`/`ttl` now claim — and a **per-upstream-peer rate limit** — at most `cluster.TIMING.RELAY_RATE_MAX` (30) forwards per peer per `cluster.TIMING.RELAY_RATE_WINDOW` (10s), beyond which forwards are dropped as `"rate_limited"`. Both live in `cluster.protocol`'s `TIMING` table alongside the other cadence constants in §7.

**Encryption note:** `inner` is encrypted with the sender's (A's) Master secret before wrapping. Relay peer B has no key to decrypt it; B can only forward or drop. `inner_type` is included as a plaintext hint for relay-side logging and metrics, not for authorization decisions.

---

## 5. TTL and lease semantics

- **Default TTL on write:** 1 hour (3600s).
- **Max single lease:** 24 hours (86400s). A `STORE_LEASE_EXTEND` that would push `expires_at` beyond 24h from *now* is clamped to 24h.
- **Unlimited extensions.** You can keep renewing indefinitely — the cap is on any single lease window, not cumulative lifetime.
- **Expiry is best-effort.** The Storage Node runs a sweep every 60s; expired keys are deleted then, not instantaneously.
- **Release is immediate.** `STORE_RELEASE` deletes on the next event loop tick.
- **Reads during sweep window:** a key whose `expires_at` has passed but that hasn't been swept yet may still return data. Readers must handle "not found" on retry anyway, so this is benign.

### 5.1 When things get evicted

Priority order when space is tight:
1. Expired keys (past `expires_at`)
2. Keys in `job-<id>/` namespaces where the job has completed
3. Least-recently-accessed keys, oldest first

The Storage Node never evicts a key whose lease is current, *unless* the RAID is actually full. In that state `STORE_PUT` returns `STORE_ERROR` with `reason="out_of_space"` and the writer must retry or give up.

---

## 6. State machines

### 6.1 Manager lifecycle (Master's view)

```
  unregistered ──[CLUSTER_REGISTER accepted]──> active
                                                   │
                                                   ├─[missed 3 heartbeats (15s)]──> degraded
                                                   │                                    │
                                                   │<─[heartbeat resumes]───────────────┘
                                                   │
                                                   ├─[CLUSTER_DRAIN sent]────────> draining
                                                   │                                    │
                                                   │                                    └─[all assignments done]─> offline
                                                   │
                                                   └─[missed heartbeats for 30s]──> offline
```

- **active:** normal operation, accepting assignments.
- **degraded:** Master keeps the Manager in the scheduler but deprioritizes it; in-flight assignments continue.
- **draining:** no new assignments, in-flight ones finish or time out.
- **offline:** removed from scheduler. In-flight assignments are marked lost. Workers are considered unreachable.

### 6.2 Worker lifecycle (Manager's view)

```
  unknown ──[register msg]──> idle ──[task dispatched]──> busy
                                 ^                          │
                                 │                          ├─[result returned]───┘
                                 │                          │
                                 │                          └─[task_timeout]──> failed ──[retry or remove]─> idle | removed
                                 │                          
                                 └──[missed 2 heartbeats]── (probing) 
```

Workers heartbeat implicitly: every task result is an implicit "alive" signal. Between tasks, Managers ping idle workers every 10s. Two missed pings → worker marked unresponsive.

### 6.3 Assignment lifecycle (Manager's view)

```
  received ──[accepted]──> queued ──[dispatch]──> running ──[all tasks done]──> completing
     │                        │                     │                              │
     │                        │                     ├─[CLUSTER_CANCEL]──> cancelled
     │                        │                     │
     │                        │                     └─[deadline exceeded]──> timed_out
     │                        │
     └─[rejected]──> done    └─[CLUSTER_DRAIN]──> drained (still processes what it has)
```

---

## 7. Timeouts and cadences

| Event | Interval / timeout | Notes |
|---|---|---|
| Manager → Master heartbeat | every 5s | configurable per Manager via register ack |
| Master marks Manager degraded | 15s without heartbeat | 3 missed intervals |
| Master marks Manager offline | 30s without heartbeat | 6 missed intervals |
| Manager → Worker ping | every 10s for idle workers | only when idle; busy workers heartbeat via progress |
| Manager marks Worker unresponsive | 2 missed pings (~20s) | |
| Task timeout | per-task, default 60s | set by Manager based on task size |
| Assignment timeout | per-assignment, default 300s | from Master's `deadline` field |
| Trust request pending | 5 min | then auto-expires |
| Public storage sweep | every 60s | expired keys deleted here |
| Public storage default TTL | 3600s (1 hour) | overridable per write |
| Public storage max lease | 86400s (24 hours) | per single extension |
| Manager bootstrap mode window | 180s (3 min) | auto-accept new Workers during this window |
| Relay peer `PEER_STATUS` | every 10s | between configured relay pairs |
| Relay peer considered down | 3 missed `PEER_STATUS` (~30s) | Manager triggers `master_path` reassessment |
| Relay envelope TTL | 3 hops default | prevents loops in misconfigured topologies |

⚠️ **Assumption:** these are starting points. They should be empirically tuned once you see real load.

---

## 8. Failure semantics

What's lost vs. recovered at each failure class.

### 8.1 Worker fails mid-task
- **Recoverable.** Manager's ping loop notices within 20s, marks worker failed.
- Task is requeued if `retry_policy != "none"`; otherwise marked failed in assignment stats.
- Task output (partial) is discarded.

### 8.2 Manager fails mid-assignment
- **Partially recoverable.** Master notices within 30s (missed heartbeats).
- In-flight assignments: 
  - If `retry_policy == "safe"`: Master redistributes to another domain.
  - If `retry_policy == "once"`: redistributed once, then gives up.
  - If `retry_policy == "none"`: marked failed, reported to user.
- Workers in the dead domain stop receiving tasks; they sit idle until Manager returns.
- `domain-<id>/` Public storage is retained for 5 min, then swept (Manager might come back).

### 8.3 Storage Node fails
- **Public tier unavailable.** Detected by timeout on next STORE_* operation.
- Managers fall back to either (a) External storage if job allows, or (b) chunked inline transfer through Master.
- Jobs that depend on Public refs currently in flight may fail or stall.
- Master can mark the cluster as `degraded: no_public_storage` and surface this to the operator.

### 8.4 Master fails
- **Coordination lost.** Managers notice via lack of assignments.
- In-flight assignments continue to completion. Results are buffered at the Manager.
- No new jobs until Master returns. Managers go into a "limbo" state: alive, responsive to heartbeat attempts, but taking no new work.
- On Master return: Managers re-register, replay buffered results.

### 8.5 Relay peer fails
- **Detection.** Managers monitor relay peers via `PEER_STATUS`; 3 missed status messages (~30s) mark the peer down.
- **Consequence.** A Manager whose `via` path is broken cannot reach the Master. From the Master's side, this is indistinguishable from the Manager itself failing — it stops heartbeating, goes degraded then offline.
- **Recovery options:**
  - If Manager has a configured fallback relay peer, switch to it.
  - If no fallback: Manager enters limbo (same as §8.4 Master failure, from its perspective).
  - ⚠️ **Known limitation:** v1 supports only one configured relay per Manager. Fallback requires either operator intervention (edit config, restart Manager) or the v2 auto-discovery feature.
- **Fail-storm note:** a relay peer failing cascades to all Managers that route through it. The Master will see multiple Managers go offline simultaneously. The Master's failure reporting should distinguish "likely single relay failure" (cluster of offlines sharing an upstream) from "actual multi-Manager outage" — or at minimum log enough context that the operator can tell the difference.

### 8.6 Network partition
- **Temporary.** Handled by the same timeouts as individual failures. If a Manager is unreachable for 30s, it's offline; when the partition heals, the Manager re-registers fresh.
- ⚠️ **Known gap:** during a partition, both sides of the partition may assume the other is offline. If the Master is on one side and a Manager on the other, the Manager goes limbo and the Master reassigns its work. When the partition heals, results from both attempts arrive. Master should dedupe by `assignment_id` and accept whichever result arrives first.

---

## 9. Scheduler inputs (updated)

The Master's scheduler, per assignment, evaluates each registered Manager on:

| Input | Source | Weight |
|---|---|---|
| `workers_active - workers_busy` (free capacity) | heartbeat | high |
| `state` (`active` > `degraded`; reject `draining`/`offline`) | heartbeat | gating |
| `storage.external_type` vs job's declared preference | register | medium |
| `storage_used` (avoid >90% full domains) | heartbeat | medium |
| `queue_depth` (prefer lighter queues) | heartbeat | medium |
| `errors_last_min` (penalize flapping domains) | heartbeat | low |
| Data locality: job inputs already in this domain's `domain-<id>/` namespace | known at scheduling time | low (optional, v2) |

### 9.1 Compute throughput ceiling (host-thread budget)

OpenComputers schedules Lua execution across a fixed pool of JVM worker threads, set by the server's `opencomputers.computer.threads` config value (default: `4`). At any instant, only that many OC computers across the entire world are executing Lua — everything else is queued by the mod.

**Implication for scheduling:** for **compute-bound** tasks (tasks that saturate their call budget with arithmetic/serialization work rather than waiting on components or I/O), scheduling more simultaneous tasks than the host's thread count adds latency without adding throughput. For **I/O-bound** tasks (waiting on modem, robot ticks, redstone, filesystem), thread count is a much weaker constraint — waiting tasks don't consume threads.

**Configurable budget:** the Master has a config field `host_thread_budget` that declares how many compute-bound tasks can usefully run in parallel across the cluster. Defaults to `4` (matching the OC default). Operators with modified `opencomputers.computer.threads` should set this to match.

```lua
-- /etc/cluster-master.cfg
return {
  host_thread_budget = 4,   -- match opencomputers.computer.threads on the host
  -- ...other Master config...
}
```

**Job-level hint:** assignments carry a `compute_profile` field so the scheduler knows which ceiling applies:

```lua
-- In CLUSTER_ASSIGN payload (addition to §4.3)
compute_profile = "io_bound",   -- "compute_bound" | "io_bound" | "mixed"
```

**Scheduling rule:**

- For `compute_bound` assignments, the Master tracks cluster-wide concurrent compute-bound task count and soft-caps at `host_thread_budget`. Tasks beyond that queue at the Master until a slot frees.
- For `io_bound` or `mixed` assignments, the cap doesn't apply — dispatch as capacity allows.
- The cap is a **soft limit**: if an operator submits `compute_profile=compute_bound` but the cluster has idle capacity, the Master may exceed the cap by a small margin (up to 2× is a reasonable implementation default) to avoid wasting workers.

**Why soft and configurable:** hard-coding `4` would be wrong on any server with tuned `opencomputers.computer.threads`. Making it a hard limit would cause counter-intuitive behavior when the operator expects a cluster with 20 workers to use all 20. The soft-cap + explicit profile keeps the scheduler honest without being surprising.

⚠️ **Assumption:** most submitters won't correctly tag their jobs. Default `compute_profile` when not specified is `"mixed"` — no thread-budget enforcement. Getting the speedup requires opting in. This matches how thread-pool sizing works in most real systems and avoids penalizing users who don't know about the knob.

---

## 10. What's deliberately out of scope for v1

- **Multiple Storage Nodes.** v1 is 0 or 1. Sharding keys across nodes is v2.
- **Master HA / failover.** Single Master, single point of failure by design.
- **Cross-domain task migration.** Once an assignment lands on a Manager, it stays there until complete, cancelled, or failed.
- **Priority preemption.** Higher-priority jobs don't kick lower-priority ones off workers; they queue.
- **Workers as TOS nodes.** Workers stay OpenOS. If you ever want encrypted Worker traffic or Worker → Master comms, that's a separate design.
- **Public storage replication.** Data on the Storage Node is single-copy. RAID handles disk-level redundancy; the cluster doesn't.
- **Relay auto-discovery.** v1 uses operator-configured `master_path` per Manager. v2 will add Master-managed topology discovery via `RELAY_PROBE` / `RELAY_ROUTE_UPDATE`, allowing Managers to learn routes automatically and fail over between relay peers without operator intervention. This is the principled long-term answer to the automation principle (§0) for relay — v1 ships the simple version first.
- **Multiple relay paths per Manager.** Related to the above. v1 = single `relay_peer`. Fallback routing is v2.

---

## 11. Open questions

No `❓` items remain unresolved as of this draft — see below and §3.5.

### Resolved since previous draft

- ~~Worker → Manager protocol on port `2001 + domain_id`~~ → implemented:
  `magic="WRK"` table-literal frames (`kernel.serialize` / OpenOS
  `serialization.serialize`, same on-wire shape), HMAC-SHA256 authenticated,
  nonce-based replay protection. Fully specified in §3.5.

- ~~Domain ID assignment~~ → hybrid: Manager uses a temp bootstrap ID until registration, Master issues the official `domain_id` in `CLUSTER_REGISTER_ACK`.
- ~~Bootstrap mode for Workers~~ → time-limited window, 3 minutes.
- ~~Chunked inline results vs. Public refs~~ → cascade: prefer Public when available, fall back to External, chunked inline as last resort when neither exists.
- ~~Relay path configuration~~ → operator-configured per Manager in v1 via local config file. Master-managed auto-discovery deferred to v2 (see §10).
- ~~Relay fallback paths~~ → single `relay_peer` in v1; multiple paths and automatic failover deferred to v2.
- ~~Assignment retry storage~~ → Master always writes to `job-<id>/`, never `domain-<id>/`. See §4.6 convention note.
- ~~Encryption for cluster control~~ → selective opt-out allowed for `PEER_STATUS` and `CLUSTER_HEARTBEAT` only, with hard schema locks. v1 ships encrypted-everywhere, opt-out is a future config knob. See §3.3.
- ~~Version negotiation~~ → separate `cluster.PROTOCOL_VERSION`, semver-style major/minor compatibility, hard reject on major mismatch. See §3.4.

---

## 12. Next drafts

- ~~**Worker-side wire format**~~ → done, see §3.5.
- ~~**Operator tooling**~~ → done; `cluster status`, `cluster submit <job>`,
  `cluster drain <domain>`, and the rest of §0.5.5's surface are implemented
  in `master-skeleton/cluster.lua`. See `cluster/Plan.md`'s "Current status"
  section for the full built/missing breakdown.
- **Storage Node reference implementation** — still genuinely open. Nothing
  under `TOS-Extras/cluster/` implements the Storage Node's request handler
  or the `STORE_*` write path (§4.5's "NOT YET IMPLEMENTED" banner). The
  Master's and Manager's scheduler loop / state machine are implemented
  (see `cluster/Plan.md`), so this is the one piece of the original v1
  reference-implementation list still to write.
