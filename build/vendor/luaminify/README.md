# Vendored: stravant/LuaMinify

Source: https://github.com/stravant/LuaMinify, commit `cce8f5b51bdffd1e0439956ccc308d0e5d164f90` (2019-02-19, the tip of `master` as of 2026-10-17). MIT licensed — see `LICENSE.md`, unmodified.

Only the four files `strip.lua`'s driver (`build/minify_vars.lua`) actually
needs are vendored: `ParseLua.lua`, `Scope.lua`, `Util.lua`,
`FormatMini.lua`. Upstream also ships `FormatBeautiful.lua`,
`FormatIdentity.lua`, command-line wrappers, a Roblox Studio plugin and a
`strict.lua` dev aid — none of those are used here and none are vendored.

`DedupStrings.lua` is a fifth file in this directory but is **not**
upstream LuaMinify — it is a TOS addition that runs between parsing and
formatting, documented in its own header comment rather than here.

## Why vendored and patched, not used as-is

Upstream's parser predates, and has no support for, Lua 5.3's bitwise/shift
operators (`& | ~ << >>`) or floor division (`//`) — it hard-errors on all
five. TOS requires Lua 5.3+ (5.2 is explicitly rejected at boot — see
`tos/kernel/hal.lua`), and `tos/kernel/sha256.lua` alone uses every one of
them in its core compression function. This is not an edge case; it is
load-bearing cryptography. Upstream also targets Roblox's Lua dialect
(the repo ships a Roblox Studio plugin), which has never had these
operators, which is almost certainly why they were never added.

## What was changed, and why each piece is safe

All changes are marked `-- TOS PATCH` in place, in both files.

**`ParseLua.lua` — lexer**
- `&` and `|` added as plain single-character symbols.
- `~` is no longer a hard parse error when not followed by `=`. Previously
  only `~=` was accepted; bare `~` (bitwise xor as a binary operator, or
  bitwise not as a unary one) now lexes as its own `Symbol` token, exactly
  parallel to how `~=` already worked.
- `/` moved out of the generic `Symbols` table into its own lexer branch
  so it can look ahead for a second `/` and emit `//` (floor division) —
  mirrors the existing handling of `.` looking ahead for `..`/`...`.
- `<` and `>` (inside the existing combined `>=<` branch, which already
  handles `<=`/`>=`/`==`) gained two more `elseif` arms: a repeated `<`
  or `>` emits `<<`/`>>`. Checked AFTER the existing `=` check, so
  `<=`/`>=`/`==` are produced exactly as before; the new arms are only
  reached when that check fails and the character repeats itself.

**`ParseLua.lua` — parser (operator precedence)**
- `~` added to `unops` (Lua gives all four unary operators — `not`, `#`,
  `-`, `~` — the same precedence tier; this reuses the existing
  `unopprio`, no new tier needed). Whether a `~` is unary (bitwise not) or
  binary (xor) is purely positional — `ParseSubExpr` already only
  consults `unops` at the START of an expression and the binary
  `priority` table when continuing one — so this falls out of the
  existing structure with no further change, the same way real Lua
  disambiguates it.
- `|`, `~` (binary), `&`, `<<`, `>>` added to the `priority` table at
  fractional levels (`3.1`..`3.4`) between the existing comparison tier
  (`3`) and concat (`5`/`4`) — matching real Lua 5.3 precedence order
  (`|` loosest, `<<`/`>>` tightest, among these five) without renumbering
  every existing entry; the comparisons that consult this table are
  ordinary arithmetic on these numbers, so a fractional level is exactly
  as valid as an adjacent integer one. All five are left-associative
  (equal left/right values, like the existing arithmetic/comparison
  entries) — none of Lua's new 5.3 operators are right-associative the
  way `..` and `^` are, so the formatter's existing special case for
  those two needed no change.
- `//` added to the existing `*`/`/`/`%` tier (`{7,7}`) — Lua gives it the
  same precedence as the other multiplicative operators.

**`ParseLua.lua` — removed, not patched**
- The upstream `require'strict'` at the top of the file is gone. It
  installs a metatable on `_G` that errors on any undeclared global
  access for the rest of that Lua process — a dev aid with no bearing on
  parsing or formatting correctness, and not something a build tool
  should spring on whatever else happens to run in the same process.

