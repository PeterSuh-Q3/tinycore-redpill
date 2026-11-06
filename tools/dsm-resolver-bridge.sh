# Sourced by functions.sh and functions_t.sh. No side effects at source time.
mshellDsmResolve() {
    local op="$1" model="$2" release="${3:-}" module="${4:-}" method="${5:-}" cpu request
    local root="${MSHELL_SCRIPT_ROOT:-/home/tc}" channel=stable
    [ ! -f /tmp/test_mode ] || channel="test"
    if [ -n "${MSHELL_TARGET_CPU_JSON:-}" ]; then
        cpu=$(cat "$MSHELL_TARGET_CPU_JSON") || return 2
        printf '%s' "$cpu" | jq -e '(.flags_known|type=="boolean") and (.flags|type=="array") and all(.flags[];type=="string")' >/dev/null 2>&1 || {
            echo 'Invalid target CPU snapshot; expected flags_known and string flags[]' >&2; return 2;
        }
    elif [ "${MSHELL_DOCKER_BUILDER:-0}" = 1 ] || [ "${BUS:-}" = block ]; then
        local cpu_config="${userconfigfile:-${MSHELL_USER_CONFIG:-/home/tc/user_config.json}}"
        if [ -r "$cpu_config" ]; then
            cpu=$(jq -ce '.general.target_cpu | select((.flags_known|type=="boolean") and (.flags|type=="array") and all(.flags[];type=="string"))' "$cpu_config" 2>/dev/null) || cpu='{"flags_known":false,"flags":[],"source":"target-unknown"}'
        else
            cpu='{"flags_known":false,"flags":[],"source":"target-unknown"}'
        fi
    elif [ -r /proc/cpuinfo ]; then
        cpu=$(awk -F: '/^flags[[:space:]]*:/ {print $2}' /proc/cpuinfo | jq -Rs '
          split("\n")|map(select(length>0)|split(" ")|map(select(length>0)))|
          if length==0 then {flags_known:false,flags:[]} else
          {flags_known:true,flags:(reduce .[] as $f (.[0]; map(select(. as $x|$f|index($x)))))} end') || return 2
    else
        cpu='{"flags_known":false,"flags":[]}'
    fi
    request=$(jq -n --arg op "$op" --arg model "$model" --arg release "$release" \
        --arg module "$module" --arg method "$method" --arg channel "$channel" --argjson cpu "$cpu" \
        '{operation:$op,model:$model,release:$release,channel:$channel,cpu:$cpu,mode:{module:$module,method:$method}}') || return 2
    [ -r "$root/tools/dsm-target-resolver.sh" ] || { echo 'DSM resolver missing; update the complete MSHELL bundle.' >&2; return 3; }
    printf '%s' "$request" | sh "$root/tools/dsm-target-resolver.sh"
}

mshellDsmValidate() {
    local result rc
    result=$(mshellDsmResolve validate "$1" "$2" "$3" "$4"); rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%s\n' "$result" | jq -r '.reasons[]?.code' >&2
        return "$rc"
    fi
    printf '%s\n' "$result"
}

# Pin the chosen recipe through a local index understood by ext-manager/curl.
# Every payload still passes the existing ext-manager SHA-256 verifier.
mshellDsmPinRecipe() {
    local selection="$1" root="${MSHELL_SCRIPT_ROOT:-/home/tc}" dir id key tmp index detour_addon=0 addon_id=mshell-volume-recovery
    local addon_index="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/mshell-volume-recovery/rpext-index.json"
    id=$(printf '%s' "$selection" | jq -r '.selected_mode.module') || return 6
    # Buildroot's jq may be compiled without Oniguruma. Keep this filter
    # independent of jq's regex functions (test/match/sub/gsub).
    key=$(printf '%s' "$selection" | jq -r '.target | .platform+"_"+(.tuple[0]|tostring)+(.tuple[1]|tostring)+"_"+(.kernel|tostring|split(".")|join(""))') || return 6
    dir="$root/dsm-selection"
    mkdir -p "$dir" || return 6
    printf '%s\n' "$selection" > "$dir/selection.lock.json" || return 6
    printf '%s' "$selection" | jq '
      .source_revisions["tcrp-modules"] as $commit | .selected_mode.recipe |
      if (($commit | type) == "string" and ($commit | length) == 40 and
          all($commit | explode[]; (. >= 48 and . <= 57) or (. >= 97 and . <= 102))) then
        .files |= map(.url |= (
          if startswith("raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/") then
            "raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/" + $commit + "/" +
            ltrimstr("raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/")
          else . end))
      else . end' > "$dir/recipe.json" || return 6
    if [ -d /dev/shm/tcrp-modules ]; then
        printf '%s' "$selection" | jq '.selected_mode.recipe' > "$dir/recipe.json" || return 6
    fi
    # The DSM runtime helper is bundled only for the selected BMI2 detour.
    # Require the resolver's exact CPU_FEATURE_MISSING rejection plus the
    # supported platform/release/kernel set; ordinary PML and IML builds do
    # not inherit this addon from a previous build.
    if printf '%s' "$selection" | jq -e '
      .selected_mode.id == "all-modules:PML" and
      (.selected_mode.reasons | type == "array" and length == 1 and .[0].code == "CPU_FEATURE_MISSING") and
      (.selected_mode.cpu_flags | type == "array" and index("bmi2") != null) and
      (.target as $target |
        [["epyc7002",3],["epyc7002",4],["epyc7003",4],["icelaked",4],
         ["v1000nk",3],["v1000nk",4],["r1000nk",3],["r1000nk",4],
         ["geminilakenk",3],["geminilakenk",4]]
        | any(.[]; .[0] == $target.platform and .[1] == $target.tuple[1])) and
      .target.tuple[0] == 7 and
      .target.kernel == "5.10.55"
    ' >/dev/null 2>&1; then
        detour_addon=1
    fi
    index="file://$dir/index.json"
    jq -n --arg id "$id" --arg key "$key" --arg recipe "file://$dir/recipe.json" --arg index "$index" \
       '{id:$id,url:$index,info:{name:$id,help_url:"https://github.com/PeterSuh-Q3/tinycore-redpill"},releases:{($key):$recipe}}' > "$dir/index.json" || return 6
    tmp=$(mktemp "$root/redpill-load/bundled-exts.json.XXXXXX") || return 6
    if ! jq --arg id "$id" --arg index "$index" --arg addon_id "$addon_id" \
       --arg addon_index "$addon_index" --argjson detour_addon "$detour_addon" \
       'del(.["all-modules"],.["custom-modules"],.["anodrm-modules"],.[$addon_id])
        | .[$id]=$index
        | if $detour_addon == 1 then .[$addon_id]=$addon_index else . end' \
       "$root/redpill-load/bundled-exts.json" > "$tmp" || ! mv -f "$tmp" "$root/redpill-load/bundled-exts.json"; then
        rm -f "$tmp"; return 6
    fi
    if [ "$detour_addon" -eq 1 ]; then
        echo "[detourbmi2] bundled ${addon_id} for ${key}"
    else
        rm -rf "$root/redpill-load/custom/extensions/$addon_id" || return 6
        echo "[detourbmi2] omitted ${addon_id}; selection is not an eligible BMI2 detour"
    fi
    # Remove only competing module extensions; never leave an old pack active.
    local pack
    for pack in all-modules custom-modules anodrm-modules; do
        if [ "$pack" != "$id" ]; then
            rm -rf "$root/redpill-load/custom/extensions/$pack" || return 6
        fi
    done
    (cd "$root/redpill-load" && ./ext-manager.sh force_add "$id" "$index")
}
