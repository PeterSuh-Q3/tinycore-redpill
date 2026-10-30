#!/usr/bin/env bash
set -eu
base=$(cd "$(dirname "$0")/.." && pwd)
calc="$base/tools/nondt-mapping-calculate.sh"
result=$(bash "$calc" 12 4 2)
jq -e '.SataPortMap == "42" and .DiskIdxMap == "0004" and .allocated_ports == 6 and .verified == false' <<<"$result" >/dev/null
result=$(bash "$calc" 24 8 8 8)
jq -e '.SataPortMap == "888" and .DiskIdxMap == "000810"' <<<"$result" >/dev/null
for args in '4 4 2' '12 10' '12 0' '12 x' '0 1'; do
  # Deliberate word splitting of constant test arguments.
  if bash "$calc" $args >/dev/null 2>&1; then echo "Invalid candidate accepted: $args" >&2; exit 1; fi
done
echo 'Non-DT mapping calculator tests passed.'
