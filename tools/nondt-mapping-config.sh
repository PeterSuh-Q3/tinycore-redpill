#!/usr/bin/env bash
# Pure JSON transformations: stdout only; caller owns persistence and rollback.
set -eu
operation=${1:-}
config=${2:-}
[ -r "$config" ] && jq -e 'type == "object" and ((.extra_cmdline // {}) | type == "object")' "$config" >/dev/null || exit 2
case "$operation" in
  snapshot)
    jq '{schema:1, values:(.extra_cmdline // {} | with_entries(select(.key == "SataPortMap" or .key == "DiskIdxMap")))}' "$config"
    ;;
  apply)
    portmap=${3:-}; idxmap=${4:-}
    [[ "$portmap" =~ ^[1-9]+$ ]] || exit 2
    [[ "$idxmap" =~ ^[0-9a-fA-F]+$ ]] || exit 2
    [ "${#idxmap}" -eq $((2 * ${#portmap})) ] || exit 2
    offset=0
    for ((i=0; i<${#portmap}; i++)); do
      expected=$(printf '%02x' "$offset")
      actual=${idxmap:$((2*i)):2}
      [ "${actual,,}" = "$expected" ] || exit 2
      offset=$((offset + ${portmap:i:1}))
      [ "$offset" -le 256 ] || exit 2
    done
    jq -e --argjson count "$offset" '
      (.synoinfo.maxdisks | tostring | test("^[0-9]{1,3}$")) and
      ((.synoinfo.maxdisks | tonumber) >= $count) and
      (((.extra_cmdline // {}).sata_remap // "") == "") and
      ([((.general.usb_line // ""), (.general.sata_line // "")) | gsub("[[:space:]]+"; " ") | split(" ")[] | select(. == "sata_remap" or startswith("sata_remap="))] | length == 0)
    ' "$config" >/dev/null || { echo 'Mapping conflicts with maxdisks or sata_remap' >&2; exit 2; }
    jq --arg p "$portmap" --arg i "$idxmap" '.extra_cmdline //= {} | .extra_cmdline.SataPortMap=$p | .extra_cmdline.DiskIdxMap=$i' "$config"
    ;;
  restore)
    snapshot=${3:-}
    [ -r "$snapshot" ] && jq -e '.schema == 1 and (.values | type == "object") and ([.values | keys[] | select(. != "SataPortMap" and . != "DiskIdxMap")] | length == 0)' "$snapshot" >/dev/null || exit 2
    jq --slurpfile snapshot "$snapshot" '.extra_cmdline //= {} | .extra_cmdline |= (del(.SataPortMap,.DiskIdxMap) + $snapshot[0].values)' "$config"
    ;;
  *) echo 'usage: nondt-mapping-config.sh snapshot|apply|restore config [arguments]' >&2; exit 2 ;;
esac
