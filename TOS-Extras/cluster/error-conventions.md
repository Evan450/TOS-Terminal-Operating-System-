# Cluster error-handling conventions

> **Scope:** the return-value contract for every module under `master-skeleton/lib/cluster/` and `manager-skeleton/usr/lib/cluster/`. It governs how failures are *reported*, not how they are handled. For the wire protocol see [cluster-protocol-spec-draft.md](cluster-protocol-spec-draft.md); for the Master's file layout see [Plan.md](Plan.md).
>
> **Status:** the rules in §1–§6 are the contract; §7 records how the code measures against them. The contract was written *after* the code, and the Master-side modules were migrated to it in the same pass — so §7 reads as a changelog rather than a backlog. The Manager side is not migrated; see §7.3.

---

## 0. Why this is a document and not a habit

Two things forced this.

The first is ordinary: modules returning failures in several different shapes means every caller guesses, and the guesses are usually right, which is worse than usually wrong. `jobs.lua`'s dispatch path used to check `if not ok_set then` against a function that can fail two distinguishable ways and flatten both into `"state update failed"`, discarding on the way through the only diagnosis available at that point.

The second is specific to the agent. [ai-operator-spec-draft.md](ai-operator-spec-draft.md) §11 puts it exactly: the moment error *strings* are fed back into a model's context they become an API surface. An agent that sees `no_eligible_manager` on Monday and `no active managers with free workers` on Tuesday cannot tell that those are the same condition, and a maintainer rewording the second one has changed the agent's behaviour without touching a line of logic. Prose is fine for an operator reading `cluster jobs`. It is not fine as a classification key.

So the contract's central rule is §4: **the failure reason is a stable code, and the human sentence rides behind it.**

---

## 1. The two shapes

Every function that can fail returns one of exactly two shapes. Which one it uses is determined by what it returns on success, not by preference.

**`ok, err` — for functions whose success has no payload.** Returns `true` on success, `false, err` on failure.

```lua
local ok, err = state.setManagerState(addr, "draining")
if not ok then return false, err end
```

**`value, err` — for functions that produce something.** Returns the value on success, `nil, err` on failure.

```lua
local job_id, err = api.submit(spec)
if not job_id then return nil, err end
```

The rule that makes these safe to mix: **the first return value is always testable with `if not x then`.** Never return `0`, `""`, or a table as a failure signal, and never return `true` from a `value, err` function.

**Predicates are exempt.** A function that answers a yes/no question — `pair.windowOpen()`, `jobs._internal.allAssignmentsTerminal()` — returns a bare boolean and carries no error, because `false` is an answer rather than a failure. The distinction is whether the caller asked "did this work?" or "is this true?". Name predicates so the question is obvious.

## 2. Absence is not failure

A lookup that finds nothing has succeeded. `getJob(999)` returning `nil` means "there is no job 999", which is a complete and correct answer to the question asked.

Distinguish the two cases by whether the *caller could have known*:

- **Bare `nil`, no error** — the query was well-formed and the answer is empty. `state.getJob`, `state.getManager`, `state.getManagerByDomainId`, `api.storageStatus` when no Storage Node is configured.
- **`nil, err`** — the call could not be carried out. Missing argument, malformed spec, wrong state, daemon not reachable.

The trap this rule exists to prevent: a caller writing `local j, err = getJob(id); if err then` and never noticing that a missing job produced no error, or writing `if not j then die(err)` and printing `nil`. **A function must pick one behaviour for a given condition and keep it.** `api.getJob(999)` and `api.retryJob(999)` used to disagree about exactly this — bare `nil` from one, `nil, "no such job"` from the other, for the same missing job. Both now answer `nil, "no_such_job"`.

## 3. Failures that throw

Three conditions raise rather than return, because they indicate a broken program rather than a rejected request:

1. **Precondition violations on the API surface.** `api._requireBound()` raises `"cluster daemon is not running (clusterd not started)"` with level 2. Every `api.*` function except `bind`/`unbind` begins with it, so **every API call can raise**, and `ai-exec` must wrap its dispatch in `pcall` regardless of the verb.
2. **A wedged cooperative lock.** `state.withLock` raises after ~10 s of waiting. There is no return path for this; a stuck lock holder is not a condition a caller can retry around.
3. **Errors propagated out of `withLock`.** It `pcall`s the body and re-raises with level 2, so a failure inside a locked section surfaces at the caller's line, not inside `state.lua`.

Everything else returns. In particular, bad *user* input never throws — an invalid `retry_policy` is a rejected request, not a broken program.

## 4. The error string

**`err` is a stable snake_case code, optionally followed by `": "` and human detail.**

```lua
return false, "no_such_job"
return false, "invalid_retry_policy: " .. tostring(spec.retry_policy)
return nil,   "namespace_denied: domain-<id> requires owning Manager"
```

The code is the contract; the detail is not. Callers classify on the code and display the whole string:

```lua
local code = err:match("^[%a_][%w_]*")
```

Three properties this buys, in the order they matter:

- **The agent gets a key that survives rewording.** §10 of the AI-operator spec leans on the verb whitelist as the real control and treats everything else as noise reduction; a stable reason code is the same kind of move for the return path.
- **The CLI still prints something a person can read.** `die("pair start failed: " .. err)` is unchanged by this rule.
- **Codes are greppable.** `storage_pref_mismatch` appears in `scheduler.lua`, in `test_cluster_storage_pref.lua`, and in the operator's `cluster log` output, and it is the same token in all three.

This is not a new invention. `scheduler.lua` already emits `no_snapshot`, `no_free_workers`, `storage_full`, `storage_pref_mismatch`, `thread_budget_saturated`, and `state:<manager state>`; `protocol.lua` already emits `namespace_denied: <detail>`. The convention is adopted from the two modules that got it right, not imposed on them.

**Codes are lowercase, `[a-z0-9_]`, and name the condition, not the remedy.** `no_free_workers`, not `wait_and_retry`. Reuse an existing code rather than minting a synonym — the canonical list is §5.

## 5. Canonical codes

Reuse these. A new code is fine when the condition is genuinely new; a second spelling of one of these is not.

| Code | Meaning |
|---|---|
| `no_such_job` | Job id does not exist |
| `no_such_assignment` | Assignment id does not exist |
| `no_such_domain` | No Manager with that `domain_id` |
| `unknown_manager` | No Manager at that address |
| `missing_argument: <name>` | A required argument was nil |
| `invalid_<field>: <value>` | Argument present but not a legal value |
| `wrong_state: <actual>` | Operation illegal from the object's current state |
| `duplicate_result` | A result already settled this assignment (§8.6) |
| `incomplete` | Chunk set is not yet whole; not an error, a "not yet" |
| `no_state_path` | `state.init()` was never called |
| `send_failed: <detail>` | The packet did not leave the Master |
| `no_eligible_manager` | Scheduler found nothing viable |
| `no_snapshot` / `no_free_workers` / `storage_full` / `storage_pref_mismatch` / `thread_budget_saturated` | Per-Manager scheduler rejects |
| `namespace_denied: <detail>` | Public-storage ACL refusal |
| `pairing_unsupported` | Daemon has no pairing subsystem bound |
| `read_failed` / `write_failed` / `rename_failed` / `decode_failed` / `bad_state_shape` | Persistence failures, each `: <detail>` |
| `empty_reverse_path` | Relay reply has no next hop |
| `invalid_spec` / `invalid_tasks` / `invalid_priority` / `invalid_key` / `invalid_value` | Rejected `submit`/`config set` input |

Two success payloads share this namespace because they answer "which kind of success": `state.load` returns `true, "cold_start"` when no state file existed and `true, "loaded"` when one was restored. A Master that came up with an empty registry because the file was absent is a different situation from one that restored an empty registry, and the caller could not previously tell them apart.

`incomplete` earns its place in the table despite not being a failure: `onResultChunk` returns `false, "incomplete"` on every chunk but the last, which is the normal path, and a caller that logs every `false` as an error will flood the ring buffer during a large transfer.

## 6. The second slot on success

