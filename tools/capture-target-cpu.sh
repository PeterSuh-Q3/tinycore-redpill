#!/bin/sh
# Emit the intersection of CPU feature flags across processors on this host.
# Run on the destination DSM host; do not run it inside the remote builder.
set -eu

cpuinfo_file=${CPUINFO_FILE:-/proc/cpuinfo}
[ -r "$cpuinfo_file" ] || {
    printf '%s\n' '{"flags_known":false,"flags":[],"source":"target-snapshot"}'
    exit 0
}

flags=$(awk -F: '
    /^[[:space:]]*(flags|Features)[[:space:]]*:/ {
        count++
        value = $0
        sub(/^[^:]*:/, "", value)
        n = split(value, parts, /[^[:alnum:]_]+/)
        for (i = 1; i <= n; i++) if (parts[i] != "") current[count, parts[i]] = 1
        if (count == 1) {
            for (i = 1; i <= n; i++) if (parts[i] != "") common[parts[i]] = 1
        } else {
            for (flag in common) if (!((count SUBSEP flag) in current)) delete common[flag]
        }
    }
    END { for (flag in common) print flag }
' "$cpuinfo_file" | sort -u)

if ! grep -Eq '^[[:space:]]*(flags|Features)[[:space:]]*:' "$cpuinfo_file"; then
    printf '%s\n' '{"flags_known":false,"flags":[],"source":"target-snapshot"}'
    exit 0
fi

printf '%s\n' "$flags" | awk '
    BEGIN { printf "{\"flags_known\":true,\"flags\":["; first = 1 }
    NF { if (!first) printf ","; printf "\"%s\"", $0; first = 0 }
    END { printf "],\"source\":\"target-snapshot\"}\n" }
'
