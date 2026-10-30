#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/historical-mapping.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
source <(sed -n '/^function historical_collect_mapping_helpers()/,/^}/p' "$root/menu.sh")
EXTRACT_DIR="$tmp/tag" TAG=v1.4.6.1
mkdir -p "$EXTRACT_DIR/tools"
printf '%s\n' '# old version without mapping assistant' > "$EXTRACT_DIR/menu_m.sh"
FILES=(menu_m.sh functions.sh i18n.h my.sh.gz)
historical_collect_mapping_helpers
[ "${#FILES[@]}" -eq 4 ]
for helper in nondt-mapping-inventory.sh nondt-mapping-calculate.sh nondt-mapping-config.sh nondt-sata-remap.sh; do
  printf '%s\n' "$helper" >> "$EXTRACT_DIR/menu_m.sh"
  printf '%s\n' '#!/bin/bash' > "$EXTRACT_DIR/tools/$helper"
done
historical_collect_mapping_helpers
[ "${#FILES[@]}" -eq 8 ]
for helper in nondt-mapping-inventory.sh nondt-mapping-calculate.sh nondt-mapping-config.sh nondt-sata-remap.sh; do
  [[ " ${FILES[*]} " == *" tools/$helper "* ]] || exit 1
done
rm -f "$EXTRACT_DIR/tools/nondt-mapping-config.sh"
FILES=(menu_m.sh functions.sh i18n.h my.sh.gz)
if historical_collect_mapping_helpers 2>/dev/null; then
  echo 'Missing referenced helper unexpectedly accepted' >&2; exit 1
fi
echo 'Historical optional and required mapping helper tests passed.'
