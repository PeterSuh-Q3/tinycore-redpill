#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu_file="${repo_root}/menu.sh"
menu_m_file="${repo_root}/menu_m.sh"
functions_file="${repo_root}/functions.sh"
functions_test_file="${repo_root}/functions_t.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

# Load the production function without executing menu.sh's interactive startup.
awk '
  /^function run_alpine_partition_recovery\(\) \{$/ { copy = 1 }
  copy { print }
  copy && /^}$/ { exit }
' "${menu_file}" > "${tmp_dir}/recovery-function.sh"
grep -q '^function run_alpine_partition_recovery() {' "${tmp_dir}/recovery-function.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/recovery-function.sh"

awk '
  /^function ensure_alpine_partition_recovery_before_backup\(\) \{$/ { copy = 1 }
  copy { print }
  copy && /^}$/ { exit }
' "${functions_file}" > "${tmp_dir}/backup-recovery-function.sh"
grep -q '^function ensure_alpine_partition_recovery_before_backup() {' "${tmp_dir}/backup-recovery-function.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/backup-recovery-function.sh"

calls_file="${tmp_dir}/calls"
: > "${calls_file}"
UPDATE_BRANCH=alpine-redpill
is_alpine() { echo is_alpine >> "${calls_file}"; return 0; }
curl() { echo curl >> "${calls_file}"; return 1; }

# Exercise both startup recovery gates as menu.sh does. The menu may proceed
# only if both calls return success.
startup_recovery_gates() {
    if is_alpine; then
        run_alpine_partition_recovery || return 1
    fi
    if is_alpine; then
        run_alpine_partition_recovery || return 1
    fi
    echo MENU_ENTERED >> "${calls_file}"
}

export MSHELL_DOCKER_BUILDER=1
startup_recovery_gates
ensure_alpine_partition_recovery_before_backup
grep -q '^MENU_ENTERED$' "${calls_file}"
! grep -q '^curl$' "${calls_file}"
! grep -q '^is_alpine$' "${calls_file}"

# The production and test-track backup guards must remain synchronized.
cmp -s \
  <(sed -n '/^function ensure_alpine_partition_recovery_before_backup() {/,/^}/p' "${functions_file}") \
  <(sed -n '/^function ensure_alpine_partition_recovery_before_backup() {/,/^}/p' "${functions_test_file}")

# Without Docker mode, the ordinary Alpine path must still reach its helper
# fetch/validation path rather than silently taking the Docker skip.
: > "${calls_file}"
unset MSHELL_DOCKER_BUILDER
if run_alpine_partition_recovery; then
    echo 'FAIL: normal Alpine recovery unexpectedly succeeded without a helper' >&2
    exit 1
fi
grep -q '^is_alpine$' "${calls_file}"
grep -q '^curl$' "${calls_file}"

# The recovery implementation is centralized in menu.sh; menu_m.sh has no
# parallel P3/P4 recovery entrypoint that could bypass this guard.
test "$(grep -c 'run_alpine_partition_recovery' "${menu_file}")" -ge 3
! grep -Eq 'run_alpine_partition_recovery|recover-alpine-p3' "${menu_m_file}"

echo 'PASS: Docker startup skips both P3/P4 recovery gates and reaches menu entry.'
echo 'PASS: Docker backup path skips P3/P4 recovery in both functions files.'
echo 'PASS: Normal Alpine still enters the recovery helper path.'
