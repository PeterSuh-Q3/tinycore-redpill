#!/bin/sh
# Exit 0 only for a current-attempt, reviewed QEMU execution that ended in SIGILL.
report=${1:-} attempt=${2:-}
[ -n "$report" ] && [ -r "$report" ] && [ -n "$attempt" ] && command -v jq >/dev/null 2>&1 || exit 1
jq -e --arg attempt "$attempt" '
  .schema == "mshell-nehalem-loader-v1" and .attempt == $attempt and
  .status == "FAIL" and
  (.artifact_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.evidence.kind == "allowlisted-nehalem-execution") and
  (.evidence.signal == "SIGILL") and
  (.evidence.exit_code == 132) and
  (.evidence.file_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
  (.evidence.tool | type == "string" and startswith("qemu-x86_64"))
' "$report" >/dev/null 2>&1
