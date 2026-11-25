#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

awk '
  /^function run_synoxtract\(\) \{$/ { copy = 1 }
  copy { print }
  copy && /^}$/ { exit }
' "${repo_root}/functions.sh" > "${tmp_dir}/run-synoxtract.sh"

test -s "${tmp_dir}/run-synoxtract.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/run-synoxtract.sh"

HOME="${tmp_dir}/home"
mkdir -p "${HOME}" "${tmp_dir}/out"
pat="${tmp_dir}/sample.pat"
: > "${pat}"
CALL_LOG="${tmp_dir}/calls"
sudo() { printf '%s\n' "$*" >> "${CALL_LOG}"; }

# A normal block-bus case retains the legacy Docker fallback.
: > "${CALL_LOG}"
BUS=block MSHELL_DOCKER_BUILDER=0 MSHELL_SYNOXTRACT_BACKEND=auto \
  run_synoxtract "${pat}" "${tmp_dir}/out"
grep -q '^docker run ' "${CALL_LOG}"

# Manager Docker rebuilder remains distinct even if its mapped disk says block.
: > "${CALL_LOG}"
BUS=block MSHELL_DOCKER_BUILDER=1 MSHELL_SYNOXTRACT_BACKEND=auto \
  run_synoxtract "${pat}" "${tmp_dir}/out"
grep -q '^/home/tc/synoxtract ' "${CALL_LOG}"
! grep -q '^docker run ' "${CALL_LOG}"

# The issue workflow explicitly selects native extraction on its Linux runner.
: > "${CALL_LOG}"
BUS=block MSHELL_DOCKER_BUILDER=0 MSHELL_SYNOXTRACT_BACKEND=native \
  run_synoxtract "${pat}" "${tmp_dir}/out"
grep -q '^/home/tc/synoxtract ' "${CALL_LOG}"
! grep -q '^docker run ' "${CALL_LOG}"

echo 'PASS: block bus and extraction backend are independently selected.'
