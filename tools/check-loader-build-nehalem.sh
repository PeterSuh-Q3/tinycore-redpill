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
if [ "$mode" = auto ] && [ "$gate" = SKIP ]; then
  status=SKIPPED reason='builder exposes AVX and BMI2 on every CPU'
elif [ "$mode" = auto ] && [ "$gate" = UNKNOWN ]; then
  reason='builder CPU flags are unavailable or inconsistent'
else
  missing=
  for tool in cpio xz bsdtar objdump readelf jq sha256sum; do command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"; done
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
        # Only inspect selected extension files; no archive path is extracted to disk.
        LC_ALL=C awk '/^(\.\/)?exts\// && !/\.\./ && length($0)<512 {print}' "$work/paths" > "$work/selected"
        count=$(wc -l < "$work/selected" | tr -d ' ')
        if [ "$count" -gt 2000 ]; then reason='extension inventory exceeds 2000-file inspection limit'; fi
      fi
      if [ -z "$reason" ]; then
        while IFS= read -r path; do
          case "$path" in *'..'*|/*|*'\\'*|'') continue;; esac
          kind_line=$(bsdtar -tvf "$archive" "$path" 2>/dev/null | sed -n '1p')
          case "$kind_line" in -*) ;; *) continue;; esac
          # Stream regular-file bytes only; no destination path can be traversed.
          bsdtar -xOf "$archive" "$path" > "$work/item" 2>/dev/null || { untested=$((untested+1)); continue; }
          bytes=$(wc -c < "$work/item" | tr -d ' ')
          [ "$bytes" -le 67108864 ] || { untested=$((untested+1)); continue; }
          magic=$(od -An -tx1 -N4 "$work/item" | tr -d ' \n')
          case "$path" in *.ko) kind=kernel-module;; *) kind=other;; esac
          if [ "$magic" = 7f454c46 ]; then
            [ "$kind" = kernel-module ] || kind=elf
            checked=$((checked+1))
            machine=$(readelf -h "$work/item" 2>/dev/null | awk -F: '/Machine:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
            [ -n "$machine" ] || machine=unknown
            if readelf -l "$work/item" 2>/dev/null | grep -q 'Requesting program interpreter'; then linkage=dynamic; else linkage='static-or-relocatable'; fi
            # Opcode presence is advisory: CPU dispatch may make it unreachable.
            if objdump -d "$work/item" 2>/dev/null | LC_ALL=C grep -Eq '[[:space:]](v[a-z0-9]+|shlx|shrx|sarx|blsr|blsi|bzhi|pdep|pext)([[:space:]]|$)'; then
              warnings=$((warnings+1)); verdict=WARN
            else
              verdict=UNTESTED; untested=$((untested+1))
            fi
            itemhash=$(sha256sum "$work/item" | awk '{print $1}')
            jq -cn --arg path "$path" --arg sha256 "$itemhash" --arg type "$kind" --arg status "$verdict" \
              --arg architecture "$machine" --arg linkage "$linkage" \
              '{path:$path,sha256:$sha256,type:$type,architecture:$architecture,linkage:$linkage,status:$status,scope:"static opcode observation only; execution not proven"}' >> "$items"
          else
            case "$path" in
              *.tgz|*.tar.gz|*.gz|*.xz|*.cpio|*.tar)
                untested=$((untested+1))
                itemhash=$(sha256sum "$work/item" | awk '{print $1}')
                jq -cn --arg path "$path" --arg sha256 "$itemhash" \
                  '{path:$path,sha256:$sha256,type:"nested-archive",status:"UNTESTED",scope:"nested contents were not executed or inspected"}' >> "$items"
                ;;
            esac
          fi
        done < "$work/selected"
        if [ "$warnings" -gt 0 ]; then status=WARN; else status=UNTESTED; fi
        reason='static inspection cannot prove Nehalem execution; nested archives and kernel ABI untested'
      fi
    fi
  fi
fi
tmp="${report}.tmp.$$"
jq -s --arg schema 'mshell-nehalem-loader-v1' --arg attempt "${MSHELL_NEHALEM_ATTEMPT:-standalone}" \
  --arg sha256 "$hash" --arg gate "$gate" --arg mode "$mode" --arg status "$status" --arg reason "$reason" \
  --argjson checked "$checked" --argjson warnings "$warnings" --argjson untested "$untested" \
  '{schema:$schema,attempt:$attempt,artifact_sha256:$sha256,cpu_gate:$gate,mode:$mode,status:$status,reason:$reason,checked:$checked,warnings:$warnings,untested:$untested,files:.}' \
  "$items" > "$tmp" 2>/dev/null && mv -f "$tmp" "$report" || { rm -f "$tmp"; exit 2; }
printf 'Nehalem check: %s (%s); checked=%s warnings=%s untested=%s; report=%s\n' "$status" "$reason" "$checked" "$warnings" "$untested" "$report"
