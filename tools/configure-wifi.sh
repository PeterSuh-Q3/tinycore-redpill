#!/bin/bash
# Interactive, local-only WPA2 Personal configuration.
set +x
set -euo pipefail
umask 077
cfg=${1:-user_config.json}
command -v jq >/dev/null
read -r -p 'Wi-Fi SSID (empty disables Wi-Fi): ' ssid
tmp=$(mktemp "${cfg}.wifi.XXXXXX")
secret=$(mktemp)
trap 'rm -f "$tmp" "$secret"' EXIT
if [ -z "$ssid" ]; then
    jq 'del(.wifi)' "$cfg" > "$tmp"
else
    read -r -s -p 'Wi-Fi password: ' password
    printf '\n'
    printf '%s' "$password" > "$secret"
    unset password
    jq --arg ssid "$ssid" --rawfile password "$secret" '.wifi={ssid:$ssid,password:$password} | if (.wifi.ssid|utf8bytelength)>32 or (.wifi.password|length)<8 or (.wifi.password|length)>63 or (.wifi.password|test("[^ -~]")) or (.wifi.ssid|test("[\\u0000-\\u001f]")) then error("Invalid WPA2 credentials") else . end' "$cfg" > "$tmp"
fi
mv "$tmp" "$cfg"
echo 'Wi-Fi configuration saved; rebuild the loader to apply.'
