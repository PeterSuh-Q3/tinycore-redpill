#!/bin/sh
# Classify all CPUs visible to this builder; never infer flags from the host.
set -eu
cpuinfo=${1:-/proc/cpuinfo}
[ -r "$cpuinfo" ] || { echo UNKNOWN; exit 0; }
awk -F: '
  /^processor[[:space:]]*:/ { cpus++ }
  /^flags[[:space:]]*:/ {
    records++
    avx=0; bmi2=0
    n=split($2, f, /[[:space:]]+/)
    for (i=1; i<=n; i++) { if(f[i]=="avx") avx=1; if(f[i]=="bmi2") bmi2=1 }
    states[avx ":" bmi2]++
    if (!avx || !bmi2) missing=1
  }
  END {
    kinds=0; for (s in states) kinds++
    if (cpus == 0 || records != cpus || kinds != 1) print "UNKNOWN"
    else if (missing) print "CHECK"
    else print "SKIP"
  }
' "$cpuinfo"
