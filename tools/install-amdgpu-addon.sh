#!/usr/bin/env bash

# Select and stage only the pinned Synology AMDGPU runtime metadata in a loader
# ramdisk. The SPK itself is downloaded after DSM has mounted a package volume.
# AMDGPU Top is bundled and managed by MSHELL Manager, so it is not staged here.
set -u

PLATFORM="${1:?platform is required}"
DSM_VERSION="${2:?DSM version is required}"
KERNEL_VERSION="${3:?kernel version is required}"
ADDONS_DIR="${4:?addons directory is required}"
MANIFEST_PATH="${5:-}"
mkdir -p "${ADDONS_DIR}"
# Do not let a reused ramdisk tree retain an older AMD SPK or its metadata
# when the current machine/platform/kernel no longer qualifies.
rm -f "${ADDONS_DIR}"/syno-amdgpu-runtime-*.spk "${ADDONS_DIR}/amdgpu-driver.json"

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

case "${DSM_VERSION}" in
  7.4*) ;;
  *) echo "[amdgpu] DSM ${DSM_VERSION} has no matching runtime asset; staging skipped"; exit 0 ;;
esac

if [ -z "${MANIFEST_PATH}" ] || [ ! -s "${MANIFEST_PATH}" ]; then
  echo "[amdgpu] central package manifest is unavailable" >&2
  exit 0
fi

# The runtime asset is selected from packages.amd_gpu_runtime. This point is
# reached only for kernel 5.10.55 (kernel 4.4.x exits above). Preserve the
# build-time compatibility decision in the metadata for DSM-side validation.
stage_amdgpu_package() {
  local manifest_key="$1" name_pattern="$2" out_json="$3"
  local asset_json asset_name asset_url asset_sha256 asset_size version

  asset_json="$(jq -c --arg suffix "-7.4-x86_64-${KERNEL_ASSET}.spk" \
    --arg key "${manifest_key}" --arg platform "${PLATFORM}" \
    --arg kernel "${KERNEL_VERSION}" --arg dsm "${DSM_VERSION}" '
    .packages[$key].assets[]? | select(.name | endswith($suffix)) |
    . + {package_id: "syno-amdgpu-runtime", dsm_version: $dsm,
         platform: $platform, kernel: $kernel,
         version: (.name | capture("-(?<version>[0-9]+\\.[0-9]+\\.[0-9]+)-7\\.4-").version)}' \
    "${MANIFEST_PATH}" | head -n 1)"

  asset_name="$(printf '%s' "${asset_json}" | jq -r '.name // empty')"
  asset_url="$(printf '%s' "${asset_json}" | jq -r '.url // empty')"
  asset_sha256="$(printf '%s' "${asset_json}" | jq -r '.sha256 // empty')"
  asset_size="$(printf '%s' "${asset_json}" | jq -r '.size // empty')"
  version="$(printf '%s' "${asset_json}" | jq -r '.version // empty')"
  if ! echo "${asset_name}" | grep -Eq "${name_pattern}" || \
     [ "${asset_url##*/}" != "${asset_name}" ] || \
     ! echo "${asset_sha256}" | grep -Eq '^[a-f0-9]{64}$' || \
     ! echo "${asset_size}" | grep -Eq '^[1-9][0-9]*$' || \
     [ -z "${version}" ]; then
    echo "[amdgpu] no matching verified ${manifest_key} SPK in the latest release" >&2
    return 1
  fi

  rm -f "${ADDONS_DIR}/${asset_name}"
  printf '%s\n' "${asset_json}" > "${ADDONS_DIR}/${out_json}"
  echo "[amdgpu] staged metadata for ${asset_name}; SPK download deferred until DSM is ready"
  return 0
}

runtime_staged=0

if stage_amdgpu_package "amd_gpu_runtime" \
  '^syno-amdgpu-runtime-[0-9]+\.[0-9]+\.[0-9]+-7\.4-x86_64-kernel(5\.10\.55|4\.4\.x)\.spk$' \
  "amdgpu-driver.json"; then
  runtime_staged=1
fi

if [ "${runtime_staged}" -ne 1 ]; then
  echo "[amdgpu] runtime staging incomplete" >&2
  exit 1
fi

exit 0
