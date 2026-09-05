# AI Operator Spec (Draft v0.1)

> **Scope:** this document specifies the `ai-operator` add-on — a
> language-model agent that observes cluster state and drives the Master's
> operator surface through a fixed verb whitelist, plus an optional
> `reactor-guard` module for supervisory control of a modded reactor.
> It extends [cluster-protocol-spec-draft.md](cluster-protocol-spec-draft.md)
> and assumes its trust topology (§1), port layout (§2) and message-type
> conventions (§3). Nothing here is implemented. Every section is design.

---

## 0. Design principles

1. **The agent proposes; TOS disposes.** The model never executes anything.
   It emits an *intent* — a verb from a closed set plus typed arguments — and
   a small, deterministic, auditable module decides whether that intent runs.
2. **The whitelist is the security boundary, not the prompt.** No instruction
   in a system prompt is load-bearing. If the only way to say a thing is
   absent from the verb table, the model cannot say it, however it is asked.
3. **No model-authored code, ever.** Not Lua, not addresses, not hostnames,
   not URLs. Model output that reaches the machine is a verb name and a set
   of scalars that pass a validator.
4. **The control plane holds no internet card.** Network egress lives on one
   dedicated machine that is in the compute pool for nothing.
5. **Latency-honest control.** A model round trip is 5–60 s. Anything whose
   failure mode is faster than that is owned by deterministic code, and the
   agent is only allowed to move its setpoint.
6. **Every action is in the log with a name on it.** `cluster log` must be
   able to answer "did a human do this, or did the agent?" without ambiguity.

---

## 0.5 What "in Minecraft" means here

The agent's weights run on real hardware, off the game server. This does not
make it less confined than any other OC program, and it is worth writing down
precisely why, because the claim is easy to overstate.

**What is confined.** The agent's *effects* are exactly the set of verbs
`ai-exec` will dispatch. Its *observations* are exactly the state digest
`ai-exec` chooses to emit. Both ends are enumerable, both are enforced by
TOS's capability sandbox rather than by convention, and `pkg info ai-operator`
is an honest record of the set. This is a stronger containment story than the
usual "agent plays Minecraft" arrangement, where the agent process runs on the
host with an ordinary OS account and the confinement is a habit rather than a
mechanism.

The right analogy is a player. A player's cognition also runs on hardware
outside the game; what makes them a participant rather than an administrator
is that their effects are mediated by an avatar with defined affordances. The
harness is the agent's avatar.

**What is not confined, stated plainly:**

- **The proxy is a real process on a real machine** with real network and
  real filesystem access. The agent's I/O is confined; the thing computing
  its next token is not. §5 therefore specifies the proxy as a deliberately
  stupid component: fixed model endpoint, fixed template directory, no
  ability to act on anything the model asks it to do.
- **Prior knowledge is not confined.** The model knows what an RBMK is and
  how Lua works before it is switched on. This is fine — it is an operator
  who has read the manual — but it means containment is a property of the
  I/O surface, not of what the thing knows.
- **An internet card anywhere the agent can reach voids the whole scheme.**
  This is the sharpest edge and it is not hypothetical, because §1.2 puts an
  internet card on the uplink box by design. See §1.4.

---

## 1. Topology

### 1.1 Components

| Component | Machine | Capabilities | Role |
|---|---|---|---|
| `aid` | uplink box | `internet`, `net`, `fs.read`, `fs.write` | HTTP client to the proxy. Holds conversation state. Never touches `cluster.api`. |
| `ai-exec` | Master | `net` + `require("cluster.api")` | Validates and dispatches intents. The security boundary. **No `internet`.** |
| `ai` | any TOS box | `net` | Operator chat client. A persistent tab, like `chat` (§4.1 of the Manual). |
| `reactor-guard` | adapter box | `peripheral.reactor`, `net` | Deterministic interlocks. Owns SCRAM. Optional. |

Four packages, not one, because they have four different capability sets and
a single manifest would have to request the union of them. The union is
precisely the thing this design exists to avoid.

### 1.2 Why not on the Master

The Master is the obvious home and it is the wrong one:

- **Slots.** §0.5.1 of the protocol spec already wants a T3 GPU, ≥1 modem and
  a T2+ data card. Adding an internet card may force a server chassis, and
  the spec lists that card as "optional, not v1" for exactly this reason.
