<!-- Opening this against `main`? Please retarget it to `dev`. -->

## Targeting

- [ ] This PR targets **`dev`**, not `main`.

`main` is a build artifact generated from `dev` by `build/strip.lua`.
A commit made against `main` is overwritten by the next release build.

## What this changes

<!-- What changed, and why. If it is a design decision rather than a fix,
     say what you considered and rejected. -->

## Verification

- [ ] `python run_tests.py` passes
- [ ] New/changed runtime files are listed in `tos/system_manifest.lua`
- [ ] Security-relevant comments use the `--!` marker so the release build keeps them

<!-- Paste the test summary line. -->
