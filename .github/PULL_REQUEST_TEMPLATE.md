<!-- Check the base branch shown at the top of this page. It must be `dev`. -->

## Targeting

- [ ] The base branch above is **`dev`** (not `main`).

`main` is a build artifact generated from `dev` by `build/strip.lua`, so a
commit landing on `main` is overwritten by the next release build. If the base
says `main`, change it before opening this.

## What this changes

<!-- What changed, and why. If it is a design decision rather than a fix,
     say what you considered and rejected. -->

## Verification

- [ ] `python run_tests.py` passes
- [ ] New/changed runtime files are listed in `tos/system_manifest.lua`
- [ ] Security-relevant comments use the `--!` marker so the release build keeps them

<!-- Paste the test summary line. -->
