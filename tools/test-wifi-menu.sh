#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed -n '/^function wifiScanSelect()/,/^function staticIpMenu()/p' "$root/menu_m.sh" | sed '$d' > "$tmp/functions.sh"
source "$tmp/functions.sh"
export userconfigfile="$tmp/config.json"
printf '%s\n' '{"other":42,"wifi":{"ssid":"old","password":"oldpassword"}}' > "$userconfigfile"
sudo() { "$@"; }
gettext() { printf '%s' "$2"; }
sync_part_config() { :; }
dlgmenuheight() { echo 5; }
test_step=0
dialog() {
  case " $* " in
    *' --menu '* ) test_step=$((test_step+1)); if [ "$test_step" -eq 1 ]; then printf m >&2; else printf q >&2; fi ;;
    *' --inputbox '*) printf '%s' 'WiFi test' >&2 ;;
    *' --passwordbox '*) printf '%s' 'safe pass$word' >&2 ;;
    *' --yesno '*) return 0 ;;
    *' --msgbox '*) return 0 ;;
    *) return 1 ;;
  esac
}
wifiAutoConnectMenu
jq -e '.other == 42 and .wifi.ssid == "WiFi test" and .wifi.password == "safe pass$word"' "$userconfigfile" >/dev/null
[ "$(stat -c %a "$userconfigfile" 2>/dev/null || stat -f %Lp "$userconfigfile")" = 600 ]
echo 'Wi-Fi menu manual-save test passed'

# Cancelling at the password dialog must leave the original config untouched.
before=$(shasum -a 256 "$userconfigfile" | awk '{print $1}')
test_step=0
dialog() {
  case " $* " in
    *' --menu '*) test_step=$((test_step+1)); if [ "$test_step" -eq 1 ]; then printf m >&2; else printf q >&2; fi ;;
    *' --inputbox '*) printf '%s' 'cancelled' >&2 ;;
    *' --passwordbox '*) return 1 ;;
    *) return 0 ;;
  esac
}
wifiAutoConnectMenu
[ "$before" = "$(shasum -a 256 "$userconfigfile" | awk '{print $1}')" ]
echo 'Wi-Fi cancellation test passed'

# Scan returns exact selected SSID without evaluating shell syntax and restores
# a radio which was originally down.
export MSHELL_WIFI_SYS_ROOT="$tmp/sys"
mkdir -p "$tmp/sys/class/net/wlan0/phy80211"
printf '%s\n' 0x1002 > "$tmp/sys/class/net/wlan0/flags"
printf '%s\n' 0 > "$tmp/sys/class/net/wlan0/carrier"
printf '%s\n' 00:11:22:33:44:55 > "$tmp/sys/class/net/wlan0/address"
wifi_tmp="$tmp/scan-test"; mkdir -p "$wifi_tmp"
ip() { printf '%s\n' "$*" >> "$tmp/ip-calls"; }
iw() {
  case "$*" in
    *' scan') printf '%s\n' 'BSS aa:bb:cc:dd:ee:ff(on wlan0)' ' freq: 5180' ' signal: -42.00 dBm' ' SSID: test$(touch NEVER)' ' RSN:' ;;
    *' link') printf '%s\n' 'Not connected.' ;;
  esac
}
dialog() { case " $* " in *' --menu '*) printf 1 >&2;; *) return 0;; esac; }
wifiScanSelect
[ "$WIFI_SELECTED_SSID" = 'test$(touch NEVER)' ]
[ ! -e NEVER ]
grep -q 'set dev wlan0 up' "$tmp/ip-calls"
grep -q 'set dev wlan0 down' "$tmp/ip-calls"
echo 'Wi-Fi scan selection test passed'
