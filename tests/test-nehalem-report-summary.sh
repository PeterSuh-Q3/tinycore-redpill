#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
hash=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
jq -n --arg hash "$hash" '{schema:"mshell-nehalem-loader-v1",attempt:"one",artifact_sha256:$hash,cpu_gate:"CHECK",status:"UNTESTED",reason:"static only",checked:1,warnings:0,untested:1,files:[]}' > "$tmp/report.json"
sh "$root/tools/nehalem-report-summary.sh" "$tmp/report.json" one | grep -q 'Nehalem compatibility: UNTESTED'
jq '.files=[{path:"exts/example",display_status:"PASSED (AVX present; runtime-tested)"}]' "$tmp/report.json" > "$tmp/avx-report.json"
sh "$root/tools/nehalem-report-summary.sh" "$tmp/avx-report.json" one | grep -q 'PASSED (AVX present; runtime-tested): exts/example'
sh "$root/tools/nehalem-report-summary.sh" "$tmp/report.json" two | grep -q 'NOT RUN'
printf '{broken\n' > "$tmp/report.json"
sh "$root/tools/nehalem-report-summary.sh" "$tmp/report.json" one | grep -q 'NOT RUN'
: > "$tmp/report.json.attempted"
sh "$root/tools/nehalem-report-summary.sh" "$tmp/report.json" one | grep -q 'UNTESTED'
echo 'Report summary tests passed'
