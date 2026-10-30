#!/usr/bin/env bash
# Pure arithmetic only. Caller must independently validate controller order,
# port availability, boot disk, HBA and actual DSM behavior before applying.
set -eu
if [ "$#" -lt 2 ]; then echo 'usage: nondt-mapping-calculate.sh maxdisks port-count...' >&2; exit 2; fi
maxdisks=$1; shift
case "$maxdisks" in ''|*[!0-9]*) echo 'Invalid maxdisks' >&2; exit 2 ;; esac
[ "${#maxdisks}" -le 3 ] || { echo 'Invalid maxdisks' >&2; exit 2; }
maxdisks=$((10#$maxdisks))
if [ "$maxdisks" -lt 1 ] || [ "$maxdisks" -gt 256 ]; then echo 'maxdisks outside supported range' >&2; exit 2; fi
offset=0
portmap=''
idxmap=''
for count in "$@"; do
  case "$count" in [1-9]) ;; *) echo 'Only port counts 1 through 9 are supported' >&2; exit 2 ;; esac
  if [ "$offset" -gt 255 ] || [ $((offset + count)) -gt "$maxdisks" ]; then
    echo 'Candidate exceeds index or maxdisks limit' >&2
    exit 2
  fi
  portmap="${portmap}${count}"
  idxmap="${idxmap}$(printf '%02x' "$offset")"
  offset=$((offset + count))
done
jq -n --arg portmap "$portmap" --arg idxmap "$idxmap" --argjson count "$offset" \
  '{SataPortMap:$portmap,DiskIdxMap:$idxmap,allocated_ports:$count,verified:false}'
