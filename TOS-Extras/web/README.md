# web — text-mode browser and the TOS-to-TOS fetch proxy

Design only; no code yet. `browser-spec-draft.md` is the design for a
text-mode web browser package plus the fetch proxy that lets a TOS box
*without* an internet card borrow one that has it, and the page cache
that turns a network of TOS machines into a small shared archive.

The browser itself is a package (`internet` + `fullscreen` capabilities),
never part of the base image — see `TOS-Dev/TODO.txt`, the deferred
OPERATOR IDEA entry from 2026-08-04.
