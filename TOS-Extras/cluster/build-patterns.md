# Cluster Build Patterns (Draft v0.1)

Companion to [cluster-protocol-spec-draft.md](cluster-protocol-spec-draft.md).
That document says what the software does; this one says **what to place in the
world so the software has something to run on** — a set of repeatable Minecraft
structures that scale from one closet to a full data centre without ever
changing the pattern, only repeating it.

**Status:** Draft. `❓` = a design question still open. `⚠️` = a number to
verify in *your* pack version before you build 40 of them.

---

## 0. The one rule

> **Touching blocks share a component network. The layout *is* the topology.**

Everything below follows from that. A row of racks shoved together is one
enormous network where every server sees every screen, every disk, and every
other machine's modem traffic. A one-block gap is an air gap. This is normally
the thing that ruins OC builds; here we make it the organising principle:

| You want | You build |
|---|---|
| One domain, isolated | A block of Us with gaps on both ends |
| Two domains that must not see each other | A gap, or a dyed cable that doesn't touch |
| A shared storage rail | Us placed shoulder-to-shoulder on purpose |
| A controlled bridge | A Relay block, not a cable |

The protocol spec spends §1.2 and §3.1 keeping domains from reading each
other's traffic. Wired bays enforce most of that in dirt and iron before a
single packet is signed.

---

## 1. The unit: **the U**

One **U** = **1×1×2** (L×W×H), exactly as sketched:

```
        ┌─────┐
  y+2   │ CAP │   ← swappable: RAID / computer / tape / disk drive / relay
        ├─────┤
  y+1   │RACK │   ← always a Server Rack, 4 mountable slots
        └─────┘
  y+0     ███      floor (raised floor / cable trench below)
```

The rack never changes. The **cap is the module's personality**, and it is
legible from the aisle — you can walk a hall and read what every machine is
without opening a single GUI. That legibility is the whole point of fixing the
form factor.

### 1.1 Cap catalogue

| Code | Cap block | What it gives the U | Manager config line |
|---|---|---|---|
| **U‑R** | RAID (3× HDD) | Bulk scratch/results storage for the domain | `storage_type = "raid"` |
| **U‑T** | Tape Drive (Computronics) | Archive / log spool / `tape-auth` media | `storage_type = "tape"` |
| **U‑C** | Computer Case | A 5th machine with its **own card slots and console** | this box *is* the Manager |
| **U‑D** | Disk Drive | Floppy slot — the install/service point | — (holds the `cluster-install` floppy) |
| **U‑X** | Relay | Bridges this bay to another network / goes wireless | — (physical layer only) |
| **U‑0** | Blank (iron block, lamp, decorative) | Reserved slot, keeps the row uniform | — |

The U‑C cap is doing the most work: a rack Server has no screen, so putting a
real Computer Case on top is how a domain gets a local operator console without
burning a rack slot on a Terminal Server. That was the right instinct — keep it.

⚠️ **Verify:** whether the Computronics Tape Drive in your pack is also
*rack-mountable*. If it is, U‑T can move into the rack and the cap frees up.

---

## 2. Rack loadouts — the 4 slots

A Server Rack holds four mountables: Servers, Terminal Servers, Disk Drives,
Relays. Four slots is the number the whole build scales on, and it happens to
land exactly on the spec's M3 / M4 / M8 profiles (§4.1).

### L‑A — "Solo domain" (M3) — 1 U, headless

```
  CAP:  U-R (RAID)
  ┌──────────────────────┐
  │ 0  Server T3  MANAGER│  runs cluster-manager
  │ 1  Server T2  worker │  OpenOS + cluster-worker.lua
  │ 2  Server T2  worker │
  │ 3  Server T2  worker │
  └──────────────────────┘
```

`worker_count = 3`, no console — you administer it with `rsh` from the Master.
**One block footprint, one complete domain.** This is the pattern you repeat.

### L‑B — "Console domain" (M4) — 1 U, with a screen

```
  CAP:  U-C (Computer Case = the MANAGER, has_console)
  ┌──────────────────────┐
  │ 0..3  Server ×4      │  four workers
  └──────────────────────┘
```

`worker_count = 4`. The cap computer takes GPU + screen + keyboard on the aisle
wall. Use this as the **head-end of a hall** so someone standing in the room can
actually see something.

### L‑C — "Twin" (M8) — 2 U

