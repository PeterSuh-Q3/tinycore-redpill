#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nondt-menu.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT

# Guard and dispatch must remain the established platform-string policy.
grep -Fq 'if ! echo "${platform}" | grep -q "(DT)"; then' "$root/menu_m.sh"
grep -Fq 'h) nondtMappingMenu;' "$root/menu_m.sh"
! grep -Fq 'd) nondtMappingMenu;' "$root/menu_m.sh"
grep -Fq 'tools/nondt-mapping-inventory.sh' "$root/.github/workflows/alpine-make.my.sh.gz.yml"
awk '/# Keep the established \(DT\) marker guard/{capture=1;next} capture {print; if ($0 ~ /^[[:space:]]*fi$/) exit}' "$root/menu_m.sh" > "$tmp/guard.sh"
test -s "$tmp/guard.sh"
TMP_PATH="$tmp" MSGZZ204='Non-DT mapping'
platform=apollolake
: > "$tmp/menu"
source "$tmp/guard.sh"
grep -Fq 'h "Non-DT mapping"' "$tmp/menu"
platform='epyc7002(DT)'
: > "$tmp/menu"
source "$tmp/guard.sh"
test ! -s "$tmp/menu"
awk '/# Keep the established \(DT\) marker guard/ {guard=NR} /nv_locked.*hide.*echo.*g / {nvidia=NR} END {exit !(guard && nvidia && guard < nvidia)}' "$root/menu_m.sh"

sed -n '/^function nondtMappingMenu()/,/^}/p' "$root/menu_m.sh" > "$tmp/menu-function.sh"
test -s "$tmp/menu-function.sh"
source "$tmp/menu-function.sh"
backtitle() { printf '%s' test; }
dlgmenuheight() { printf '%s' "$1"; }
for n in {204..252}; do printf -v "MSGZZ$n" '%s' "message$n"; done
userconfigfile="$tmp/menu-config.json"
printf '%s\n' '{"extra_cmdline":{}}' > "$userconfigfile"
dialog() {
  case " $* " in
    *' --menu '*)
      local step=0
      [ ! -f "$tmp/step" ] || step=$(<"$tmp/step")
      step=$((step + 1))
      printf '%s' "$step" > "$tmp/step"
      case "$step" in 1) printf a >&2 ;; 2) printf c >&2 ;; 3) printf d >&2 ;; 4) printf b >&2 ;; 5) printf e >&2 ;; *) printf q >&2 ;; esac
      ;;
    *' --yesno '*) printf 'notice\n' >> "$tmp/actions"; return 1 ;;
    *) printf 'notice\n' >> "$tmp/actions" ;;
  esac
}
nondtMappingInventory() { printf 'inventory\n' >> "$tmp/actions"; }
remapsata() { printf 'remap\n' >> "$tmp/actions"; }
nondtMappingCandidate() { printf 'candidate\n' >> "$tmp/actions"; }
nondtMappingMenu
test "$(grep -c '^inventory$' "$tmp/actions")" -eq 2
test "$(grep -c '^remap$' "$tmp/actions")" -eq 1
test "$(grep -c '^candidate$' "$tmp/actions")" -eq 1
test "$(grep -c '^notice$' "$tmp/actions")" -eq 1

# Existing SATA mappings require explicit confirmation before the legacy remap.
printf '%s\n' '{"extra_cmdline":{"SataPortMap":"4","DiskIdxMap":"00"}}' > "$userconfigfile"
printf '0' > "$tmp/step"
dialog() {
  case " $* " in
    *' --menu '*)
      local step
      step=$(<"$tmp/step"); step=$((step + 1)); printf '%s' "$step" > "$tmp/step"
      if [ "$step" -eq 1 ]; then printf c >&2; else printf q >&2; fi ;;
    *' --yesno '*) printf 'conflict-warning\n' >> "$tmp/actions"; return 1 ;;
  esac
}
nondtMappingMenu
test "$(grep -c '^conflict-warning$' "$tmp/actions")" -eq 1
test "$(grep -c '^remap$' "$tmp/actions")" -eq 1

