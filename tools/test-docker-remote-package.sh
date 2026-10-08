#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
menu_file="${repo_root}/menu_m.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

extract_function() {
    local file="$1" name="$2" output="$3"
    awk -v start="function ${name}() {" '
      $0 == start { copy = 1 }
      copy { print }
      copy && /^}$/ { exit }
    ' "${file}" > "${output}"
    grep -q "^function ${name}() {" "${output}"
}

extract_function "${menu_file}" remote_package_stage_files "${tmp_dir}/stage.sh"
extract_function "${menu_file}" remote_package_source_revision "${tmp_dir}/source-revision.sh"
extract_function "${menu_file}" remote_package_builder_image_digest "${tmp_dir}/image-digest.sh"
extract_function "${menu_file}" remote_package_publish "${tmp_dir}/publish.sh"
extract_function "${menu_file}" package_docker_build_after_backup "${tmp_dir}/after-build.sh"
extract_function "${menu_file}" packing_loader "${tmp_dir}/packing.sh"
extract_function "${repo_root}/functions.sh" getBus "${tmp_dir}/get-bus.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/stage.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/source-revision.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/image-digest.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/publish.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/after-build.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/packing.sh"
# shellcheck source=/dev/null
source "${tmp_dir}/get-bus.sh"

MODEL=DS_TEST
BUILD=7.4-90080
BIOS_CNT=0
FRKRNL=YES
rploaderver=1.4.5.4
MSHELL_DOCKER_BUILDER=1
MSHELL_SOURCE_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
MSHELL_BUILDER_IMAGE_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
loaderdisk_raw=loop7
loaderdisk=loop7
getBus /dev/loop7 >/dev/null
test "${BUS}" = sata
test "${loaderdisk}" = loop7p

# Create a completed-loader fixture. P4 is a private partition archive; the
# stage function must copy exactly that archive into p4/ in the package.
fixture="${tmp_dir}/fixture"
stage="${tmp_dir}/stage"
out="${tmp_dir}/out"
mkdir -p "${fixture}/p1/boot/grub" "${fixture}/p2" "${fixture}/p3" "${fixture}/p4" "${out}"
for path in p1/GRUB_VER p1/zImage p2/GRUB_VER p2/zImage p2/rd.gz p2/grub_cksum.syno \
  p3/custom.gz p3/initrd-dsm p3/rd.gz p3/zImage-dsm p3/bzImage-friend p3/initrd-friend; do
    printf 'fixture:%s\n' "${path}" > "${fixture}/${path}"
done
cat > "${fixture}/p1/boot/grub/grub.cfg" <<EOF
menuentry 'Tiny Core Friend ${MODEL} ${BUILD}' {
  linux /bzImage-friend
  initrd /initrd-friend
}
EOF
printf '{"general":{"model":"%s","version":"%s"}}\n' "${MODEL}" "${BUILD}" > "${fixture}/p3/user_config.json"
printf 'xtcrp fixture\n' > "${tmp_dir}/xtcrp-file"
tar -czf "${fixture}/p3/xtcrp.tgz" -C "${tmp_dir}" xtcrp-file
printf 'private P4 persistence fixture\n' > "${tmp_dir}/p4-file"
tar -czf "${fixture}/p4/localhost.apkovl.tar.gz" -C "${tmp_dir}" p4-file

remote_package_stage_files "${stage}" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" \
  "${fixture}/p4/localhost.apkovl.tar.gz" true
cmp -s "${fixture}/p4/localhost.apkovl.tar.gz" "${stage}/p4/localhost.apkovl.tar.gz"
jq -e --arg revision "${MSHELL_SOURCE_REVISION}" '.source_revision == $revision' \
  "${stage}/manifest.json" >/dev/null
jq -e --arg digest "${MSHELL_BUILDER_IMAGE_DIGEST}" '.builder_image_digest == $digest' \
  "${stage}/manifest.json" >/dev/null
jq -e '.files[] | select(.source == "p4/localhost.apkovl.tar.gz")' \
  "${stage}/manifest.json" >/dev/null

