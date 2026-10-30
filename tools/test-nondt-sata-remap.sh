#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
helper="$root/tools/nondt-sata-remap.sh"
for value in '0>4:4>0' '0>1:1>2:2>0' '254>255:255>254'; do
  [ "$(bash "$helper" "$value")" = "$value" ] || exit 1
done
for value in '' '0>1' '0>0' '0>1:0>1' '0>1:2>1' '0>256:256>0' '0>1:1>0;reboot' '01>1:1>01'; do
  if bash "$helper" "$value" >/dev/null 2>&1; then echo "Invalid mapping accepted: $value" >&2; exit 1; fi
done
test "$(bash "$helper" --generate 0,1,2,3,4 4,1,2,3,0)" = '0>4:4>0'
test "$(bash "$helper" --generate 0,1,2 1,2,0)" = '0>1:1>2:2>0'
for pair in '0,1 0,1' '0,1 1,2' '0,0 0,0' '0,1 1' '0,256 256,0' '0,1 1,1'; do
  if bash "$helper" --generate $pair >/dev/null 2>&1; then echo "Invalid lists accepted: $pair" >&2; exit 1; fi
done
value='0>4:4>0'
encoded=${value//>/\\>}
json=$(jq -n --arg v "$encoded" '{extra_cmdline:{sata_remap:$v}}')
test "$(jq -r '.extra_cmdline.sata_remap' <<< "$json")" = '0\>4:4\>0'
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nondt-remap.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
sed -n '/^function remapsata()/,/^}/p' "$root/menu_m.sh" > "$tmp/function"
source "$tmp/function"
MSHELL_MAPPING_TOOLS_ROOT="$root/tools" userconfigfile="$tmp/config"
printf '%s\n' '{"extra_cmdline":{"SasIdxMap":"0"}}' > "$userconfigfile"
for n in 208 220 225 227 228 229 230 231 232 233 234 235 236; do printf -v "MSGZZ$n" '%s' "message$n"; done
backtitle() { echo test; }
dialog() { case " $* " in *' --menu '*) printf '%s' "$menu_choice" >&2;; *' --inputbox '*) printf '%s' "$input_value" >&2;; esac; }
config_change_begin() { CONFIG_CHANGE_SNAPSHOT="$tmp/before"; cp "$userconfigfile" "$CONFIG_CHANGE_SNAPSHOT"; }
write_user_config_json() { printf '%s\n' "$2" > "$1"; }
sync_usb_line() { :; }
sync_part_config() { :; }
config_change_finish() { rm -f "$CONFIG_CHANGE_SNAPSHOT"; }
input_value='0>4:4>0'
menu_choice=b
remapsata
jq -e '.extra_cmdline.sata_remap == "0\\>4:4\\>0" and .extra_cmdline.SasIdxMap == "0"' "$userconfigfile" >/dev/null
before=$(cksum "$userconfigfile")
input_value='0>4'
if remapsata; then echo 'Invalid menu mapping accepted' >&2; exit 1; fi
test "$before" = "$(cksum "$userconfigfile")"
menu_choice=a
if remapsata; then echo 'Existing mapping was not blocked' >&2; exit 1; fi
test "$before" = "$(cksum "$userconfigfile")"
jq 'del(.extra_cmdline.sata_remap)' "$userconfigfile" > "$tmp/clean"
cp "$tmp/clean" "$userconfigfile"
dialog() {
  case " $* " in
    *' --menu '*) printf a >&2;;
    *' --inputbox '*message233*) printf '0,1,2,3,4' >&2;;
    *' --inputbox '*message234*) printf '4,1,2,3,0' >&2;;
  esac
}
remapsata
jq -e '.extra_cmdline.sata_remap == "0\\>4:4\\>0" and .extra_cmdline.SasIdxMap == "0"' "$userconfigfile" >/dev/null
echo 'sata_remap permutation and GRUB escaping tests passed.'
