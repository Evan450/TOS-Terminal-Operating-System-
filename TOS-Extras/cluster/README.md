# cluster — spread work across several TOS machines

One **Master** machine accepts jobs and schedules them. Any number of **Manager** machines take assignments and run them, either themselves or on cheap **OpenOS worker** machines next to them. All of it travels over modems, and every machine is paired with the Master before it is trusted.

**To set one up, read [installer/README.md](installer/README.md).** In short: on each machine, as root, run `cluster-setup`. It is part of the base TOS image, picks the right package for the machine's role, installs it from the Optional Utilities disk, writes the configuration and handles pairing.

> **Known issue.** The operator commands `cluster` (on the Master) and `cluster-manager` (on a Manager) do not start at present. They were written to share the running service's state, and since the September sandbox hardening a program's libraries load privately inside its own sandbox. The services themselves run normally, and `cluster-setup` pairs machines without them. Restoring the commands is an open decision about what a trusted package's own program may reach.

## What's here

| Path | What it is |
|---|---|
| `master-skeleton/` | the `cluster-master` package: the `clusterd` service for the one control machine, and the `cluster` command |
| `manager-skeleton/` | the `cluster-manager` package: the service for each compute machine, and the `cluster-manager` command |
| `storage-skeleton/` | `cluster-storage` 0.1.0, an early storage node. Not on the published pack: the pack leaves out anything below 1.0.0, and its spec is still a draft. |
| `openos/` | the OpenOS worker, `cluster-worker.lua`, and its setup wizard, `cluster-worker-setup.lua`. These are copied onto OpenOS machines by hand, since TOS's package manager does not reach OpenOS. |
| `installer/` | the setup guide. `cluster-install.lua` and `cluster-make-floppy.lua` there are older tools, superseded by `cluster-setup`; the guide says what each still does. |

Both packages are services, so installing either needs root.

## Design documents

| Document | What it covers |
|---|---|
| [cluster-protocol-spec-draft.md](cluster-protocol-spec-draft.md) | the wire protocol, trust between machines, state machines and failure handling between Master, Manager and worker |
| [Plan.md](Plan.md) | the Master package's file layout and how its modules depend on one another |
| [error-conventions.md](error-conventions.md) | how every cluster module reports a failure, and how the code measures up |
| [build-patterns.md](build-patterns.md) | what to build in the Minecraft world so the cluster has machines to run on |
| [storage-spec-draft.md](storage-spec-draft.md) | a shared storage tier for the cluster (design) |
| [ai-operator-spec-draft.md](ai-operator-spec-draft.md) | an add-on in which a language model watches the cluster and drives the Master through a fixed list of operator actions (design) |

## Tests

The OpenOS side is tested from `TOS-Extras/`: `lua cluster/openos/test_cluster_worker_frames.lua` (the Manager's side of the worker bridge and the worker agree on every authenticated frame) and `lua cluster/openos/test_worker_setup.lua` (the setup wizard). The Master and Manager are tested in the base OS's suite, where they run against the real kernel modules; `python run_tests.py` in the TOS source runs all of them.
