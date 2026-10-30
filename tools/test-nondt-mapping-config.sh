#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nondt-config.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
tool="$root/tools/nondt-mapping-config.sh"
printf '%s\n' '{"general":{"usb_line":"quiet","sata_line":""},"synoinfo":{"maxdisks":"12","usbportcfg":"0x40"},"extra_cmdline":{"SasIdxMap":"0","SataPortMap":null,"other":"keep"}}' > "$tmp/config"
bash "$tool" snapshot "$tmp/config" > "$tmp/snapshot"
bash "$tool" apply "$tmp/config" 42 0004 > "$tmp/applied"
jq -e '.extra_cmdline.SataPortMap == "42" and .extra_cmdline.DiskIdxMap == "0004" and .extra_cmdline.SasIdxMap == "0" and .synoinfo.usbportcfg == "0x40"' "$tmp/applied" >/dev/null
if "$tool" apply "$tmp/config" @ 0000 >/dev/null 2>&1; then echo 'Automatic @ SataPortMap unexpectedly accepted' >&2; exit 1; fi
bash "$tool" restore "$tmp/applied" "$tmp/snapshot" > "$tmp/restored"
jq -e '(.extra_cmdline | has("SataPortMap")) and .extra_cmdline.SataPortMap == null and (.extra_cmdline | has("DiskIdxMap") | not) and .extra_cmdline.SasIdxMap == "0" and .extra_cmdline.other == "keep"' "$tmp/restored" >/dev/null
for pair in '42 0005' '90 0009' '99 0009'; do
  if bash "$tool" apply "$tmp/config" $pair >/dev/null 2>&1; then echo "Invalid mapping accepted: $pair" >&2; exit 1; fi
done
jq '.general.usb_line="quiet sata_remap=0>1"' "$tmp/config" > "$tmp/conflict"
if bash "$tool" apply "$tmp/conflict" 42 0004 >/dev/null 2>&1; then echo 'sata_remap conflict accepted' >&2; exit 1; fi
jq '.general.sata_line="sata_remap=0>1"' "$tmp/config" > "$tmp/conflict"
if bash "$tool" apply "$tmp/conflict" 42 0004 >/dev/null 2>&1; then echo 'SATA line conflict accepted' >&2; exit 1; fi
jq '.general.usb_line="quiet\tsata_remap=0>1"' "$tmp/config" > "$tmp/conflict"
if bash "$tool" apply "$tmp/conflict" 42 0004 >/dev/null 2>&1; then echo 'Whitespace conflict accepted' >&2; exit 1; fi
jq '.general.usb_line="sata_remap"' "$tmp/config" > "$tmp/conflict"
if bash "$tool" apply "$tmp/conflict" 42 0004 >/dev/null 2>&1; then echo 'Bare remap accepted' >&2; exit 1; fi
echo 'Non-DT mapping config transformation tests passed.'
