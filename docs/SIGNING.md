# Signing packages

`pkg` supports Ed25519 publisher signatures. An operator adds your public key once (`pkg trust add <label> <key>`), and from then on your packages verify as yours. With `pkg trust require on`, an operator can refuse anything unsigned.

Most contributors never sign anything: the maintainer signs the Optional Utilities pack. Read this if you publish packages of your own.

## The passphrase is the key

Your private key is derived from a passphrase, not stored anywhere, so the passphrase **is** the private key. Whoever has it signs as you.

- **It is never a command-line flag.** `tos.py` prompts for it without echoing, or reads `TOS_SIGNING_PASSPHRASE` if you have already exported it.
- **It must be at least 20 characters and use at least 10 distinct ones.**
- **Generate it; do not invent one:**

  ```bash
  python -c "import secrets; print(secrets.token_urlsafe(32))"
  ```

- **Store it in a password manager before you sign.** It is never written to disk, so there is no keyfile to back up. The passphrase is the only copy.

> [!WARNING]
> Lose the passphrase and you lose the identity. There is no recovery: the only remedy is to publish a new key and ask every operator who trusted the old one to trust the new one. Do not reuse the passphrase anywhere else.

Why the length rule is enforced rather than advised: the key is derived by SHA-512 over `TOS-pkg-signing-key-v2`, your publisher label and the passphrase, iterated 4096 times. That is deliberately cheap, because it has to run on a Tier 1 CPU that every seat shares, and cheap means *the passphrase's own entropy is the whole defence*. A derivation that could genuinely protect a memorable phrase needs on the order of 10⁵–10⁶ rounds, which is not reachable here.

## Your publisher label

**Your label is part of your key.** It salts the derivation, so the same passphrase under `acme` and under `Acme Corp` gives two different identities with two different public keys. Pick one label and keep using it. Case and surrounding whitespace are normalised (`Discover` and `discover` agree); nothing else is.

The label is public: it is printed beside the key in the README of the `optional-utilities` branch. Unlike the passphrase, it is fine on a command line.

What the salt does and does not buy: one precomputed passphrase-to-key table cannot yield every publisher's key at once, so each identity has to be attacked separately. It adds no secrecy of its own, and does nothing against someone targeting you specifically.

## Signing off-box, with `tos.py`

```
python tos.py key                      print your public key; signs nothing
python tos.py pack --sign              build a signed pack  <- to PUBLISH
python tos.py sign modules/mything     sign one source package, in place
python tos.py sign --all               every discovered source package
```

**`pack --sign` is the one that publishes.** The other two sign the *source* manifests. That is what you want when you hand someone a package directory to `pkg install` directly, but those signatures never reach the pack and cannot. The disk builder rewrites every manifest as it assembles, adding the `hashes` block, so the shipped bytes differ from the source bytes, and a signature over the source verifies as **invalid** against the shipped copy. `--sign` therefore signs the assembled manifests itself and ignores anything signed in the source tree.

Signing writes `package.sig` beside each `package.lua`. `programs.cfg` advertises every `package.sig`, so signatures travel over `pkg fetch` as well as on a floppy. That matters: `pkgremote` downloads only what the index lists, so an unadvertised signature means a package that is signed on the disk and arrives **unsigned** over the network. With `pkg trust require on`, that is the difference between installing and being refused.

## Signing on a TOS machine

```
pkg trust key <publisher-label>       prints the public key you sign as
pkg sign <directory> --as <name>      signs a package tree on-box
```

Both ask for the passphrase without echoing it. The argument is your *label*, which is public. The passphrase is never accepted on a command line, because the line is echoed as you type it and stays in the recall buffer for anyone at that seat. `--as` is required for the same reason as off-box: it salts the key, so signing without it would quietly produce a different identity.

Publish the key it prints; never the passphrase.