- **Per-tick budget.** Ch. 1 of the Manual is explicit that a computer has
  one CPU and one shared call budget. An agent poll loop on the Master
  competes with the scheduler tick, the heartbeat sweep and the 2 s status
  snapshot — the three latencies the cluster's correctness rests on.
- **Posture.** The control plane is the machine you took the most trouble to
  isolate. Putting the only internet-facing card on it inverts that for a
  feature that is, by design, optional.

With `aid` elsewhere, the Master can carry `deny = { ["*"] = { "internet" } }`
in `/etc/pkg_caps.cfg` and mean it: no package on the control plane can reach
the network, now or after any future install.

### 1.3 Trust edges (extending protocol spec §1.1)

| Edge | Trust level | Direction | Why |
|---|---|---|---|
| uplink ↔ Master | TRUSTED | bidirectional | Intents and results; MAC + nonce + replay from the TOS stack |
| uplink ↔ `ai` client | TRUSTED | bidirectional | Operator utterances and model replies |
| Master ↔ `reactor-guard` | TRUSTED | bidirectional | Setpoint requests, guard status, alerts |
| uplink ↔ `reactor-guard` | **forbidden** | — | The agent reaches the reactor only through `ai-exec`'s gate |
| uplink ↔ any Manager | **forbidden** | — | The uplink box is not in the cluster |
| uplink ↔ any Worker | **forbidden** | — | ditto |

Pairing reuses the existing `CLUSTER_PAIR_INIT` / `CLUSTER_PAIR_CONFIRM`
flow (§3.1.1). No new bootstrap mechanism; no auto-discovery, for the reason
given in the cluster README — a "who's out there?" broadcast lets whoever
answers first become your gateway.

### 1.4 The uplink box is not a Manager

**Do not install `cluster-manager` on the uplink box.** §3.5 assignments
carry `code = <s>` — Lua source, executed on the assignee. A Manager on the
same machine as the internet card means any job the cluster schedules there
runs next to network egress. The uplink box joins nothing, runs `aid` and the
base image, and has `cluster-manager` in `conflicts` if `ai-operator` ever
ships as a package with dependencies declared.

Corollaries, all of them things that void containment if missed:

- `aid`'s endpoint URL comes from `/etc/ai-uplink.cfg` and nowhere else. It is
  never taken from model output, an intent argument, or a response body.
- The agent cannot trigger `pkg fetch`, `pkg repo add`, or `internet get`.
  §7.6 of the Manual is right that adding a repo is a standing decision about
  where executable code comes from; that decision is not delegable to a model.
- `internet off` on the uplink box is the whole-system kill switch and should
  be the first thing an operator reaches for.

---

## 2. Channel and port layout

### 2.1 Reserved port

| Port | Purpose | Protocol | Trust required |
|---|---|---|---|
| `2200` | AI plane (uplink ↔ Master ↔ client ↔ guard) | TOS protocol | TRUSTED |

One port, separate from `2000`, so that a misconfigured agent cannot put
traffic on the cluster control plane at all — and so that an operator
sniffing one plane is not reading the other.

### 2.2 New message types (extending §3.1)

```lua
-- Operator conversation (client ↔ uplink)
AI_UTTER            -- operator's message to the agent
AI_REPLY            -- agent's text reply (may be chunked)
AI_REPLY_CHUNK      -- one chunk of a multi-chunk reply

-- Observation (uplink → Master)
AI_OBSERVE_REQ      -- uplink asks for a state digest
AI_OBSERVE_RES      -- Master's digest (see §3.2)

-- Action (uplink → Master)
AI_INTENT           -- one proposed verb + args
AI_INTENT_RESULT    -- accepted / refused / needs-confirm, plus ok,err

-- Operator gate (Master ↔ client)
AI_CONFIRM_REQ      -- ai-exec asks a human to approve a gated intent
AI_CONFIRM          -- operator's answer, carrying the token

-- Reactor supervision (Master ↔ guard)
AI_SETPOINT         -- requested setpoint, subject to clamping
AI_SETPOINT_RESULT  -- what the guard actually applied, and why
GUARD_STATUS        -- periodic readings + envelope + last-SCRAM
GUARD_ALERT         -- unsolicited: SCRAM fired, or envelope breached
```

