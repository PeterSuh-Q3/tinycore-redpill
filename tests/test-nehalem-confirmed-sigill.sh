#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
hash=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
make_report() {
  jq -n --arg hash "$hash" --arg state "$1" --arg signal "$2" \
    '{schema:"mshell-nehalem-loader-v1",attempt:"attempt-1",artifact_sha256:$hash,status:$state,evidence:{kind:"allowlisted-nehalem-execution",signal:$signal,exit_code:132,file_sha256:$hash,tool:"qemu-x86_64 9.0"}}' > "$tmp/report.json"
}
make_report FAIL SIGILL
sh "$root/tools/nehalem-confirmed-sigill.sh" "$tmp/report.json" attempt-1
if sh "$root/tools/nehalem-confirmed-sigill.sh" "$tmp/report.json" attempt-2; then exit 1; fi
for state in PASSED WARN UNTESTED SKIPPED; do
  make_report "$state" SIGILL
  if sh "$root/tools/nehalem-confirmed-sigill.sh" "$tmp/report.json" attempt-1; then exit 1; fi
done
make_report FAIL SIGTERM
if sh "$root/tools/nehalem-confirmed-sigill.sh" "$tmp/report.json" attempt-1; then exit 1; fi
printf '{invalid\n' > "$tmp/report.json"
if sh "$root/tools/nehalem-confirmed-sigill.sh" "$tmp/report.json" attempt-1; then exit 1; fi
echo 'Confirmed SIGILL retry-gate tests passed'