```
  CAPS: [ U-C: MANAGER ]  [ U-R: RAID ]
  RACKS:[ 4 workers    ]  [ 4 workers  ]
```

`worker_count = 8`. Both racks bound to the same back-side bus so the one
Manager's port `2001+domain_id` broadcast reaches all eight.

### L‑D — "Edge / gateway" — 1 U, for a far-flung bay

```
  CAP:  U-X (Relay, wireless card fitted)
  ┌──────────────────────┐
  │ 0  Server T3  MANAGER│  master_path = "via", relay_peer = <other mgr>
  │ 1  Terminal Server   │  remote console, no screen needed
  │ 2  Server T2  worker │
  │ 3  Disk Drive        │  service floppy lives here
  └──────────────────────┘
```

Note the distinction, because it bites people: the **Relay block** is a
*physical* bridge that moves component-network packets. The spec's **relay peer**
(§1.3) is a *Manager* forwarding `RELAY_FORWARD` envelopes at the protocol
layer. You can have either, both, or neither. They solve different problems —
distance vs. reachability.

### L‑E — Master

Do **not** put the Master in a rack. Per spec §0.5.1 it wants T3 GPU + screen +
keyboard, and the operator console is the point. Build it as a Computer Case in
the control room facing a multiblock screen. See §5.3.

---

## 3. Build → config crosswalk

The physical build should be readable off the config file and vice versa. This
is the table to keep honest:

| You placed | `/etc/cluster-manager.cfg` |
|---|---|
| 3 worker servers in the rack | `worker_count = 3` |
| U‑R cap (RAID) | `storage_type = "raid"` |
| U‑T cap (tape) | `storage_type = "tape"` |
| JBOD drives on the bay bus | `storage_type = "jbod"` |
| Bay wired only to its own bus, Manager also on the aisle bus | `worker_bridge_enabled = true`, `worker_bridge_domain = <n>` |
| Bay is out of the Master's modem range | `master_path = "via"` + `relay_peer` |
| Nothing but servers, no storage cap | leave `storage_type = nil` |

