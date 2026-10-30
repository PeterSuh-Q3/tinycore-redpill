#!/usr/bin/env bash
# Validate an explicitly supplied disk-index permutation. Never infer DSM order.
set -eu
if [ "${1:-}" = --generate ]; then
  current=${2:-}; desired=${3:-}
  [[ "$current" =~ ^[0-9]+(,[0-9]+)*$ && "$desired" =~ ^[0-9]+(,[0-9]+)*$ ]] || exit 2
  IFS=, read -r -a from_list <<< "$current"
  IFS=, read -r -a to_list <<< "$desired"
  [ "${#from_list[@]}" -eq "${#to_list[@]}" ] || exit 2
  declare -A from_seen=() to_seen=()
  mapping=''
  for ((i=0; i<${#from_list[@]}; i++)); do
    from=${from_list[$i]}; to=${to_list[$i]}
    [[ ${#from} -le 3 && ${#to} -le 3 ]] || exit 2
    from=$((10#$from)); to=$((10#$to))
    (( from <= 255 && to <= 255 )) || exit 2
    [[ ! ${from_seen[$from]+yes} && ! ${to_seen[$to]+yes} ]] || exit 2
    from_seen[$from]=1; to_seen[$to]=1
    if (( from != to )); then
      [ -z "$mapping" ] || mapping+=':'
      mapping+="$from>$to"
    fi
  done
  for from in "${!from_seen[@]}"; do [[ ${to_seen[$from]+yes} ]] || exit 2; done
  [ -n "$mapping" ] || { echo 'No index changes requested' >&2; exit 2; }
else
  mapping=${1:-}
fi
[[ "$mapping" =~ ^[0-9]+\>[0-9]+(:[0-9]+\>[0-9]+)*$ ]] || exit 2
declare -A sources=() targets=()
IFS=: read -r -a pairs <<< "$mapping"
for pair in "${pairs[@]}"; do
  from=${pair%%>*}; to=${pair#*>}
  [[ ${#from} -le 3 && ${#to} -le 3 ]] || exit 2
  from=$((10#$from)); to=$((10#$to))
  (( from <= 255 && to <= 255 && from != to )) || exit 2
  [[ ! ${sources[$from]+yes} && ! ${targets[$to]+yes} ]] || exit 2
  sources[$from]=1; targets[$to]=1
done
for from in "${!sources[@]}"; do [[ ${targets[$from]+yes} ]] || exit 2; done
printf '%s\n' "$mapping"
