#!/bin/sh
set -eu

config_file=${1:?usage: set-target-cpu-snapshot.sh USER_CONFIG.json supported|unknown}
capability=${2:-unknown}

case "$capability" in
    supported)
        snapshot='{"flags_known":true,"flags":["bmi2"],"source":"issue-target-confirmed"}'
        ;;
    unknown)
        snapshot='{"flags_known":false,"flags":[],"source":"target-unknown"}'
        ;;
    *)
        echo "Invalid target CPU BMI2 capability: $capability" >&2
        exit 2
        ;;
esac

[ -f "$config_file" ] || {
    echo "User config not found: $config_file" >&2
    exit 1
}

tmp_file="${config_file}.tmp.$$"
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
jq --argjson target_cpu "$snapshot" '.general.target_cpu = $target_cpu' "$config_file" > "$tmp_file"
mv -f "$tmp_file" "$config_file"
