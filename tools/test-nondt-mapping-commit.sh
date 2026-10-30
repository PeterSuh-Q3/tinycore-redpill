#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nondt-commit.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
sed -n '/^function nondtMappingCommit()/,/^}/p' "$root/menu_m.sh" > "$tmp/function"
source "$tmp/function"
TMP_PATH="$tmp" MSHELL_MAPPING_TOOLS_ROOT="$root/tools" MSHELL_MAPPING_BACKUP="$tmp/previous.json" tcrppart=unused
userconfigfile="$tmp/link.json"
printf '%s\n' '{"general":{"usb_line":"quiet","sata_line":""},"synoinfo":{"maxdisks":"16"},"extra_cmdline":{"SasIdxMap":"0"}}' > "$tmp/config.json"
ln -s "$tmp/config.json" "$userconfigfile"
MSGZZ220=missing MSGZZ223=conflict MSGZZ224=missingbackup MSGZZ225=error
dialog() { :; }
config_change_begin() { CONFIG_CHANGE_SNAPSHOT="$tmp/before"; cp "$userconfigfile" "$CONFIG_CHANGE_SNAPSHOT"; }
config_change_finish() { rm -f "$CONFIG_CHANGE_SNAPSHOT"; }
strip_usb_line_key() { :; }
sync_usb_line() { :; }
sync_part_config() { :; }
validate_loader_cmdline() { [ "${FAIL_VALIDATION:-0}" = 0 ]; }
nondtMappingCommit apply 44 0004
test -L "$userconfigfile"
jq -e '.extra_cmdline.SataPortMap == "44" and .extra_cmdline.DiskIdxMap == "0004" and .extra_cmdline.SasIdxMap == "0"' "$userconfigfile" >/dev/null
jq -e '.values == {}' "$MSHELL_MAPPING_BACKUP" >/dev/null
nondtMappingCommit restore
jq -e '(.extra_cmdline | has("SataPortMap") | not) and (.extra_cmdline | has("DiskIdxMap") | not) and .extra_cmdline.SasIdxMap == "0"' "$userconfigfile" >/dev/null
before=$(cksum "$userconfigfile")
FAIL_VALIDATION=1
if nondtMappingCommit apply 44 0004; then echo 'validation failure was accepted' >&2; exit 1; fi
test "$before" = "$(cksum "$userconfigfile")"
echo 'Non-DT mapping apply, restore, symlink and rollback tests passed.'