**`FormatMini.lua` — a real upstream bug, not a TOS-specific patch**
- `LabelStatement` and `GotoStatement` both called an undefined global
  `getIndentation()` — copy-pasted from `FormatBeautiful.lua`, which
  tracks indentation for pretty-printing; `FormatMini` has no indentation
  concept anywhere else in the file. Any file with a `goto` or a `::label::`
  hard-errored the first time this formatter ever tried to emit one.
  Found by running it over every real TOS source file:
  `tos/kernel/init.lua`, `tos/shell/syntax.lua` and
  `tos/shell/panels/commands/admin.lua` all use `goto`. Fixed by just not
  calling it — `out = "::" .. statement.Label .. "::"` and
  `out = "goto " .. statement.Label`, matching every other branch in this
  function.

**`Scope.lua` — naming strategy, not a correctness patch**
- Upstream's `ObfuscateLocals` (what `FormatMini` calls, via
  `ObfuscateVariables`) generates RANDOM names 1-8 characters long. That
  is the right shape for obfuscation — resisting pattern-matching — but
  actively counterproductive for size: a 1-character original name can
  come back as a 6-character random one, making the file BIGGER. Added
  `MinifyLocals`: the shortest not-yet-used identifier, in a fixed,
  deterministic order (`a, b, c, ... z, A, ... Z, _, aa, ab, ...` —
  bijective base-53 counting, which is exactly what guarantees every
  1-character name is exhausted before any 2-character one is needed),
  skipping Lua's 22 reserved keywords. Uses the IDENTICAL collision check
  as `ObfuscateLocals` (`self:GetVariable`, which walks the parent scope
  chain and so also refuses a name that would shadow an enclosing local
  or collide with a used global) and touches only `self.Locals` — never
  `self.Globals` — so the only thing that differs from upstream is which
  names get picked, never what is safe to rename. `ParseLua.lua`'s
  `CreateScope` now points `ObfuscateVariables`/`RenameVars` at
  `MinifyLocals` instead of `ObfuscateLocals` (both methods are still
  present; `ObfuscateLocals` is simply unused).

## What is NOT renamed, by construction

Only `self.Locals` is ever touched (locals and function parameters).
Globals (`self.Globals`, a separate table) are never renamed. Table field
names (`MemberExpr`), string literals, and parenthesized sub-expressions
recorded as their own `Parentheses` AST node are always emitted verbatim —
`FormatMini`'s only paren-dropping logic is precedence-based and applies
only to a `BinopExpr`'s own recorded `ParenCount`, which is exactly the
mechanism the new operators' precedence entries above had to get right.

## Verification

Not just "does it parse" — every patch here was checked by actually
*running* both the original and the minified code and comparing results,
not by reading the diff and trusting it:

- A standalone operator smoke test (precedence, associativity, explicit
  parens that must survive vs. ones that are genuinely redundant) for
  all six new operators, checked by executing both versions and comparing
  return values — see `test_minify_vars.lua`.
- Every `.lua` file in the real `TOS-Release` build (130 files) minifies
  without error and the result still compiles (`load()`), for an
  additional 33.8% size reduction on top of the existing comment-strip +
  whitespace-minify pass.
- `tos/kernel/sha256.lua` and `tos/kernel/ed25519.lua` — the two most
  bitwise-operator-heavy and field-arithmetic-heavy modules in the kernel,
  and the ones with the most to lose from a precedence mistake — were
  minified and run against their real FIPS/RFC test vectors
  (`test_sha256.lua`, `test_ed25519.lua`), with identical results to the
  unminified originals.
- `DedupStrings.lua`: a repeated string is hoisted and the literal
  confirmed to appear exactly once in the output; below-threshold cases
  (too short, too few repeats) are confirmed to stay inline; the two
  exclusions (`f"str"` sugar, a `{foo=1}` table key) are confirmed to
  survive untouched even when they would otherwise qualify — all checked
  by running the minified code and comparing results, not just by
  reading the output.
