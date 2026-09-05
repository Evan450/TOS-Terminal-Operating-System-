# Setting up a cluster

**Short version:** every machine installs **one** package from the ordinary
Optional Utilities disk, then runs `cluster-setup`. You never copy files by
hand.

| Machine | Package | Service |
|---|---|---|
| The control machine (exactly **one**) | `cluster-master` | `clusterd` |
| Every compute machine (**as many as you like**) | `cluster-manager` | `cluster-manager` |

A second Master would accept registrations of its own and the cluster would
split in half without telling you — so, one.

## The whole procedure

On **each** machine, as root:

```bash
cluster-setup
```

That's it. `cluster-setup` lives in the base TOS image, so it is there
*before* either package is — which is the point. It will:

1. Ask what this machine is (and explain the difference if you don't know).
2. Check there's a modem, and stop early if there isn't.
3. Install the right package for the role you picked.
4. Ask a handful of tuning questions, all with defaults you can Enter past.
5. Write `/etc/cluster-master.cfg` or `/etc/cluster-manager.cfg`.
6. Start the service, and honour your answer about starting it at boot.
7. Handle pairing — see below.

If you just want to know what you're in for without changing anything:

```bash
cluster-setup explain
```

## Pairing

Managers have to be told which Master to trust, and the Master has to be told
to expect them. Do the Master **first**:

1. Run `cluster-setup` on the Master. At the end it prints two things:

   ```
     Master address:  3f8a1c2d-44b5-4e0a-9c11-77aa0099bbcd
     Pairing code:    <code>
   ```

   The address is printed **in full**, because you are going to type it into
   every Manager. Write both down.

2. Run `cluster-setup` on each Manager. It asks for that address and that
   code. It rejects a shortened address (every TOS listing abbreviates to 8
   characters, so pasting one back is the easy mistake) and tells you so
   rather than writing a config that can never connect.

3. Back on the Master, `cluster pair status` shows them arriving, and
   `cluster managers` lists them once registered. `cluster pair close` ends
   the window early.

The pairing window lasts five minutes. If it lapses, `cluster pair start` on
the Master opens another.

## Afterwards

On the Master:

```bash
cluster status      # overview
cluster managers    # who has joined
cluster watch       # live dashboard
```

On a Manager:

```bash
cluster-manager status
```

## OpenOS worker machines (optional)

Everything above is pure TOS and needs no manual file copying. Worker boxes
are the one exception, because they run **OpenOS**, which TOS's package
manager has no reach into. Skip this entirely unless you want it — a Manager
runs work inline perfectly well on its own.

1. **On the Manager**, add to `/etc/cluster-manager.cfg`:

   ```lua
   worker_bridge_enabled = true,
   worker_bridge_domain  = 0,                       -- worker port = 2001 + this
   worker_bridge_secret  = "a-long-shared-secret",  -- 16+ bytes, keep it secret
   worker_bridge_mode    = "opt-in",                -- or "prefer" for all tasks
   ```

   then `service start cluster-manager`. Confirm with `cluster-manager status`
   ("worker bridge: N OpenOS worker(s)") and `cluster-manager workers`.

2. **On each OpenOS worker**, copy **both** `cluster/openos/cluster-worker.lua`
   and `cluster/openos/cluster-worker-setup.lua` onto the machine (same
   directory), then run the setup:

   ```
   cluster-worker-setup
   ```

   It asks for the domain id, a name for this worker, and the shared secret,
   writes `/etc/cluster-worker.cfg`, and offers to add the daemon to
   `/etc/rc.cfg` so it starts at boot. It then prints exactly what the
   Manager's config needs to match.

   `shared_secret` and `domain_id` **must** match the Manager. Every frame is
   HMAC-authenticated: without a matching secret the worker refuses to run
   tasks and the Manager drops its frames. The wizard enforces a 16-character
   minimum and rejects secrets containing spaces, because it is an HMAC key
   rather than a password and a stray space is invisible in a config file. A
   worker that goes silent yields a `timeout` result, so an assignment never
   hangs.

   **Run it on the OpenOS box, not on TOS.** If you run it on a TOS machine it
   will tell you so, explain how it can tell, and point you at `cluster-setup`
   (choose Manager) instead — TOS machines join a cluster as Managers, and
   worker nodes are OpenOS-native by design.

   By hand instead, if you prefer:

   ```lua
   return { domain_id = 0, hostname = "wk-a", shared_secret = "a-long-shared-secret" }
   ```

## Requirements

- **ROOT** on the TOS session — setup touches `/etc`, the trust DB and rc
  service state.
- A modem on every node. Wireless is easiest; wired works if every node is
  cabled to the Master.
- The Optional Utilities disk (or any repo carrying the two packages) in the
  machine when you run `cluster-setup`, unless the package is already
  installed.

## What it does not do

- **No Master auto-discovery.** You type the Master's address. A
  "any Masters out there?" broadcast would let anyone on the OC network lure
  a fresh Manager onto a rogue Master just by answering first, so this is
  deliberate rather than unfinished.
- **No rollback.** If something fails mid-way the wizard says what failed and
  stops; re-running it is safe and is the intended recovery.
- **No first-boot account setup.** TOS's own first-boot password flow has to
  have run already — `cluster-setup` refuses without a root session.

## Legacy files in this directory

`cluster-install.lua` is superseded and now just points at `cluster-setup`.
It used `io.read` and ANSI colour codes, neither of which works in the panels
shell: TOS's display is GPU-driven and interprets no escape sequences, and
`io.read` resolves to `term.read`, which paints straight to the screen and
takes over the event loop. It also printed the Master's address truncated
inside a "copy this" command line, and its "start at boot?" question wrote the
package-enable byte instead of the rc marker, so the answer had no effect
either way.

`cluster-make-floppy.lua` still builds a standalone cluster floppy if you want
one, but it is no longer the recommended path — the Optional Utilities disk
already carries both packages.