`ok, err` functions may return `true, <payload>` where the payload is genuinely secondary — `jobs.finalizeJob` returns `true, newState`, `api.setConfig` returns `true, { restart_required = ... }`. This is fine, because the first value still answers "did it work" and nothing reads the second slot unless the first was true.

**What is not fine is the inverse: putting a success payload in the error slot of a `value, err` function.** `api.startPairing()` returns `(code, remaining_seconds)` on success and `(nil, "daemon does not support pairing")` on failure, so the second value is a number or a string depending on an outcome the caller has not checked yet. It works today only because `cluster.lua:342` knows to read it as `expires_in`. A generic caller — `ai-exec` handling `pair`, if that verb ever leaves the deny list — cannot write correct code against it. Return a table instead: `{ code = ..., expires_in = ... }, nil`.

---

## 7. Conformance

The Master-side modules were migrated to this contract in the same pass that wrote it. What follows is the state after that migration.

### 7.1 Conforming

- **`scheduler.lua`** — `value, err` throughout, snake_case codes, no throws. The convention was taken from here; nothing in it changed.
- **`api.lua`, `state.lua`, `jobs.lua`, `net.lua`** — migrated. 30 literal strings recoded, plus the structural fixes in §7.2.
- **Shape selection generally.** Every module already picked `ok, err` vs `value, err` correctly for its success type, and none returned `0` or `""` as a failure signal. That part of the contract described the code rather than correcting it.

`test_cluster_jobs.lua` §15 enforces this. It calls fifteen real failure paths across `state.lua` and `jobs.lua` and asserts each `err` matches `^[a-z][a-z0-9_]*$` or `^[a-z][a-z0-9_]*: .`, then asserts that two lookups returning absence carry no error at all. The shape matcher is itself tested against prose, capitals and a dangling colon, so a check that quietly stopped checking would fail rather than pass.

`api.lua` is not reachable from that harness — it needs a bound daemon — so its strings are verified by inspection here rather than by assertion. That is the weakest link in the enforcement and worth closing when `api.lua` gets a harness of its own.

### 7.2 What the migration changed structurally

Beyond the rewording:

- `api.getJob` returned bare `nil` for a missing job while `api.retryJob` returned `nil, "no such job"` for the identical condition. Both now return `nil, "no_such_job"`.
- `api.startPairing` returned `(code, expires_in)` on success and `(nil, err)` on failure — a number or a string in the same slot, discriminated by an outcome the caller had not checked yet. It now returns `{ code, expires_in }`, and `cluster.lua`'s `pair start` reads the table.
- `api.closePairing` returned bare `false`, and `api.pairingInfo` bare `nil`, when the daemon lacked pairing support. Both now return `pairing_unsupported`. `pairingInfo` still returns bare `nil` for "no window open" — absence, not failure — so the two cases are finally distinguishable.
- `jobs.dispatch` collapsed `state.setAssignmentState`'s two distinct failures into `"state update failed"`. It now passes the store's own reason through, so `no_such_job` and `no_such_assignment` survive the trip.
- `state.load` returned plain `true` both for "no state file" and for "restored successfully". It now returns `true, "cold_start"` and `true, "loaded"`.

One thing deliberately left as prose: `state.lua`'s private `validateShape` helper. Its reasons are the *detail* half of the caller's error — `state.load` wraps them as `bad_state_shape: <reason>` — so the stable code is minted once at the public boundary instead of seven times inside a helper nobody outside the module calls.

### 7.3 Not migrated

The Manager-side modules were outside the audited scope and still carry prose: `protocol.lua`'s key and packet validators (`"empty key"`, `"bad magic"`, `"GET needs key"`, `"malformed cluster.cfg: …"`) and a handful in `worker.lua`. `protocol.lua`'s `namespace_denied: <detail>` already conforms and is where §4's shape came from — the rest of that file simply predates it.

This is lower priority than the Master side was, on two grounds: none of it sits on the agent's observation or action path, and the public-storage validators guard a Storage Node that does not exist yet (protocol spec §4.5). Migrate them when the Storage Node lands, so those strings get written once against a working implementation rather than reworded twice.