**The cap really does steer the scheduler.** A job submitted with
`storage_preference = "raid"` will land on a U‑R domain and nowhere else — set
`storage_type` to match the cap you placed and the Master's scoring does the
rest (+25 on a match, and a hard skip for domains that can't satisfy it).

Two things worth knowing when you re-cap a module:

- **You don't need to re-pair.** The declared type rides both the registration
  payload *and* every heartbeat, so bolting a RAID onto a live domain is: place
  the cap → edit `storage_type` → `service restart cluster-manager`. The Master
  converges on the next beat and logs a `manager_storage_change` event.
- **Only one type per domain.** `storage_type` is a single string, so a bay with
  both a RAID and a tape cap has to pick which one it advertises. If you want
  both addressable, split it into two domains — which is the honest modelling
  anyway, since they have different performance stories.

*(Historical note: before the fix in this cycle, preference-bearing jobs were
rejected cluster-wide with `storage_pref_mismatch` — the Manager never sent its
storage declaration at all. Pinned now by `test_cluster_storage_pref`.)*

---

## 4. Bays — grouping Us into domains

A **bay** is a run of Us that forms one domain, with a gap at each end.

```
 plan view, one hall row (▓ = wall, · = walkable aisle, ␣ = air gap)

 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
 ▓ U U ␣ U U ␣ U U ␣ U U ␣ U ␣ U ▓
 ▓ ·  ·  ·  ·  ·  ·  ·  ·  ·  · ·▓   ← 3-wide aisle
   └B1┘   └B2┘   └B3┘   └B4┘  ^  ^
                              │  └ U-D service module (floppies)
                              └ U-X relay module
```

**Spacing rules**

1. **Inside a bay:** Us touch. They share the bay bus on purpose.
2. **Between bays:** one block of air, or one block of *anything that isn't OC
   cable*. That air gap is a security boundary, not decoration.
3. **Bay size:** 1 U (M3/M4), 2 U (M8), 4 U max. Past 4 you're better off
   splitting into two domains — the Master schedules per domain, and one giant
   domain is one scheduling unit that can only be drained all at once.
4. **Every bay gets a dye colour.** OC cables take dye; run bay *n* in colour
   *n* and the hall becomes self-documenting. Match it to `domain_id`.

### 4.1 The two-bus trick

Bind rack mountables to sides in the rack GUI so each bay carries **two
independent networks**:

```
        back side  ──── worker bus ────  (port 2001+domain_id, raw modem,
        │                                  HMAC-authed, never leaves the bay)
   [ U ][ U ]
        │
        front side ──── control plane ──  (port 2000, TOS protocol, TRUSTED,
                                            runs the aisle to the Master)
```

Only the **Manager** mountable sits on both. Workers touch the worker bus only.
This is the physical mirror of the spec's port split (§2), and it fixes by
construction the thing §2 warns about — promiscuous modems letting two domains
on the same port see each other's worker traffic. Wired bays simply cannot
overhear each other.

⚠️ **Verify:** exact side names/count in your rack GUI's connection matrix
(orientation-dependent). The concept holds; the labels vary.

---

## 5. Rooms

### 5.1 The Closet — 1 bay

Interior **3×3×3**. One L‑A U against the back wall, service floppy in an item
frame, a lamp. That's a working cluster domain in nine floor blocks. Good for a
first build and for satellite bases that just contribute compute.

### 5.2 The Server Hall — 4 to 8 bays

Hot-aisle/cold-aisle, two rows facing a shared walkway.

```
 cross-section (looking down the hall)

  y+4 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  ceiling
  y+3 ▓ ══════════ lamps ═══════ ▓  ceiling raceway (uplink cable + lighting)
  y+2 ▓ [CAP]   ·  ·  ·   [CAP] ▓  ← caps at eye level, readable
  y+1 ▓ [RACK]  ·  ·  ·  [RACK] ▓  ← rack front faces the aisle (GUI access)
  y+0 ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓  raised floor: slabs/trapdoors over the trench
  y-1 ▓   ░ cable trench, per-bay segments ░  ▓
      └─1─┘└──── aisle 3 ────┘└─1─┘
```

- **Interior width:** 5 (1 rack + 3 aisle + 1 rack). Add 2 if you want a
  service margin behind the racks for the back-side worker bus — recommended,
  it makes the two-bus trick buildable without breaking floor blocks.
- **Interior length:** 3 blocks per bay (2 U + 1 gap) — so 8 bays ≈ 24 long.
- **Height:** 4 interior. Caps land at eye level; the raceway rides above.
- **Raised floor:** the trench carries each bay's control-plane drop up to the
  aisle spine. Keep trench segments **discontinuous between bays** or you've
  just welded every domain into one network under the floor.
- **Head-end:** one L‑B (U‑C cap) with a 3×2 screen on the end wall running
  `cluster watch`.

### 5.3 The Data Centre — many halls

```
 plan view (one floor)

   ┌──────────┐  ┌──────────┐   ┌──────────────────┐
   │  HALL A  │  │  HALL B  │   │   STORAGE VAULT  │
   │  8 bays  │  │  8 bays  │   │  U-R bank + tape │
   └────┬─────┘  └────┬─────┘   └────────┬─────────┘
        │             │                  │
   ═════╧═════════════╧══════════════════╧══════════  spine (dyed cable, 1 colour
        │             │                  │             per hall) + relay blocks
   ┌────┴─────┐  ┌────┴─────┐   ┌────────┴─────────┐
   │  HALL C  │  │  HALL D  │   │   CONTROL ROOM   │
   │  8 bays  │  │  8 bays  │   │  MASTER + wall   │
   └──────────┘  └──────────┘   └──────────────────┘
                                 ┌──────────────────┐
                                 │   POWER ROOM     │
                                 └──────────────────┘
```

**Control room.** The Master case, a multiblock T3 screen (⚠️ max size varies —
plan 6×4, it's comfortable and safely under any limit), keyboard, and a rack of
Terminal Servers so you can carry a Remote Terminal into any hall and still have
a console. `cluster watch` on the wall, `cluster managers` on a second screen if
you have the GPUs.

**Storage vault.** A bank of U‑R modules shoulder-to-shoulder — this is the one
place you *want* the networks merged, because it's the future Storage Node
(spec §4.6). Tape library on the facing wall: U‑T modules with item-frame
labels. Note the vault is a *build-ahead* — no `STORE_PUT` handling ships yet
(spec §4.5 "NOT YET IMPLEMENTED"), so today it's shared storage you mount by
hand.

**Spine.** Relay blocks between halls rather than raw cable, so a hall can be
isolated without breaking blocks. Each hall's spine drop gets its own dye.

**Power room.** OC energy is the real scaling limit long before Lua is — see §7.

---

## 6. Signage and legibility

Cheap, and it turns the build into a readable machine:

- **Item frame on every cap** with the domain number — matches `cluster managers`
  output, so the room and the terminal agree.
- **Cap type readable at a glance** (that's the whole reason for the fixed form
  factor): RAID = storage, tape = archive, case = has a console, drive = service.
- **Cable dye per domain**, spine colour per hall.
- **Status wall (optional, real):** TOS ships a `redstone` / `rs set|pulse`
  command when a redstone card is present. A ~20-line script polling
  `/var/cluster/status.dat` (written every 2s, spec §0.5.3) can drive one lamp
  per domain — green while active, dark when the Master marks it offline. This
  is the highest-value decorative feature in the whole build: the room tells you
  the cluster is sick before you open a terminal.

---

## 7. Scaling limits — read before the 4th hall

The build stops scaling for these reasons, in this order:

1. **Server tick budget.** OC runs computers on a fixed thread pool
   (`opencomputers.computer.threads`); the Master's `host_thread_budget`
   (`/etc/cluster-master.cfg`) is meant to be set to match it. Machines beyond
   that number don't fail — they just time-slice, and everything gets slower.
   **Count every running server, not every block.** A powered-down rack costs
   nothing.
2. **Energy.** Every running server drains continuously. Size the power room for
   *all* racks running, then add margin; a brownout that resets machines
   mid-assignment is exactly the failure the retry policy has to clean up.
3. **Chunk loading.** A hall that unloads is a hall of Managers that go
   `offline` after 30s (`heartbeat_offline_after`) and get their work
   redistributed. Keep halls chunk-loaded or accept the churn.
4. **Scheduler working set.** Grows with `# Managers × # active jobs` — small,
   but it's why the Master wants the T3.5 RAM pair.

**Rough budget per pattern:**

| Pattern | Blocks | Running machines | Notes |
|---|---|---|---|
| Closet (L‑A) | 2 | 4 | 1 Manager + 3 workers |
| Hall, 8 bays of L‑A | ~30 | 32 | already past a default thread pool |
| Data centre, 4 halls | ~150 | 128 | needs a raised `threads` config + real power |

⚠️ The honest version: **a "data centre" in OC is mostly a set that looks like
one.** Build 4 halls, run one or two, power the rest down as cold spares and
bring them up with `cluster undrain` when you actually need the throughput. The
software already models this — `drain` / `undrain` exist precisely so a domain
can be present but not scheduled.

---

## 8. Build order

1. **Power first.** Nothing below works intermittently-powered.
2. **Master + control room.** One machine, install TOS, install
   `cluster-master`, start `clusterd`.
3. **One L‑A U, adjacent to the Master.** Pair it. Prove `cluster managers`
   shows it and heartbeats land. *Do not build 30 of anything before this
   works.*
4. **Cut the U‑D service module.** Build the install floppy with
   `cluster-make-floppy`; from here every new bay is: place blocks → insert
   floppy → `run /mnt/<label>/cluster-install.lua` → answer 4 prompts.
5. **Replicate to a full hall.** Same U, different domain colour.
6. **Add the vault and the spine** once two halls exist and you actually feel
   the distance.

Have the Master's **full** modem address written down before step 4 — the
installer prints a truncated one (documented limitation in
[installer/README.md](installer/README.md)).

---

## 9. Open questions

- ❓ **Cap-driven config.** Should `cluster-install` *detect* the cap (RAID /
  tape drive / drive component present) and set `storage_type` automatically,
  instead of asking? The installer already probes hardware. This would make the
  physical build the single source of truth — place a RAID cap, get a RAID
  domain, no config editing. Strong candidate.
- ❓ **`worker_count` autodetect.** Same idea: count paired workers after the
  bootstrap window rather than trusting a hand-typed number that drifts the
  moment someone pulls a server.
- ❓ **Do we want an M2?** A 1×1×1 "half-U" (rack, no cap) for filler rows in
  big halls — pure decoration that's also real compute.
- ❓ **Bay drain switch.** A lever wired to a redstone card that runs
  `cluster drain <domain>` — physical maintenance mode before you pull a rack.
  Fun, and it matches how you'd actually service the thing.