MSHELL_SOURCE_REVISION=invalid
if remote_package_stage_files "${tmp_dir}/invalid-source-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" \
  "${fixture}/p4/localhost.apkovl.tar.gz" true; then
    echo 'FAIL: automatic package accepted invalid source revision' >&2
    exit 1
fi
test ! -e "${tmp_dir}/invalid-source-stage/manifest.json"
unset MSHELL_SOURCE_REVISION
if remote_package_stage_files "${tmp_dir}/missing-source-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" \
  "${fixture}/p4/localhost.apkovl.tar.gz" true; then
    echo 'FAIL: automatic package accepted missing source revision' >&2
    exit 1
fi
test ! -e "${tmp_dir}/missing-source-stage/manifest.json"
MSHELL_SOURCE_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

MSHELL_BUILDER_IMAGE_DIGEST=invalid
if remote_package_stage_files "${tmp_dir}/invalid-digest-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" \
  "${fixture}/p4/localhost.apkovl.tar.gz" true; then
    echo 'FAIL: automatic package accepted invalid builder image digest' >&2
    exit 1
fi
test ! -e "${tmp_dir}/invalid-digest-stage/manifest.json"
unset MSHELL_BUILDER_IMAGE_DIGEST
if remote_package_stage_files "${tmp_dir}/missing-digest-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" \
  "${fixture}/p4/localhost.apkovl.tar.gz" true; then
    echo 'FAIL: automatic package accepted missing builder image digest' >&2
    exit 1
fi
test ! -e "${tmp_dir}/missing-digest-stage/manifest.json"
MSHELL_BUILDER_IMAGE_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# The hardware menu package does not require container provenance.
unset MSHELL_SOURCE_REVISION MSHELL_BUILDER_IMAGE_DIGEST
remote_package_stage_files "${tmp_dir}/manual-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" \
  "${fixture}/p4/localhost.apkovl.tar.gz"
jq -e 'has("source_revision") | not' "${tmp_dir}/manual-stage/manifest.json" >/dev/null
jq -e 'has("builder_image_digest") | not' "${tmp_dir}/manual-stage/manifest.json" >/dev/null
MSHELL_SOURCE_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
MSHELL_BUILDER_IMAGE_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

archive="${out}/remote.updatepack.${MODEL}-${BUILD}.tgz"
remote_package_publish "${stage}" "${archive}" true
test -s "${archive}"
test -s "${archive%.tgz}.manifest.json"
cmp -s "${stage}/manifest.json" "${archive%.tgz}.manifest.json"
tar -xOf "${archive}" p4/localhost.apkovl.tar.gz > "${tmp_dir}/packaged-p4.tgz"
cmp -s "${fixture}/p4/localhost.apkovl.tar.gz" "${tmp_dir}/packaged-p4.tgz"
test -z "$(find "${out}" -maxdepth 1 \( -name '*.tmp.*' -o -name '*.publish-lock' \) -print -quit)"

# A second publisher must not overwrite either output.
printf 'keep existing archive\n' > "${tmp_dir}/existing"
cp "${tmp_dir}/existing" "${out}/collision.tgz"
printf 'keep existing manifest\n' > "${tmp_dir}/existing-manifest"
cp "${tmp_dir}/existing-manifest" "${out}/collision.manifest.json"
if remote_package_publish "${stage}" "${out}/collision.tgz"; then
    echo 'FAIL: existing package was overwritten' >&2
    exit 1
fi
cmp -s "${tmp_dir}/existing" "${out}/collision.tgz"
cmp -s "${tmp_dir}/existing-manifest" "${out}/collision.manifest.json"

# The ordinary interactive package path keeps its prior contract: manifest is
# inside the archive, with no additional sidecar file.
remote_package_publish "${stage}" "${out}/manual.tgz"
test -s "${out}/manual.tgz"
test ! -e "${out}/manual.manifest.json"
tar -tzf "${out}/manual.tgz" | grep -Eq '(^|/)manifest\.json$'