---

## 3. Payload schemas

### 3.1 Intent

```lua
-- AI_INTENT (uplink → Master)
{
  intent_id = 41,
  verb      = "drain",              -- MUST be a key in the §4 table
  args      = { domain_id = 3 },    -- scalars only; no tables, no strings
                                    -- that will be executed or resolved
  rationale = "mgr-alpha error rate 0.4 over 5 min",  -- for the log, never executed
  turn_id   = 17,                   -- conversation turn that produced it
}
```

`rationale` is free text from the model and is treated as tainted: it is
written to the event ring buffer and displayed to the operator, and it is
never parsed, matched against, or used in any control decision.

### 3.2 Observation digest

```lua
-- AI_OBSERVE_RES (Master → uplink)
{
  digest_at   = <uptime>,
  managers    = {                    -- one row per Manager, flattened
    { domain_id = 3, state = "active", queue_depth = 2,
      free_capacity = 6, error_rate = 0.0, last_heartbeat_age = 4 },
  },
  jobs        = {
    { job_id = 104, state = "running", assignments = 3, oldest_age = 120 },
  },
  storage     = nil,                 -- until a Storage Node exists
  guard       = { temp = 812, flux = 44, level = 0.35, scrammed = false },
  events      = { ... },             -- last N, SANITISED — see §10
}
```

The digest is built from `/var/cluster/status.dat`, not by entering the
daemon's process. §0.5.3 designates that file as the lag-tolerant path for
external readers, and an agent is the archetypal external reader. Up to 2 s
stale is correct for deciding *what to propose*; the API's own consistency
handles the doing.

**Hostnames are replaced by `domain_id` in the digest.** See §10.

### 3.3 Setpoint

```lua
-- AI_SETPOINT (Master → guard)
{ setpoint_id = 9, level = 0.42, ttl = 30 }

-- AI_SETPOINT_RESULT (guard → Master)
{ setpoint_id = 9,
  requested   = 0.42,
  applied     = 0.40,               -- after clamping
  clamped_by  = "rate_limit",       -- nil | "level_max" | "level_min"
                                    -- | "rate_limit" | "scrammed" | "ai_disabled"
  reverts_at  = <uptime + 30> }
```

The guard always reports what it *actually did*, never a bare ack. A model
that asked for 0.42 and got 0.40 must be told so, or its next request
compounds an error it does not know it made.

---

## 4. The verb whitelist

### 4.1 Read verbs — no gate

| Verb | Args | Maps to |
|---|---|---|
| `status` | — | `api.status()` |
| `managers` | `[domain_id]` | `api.managers()` |
| `jobs` | `[job_id]` | `api.jobs()` |
| `storage` | — | `api.storage()` |
| `log` | `[n]` | event ring buffer, sanitised |
| `config_show` | — | `api.config()` read path only |
| `guard_status` | — | last `GUARD_STATUS` |

### 4.2 Mutating verbs — rate-limited, logged, reversible

| Verb | Args | Notes |
|---|---|---|
| `drain` | `domain_id` | Reversible by `undrain`; worst case is idle capacity |
| `undrain` | `domain_id` | |
| `cancel` | `job_id` | |
| `retry` | `job_id` | Rate-limited hard — see §4.5 |
| `setpoint` | `level` | Clamped by the guard regardless (§6) |

### 4.3 Confirm-gated verbs — a human presses a key

| Verb | Args | Why gated |
|---|---|---|
| `forget` | `domain_id` | Destroys registration state; recovery is re-pairing |
| `submit` | `template`, `params` | Schedules work across the cluster (§5.3) |
| `scram` | — | Should be available, should never be casual |

### 4.4 Denied outright

`lua`, `component`, `run`, `service`, `pkg` (all subcommands), `internet`,
`rs`/`redstone`, `robot`, `cluster pair *`, `config_set`, and `submit` with
a free-text body.

The first two are denied because the Manual is explicit that both bypass the
capability system — `component` invocation is ROOT precisely because raw
method calls drive hardware directly, and `lua` has full `_ENV`. A capability
manifest that carefully declines `peripheral.reactor` means nothing if the
agent can reach a shell that doesn't. **There must be no debug passthrough,
not even one behind a flag**, because that flag will be on during exactly the
session where something goes wrong.

