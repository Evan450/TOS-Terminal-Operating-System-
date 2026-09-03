#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════╗
# ║  TOS centralized test harness (serial)                   ║
# ║                                                          ║
# ║  Runs EVERY test in one pass and reports one total:      ║
# ║   • TOS-Dev unit tests        usr/lib/tests/test_*.lua   ║
# ║   • Optional Utilities tests  ../TOS-Extras (pkg+build)  ║
# ║                                                          ║
# ║  PREFER `python run_tests.py` — same discovery + totals, ║
# ║  runs the ~110 files in PARALLEL (seconds vs a minute).  ║
# ║  This shell version stays as the no-Python fallback and  ║
# ║  the definition-of-record for pass/fail/skip semantics   ║
# ║  (the .py mirrors these rules exactly).                  ║
# ║                                                          ║
# ║  Dev-only: build-release.{sh,cmd} exclude BOTH runners   ║
# ║  from TOS-Release (test_release_excludes.lua guards it). ║
# ╚══════════════════════════════════════════════════════════╝
cd "$(dirname "$0")" || exit 1
DEV_DIR="$(pwd)"
pass=0; fail=0; skip=0; failed_list=""

# Per-test timeout (seconds): a hung test must not block the whole suite
# (review finding). `timeout` exits 124 on expiry — treated as failure below.
TEST_TIMEOUT="${TEST_TIMEOUT:-120}"
_run_lua() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TEST_TIMEOUT" lua "$1" 2>&1
  else
    lua "$1" 2>&1
  fi
}

# Run one test file (CWD-relative) and fold its result into the totals.
# A pass needs BOTH the marker AND exit code 0 (review finding): marker-only
# matching let a test print the marker and then crash in teardown and still
# count as a pass. Skip likewise requires a clean exit — a real failure whose
# output happens to contain "run inside TOS" must NOT be misfiled as skipped.
run_one() {
  local t="$1" out rc
  out=$(_run_lua "$t"); rc=$?
  local has_pass=0 has_fail=0 has_skip=0
  echo "$out" | grep -qE "All tests passed\.|\*\*\* ALL TESTS PASSED \*\*\*" && has_pass=1
  echo "$out" | grep -q "\*\*\* TESTS FAILED \*\*\*" && has_fail=1
  echo "$out" | grep -qi "not available; run inside TOS\|run inside TOS" && has_skip=1

  if [ "$rc" -eq 124 ]; then
    fail=$((fail+1)); failed_list="$failed_list $t"
    echo "=== FAILED (timed out after ${TEST_TIMEOUT}s): $t ==="
  elif [ "$rc" -eq 0 ] && [ "$has_pass" -eq 1 ]; then
    pass=$((pass+1))
  elif [ "$rc" -eq 0 ] && [ "$has_skip" -eq 1 ]; then
    skip=$((skip+1))
  elif [ "$has_pass" -eq 1 ] && [ "$rc" -ne 0 ]; then
    fail=$((fail+1)); failed_list="$failed_list $t"
    echo "=== FAILED (passed then exited $rc — teardown crash?): $t ==="
    echo "$out" | tail -5
  elif [ "$has_fail" -eq 1 ] || [ "$rc" -ne 0 ]; then
    fail=$((fail+1)); failed_list="$failed_list $t"
    echo "=== FAILED (exit $rc): $t ==="
    echo "$out" | grep -E "FAIL:|Results:" | head -20
    [ "$has_fail" -eq 0 ] && echo "$out" | tail -5
  else
    # Clean exit, no recognizable marker — surface for manual inspection.
    fail=$((fail+1)); failed_list="$failed_list $t"
    echo "=== UNCLEAR: $t ==="
    echo "$out" | tail -5
  fi
}

# ── TOS-Dev unit tests ──────────────────────────────────────
for t in usr/lib/tests/test_*.lua; do
  [ -f "$t" ] && run_one "$t"
done

# ── Optional Utilities (TOS-Extras) package + build tests ───
# Run from the Extras root so each test's relative module paths resolve.
EXTRAS="$DEV_DIR/../TOS-Extras"
if [ -d "$EXTRAS" ]; then
  cd "$EXTRAS" || exit 1
  # Add-ons that don't live under modules/ still ship tests. rbmk/ and
  # cluster/ were written and then silently never run for want of a glob
  # (rbmk/test_rbmk.lua alone is 72 assertions). Keep in step with
  # run_tests.py, which mirrors these rules.
  for t in modules/*/test_*.lua build/test_*.lua pane-ui/test_*.lua \
           rbmk/test_*.lua cluster/*/test_*.lua; do
    [ -f "$t" ] && run_one "$t"
  done
  cd "$DEV_DIR" || exit 1
fi

echo "-------------------------------------------"
echo "PASS=$pass FAIL=$fail SKIP(needs-TOS)=$skip"
[ -n "$failed_list" ] && echo "Failed/unclear:$failed_list"
# Exit 1 on ANY failure (not `exit $fail` — a shell exit status wraps mod 256,
# so 256 failures would report 0/success). 0 only when everything passed.
[ "$fail" -gt 0 ] && exit 1
exit 0
