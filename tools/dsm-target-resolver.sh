#!/bin/sh
# Pure offline reader. Request JSON on stdin; exactly one response on stdout.
base=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd) || exit 6
catalog=${MSHELL_DSM_CATALOG:-$base/config/dsm-targets.v1.json}
if [ -e "$base/config/dsm-resolver-updating" ] || [ ! -r "$catalog" ] || [ ! -r "$base/tools/dsm-target-resolver.jq" ]; then
    echo '{"ok":false,"exit_code":3,"reasons":[{"code":"CATALOG_MISSING"}]}'
    exit 3
fi
request=$(cat) || exit 6
if ! printf '%s' "$request" | jq -e 'type=="object"' >/dev/null 2>&1; then
    echo '{"ok":false,"exit_code":2,"reasons":[{"code":"INVALID_REQUEST"}]}'
    exit 2
fi
response=$(jq -n --argjson q "$request" --slurpfile catalogs "$catalog" -f "$base/tools/dsm-target-resolver.jq") || {
    echo '{"ok":false,"exit_code":3,"reasons":[{"code":"CATALOG_INCONSISTENT"}]}'
    exit 3
}
printf '%s\n' "$response"
exit "$(printf '%s' "$response" | jq -r '.exit_code')"
