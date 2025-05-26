#!/usr/bin/env bash

function writeConfigKey() {
    local block="$1"
    local field="$2"
    local value="$3"
    local userconfigfile="$4"

    # Check all arguments
    if [ -z "$block" ] || [ -z "$field" ] || [ -z "$value" ] || [ -z "$userconfigfile" ]; then
        echo "Error: Missing arguments. (block, field, value, userconfigfile)"
        return 1
    fi

    # Check if file exists and has read/write permissions
    if [ ! -f "$userconfigfile" ]; then
        echo "Error: File does not exist: $userconfigfile"
        return 2
    fi
    if [ ! -r "$userconfigfile" ] || [ ! -w "$userconfigfile" ]; then
        echo "Error: No read/write permission for file: $userconfigfile"
        return 3
    fi

    # Use a temporary file for safe update
    local tmpfile
    tmpfile=$(mktemp) || { echo "Error: Failed to create temporary file"; return 4; }

    # Try to update using jq
    if ! jq ".$block += {\"$field\":\"$value\"}" "$userconfigfile" > "$tmpfile"; then
        echo "Error: jq failed (check if the JSON file is valid)"
        rm -f "$tmpfile"
        return 5
    fi

    # Overwrite the original file if successful
    mv "$tmpfile" "$userconfigfile"
    echo "Successfully updated: $block.$field = $value"
}

writeConfigKey "$1" "$2" "$3" "$4"