`submit` with a body is denied for the reason in §1.4: assignment `code` is
Lua source that executes on Managers and, via the worker bridge, on **OpenOS
Workers where none of TOS's sandbox exists**. An agent with free-text submit
does not have cluster access, it has arbitrary code execution on every
machine in the estate.

### 4.5 Rate limits

- At most one mutating intent in flight at a time. A second is refused with
  `busy`, not queued.
- At most 6 mutating intents per 60 s window.
- `retry` on a given `job_id`: at most 2 per 10 minutes. An agent that
  reflexively retries a job failing for a structural reason is a loop with a
  cost, and the retry path is currently the least-tested code in the tree
  (see §11).
- Refusals are returned to the model as ordinary `ok, err` results so it can
  say something sensible to the operator, rather than silently dropped.

### 4.6 The confirm gate

1. `ai-exec` receives a gated intent, validates args, and does **not** run it.
2. It mints a single-use token: 6 characters, 60 s expiry, bound to the
   HMAC of the *canonical serialisation of the exact verb and args*.
3. `AI_CONFIRM_REQ` goes to every logged-in `ai` client, rendering the
   proposed action in operator language and the model's `rationale` clearly
   marked as the model's words.
4. An operator answering `AI_CONFIRM` with the token causes the intent to
   run. The binding is checked again at execution.

Binding to the argument hash, not just the intent id, follows the same
reasoning as §3.5's whole-frame MAC: approval must cover the payload, or an
approved `drain 3` becomes an executed `drain 7`.

---

## 5. The proxy (off-machine)

### 5.1 Contract

`aid` speaks a two-endpoint HTTP API and nothing else.

```
POST /turn      body: serialised digest + operator utterance
                returns immediately: { job = "<id>" }

GET  /turn/<id> returns: { state = "pending" }
                     or: { state = "done", reply = "<text>",
                           intent = { verb = "...", args = {...},
                                      rationale = "..." } }
```

Submit-and-poll rather than a held connection, because generation takes tens
of seconds and neither a Minecraft computer's call budget nor an OC internet
handle wants to sit open that long.

**The proxy returns at most one intent per turn.** Multi-step plans are
multiple turns, each of which passes the whitelist and the rate limiter
separately. A plan that is approved as a unit is a plan whose later steps were
never really examined.

### 5.2 Why the proxy assembles the prompt

The Master has ~3.6 MB apparent RAM holding full cluster state, job queues and
working memory (§0.5.1), and `aid`'s box is not necessarily better. Building a
prompt — system instructions, the verb table, conversation history, few-shot
examples — is string concatenation on a scale that will not fit comfortably
anywhere in-game. So the machine ships a compact digest and receives a verb
plus scalars; every large string lives outside.

This also means the verb table exists in two places, and they must agree. The
proxy's copy shapes what the model tries; `ai-exec`'s copy is what is
enforced. **Only the second one matters for safety.** Skew makes the agent
clumsy, never dangerous.

### 5.3 Job templates

`submit` names a file in `/usr/share/ai-templates/`, written by an operator,
installed as ordinary package files. Each declares typed parameters with
ranges. The model chooses which template and fills the parameters; it never
supplies the body. Every parameter is validated against the declaration on
the Master, not on the proxy.

---

## 6. `reactor-guard`

### 6.1 Three tiers

| Tier | Who | Loop | Owns |
|---|---|---|---|
| Reflex | `reactor-guard` | ~1 s, deterministic | SCRAM, hard limits, deadman revert |
| Supervisory | the agent | 5–60 s | setpoint requests inside the envelope |
| Operator | you | human | envelope changes, refuelling, restart after SCRAM |

The tiering is a sampling-rate argument before it is a safety one: a
controller slower than its plant is not a controller. HBM's NTM does expose
OpenComputers integration for exactly this class of work — `getInfo`-style
readouts of temperature, flux, level and target level, `setParams`/`getParams`
on control blocks, per-rod xenon poisoning, and console/crane callbacks — so
the reflex tier has real instrumentation to work from rather than inferring
state from redstone levels. (ComputerCraft has no equivalent; this is an
OC-only capability.) Confirm the method names against your NTM version before
implementing; the integration has been extended repeatedly.

### 6.2 The envelope

`/etc/reactor-guard.cfg`, operator-written, never agent-writable:

```lua
return {
  poll_interval = 1,        -- seconds
  scram_temp    = 1200,     -- hard limit; guard acts, tells no one first
  warn_temp     = 900,      -- enters GUARD_STATUS, agent may react
  level_min     = 0.00,     -- bounds on what the agent may request
  level_max     = 0.80,
  level_rate    = 0.05,     -- max change per accepted setpoint
  setpoint_ttl  = 30,       -- deadman: revert to safe_level if no refresh
  safe_level    = 0.70,
  ai_enabled    = true,     -- operator kill switch, checked every request
}
```

The deadman is the piece most easily forgotten. A hung proxy, a dropped
uplink, or a rate-limited API leaves the last setpoint pinned indefinitely
unless the guard reverts on its own. Silence must mean "go safe," never
"carry on."

### 6.3 SCRAM ownership

SCRAM is the guard's, unconditionally. It does not ask, does not wait for an
intent, and does not check `ai_enabled`. The agent has a `scram` verb (§4.3)
so it can act on something it reasons about before a threshold trips, but it
cannot *prevent* one, cannot raise a limit, and cannot clear a SCRAM state —
that is an operator action at the machine.

Announcing over the `intercom` add-on is the natural output here: its own
documented example cue is a reactor fuel warning, and an agent that says what
it is about to do before it moves a rod group gives you an audit trail in the
most human-readable form available.

---

## 7. Capabilities and manifests

```lua
-- ai-exec/package.lua  (Master)
return {
  name = "ai-exec", version = "0.1.0", kind = "service",
  files = { "/usr/lib/ai/exec.lua", "/etc/rc.d/ai-exec.lua" },
  capabilities = { "net", "fs.read", "fs.write" },   -- NOT internet, NOT component
  conflicts = { },
}
```

Prerequisites in `/etc/pkg_caps.cfg` and `/etc/component_caps.cfg`:

```lua
-- /etc/pkg_caps.cfg  on the Master
{ allow = { "peripheral.reactor" },
  deny  = { ["*"] = { "internet" } } }
```

`peripheral.reactor` is already the worked example in both Manual §7.3 and the
changelog entry that introduced `pkg_caps.cfg`, so the gating path is
documented; the NTM component type goes in `/etc/component_caps.cfg` and
`component reload-caps` picks up both halves.

Note the asymmetry that makes this work: `reactor-guard` holds
`peripheral.reactor` and `ai-exec` does not. The agent's reach into the
reactor is exactly the verbs the guard chooses to expose over the mesh, and
widening it requires editing an operator config on a different machine.

❓ **Open:** should the agent also hold a TOS user account at USER tier, so
securefs ACLs apply to anything `ai-exec` reads or writes on its behalf?
It would make `users` list the agent, which has a certain honesty to it.

---

## 8. Audit

Every intent — accepted, refused or gated — writes one event to the ring
buffer in `state.lua`, with:

```lua
{ actor = "ai", verb = "drain", args = {...}, outcome = "ok",
  rationale = "<model text>", approved_by = "root" | nil, at = <uptime> }
```

`cluster log` must render `actor` prominently. The question "did a human do
this?" is the first one asked after anything surprising, and an audit trail
that requires inference to answer it is not an audit trail.

Refusals are logged as loudly as successes. A model repeatedly attempting a
denied verb is the signal that something upstream is wrong — a bad prompt, a
stale template, or §10.

---

## 9. Failure semantics

| Failure | Behaviour |
|---|---|
| Proxy unreachable | `aid` retries with backoff; agent is simply absent; cluster unaffected |
| Uplink box down | Master and cluster unaffected; guard deadman reverts to `safe_level` |
| Master down | Agent can observe nothing and do nothing; §8.4 already covers the cluster |
| `ai-exec` down | Intents unacknowledged; `aid` surfaces this to the operator rather than retrying blind |
| Guard down | Reactor loses its interlocks — **this is the one that matters.** The guard should be the last thing on its machine and its absence should raise `GUARD_ALERT` from `ai-exec`'s side by timeout |
| Model returns nonsense | Fails validation; refusal returned as `ok, err`; logged |

---

## 10. Untrusted context

