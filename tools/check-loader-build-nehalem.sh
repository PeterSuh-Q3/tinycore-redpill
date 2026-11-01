#!/bin/sh
# Advisory inspection of the completed initrd. Never execute its contents.
set -u
mode=auto initrd= report=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --auto) mode=auto;;
    --force) mode=force;;
    --initrd|--report) key=$1; shift; [ "$#" -gt 0 ] || exit 2; [ "$key" = --initrd ] && initrd=$1 || report=$1;;
    *) exit 2;;
  esac
  shift
done
[ -r "$initrd" ] && [ -n "$report" ] || exit 2
case "$report" in /*) ;; *) exit 2;; esac
umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/mshell-nehalem.XXXXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM
hash=$(sha256sum "$initrd" | awk '{print $1}')
gate_tool="$(dirname "$0")/nehalem-cpu-gate.sh"
gate=UNKNOWN
[ -r "$gate_tool" ] && gate=$(sh "$gate_tool" "${MSHELL_NEHALEM_CPUINFO:-/proc/cpuinfo}" 2>/dev/null)
case "$gate" in SKIP|CHECK|UNKNOWN) ;; *) gate=UNKNOWN;; esac
status=UNTESTED reason= checked=0 warnings=0 untested=0
items="$work/items.jsonl"
: > "$items"
manifest="$(dirname "$0")/nehalem-loader-build-targets.v1.json"
manifest_sha=unavailable
[ -r "$manifest" ] && manifest_sha=$(sha256sum "$manifest" | awk '{print $1}')
file_count=0 total_bytes=0 sequence=0 scan_limit_hit=0

record_elf() {
  local blob=$1 path=$2 kind=$3 magic machine linkage verdict itemhash disasm tested_hash tested_cpu
  magic=$(od -An -tx1 -N4 "$blob" | tr -d ' \n')
  [ "$magic" = 7f454c46 ] || return 0
  [ "$kind" = kernel-module ] || kind=elf
  checked=$((checked+1))
  machine=$(readelf -h "$blob" 2>/dev/null | awk -F: '/Machine:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
  [ -n "$machine" ] || machine=unknown
  if readelf -l "$blob" 2>/dev/null | grep -q 'Requesting program interpreter'; then linkage=dynamic; else linkage='static-or-relocatable'; fi
  disasm="$work/disassembly.$checked"
  if [ "$machine" = unknown ] || ! objdump -d "$blob" > "$disasm" 2>/dev/null; then
    verdict=UNTESTED; untested=$((untested+1))
  elif LC_ALL=C grep -Eq '[[:space:]](v[a-z0-9]+|shlx|shrx|sarx|blsr|blsi|bzhi|pdep|pext)([[:space:]]|$)' "$disasm"; then
    warnings=$((warnings+1)); verdict=WARN
  else
    verdict=PASSED
  fi
  itemhash=$(sha256sum "$blob" | awk '{print $1}')
  tested_hash=$(jq -r --arg path "$path" '.targets[] | . as $target | select($path == $target.path or ($path | startswith($target.path + " (")) or ($path | startswith($target.path + "!/"))) | .runtime_tested.sha256 // empty' "$manifest" 2>/dev/null | sed -n '1p')
  tested_cpu=$(jq -r --arg path "$path" '.targets[] | . as $target | select($path == $target.path or ($path | startswith($target.path + " (")) or ($path | startswith($target.path + "!/"))) | .runtime_tested.cpu // empty' "$manifest" 2>/dev/null | sed -n '1p')
  if [ "$verdict" = WARN ] && [ -n "$tested_hash" ] && [ "$itemhash" = "$tested_hash" ] && [ -n "$tested_cpu" ]; then
    jq -cn --arg path "$path" --arg sha256 "$itemhash" --arg type "$kind" --arg status "$verdict" \
      --arg display_status 'PASSED (AVX present; runtime-tested)' --arg tested_cpu "$tested_cpu" \
      --arg architecture "$machine" --arg linkage "$linkage" \
      '{path:$path,sha256:$sha256,type:$type,status:$status,display_status:$display_status,runtime_tested_cpu:$tested_cpu,architecture:$architecture,linkage:$linkage,scope:"AVX is present; exact artifact runtime-tested on the listed CPU; this does not establish Nehalem execution"}' >> "$items"
    return 0
  fi
  jq -cn --arg path "$path" --arg sha256 "$itemhash" --arg type "$kind" --arg status "$verdict" \
    --arg architecture "$machine" --arg linkage "$linkage" \
    '{path:$path,sha256:$sha256,type:$type,architecture:$architecture,linkage:$linkage,status:$status,scope:"static Nehalem-instruction scan; runtime execution not performed"}' >> "$items"
}

scan_blob() {
  local blob=$1 path=$2 depth=$3 kind=${4:-other} bytes magic member expanded list members child child_kind
  [ "$depth" -le 3 ] || { untested=$((untested+1)); return; }
  bytes=$(wc -c < "$blob" | tr -d ' ')
  if [ "$bytes" -gt 67108864 ]; then untested=$((untested+1)); return; fi
  record_elf "$blob" "$path" "$kind"
  magic=$(od -An -tx1 -N4 "$blob" | tr -d ' \n')
  [ "$magic" != 7f454c46 ] || return 0

  case "$path" in
    */custom-modules/*.tgz|*/all-modules/*.tgz|*/custom-modules/*.tar.gz|*/all-modules/*.tar.gz)
      jq -cn --arg path "$path" --arg sha256 "$(sha256sum "$blob" | awk '{print $1}')" \
        '{path:$path,sha256:$sha256,type:"module-pack",status:"SKIPPED",scope:"module pack excluded by policy"}' >> "$items"
      return 0;;
  esac

  if gzip -t "$blob" >/dev/null 2>&1; then
    sequence=$((sequence+1)); member="$work/decompressed.$sequence"
    (ulimit -f 131072; gzip -dc "$blob" > "$member") 2>/dev/null || { untested=$((untested+1)); rm -f "$member"; return; }
    expanded=$(wc -c < "$member" | tr -d ' '); total_bytes=$((total_bytes+expanded))
    if [ "$total_bytes" -gt 536870912 ]; then scan_limit_hit=1; untested=$((untested+1)); rm -f "$member"; return; fi
    scan_blob "$member" "$path (gzip content)" $((depth+1)); rm -f "$member"; return
  fi
  if xz -t "$blob" >/dev/null 2>&1; then
    sequence=$((sequence+1)); member="$work/decompressed.$sequence"
    (ulimit -f 131072; xz -dc "$blob" > "$member") 2>/dev/null || { untested=$((untested+1)); rm -f "$member"; return; }
    expanded=$(wc -c < "$member" | tr -d ' '); total_bytes=$((total_bytes+expanded))
    if [ "$total_bytes" -gt 536870912 ]; then scan_limit_hit=1; untested=$((untested+1)); rm -f "$member"; return; fi
    scan_blob "$member" "$path (xz content)" $((depth+1)); rm -f "$member"; return
  fi

  if bsdtar -tf "$blob" > "$work/nested-paths.$sequence" 2>/dev/null; then
    list="$work/nested-paths.$sequence"; members=$(wc -l < "$list" | tr -d ' ')
    [ "$members" -le 2000 ] || { untested=$((untested+1)); scan_limit_hit=1; return; }
    while IFS= read -r child; do
      file_count=$((file_count+1)); [ "$file_count" -le 10000 ] || { scan_limit_hit=1; untested=$((untested+1)); break; }
      case "$child" in ''|/*|*'..'*|*'\\'*|*[![:print:]]*) untested=$((untested+1)); continue;; esac
      child_kind=$(bsdtar -tvf "$blob" "$child" 2>/dev/null | sed -n '1p')
      case "$child_kind" in -*) ;; *) continue;; esac
      sequence=$((sequence+1)); member="$work/member.$sequence"
      bsdtar -xOf "$blob" "$child" > "$member" 2>/dev/null || { untested=$((untested+1)); continue; }
      expanded=$(wc -c < "$member" | tr -d ' '); total_bytes=$((total_bytes+expanded))
      if [ "$expanded" -gt 67108864 ] || [ "$total_bytes" -gt 536870912 ]; then
        scan_limit_hit=1; untested=$((untested+1)); rm -f "$member"; continue
      fi
      child_path="$path!/$child"
      case "$child_path" in *.ko) child_kind=kernel-module;; *) child_kind=other;; esac
      scan_blob "$member" "$child_path" $((depth+1)); rm -f "$member"
    done < "$list"
  fi
}
if [ "$mode" = auto ] && [ "$gate" = SKIP ]; then
  status=SKIPPED reason='builder exposes AVX and BMI2 on every CPU'
elif [ "$mode" = auto ] && [ "$gate" = UNKNOWN ]; then
  reason='builder CPU flags are unavailable or inconsistent'
else
  missing=
  for tool in cpio xz gzip bsdtar objdump readelf jq sha256sum; do command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"; done
  [ -r "$manifest" ] || missing="$missing target-manifest"
  if [ -n "$missing" ]; then
    reason="required inspection tools missing:$missing"
  else
    size=$(wc -c < "$initrd" | tr -d ' ')
    if [ "$size" -gt 536870912 ]; then
      reason='initrd exceeds 512 MiB inspection limit'
    else
      archive="$work/initrd.cpio"
      if xz -t "$initrd" >/dev/null 2>&1; then
        # Bound the decompressed size; avoid a large or hostile archive.
        (ulimit -f 1048576; xz -dc "$initrd" > "$archive") 2>/dev/null || reason='initrd decompression failed or exceeded limit'
      else
        cp "$initrd" "$archive" || reason='cannot stage initrd for inspection'
      fi
      if [ -z "$reason" ]; then
        cpio -it < "$archive" > "$work/paths" 2>/dev/null || reason='cannot list initrd archive'
      fi
      if [ -z "$reason" ]; then
        jq -e '.schema_version == 1 and (.targets | type == "array")' "$manifest" >/dev/null 2>&1 || reason='invalid build-target manifest'
      fi
      if [ -z "$reason" ]; then
        # Only inspect artifacts explicitly tied to repository-owned build recipes.
        : > "$work/selected"
        target_count=$(jq '.targets | length' "$manifest")
        i=0
        while [ "$i" -lt "$target_count" ]; do
          target_path=$(jq -r ".targets[$i].path" "$manifest")
          target_required=$(jq -r ".targets[$i].required // false" "$manifest")
          if grep -Fxq "$target_path" "$work/paths"; then
            printf '%s\n' "$target_path" >> "$work/selected"
          else
            if [ "$target_required" = true ]; then target_status=UNTESTED; untested=$((untested+1)); else target_status=SKIPPED; fi
            jq -cn --arg path "$target_path" --arg status "$target_status" \
              '{path:$path,status:$status,scope:"allowlisted build output absent from this initrd (optional/not selected)"}' >> "$items"
          fi
          i=$((i+1))
        done
        count=$(wc -l < "$work/selected" | tr -d ' ')
        [ "$count" -le 2000 ] || reason='build-target list exceeds inspection limit'
      fi
      if [ -z "$reason" ]; then
        while IFS= read -r path; do
          case "$path" in *'..'*|/*|*'\\'*|'') continue;; esac
          kind_line=$(bsdtar -tvf "$archive" "$path" 2>/dev/null | sed -n '1p')
          case "$kind_line" in -*) ;; *) continue;; esac
          bsdtar -xOf "$archive" "$path" > "$work/item" 2>/dev/null || { untested=$((untested+1)); continue; }
          case "$path" in *.ko) kind=kernel-module;; *) kind=other;; esac
          scan_blob "$work/item" "$path" 0 "$kind"
        done < "$work/selected"
        if [ "$warnings" -gt 0 ]; then status=WARN
        elif [ "$untested" -gt 0 ]; then status=UNTESTED
        else status=PASSED
        fi
        reason='allowlisted workflow/script build outputs passed the static Nehalem instruction scan; runtime execution was not performed'
        [ "$scan_limit_hit" = 0 ] || reason="$reason; one or more archive safety limits were reached"
      fi
    fi
  fi
fi
tmp="${report}.tmp.$$"
jq -s --arg schema 'mshell-nehalem-loader-v1' --arg attempt "${MSHELL_NEHALEM_ATTEMPT:-standalone}" \
  --arg target_manifest_sha256 "$manifest_sha" \
  --arg sha256 "$hash" --arg gate "$gate" --arg mode "$mode" --arg status "$status" --arg reason "$reason" \
  --argjson checked "$checked" --argjson warnings "$warnings" --argjson untested "$untested" \
  '{schema:$schema,attempt:$attempt,artifact_sha256:$sha256,target_manifest_sha256:$target_manifest_sha256,cpu_gate:$gate,mode:$mode,status:$status,reason:$reason,checked:$checked,warnings:$warnings,untested:$untested,files:.}' \
  "$items" > "$tmp" 2>/dev/null && mv -f "$tmp" "$report" || { rm -f "$tmp"; exit 2; }
