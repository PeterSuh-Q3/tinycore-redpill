#!/bin/bash
set -euo pipefail

# ---------- 1. ISO8601 → epoch (TinyCore/BusyBox + GNU + macOS 공용) ----------
to_epoch() {
    local iso="$1"
    [ -z "$iso" ] && { echo 0; return; }

    local date_help
    date_help="$(date --help 2>&1 || true)"

    if echo "$date_help" | grep -qi 'busybox'; then
        # BusyBox date
        date -d "$iso" +%s 2>/dev/null || echo 0
        return
    elif echo "$date_help" | grep -qi 'gnu coreutils'; then
        # GNU date
        date -d "$iso" +%s 2>/dev/null || echo 0
        return
    else
        # macOS / BSD date
        if echo "$iso" | grep -q 'Z$'; then
            date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" "+%s" 2>/dev/null || echo 0
            return
        fi
        if echo "$iso" | grep -q '[+-][0-9][0-9]:[0-9][0-9]$'; then
            local base
            base="$(echo "$iso" | sed -E 's/([+-][0-9]{2}:[0-9]{2})$//')"
            date -j -f "%Y-%m-%dT%H:%M:%S" "$base" "+%s" 2>/dev/null || echo 0
            return
        fi
        date -j -f "%Y-%m-%dT%H:%M:%S" "$iso" "+%s" 2>/dev/null ||
        date -j -f "%Y-%m-%dT%H:%M" "$iso" "+%s" 2>/dev/null || echo 0
        return
    fi
}

# ---------- 2. GitHub API helpers ----------
get_releases() {
    curl -s -H "Accept: application/vnd.github.v3+json" \
         "https://api.github.com/repos/PeterSuh-Q3/tinycore-redpill/releases?per_page=20"
}

get_addons() {
    curl -s -H "Accept: application/vnd.github.v3+json" \
         "https://api.github.com/repos/PeterSuh-Q3/tcrp-addons/commits?per_page=200"
}

get_modules() {
    curl -s -H "Accept: application/vnd.github.v3+json" \
         "https://api.github.com/repos/PeterSuh-Q3/tcrp-modules/commits?per_page=200"
}

# ---------- 3. target_epoch 이전 커밋 중 가장 늦은 SHA ----------
find_latest_commit_before() {
    local commits_json="$1"
    local target_epoch="$2"

    echo "$commits_json" |
    jq -r '.[] | .sha as $sha | .commit.committer.date as $ts | "\($sha) \($ts)"' |
    while read -r sha ts; do
        local e
        e=$(to_epoch "$ts")
        if [ "$e" -gt 0 ] && [ "$e" -lt "$target_epoch" ]; then
            echo "$e $sha"
        fi
    done | sort -n | tail -n1 | awk '{print $2}'
}

# ---------- 4. main ----------
main() {
    local tmpdir
    tmpdir=$(mktemp -d -t tc-rp-commits-XXXXXX)
    trap "rm -rf $tmpdir" EXIT

    local rel_file="$tmpdir/rel.json"
    local addons_file="$tmpdir/addons.json"
    local modules_file="$tmpdir/modules.json"

    get_releases > "$rel_file"
    get_addons > "$addons_file"
    get_modules > "$modules_file"

    local releases_json addons_json modules_json
    releases_json="$(cat "$rel_file")"
    addons_json="$(cat "$addons_file")"
    modules_json="$(cat "$modules_file")"

    # tag_name 과 published_at 을 순차적으로 읽기
    echo "$releases_json" | jq -r '.[] | .tag_name, .published_at' |
    while read -r tag; do
        read -r iso_ts  # 바로 다음 줄이 published_at
        epoch=$(to_epoch "$iso_ts")
        if [ "$epoch" -le 0 ]; then
            echo "SKIP: $tag $iso_ts (to_epoch failed)"
            continue
        fi

        echo "# tinycore-redpill ${tag} (${iso_ts}, ${epoch})"

        local add_sha
        add_sha=$(find_latest_commit_before "$addons_json" "$epoch")
        [ -z "$add_sha" ] && add_sha="(no previous commit)"

        local mod_sha
        mod_sha=$(find_latest_commit_before "$modules_json" "$epoch")
        [ -z "$mod_sha" ] && mod_sha="(no previous commit)"

        echo "tcrp-addons : $add_sha"
        echo "tcrp-modules: $mod_sha"
        echo
    done
}

main "$@"