The digest carries hostnames, job names, worker names and event-log lines.
On a shared server, some of those strings are chosen by other people. A
machine named with an embedded newline and an instruction is a prompt
injection delivered through legitimate cluster state.

This is the same shape as the reasoning behind refusing Master
auto-discovery: the risk is not that the data is wrong, it is that whoever
supplies it gets to influence a decision. Mitigations:

1. **Identifiers, not names.** The digest uses `domain_id` and `job_id`.
   Hostnames appear only in operator-facing rendering on the client, never in
   the model's context.
2. **Sanitise what must be free text.** Event-log lines: strip control
   characters, collapse newlines, cap length, and fence them explicitly as
   untrusted data in the prompt.
3. **The whitelist is what actually saves you.** Injection can make the model
   *want* to do something; it cannot add a verb, unbind a confirm token, or
   raise the guard's envelope. Treat 1 and 2 as reducing noise and the verb
   table as the control.

---

## 11. Prerequisites in existing code

Two gaps flagged in `Plan.md` become blocking rather than tidy-up. One is
now closed:

- ~~**`jobs.lua` has no unit tests.**~~ **Done** —
  `TOS-Dev/usr/lib/tests/test_cluster_jobs.lua` covers splitting, retry
  policy, timeout handling and multi-chunk reassembly, which are the paths
  `cancel` and `retry` drive. The worry that motivated this was that the
  agent would exercise them in orderings no human operator would produce,
  and that is what the harness found: three shipped bugs, the worst of
  which let a duplicate result resurrect a *completed* assignment into a
  job that could then never dispatch or finalize it (§8.6 of the protocol
  spec). See `Plan.md` for the detail. The caution generalises rather than
  retires — the next verb granted should get the same treatment, because
  the untested module is exactly where an agent's unusual orderings land.
- ~~**The `ok, err` convention is undocumented.**~~ **Written** —
  [error-conventions.md](error-conventions.md). The reasoning stands as it
  was stated: the moment error *strings* are fed back into a prompt they
  become an API surface, inconsistent phrasing produces inconsistent agent
  behaviour, and a reworded error is a behaviour change with no code
  change. The contract's answer is that `err` is a stable snake_case code
  with optional human detail behind a colon — the shape `scheduler.lua` and
  `protocol.lua` already use — so the model classifies on the code and the
  operator still reads the sentence.

  **The code does not conform yet.** §7 of that document audits it: roughly
  35 prose strings across `api.lua`, `state.lua` and `jobs.lua` carry no
  code prefix, and `api.getJob` vs `api.retryJob` answer the same "no such
  job" condition two different ways. Do the rewording **before** `ai-exec`
  exists. Once a model has been prompted against today's strings, changing
  them is exactly the no-code-change behaviour change this bullet was
  warning about.

---

## 12. Out of scope for v1

- Model-authored Lua in any form.
- Autonomous operation with no operator logged in. v1 requires a live `ai`
  client for the confirm gate; an agent that can act into an empty room is a
  different design with a different risk profile.
- Any `pkg` operation, including updates of the agent's own packages.
- Storage-tier awareness, which cannot be built because the Storage Node does
  not exist (protocol spec §4.5).
- Multiple agents, or one agent addressing multiple clusters.
- Anything writing `/etc`.

---

## 13. Open questions

1. **Whose confirmation counts?** TOS is multi-seat. If three operators are
   logged in, does the first `AI_CONFIRM` win, or should gated verbs require
   a specific tier? Leaning: first ADMIN+ answer wins, and the log records
   who.
2. **Where does conversation memory live across a Master reboot?** `aid` is
   on the uplink box, so it survives — but the agent then holds context about
   a cluster state that no longer exists. Probably: drop history on any
   observed `clusterd` restart, and say so in the transcript.
3. **Does the model see the event log at all?** It is the richest context and
   the largest injection surface. Leaning: yes, sanitised and capped, because
   an agent that cannot see recent failures is not much of an operator.
4. **Should `setpoint` be gated?** It is listed as ungated in §4.2 on the
   grounds that the guard clamps it regardless. That argument holds only as
   long as the envelope is correct, which is an operator's responsibility and
   therefore an operator's mistake to make.
5. **What does the agent do when it has nothing to say?** A verb-per-turn
   design invites the model to always emit one. There should be an explicit
   no-op, and it should be the modal outcome of a healthy cluster.
