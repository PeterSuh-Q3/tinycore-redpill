#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -r -- "$tmp"' EXIT

# Source only the display helper; the full functions.sh has loader side effects.
# shellcheck disable=SC1090
source <(sed -n '/^show_nehalem_build_result() {/,/^}/p' "$root/functions.sh")
summary_tool="$root/tools/nehalem-report-summary.sh"
report="$tmp/report.json"
log="$tmp/build.log"
hash=$(printf 'a%.0s' {1..64})

jq -n --arg hash "$hash" \
  '{schema:"mshell-nehalem-loader-v1",attempt:"one",artifact_sha256:$hash,cpu_gate:"SKIP",status:"SKIPPED",reason:"builder exposes AVX and BMI2",checked:0,warnings:0,untested:0,files:[]}' > "$report"
show_nehalem_build_result "$report" one "$log" "$summary_tool" > "$tmp/display"
grep -qx 'Nehalem compatibility report:' "$tmp/display"
grep -q '"status": "SKIPPED"' "$tmp/display"
if grep -q '^Nehalem compatibility: SKIPPED' "$tmp/display"; then
    echo 'Duplicate summary appeared after the JSON report' >&2
    exit 1
fi
cmp "$tmp/display" "$log"

: > "$log"
show_nehalem_build_result "$tmp/missing.json" one "$log" "$summary_tool" > "$tmp/display"
grep -q 'Nehalem compatibility: NOT RUN' "$tmp/display"
cmp "$tmp/display" "$log"

printf 'not JSON\n' > "$report"
: > "${report}.attempted"
: > "$log"
show_nehalem_build_result "$report" one "$log" "$summary_tool" > "$tmp/display"
grep -q 'Nehalem compatibility: UNTESTED' "$tmp/display"
if grep -q 'not JSON' "$tmp/display"; then
    echo 'Malformed report was displayed as a valid result' >&2
    exit 1
fi
cmp "$tmp/display" "$log"

cmp "$root/functions.sh" "$root/functions_t.sh"
echo 'Final Nehalem report display tests passed.'
