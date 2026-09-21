#!/bin/sh
# Alpine -> DSM direct handoff runner.
#
# DISABLED GUI EXPERIMENT (2026-09-21; retained for reference)
# menu_m.sh previously attempted to reuse the fourth Extra Terminal:
#   extra_window=$(xdotool search --name 'TCRP Extra Terminal' | head -n1)
#   [ -n "$extra_window" ] || extra_window=$(xdotool search --class lxterminal | tail -n1)
#   xdotool windowactivate --sync "$extra_window"
#   xdotool windowfocus --sync "$extra_window"
#   xdotool key --window "$extra_window" --clearmodifiers ctrl+u
#   xdotool type --window "$extra_window" --clearmodifiers --delay 20 \
#     "sudo /home/tc/direct-dsm-kexec.sh --run --gui ..."
#   xdotool key --window "$extra_window" --clearmodifiers Return
#   xdotool key --window "$extra_window" --clearmodifiers alt+F10
# This GUI path is intentionally inactive because it did not provide a
# reliable NVIDIA/DRM state across kexec. The active runner remains TTY-only.

set -o pipefail
TCRP_PART=""
MODULE_METHOD="unknown"
HANDOFF_CONSOLE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run) ;;
    --tcrp-part) TCRP_PART="${2:-}"; shift ;;
    --method) MODULE_METHOD="${2:-unknown}"; shift ;;
    --console) HANDOFF_CONSOLE="${2:-}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

[ "$(id -u)" = 0 ] || { echo "This program must run as root." >&2; exit 1; }
[ -n "$TCRP_PART" ] || { echo "Missing loader partition." >&2; exit 2; }
[ -n "$HANDOFF_CONSOLE" ] || { echo "Missing handoff console." >&2; exit 2; }
[ -c "$HANDOFF_CONSOLE" ] || { echo "Invalid handoff console: $HANDOFF_CONSOLE" >&2; exit 2; }
exec <"$HANDOFF_CONSOLE" >"$HANDOFF_CONSOLE" 2>&1

CONFIG=/home/tc/user_config.json
[ -r "$CONFIG" ] || CONFIG="/mnt/$TCRP_PART/user_config.json"
ZIMAGE="/mnt/$TCRP_PART/zImage-dsm"
INITRD="/mnt/$TCRP_PART/initrd-dsm"
PERSIST_LOG="/mnt/alpine/mshell-kexec-handoff.log"
[ -w /mnt/alpine ] || PERSIST_LOG="/mnt/$TCRP_PART/mshell-kexec-handoff.log"
KEXEC_LOG=/tmp/mshell-kexec.log

log_line() { printf '%s\n' "$*" >>"$PERSIST_LOG" 2>/dev/null || true; }
fail() { log_line "FAIL: $1"; echo "DSM handoff failed: $1"; exit 1; }

log_line "direct DSM handoff $(date -u '+%Y-%m-%dT%H:%M:%SZ') method=$MODULE_METHOD"
[ -x "$(command -v kexec 2>/dev/null)" ] || fail "kexec-tools is not installed"
[ "$(cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null || echo 1)" = 0 ] || fail "kexec_load_disabled is not 0"
[ -r "$ZIMAGE" ] || fail "zImage-dsm is missing: $ZIMAGE"
[ -r "$INITRD" ] || fail "initrd-dsm is missing: $INITRD"
BASE_CMDLINE=$(jq -r '.general.use_line // .general.usb_line // empty' "$CONFIG" 2>/dev/null)
[ -n "$BASE_CMDLINE" ] || fail "DSM command line is missing"
CPU_COUNT=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
case "$CPU_COUNT" in ''|*[!0-9]*) CPU_COUNT=1 ;; esac
[ "$CPU_COUNT" -gt 24 ] && CPU_COUNT=24
CMDLINE="$BASE_CMDLINE nr_cpus=$CPU_COUNT reset_devices"
log_line "zimage=$ZIMAGE initrd=$INITRD cpu_count=$CPU_COUNT cmdline=$CMDLINE"
printf '\nDSM direct handoff\nKernel: %s\nInitrd: %s\nMethod: %s\n' "$ZIMAGE" "$INITRD" "$MODULE_METHOD"
printf 'Loading DSM kernel...\n'
kexec -u >/dev/null 2>&1 || true
kexec -a -l "$ZIMAGE" --initrd="$INITRD" --command-line="$CMDLINE" >"$KEXEC_LOG" 2>&1 || fail "DSM kernel load failed"
log_line "DSM kernel loaded; executing"
sync
kexec -e >>"$KEXEC_LOG" 2>&1 || fail "DSM kernel execute failed"
fail "kexec returned unexpectedly"