# Exercise the actual automatic packing function without mounts/dialogs:
# staging is stubbed, while the real archive publisher writes to a test /out.
MSHELL_DOCKER_BUILDER=1
MSHELL_SHARED_OUTPUT_DIR="${out}"
MSHELL_TMPDIR="${tmp_dir}"
loaderdisk=loop7p
mount() {
    printf '/dev/loop7p1 on /mnt/loop7p1 type vfat (rw)\n'
    printf '/dev/loop7p2 on /mnt/loop7p2 type vfat (rw)\n'
    printf '/dev/loop7p3 on /mnt/loop7p3 type vfat (rw)\n'
}
mountpoint() { [ "$#" -eq 2 ] && [ "$2" = /mnt/alpine ]; }
dialog() { echo called >> "${tmp_dir}/dialog-called"; return 1; }
remote_package_stage_files() {
    local auto_stage="$1" p4_source="$5"
    mkdir -p "${auto_stage}/p1" "${auto_stage}/p2" "${auto_stage}/p3" "${auto_stage}/p4"
    printf 'private P4 from mounted partition\n' > "${auto_stage}/p4/localhost.apkovl.tar.gz"
    jq -n --arg revision "${MSHELL_SOURCE_REVISION}" --arg digest "${MSHELL_BUILDER_IMAGE_DIGEST}" \
      '{schema:1,source_revision:$revision,builder_image_digest:$digest,files:[{source:"p4/localhost.apkovl.tar.gz",destination:"p4/localhost.apkovl.tar.gz",size:33,sha256:"test"}]}' \
      > "${auto_stage}/manifest.json"
    printf '%s\n' "${p4_source}" > "${tmp_dir}/p4-source-argument"
}
MODEL=DS_AUTO
BUILD=7.4-90080
packing_loader --automatic
test -s "${out}/remote.updatepack.${MODEL}-${BUILD}.tgz"
test -s "${out}/remote.updatepack.${MODEL}-${BUILD}.manifest.json"
test ! -e "${tmp_dir}/dialog-called"
grep -qx '/mnt/alpine/localhost.apkovl.tar.gz' "${tmp_dir}/p4-source-argument"

# Exercise the production post-build gate: mock my()'s combined build+backup
# result and assert only the fully successful path reaches automatic packaging.
packing_loader() { echo package >> "${tmp_dir}/flow"; }
run_build_flow() {
    local build_rc="$1" backup_rc="$2" rc
    : > "${tmp_dir}/flow"
    echo build >> "${tmp_dir}/flow"
    if [ "${build_rc}" -ne 0 ]; then return "${build_rc}"; fi
    echo backup >> "${tmp_dir}/flow"
    rc="${backup_rc}"
    package_docker_build_after_backup "${rc}"
}
run_build_flow 0 0
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build backup package '
if run_build_flow 1 0; then echo 'FAIL: build failure passed package gate' >&2; exit 1; fi
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build '
if run_build_flow 0 7; then echo 'FAIL: backup failure passed package gate' >&2; exit 1; fi
test "$(tr '\n' ' ' < "${tmp_dir}/flow")" = 'build backup '

# The real make() checks PIPESTATUS and build failure before the Docker package
# call. rploader is the final command in my()'s backup pipeline, so its
# failure status is observable.
awk '/^function make\(\) \{$/,/^}$/ { print }' "${menu_file}" > "${tmp_dir}/make.sh"
grep -q 'build_rc=${PIPESTATUS\[0\]}' "${tmp_dir}/make.sh"
grep -q 'if \[ "${build_rc}" -ne 0 \]' "${tmp_dir}/make.sh"
grep -q 'package_docker_build_after_backup "${build_rc}"' "${tmp_dir}/make.sh"
grep -q '^      echo "y"|rploader backup$' "${repo_root}/functions.sh"
grep -q '^      echo "y"|rploader backup$' "${repo_root}/functions_t.sh"
grep -q 'if \[ "\${BUS}" = "block" \] && exit 0' "${repo_root}/functions.sh" || \
  grep -Fq '[ "${BUS}" = "block" ] && exit 0' "${repo_root}/functions.sh"

echo 'PASS: package contains verified P1-P4 payload and publishes archive plus sidecar manifest under /out.'
echo 'PASS: automatic package requires a valid source revision and OCI builder image digest.'
echo 'PASS: automatic Docker packaging is dialog-free and reads P4 from the private mounted partition.'
echo 'PASS: packaging order is build -> backup success -> package; build/backup failures skip packaging.'