# Exercise the real candidate dialog with an isolated user config. The
# candidate is informational and must not write the configuration.
sed -n '/^function nondtMappingCandidate()/,/^}/p' "$root/menu_m.sh" > "$tmp/candidate-function.sh"
source "$tmp/candidate-function.sh"
MSHELL_MAPPING_TOOLS_ROOT="$root/tools"
MSHELL_INVENTORY_SYS_ROOT="$tmp/sys"
export MSHELL_INVENTORY_SYS_ROOT
mkdir -p "$tmp/sys/class/block" "$tmp/sys/bus/pci/devices/0000:02:04.0" "$tmp/sys/bus/pci/devices/0000:02:05.0"
printf '0x010601\n' > "$tmp/sys/bus/pci/devices/0000:02:04.0/class"
printf '0x010601\n' > "$tmp/sys/bus/pci/devices/0000:02:05.0/class"
for disk in a b c d e f g h; do
  case "$disk" in a|b|c|d) pci=0000:02:04.0 ;; *) pci=0000:02:05.0 ;; esac
  mkdir -p "$tmp/sys/devices/$pci/block/sd$disk/device"
  ln -s "$tmp/sys/devices/$pci/block/sd$disk" "$tmp/sys/class/block/sd$disk"
done
userconfigfile="$tmp/user_config.json"
printf '%s\n' '{"synoinfo":{"maxdisks":"12"},"extra_cmdline":{"SasIdxMap":"0"}}' > "$userconfigfile"
before=$(cksum "$userconfigfile")
dialog() {
  case " $* " in
    *' --inputbox '*message250*) printf '%s' "$test_order" >&2 ;;
    *' --inputbox '*) printf '%s\n' "$*" >> "$tmp/prompts"; printf '%s' "$test_counts" >&2 ;;
    *' --yesno '*) printf '%s\n' "$*" >> "$tmp/candidate-output"; return 1 ;;
    *' --msgbox '*) printf '%s\n' "$*" >> "$tmp/candidate-output" ;;
  esac
}
test_order='1,2'
test_counts='4,2'
nondtMappingCandidate
grep -Fq 'SataPortMap=42' "$tmp/candidate-output"
grep -Fq 'DiskIdxMap=0004' "$tmp/candidate-output"
grep -Fq '0000:02:04.0=4, 0000:02:05.0=4' "$tmp/prompts"
grep -Fq '4,4' "$tmp/prompts"
grep -Fq 'message251' "$tmp/prompts"
test "$before" = "$(cksum "$userconfigfile")"
test_counts='4,10'
if nondtMappingCandidate; then echo 'Invalid input unexpectedly accepted' >&2; exit 1; fi
test "$before" = "$(cksum "$userconfigfile")"
test_counts='9,9'
if nondtMappingCandidate; then echo 'maxdisks overflow unexpectedly accepted' >&2; exit 1; fi
test "$before" = "$(cksum "$userconfigfile")"
printf '%s\n' '{"synoinfo":{},"extra_cmdline":{"SasIdxMap":"0"}}' > "$userconfigfile"
before=$(cksum "$userconfigfile")
test_counts='4,2'
if nondtMappingCandidate; then echo 'Missing maxdisks unexpectedly accepted' >&2; exit 1; fi
test "$before" = "$(cksum "$userconfigfile")"
printf '%s\n' '{"synoinfo":{"maxdisks":"12"},"extra_cmdline":{}}' > "$userconfigfile"
before=$(cksum "$userconfigfile")
for test_order in '1' '1,1' '1,3' '0,1' '1,2,'; do
  if nondtMappingCandidate; then echo "Invalid controller order accepted: $test_order" >&2; exit 1; fi
done
test "$before" = "$(cksum "$userconfigfile")"
test_order='2,1'
test_counts='2,4'
nondtMappingCandidate
grep -Fq 'SataPortMap=24' "$tmp/candidate-output"
grep -Fq 'DiskIdxMap=0002' "$tmp/candidate-output"
grep -Fq '0000:02:05.0=2 0000:02:04.0=4' "$tmp/candidate-output"
echo 'Non-DT menu routing and guard tests passed.'
