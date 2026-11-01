#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
gate="$root/tools/nehalem-cpu-gate.sh"
check() {
  expected=$1
  input=$2
  actual=$(printf '%b' "$input" | sh "$gate" /dev/stdin)
  if [ "$actual" != "$expected" ]; then
    printf 'expected %s, got %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}
check SKIP 'processor : 0\nflags : avx bmi2\nprocessor : 1\nflags : bmi2 avx\n'
check CHECK 'processor : 0\nflags : avx\n'
check CHECK 'processor : 0\nflags : bmi2\n'
check CHECK 'processor : 0\nflags : avx2 bmi20\n'
check UNKNOWN 'processor : 0\nflags : avx bmi2\nprocessor : 1\nflags : avx\n'
check UNKNOWN 'processor : 0\nflags : avx bmi2\nprocessor : 1\n'
check UNKNOWN ''
echo 'CPU gate tests passed'
