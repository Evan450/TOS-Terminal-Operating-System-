# mail — mesh email

Addressed, store-and-forward mail between TOS machines, sealed end to end, with no server anywhere. A message hops across trusted relays until it reaches the machine it is for, and waits on the way if that machine is off.

The *transport* is part of the base OS (`tos/kernel/net/meshctl.lua`: flooded, de-duplicated, store-and-forward, end-to-end sealed, shared by any service that wants it). This package is the *mailbox*: where messages are kept, what a subject and a body are, the inbox and compose screens, and the boot service that accepts deliveries.

## Install

As **root**, with the Optional Utilities disk inserted:

```
pkg install mail
service start mail
```

Root rather than admin because mail is a service: it runs at boot, outside the package sandbox. It installs **disabled**, because receiving means accepting envelopes from trusted peers and writing them to disk, which is your decision to make. `service start mail` enables it and keeps it enabled across reboots. Until then the machine can send but not receive.

Install it on the machines that should *have* a mailbox. A TOS machine without it still relays mail for its trusted neighbours, since relaying is the transport's job and a relay cannot read the sealed payload anyway.

`mouse` is recommended, not required: with the driver installed the inbox tab is clickable.

## Use

```
mail                               open the inbox as a tab
mail send <to> [subject] [body…]   send from the command line
mail list                          list the inbox
mail read <n>                      read message n (marks it read)
mail delete <n>                    delete message n
mail ui                            the full-screen inbox in the CLI shell
```

In the inbox tab: arrows move, **Enter** reads, **c** composes (recipient, subject, then a multi-line body), **r** replies, **d** deletes and **R** refreshes. The inbox refreshes by itself while the tab is in front, and the tab's label carries an unread count, as in `Mail(2)`. **Ctrl+Q** closes the tab.

A recipient is a peer's address prefix, its hostname, `user@peer`, or `*` for every trusted peer.

- **Pair first.** Sending to a peer you have not paired with (`net pair`) is refused, not quietly sent in the clear.
- **`*` is a bulletin**, and bulletins are plaintext by definition. The screens label them as such.
- **Limits:** a subject is cut at 120 characters and a body at 4096, which keeps a sealed message under the mesh's size cap. An inbox keeps its newest 200 messages.

The base image has a `mail` command whether or not this package is installed. Without the package it prints how to install it.

## Files

| Installed at | What it is |
|---|---|
| `/usr/lib/mail.lua` | the mailbox, sending, and the delivery handler |
| `/usr/lib/mailui.lua` | the full-screen inbox for the CLI shell |
| `/usr/lib/mailapp.lua` | the inbox tab, found by the panels app registry |
| `/etc/rc.d/mail.lua` | the boot service that registers the delivery handler |

Mail is kept in `/var/mail/<user>/inbox.dat`. Only its owner, or an admin, can read an inbox, and that is checked against the session the kernel stamped on the calling process, not against anything the caller says about itself.

## Design notes

mail is a full-privilege package, like `blockfs`: its libraries live in `/usr/lib` and are loaded by the base shell and by rc with the real `require`, so they can use the kernel's network and filesystem directly. It declares no sandboxed commands of its own. The base image keeps only the thin `mail` command, which hands this package the shell's display and session.

Receiving happens in the boot service rather than in the inbox screen so that store-and-forward works with nobody logged in.

## Tests

From `TOS-Extras/`: `lua modules/mail/test_mail.lua` covers the mailbox (adding, de-duplicating, pruning, read and delete), the delivery handler, and the owner-or-admin rule on reading an inbox. The transport has its own tests in the base OS, `usr/lib/tests/test_meshctl.lua`. `python run_tests.py` in the TOS source runs both.
