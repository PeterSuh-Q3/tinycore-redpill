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
extract_function "${menu_file}" remote_package_log "${tmp_dir}/log.sh"
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
source "${tmp_dir}/log.sh"
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

# Create a completed-loader fixture. P4 may exist on the source loader, but it
# must never enter the remote package or its manifest.
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
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" true
jq -e --arg revision "${MSHELL_SOURCE_REVISION}" '.source_revision == $revision' \
  "${stage}/manifest.json" >/dev/null
jq -e --arg digest "${MSHELL_BUILDER_IMAGE_DIGEST}" '.builder_image_digest == $digest' \
  "${stage}/manifest.json" >/dev/null
jq -e '([.files[].source] | all(contains("p4/") | not)) and
  (has("p4_persistence_source") | not) and (has("p4_persistence_sha256") | not)' \
  "${stage}/manifest.json" >/dev/null
test ! -e "${stage}/p4"

MSHELL_SOURCE_REVISION=invalid
if remote_package_stage_files "${tmp_dir}/invalid-source-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" true; then
    echo 'FAIL: automatic package accepted invalid source revision' >&2
    exit 1
fi
test ! -e "${tmp_dir}/invalid-source-stage/manifest.json"
unset MSHELL_SOURCE_REVISION
if remote_package_stage_files "${tmp_dir}/missing-source-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" true; then
    echo 'FAIL: automatic package accepted missing source revision' >&2
    exit 1
fi
test ! -e "${tmp_dir}/missing-source-stage/manifest.json"
MSHELL_SOURCE_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

MSHELL_BUILDER_IMAGE_DIGEST=invalid
if remote_package_stage_files "${tmp_dir}/invalid-digest-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" true; then
    echo 'FAIL: automatic package accepted invalid builder image digest' >&2
    exit 1
fi
test ! -e "${tmp_dir}/invalid-digest-stage/manifest.json"
unset MSHELL_BUILDER_IMAGE_DIGEST
if remote_package_stage_files "${tmp_dir}/missing-digest-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3" true; then
    echo 'FAIL: automatic package accepted missing builder image digest' >&2
    exit 1
fi
test ! -e "${tmp_dir}/missing-digest-stage/manifest.json"
MSHELL_BUILDER_IMAGE_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# The hardware menu package does not require container provenance.
unset MSHELL_SOURCE_REVISION MSHELL_BUILDER_IMAGE_DIGEST
remote_package_stage_files "${tmp_dir}/manual-stage" \
  "${fixture}/p1" "${fixture}/p2" "${fixture}/p3"
jq -e 'has("source_revision") | not' "${tmp_dir}/manual-stage/manifest.json" >/dev/null
jq -e 'has("builder_image_digest") | not' "${tmp_dir}/manual-stage/manifest.json" >/dev/null
MSHELL_SOURCE_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
MSHELL_BUILDER_IMAGE_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

archive="${out}/remote.updatepack.${MODEL}-${BUILD}.tgz"
remote_package_publish "${stage}" "${archive}" true
test -s "${archive}"
test -s "${archive%.tgz}.manifest.json"
cmp -s "${stage}/manifest.json" "${archive%.tgz}.manifest.json"
! tar -tzf "${archive}" | grep -Eq '(^|/)p4(/|$)'
jq -e '([.files[].source] | all(contains("p4/") | not)) and
  (has("p4_persistence_source") | not) and (has("p4_persistence_sha256") | not)' \
  "${archive%.tgz}.manifest.json" >/dev/null
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
dialog() { echo called >> "${tmp_dir}/dialog-called"; return 1; }
remote_package_stage_files() {
    local auto_stage="$1"
    mkdir -p "${auto_stage}/p1" "${auto_stage}/p2" "${auto_stage}/p3"
    jq -n --arg revision "${MSHELL_SOURCE_REVISION}" --arg digest "${MSHELL_BUILDER_IMAGE_DIGEST}" \
      '{schema:1,source_revision:$revision,builder_image_digest:$digest,files:[{source:"p3/xtcrp.tgz",destination:"p3/xtcrp.tgz",size:33,sha256:"test"}]}' \
      > "${auto_stage}/manifest.json"
}
MODEL=DS_AUTO
BUILD=7.4-90080
packing_loader --automatic > "${tmp_dir}/automatic-console" 2>&1
test -s "${out}/remote.updatepack.${MODEL}-${BUILD}.tgz"
test -s "${out}/remote.updatepack.${MODEL}-${BUILD}.manifest.json"
test ! -e "${tmp_dir}/dialog-called"
! tar -tzf "${out}/remote.updatepack.${MODEL}-${BUILD}.tgz" | grep -Eq '(^|/)p4(/|$)'
! jq -e '.files[].source | startswith("p4/")' \
  "${out}/remote.updatepack.${MODEL}-${BUILD}.manifest.json" >/dev/null
for message in \
  'Starting automatic Docker package' \
  'Output:' \
  'Checking P1-P3 mounts' \
  'Validating and staging required files and manifest' \
  'Creating and verifying package archive' \
  'Publishing manifest to shared output' \
  'Publishing archive to shared output' \
  'Complete: archive'; do
    grep -Fq "${message}" "${tmp_dir}/automatic-console"
done
grep -Eq 'Complete: archive .* \([0-9]+ bytes\); manifest .* \([0-9]+ bytes\)' "${tmp_dir}/automatic-console"

echo 'PASS: package includes P1-P3 payload only; P4 is absent from archive and manifest.'
echo 'PASS: automatic package requires a valid source revision and OCI builder image digest.'
echo 'PASS: automatic Docker packaging shows tty progress and does not require or read P4.'
