#!/bin/sh
# Validate an untrusted per-attempt report; do not source it or trust log markers.
report=${1:-} expected=${2:-}
if [ -n "$report" ] && [ -f "$report" ] && command -v jq >/dev/null 2>&1 && \
  jq -e --arg attempt "$expected" '
    .schema == "mshell-nehalem-loader-v1" and .attempt == $attempt and
    (.artifact_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
    (.cpu_gate | IN("SKIP","CHECK","UNKNOWN")) and
    (.status | IN("SKIPPED","UNTESTED","WARN","PASS","FAIL")) and
    (.checked | type == "number" and . >= 0) and
    (.warnings | type == "number" and . >= 0) and
    (.untested | type == "number" and . >= 0) and
    (.reason | type == "string" and length < 512) and
    (.files | type == "array")
  ' "$report" >/dev/null 2>&1; then
  jq -r --arg report "$report" '"Nehalem compatibility: \(.status) — \(.reason); CPU gate=\(.cpu_gate); checked=\(.checked) warnings=\(.warnings) untested=\(.untested); report=\($report)"' "$report"
else
  if [ -n "$report" ] && [ -f "${report}.attempted" ]; then
    echo 'Nehalem compatibility: UNTESTED — checker unavailable, timed out, or returned an invalid report'
  else
    echo 'Nehalem compatibility: NOT RUN — loader build ended before compatibility check'
  fi
fi
