#!/usr/bin/env bash
#
# mayhem/test.sh — run syntax crate tests (built by mayhem/build.sh); emit CTRF.
set -uo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

unset RUSTFLAGS
log="$(mktemp)"
set +e
cargo test -p syntax -- --quiet >"$log" 2>&1
rc=$?
set -e

passed=0
failed=0
skipped=0
if grep -q 'test result:' "$log"; then
  line="$(grep 'test result:' "$log" | tail -1)"
  passed="$(printf '%s' "$line" | sed -nE 's/.* ([0-9]+) passed.*/\1/p')"
  failed="$(printf '%s' "$line" | sed -nE 's/.* ([0-9]+) failed.*/\1/p')"
  skipped="$(printf '%s' "$line" | sed -nE 's/.* ([0-9]+) ignored.*/\1/p')"
fi
passed="${passed:-0}"
failed="${failed:-0}"
skipped="${skipped:-0}"

if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then
  failed=1
fi

emit_ctrf "cargo-test" "$passed" "$failed" "$skipped"
