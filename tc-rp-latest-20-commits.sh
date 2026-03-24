#!/bin/bash
set -euo pipefail

# 1. ISO8601 → UNIX epoch (macOS/date -j -f, Linux/XXX 공용)
to_epoch() {
    local iso="$1"
    if [ -z "$iso" ]; then
        echo 0
        return
    fi
    if [[ "$iso" =~ Z$ ]]; then
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null || echo 0
        return
    fi
    if [[ "$iso" =~ [+-][0-9][0-9]:[0-9][0-9]$ ]]; then
        local base=$(echo "$iso" | sed -E 's/([+-][0-9]{2}:[0-9]{2})$//')
        date -j -f "%Y-%m-%dT%H:%M:%S" "$base" "+%s" 2>/dev/null || echo 0
        return
    fi
    date -j -f "%Y-%m-%dT%H:%M:%S" "$iso" "+%s" 2>/dev/null ||
    date -j -f "%Y-%m-%dT%H:%M" "$iso" "+%s" 2>/dev/null || echo 0
}

# 2. releases 가져오기
get_releases() {
    curl -s -H "Accept: application/vnd.github.v3+json" \
         "https://api.github.com/repos/PeterSuh-Q3/tinycore-redpill/releases?per_page=20"
}

# 3. addons 커밋
get_addons() {
    curl -s -H "Accept: application/vnd.github.v3+json" \
         "https://api.github.com/repos/PeterSuh-Q3/tcrp-addons/commits?per_page=200"
}

# 4. modules 커밋
get_modules() {
    curl -s -H "Accept: application/vnd.github.v3+json" \
         "https://api.github.com/repos/PeterSuh-Q3/tcrp-modules/commits?per_page=200"
}

# 5. repo 커밋들 중, target_epoch보다 작은 것 중 가장 큰 커밋 SHA
find_latest_commit_before() {
    local repo_name="$1"
    local commits_json="$2"
    local target_epoch="$3"

    echo "$commits_json" |
    jq -r '.[] | .sha as $sha | .commit.committer.date as $ts | "\($sha) \($ts)"' |
    while read -r sha ts; do
        local epoch=$(to_epoch "$ts")
        if [ "$epoch" -gt 0 ] && [ "$epoch" -lt "$target_epoch" ]; then
            echo "$epoch $sha"
        fi
    done | sort -n | tail -n1 | awk '{print $2}'
}

# 6. main
main() {
    local tmpdir
    tmpdir=$(mktemp -d -t tc-rp-commits-XXXXXX)
    trap "rm -rf $tmpdir" EXIT

    local rel_file="$tmpdir/rel.json"
    get_releases > "$rel_file"

    local addons_file="$tmpdir/addons.json"
    get_addons > "$addons_file"

    local modules_file="$tmpdir/modules.json"
    get_modules > "$modules_file"

    jq -r '.[] | .tag_name, .published_at' "$rel_file" |
    while read -r tag; do
        read -r iso_ts
        local epoch=$(to_epoch "$iso_ts")
        if [ "$epoch" -le 0 ]; then
            echo "SKIP: $tag $iso_ts"
            continue
        fi

        echo "# tinycore-redpill ${tag} (${iso_ts}, ${epoch})"

        local addh=$(find_latest_commit_before "tcrp-addons" "$(cat "$addons_file")" "$epoch")
        local modh=$(find_latest_commit_before "tcrp-modules" "$(cat "$modules_file")" "$epoch")

        echo "tcrp-addons: $addh"
        echo "tcrp-modules: $modh"
        echo ""
    done
}

main "$@"
