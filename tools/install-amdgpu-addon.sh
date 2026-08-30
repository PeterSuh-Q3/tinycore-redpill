#!/usr/bin/env bash

# Stage the matching Synology AMDGPU runtime + amdgpu_top SPKs in a loader
# ramdisk. This is intentionally kept in alpine-redpill instead of
# tcrp-addons: the packages are selected from the latest upstream release
# at build time.
set -u

PLATFORM="${1:?platform is required}"
DSM_VERSION="${2:?DSM version is required}"
KERNEL_VERSION="${3:?kernel version is required}"
ADDONS_DIR="${4:?addons directory is required}"
MANIFEST_PATH="${5:-}"

# AMD userspace runtime integrates the SynoCommunity Jellyfin SPK. Only stage
# it for the x64 platforms declared by that package's current DSM 7.2+ build.
# This is intentionally narrower than the amdgpu.ko platform set: a kernel
# module may be valid without a supported native Jellyfin package.
JELLYFIN_X64_PLATFORMS='apollolake avoton braswell broadwell broadwellnk broadwellnkv2 broadwellntbap bromolow denverton epyc7002 geminilake geminilakenk grantley icelaked kvmx64 purley r1000 r1000nk v1000 v1000nk'
case " ${JELLYFIN_X64_PLATFORMS} " in
  *" ${PLATFORM} "*) ;;
  *)
    echo "[amdgpu] ${PLATFORM} is outside SynoCommunity Jellyfin x64 support; runtime staging skipped"
    exit 0
    ;;
esac

# Kernel 4.4 AMDGPU is currently being validated at the kernel-module level.
# Do not automatically stage Mesa/VA-API/Jellyfin userspace there: an AMDGPU
# DRM fault must be investigated without a userspace runtime auto-install.
# Runtime userspace is portable DSM 7.4 x86_64 for the supported kernel 5
# family; DSM version is retained for diagnostics only.
case "${KERNEL_VERSION}" in
  5.10.55) KERNEL_ASSET="kernel5.10.55" ;;
  4.4.*)
    echo "[amdgpu] kernel ${KERNEL_VERSION}: runtime staging disabled while kernel 4 AMDGPU stability is under validation"
    exit 0
    ;;
  *) echo "[amdgpu] unsupported kernel family: ${KERNEL_VERSION}" >&2; exit 0 ;;
esac

if ! command -v lspci >/dev/null 2>&1; then
  echo "[amdgpu] lspci is unavailable; skipping GPU detection" >&2
  exit 0
fi

GPU_DETECTED="false"
for GPU_CLASS in 0300 0302 0380; do
  if lspci -n -d "1002::${GPU_CLASS}" 2>/dev/null | grep -q .; then
    GPU_DETECTED="true"
    echo "[amdgpu] AMD GPU detected (class ${GPU_CLASS})"
    break
  fi
done
[ "${GPU_DETECTED}" = "true" ] || { echo "[amdgpu] no supported AMD display controller detected"; exit 0; }

if [ -z "${MANIFEST_PATH}" ] || [ ! -s "${MANIFEST_PATH}" ]; then
  echo "[amdgpu] central package manifest is unavailable" >&2
  exit 0
fi

# 2026-08-30: syno-amdgpu-driver와 syno-amdgpu-top 릴리즈가 분리됐다(예전엔
# 런타임 SPK 하나에 같이 들어있었음) - 매니페스트(packages.amd_gpu_runtime /
# packages.amdgpu_top)에서 각각 따로 받아온다. 이 지점에 도달했다는 건 이미
# kernel 4.4.x가 아니라는 뜻(위에서 이미 exit 0으로 걸러짐)이므로 별도 커널
# 분기 없이 둘 다 시도한다.
stage_amdgpu_package() {
  local manifest_key="$1" name_pattern="$2" out_json="$3"
  local asset_json asset_name asset_url asset_sha256 target

  asset_json="$(jq -c --arg suffix "-7.4-x86_64-${KERNEL_ASSET}.spk" \
    --arg key "${manifest_key}" '
    .packages[$key].assets[]? | select(.name | endswith($suffix)) |
    {name, url, sha256}' "${MANIFEST_PATH}" | head -n 1)"

  asset_name="$(printf '%s' "${asset_json}" | jq -r '.name // empty')"
  asset_url="$(printf '%s' "${asset_json}" | jq -r '.url // empty')"
  asset_sha256="$(printf '%s' "${asset_json}" | jq -r '.sha256 // empty')"
  if ! echo "${asset_name}" | grep -Eq "${name_pattern}" || \
     [ "${asset_url##*/}" != "${asset_name}" ] || \
     ! echo "${asset_sha256}" | grep -Eq '^[a-f0-9]{64}$'; then
    echo "[amdgpu] no matching verified ${manifest_key} SPK in the latest release" >&2
    return 1
  fi

  mkdir -p "${ADDONS_DIR}"
  target="${ADDONS_DIR}/${asset_name}"
  if ! curl -fL --retry 2 --connect-timeout 20 "${asset_url}" -o "${target}"; then
    rm -f "${target}"
    echo "[amdgpu] ${manifest_key} package download failed" >&2
    return 1
  fi

  if [ "$(sha256sum "${target}" | awk '{print $1}')" != "${asset_sha256}" ]; then
    rm -f "${target}"
    echo "[amdgpu] ${manifest_key} package checksum mismatch" >&2
    return 1
  fi

  printf '%s\n' "${asset_json}" > "${ADDONS_DIR}/${out_json}"
  echo "[amdgpu] staged ${asset_name} in ${ADDONS_DIR}"
  return 0
}

stage_amdgpu_package "amd_gpu_runtime" \
  '^syno-amdgpu-runtime-[0-9]+\.[0-9]+\.[0-9]+-7\.4-x86_64-kernel(5\.10\.55|4\.4\.x)\.spk$' \
  "amdgpu-driver.json"

# amdgpu_top(모니터링 유틸)은 드라이버와 별개 패키지다 - 못 받아와도 위
# 드라이버 스테이징 자체를 막을 이유는 없으므로 실패해도 스크립트를
# 끝내지 않는다(있으면 좋은 부가 도구).
stage_amdgpu_package "amdgpu_top" \
  '^syno-amdgpu-top-[0-9]+\.[0-9]+\.[0-9]+-7\.4-x86_64-kernel(5\.10\.55|4\.4\.x)\.spk$' \
  "amdgpu-top.json"

exit 0
