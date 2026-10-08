#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

# Exercise the function called by the p menu, including its real post-build
# Docker gate. All device and network operations are replaced with fixtures.
awk '
  /^make_with_progress\(\) \{$/ { copy = 1 }
  copy { print }
  copy && /^}$/ { exit }
' "${repo_root}/functions.sh" > "${tmp_dir}/build-function.sh"
grep -q '^make_with_progress() {' "${tmp_dir}/build-function.sh"
awk '
  /^function package_docker_build_after_backup\(\) \{$/ { copy = 1 }
  copy { print }
  copy && /^}$/ { exit }
' "${repo_root}/menu_m.sh" > "${tmp_dir}/package-gate.sh"
grep -q '^function package_docker_build_after_backup() {' "${tmp_dir}/package-gate.sh"
awk '
  /^function remote_package_log\(\) \{$/ { copy = 1 }
  copy { print }
  copy && /^}$/ { exit }
' "${repo_root}/menu_m.sh" > "${tmp_dir}/package-log.sh"

# shellcheck source=/dev/null
source "${tmp_dir}/build-function.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/package-gate.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/package-log.sh"

MODEL=DS_TEST
BUILD=7.4-90080
BUS=sata
VERBOSE_MODE=OFF
R8168_YN=N
DMPM=EUDEV
MSHELL_DOCKER_BUILDER=1
mock_build_rc=0
mock_backup_rc=0
mock_package_rc=0

checkUserConfig() { return 0; }
usbidentify() { :; }
clear() { :; }
getip() { :; }
dhcp_freeze() { :; }
setSuggest() { :; }
writeConfigKey() { :; }
refresh_userconfig_hash() { echo baseline >> "${tmp_dir}/flow"; }
log_backup_step() { :; }
log_success() { :; }
log_build_step() { :; }
log_error() { printf 'ERROR: %s\n' "$1"; }
show_backup_error_info() { echo build-error-details; }
st() { echo finish >> "${tmp_dir}/flow"; }
tee() { command tee "${tmp_dir}/zlastbuild.log"; }
my() {
    echo build >> "${tmp_dir}/flow"
    if [ "${mock_build_rc}" -ne 0 ]; then return "${mock_build_rc}"; fi
    echo backup >> "${tmp_dir}/flow"
    return "${mock_backup_rc}"
}
packing_loader() {
    test "$1" = --automatic
    echo package >> "${tmp_dir}/flow"
    remote_package_log "Fixture archive published to /out"
    return "${mock_package_rc}"
}

: > "${tmp_dir}/flow"
make_with_progress fri OFF > "${tmp_dir}/success-console" 2>&1 <<< ''
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build backup baseline package finish '
grep -Fq '[REMOTE PACKAGE] Fixture archive published to /out' "${tmp_dir}/success-console"
grep -Fq 'press any key to continue' "${tmp_dir}/success-console"
! grep -Fq '[REMOTE PACKAGE]' "${tmp_dir}/zlastbuild.log"

mock_build_rc=7
: > "${tmp_dir}/flow"
if make_with_progress fri OFF > "${tmp_dir}/build-failure-console" 2>&1 <<< ''; then
    echo 'FAIL: build failure returned success' >&2
    exit 1
fi
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build '
! grep -Fq '[REMOTE PACKAGE]' "${tmp_dir}/build-failure-console"

mock_build_rc=0
mock_backup_rc=8
: > "${tmp_dir}/flow"
if make_with_progress fri OFF > "${tmp_dir}/backup-failure-console" 2>&1 <<< ''; then
    echo 'FAIL: backup failure returned success' >&2
    exit 1
fi
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build backup '
! grep -Fq '[REMOTE PACKAGE]' "${tmp_dir}/backup-failure-console"

mock_backup_rc=0
mock_package_rc=9
: > "${tmp_dir}/flow"
if make_with_progress fri OFF > "${tmp_dir}/package-failure-console" 2>&1 <<< ''; then
    echo 'FAIL: package failure returned success' >&2
    exit 1
fi
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build backup baseline package '
grep -Fq 'Remote package failed with exit code: 9' "${tmp_dir}/package-failure-console"
! grep -Fq 'press any key to continue' "${tmp_dir}/package-failure-console"

mock_package_rc=0
MSHELL_DOCKER_BUILDER=0
: > "${tmp_dir}/flow"
make_with_progress fri OFF > "${tmp_dir}/alpine-console" 2>&1 <<< ''
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build backup baseline finish '

# The main menu calls make_with_progress directly; remove the unused make().
grep -Fq 'make_with_progress "fri" "${PREVENT_INIT}"' "${repo_root}/menu_m.sh"
! grep -Eq '^function make\(\) \{' "${repo_root}/menu_m.sh"
cmp -s "${repo_root}/functions.sh" "${repo_root}/functions_t.sh"
grep -q '^      echo "y"|rploader backup$' "${repo_root}/functions.sh"

echo 'PASS: main-menu build and backup success publish before completion prompt.'
echo 'PASS: build/backup failures skip packaging; package failure returns its code.'
echo 'PASS: normal Alpine skips automatic packaging; unused make() is removed.'
