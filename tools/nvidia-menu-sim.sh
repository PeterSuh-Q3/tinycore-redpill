#!/bin/bash
# nvidia-menu-sim.sh — standalone simulation of the nvidiadriver submenu.
#
# Iterate on the nvidiaMenu() UX WITHOUT a full loader build. It extracts the
# REAL nvidiaMenu function from menu_m.sh (so what you see == production), runs
# it against a throwaway sandbox, and prints the resulting bundled-exts.json /
# user_config.json after each pass so you can verify what the menu actually did.
#
# Requires: dialog, jq, network (to fetch nvidia-index.json/gpu-support.json).
# GPU detection uses this box's real /sys/bus/pci — run it on the target box to
# see the "detected: <GPU> -> <ver>" Auto line; elsewhere it shows "no GPU".
#
# Usage:  ./nvidia-menu-sim.sh [platform] [path-to-menu_m.sh]
#   platform default: epyc7002
#   menu     default: /home/tc/menu_m.sh  (falls back to ./menu_m.sh)
set -u

PLATFORM_ARG="${1:-epyc7002}"
MENU="${2:-/home/tc/menu_m.sh}"; [ -f "$MENU" ] || MENU="./menu_m.sh"
[ -f "$MENU" ] || { echo "[!] menu_m.sh not found ($MENU)"; exit 1; }
command -v dialog >/dev/null || { echo "[!] 'dialog' required"; exit 1; }
command -v jq     >/dev/null || { echo "[!] 'jq' required"; exit 1; }

# --- sandbox -----------------------------------------------------------------
SB="$(mktemp -d /tmp/nvsim.XXXXXX)"
trap 'echo; echo "sandbox kept at: $SB"' EXIT
export TMP_PATH="$SB"
BEXSB="$SB/bundled-exts.json"
echo '{"redpill":"url","disks":"url"}' > "$BEXSB"
echo '{}' > "$SB/user_config.json"

# --- minimal stubs mimicking the real menu_m.sh deps -------------------------
platform="$PLATFORM_ARG"
kver5platforms="epyc7002 epyc7003ntb epyc7003 icelaked v1000nk r1000nk geminilakenk"
userconfigfile="$SB/user_config.json"
backtitle(){ echo "NVIDIA Submenu SIMULATION (platform=$platform)"; }
dlgmenuheight(){ local n="${1:-10}"; [ "$n" -lt 1 ] 2>/dev/null && n=1; echo "$n"; }
cecho(){ shift 2>/dev/null; echo "$@" >&2; }
add-addons(){ local j; j="$(jq --arg n "$1" --arg u "https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/$1/rpext-index.json" '. + {($n):$u}' "$BEXSB")" && echo "$j" | jq . > "$BEXSB"; }
del-addon(){ local j; j="$(jq --arg n "$1" 'del(.[$n])' "$BEXSB")" && echo "$j" | jq . > "$BEXSB"; }

# --- extract the REAL nvidiaMenu from menu_m.sh and load it ------------------
awk '/^function nvidiaMenu\(\)/{f=1} f{print} f&&/^\}/{exit}' "$MENU" > "$SB/fn.sh"
grep -q 'nvidiaMenu' "$SB/fn.sh" || { echo "[!] could not extract nvidiaMenu() from $MENU"; exit 1; }
# redirect the function's hardcoded bundled-exts path to the sandbox
sed -i "s#/home/tc/redpill-load/bundled-exts.json#$BEXSB#g" "$SB/fn.sh"
. "$SB/fn.sh"

# --- run loop ----------------------------------------------------------------
while true; do
  nvidiaMenu
  clear
  echo "================= SIMULATION RESULT ================="
  echo "[bundled-exts.json]  (nvidiadriver 등록 여부)"
  jq '{nvidiadriver: (.nvidiadriver // "(not added)")}' "$BEXSB"
  echo "[user_config.json]   (선택 버전 / ffmpeg)"
  jq '{nvidia_driver: (.nvidia_driver // "(Auto)"), nvidia_ffmpeg: (.nvidia_ffmpeg // false)}' "$SB/user_config.json"
  echo "===================================================="
  printf "서브메뉴 다시 열기? [y/N] : "; read -r a
  case "$a" in y|Y) ;; *) break ;; esac
done
