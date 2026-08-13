#!/usr/bin/env bash

# Stage the matching Synology AMDGPU runtime SPK in a loader ramdisk.
# This is intentionally kept in alpine-redpill instead of tcrp-addons:
# the package is selected from the latest upstream release at build time.
set -u

PLATFORM="${1:?platform is required}"
DSM_VERSION="${2:?DSM version is required}"
ADDONS_DIR="${3:?addons directory is required}"
RELEASE_API="https://api.github.com/repos/PeterSuh-Q3/syno-amdgpu-driver/releases/latest"

# Platform and DSM support is determined by the published asset name and its
# package metadata.  Do not keep a local platform whitelist or a DSM 7.4-only
# gate here: new platforms and DSM releases are added upstream independently.
# Retain the caller's full DSM string for exact asset matching, while accepting
# both 7.4 and 7.4.1 style inputs when the release publishes a 7.4 runtime.
DSM_SERIES="$(printf '%s' "${DSM_VERSION}" | sed -nE 's/^([0-9]+\.[0-9]+)(\..*)?$/\1/p')"
[ -n "${DSM_SERIES}" ] || { echo "[amdgpu] invalid DSM version: ${DSM_VERSION}" >&2; exit 0; }

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

RELEASE_JSON="$(curl -fsSL --retry 2 --connect-timeout 15 "${RELEASE_API}")" || {
  echo "[amdgpu] failed to query latest release" >&2
  exit 0
}

# Prefer a platform-specific asset when one exists.  Otherwise accept the
# portable x86_64 runtime introduced by v0.3.7.  The DSM series is matched from
# the asset itself; if the upstream release has no compatible asset, skip it.
ASSET_JSON="$(printf '%s' "${RELEASE_JSON}" | jq -c --arg dsm "${DSM_SERIES}" --arg platform "${PLATFORM}" '
  [ .assets[] | select(.name | test("^syno-amdgpu-runtime-[0-9]+\\.[0-9]+\\.[0-9]+-" + $dsm + "(-[A-Za-z0-9._-]+)?\\.spk$"))
    | {name, url: .browser_download_url, sha256: ((.digest // "") | sub("^sha256:"; "")),
       platform_match: (if (.name | endswith("-" + $platform + ".spk")) then 1 else 0 end),
       universal_match: (if (.name | endswith("-x86_64.spk")) then 1 else 0 end)} ]
  | sort_by(.platform_match, .universal_match) | reverse | .[0] // empty')"

ASSET_NAME="$(printf '%s' "${ASSET_JSON}" | jq -r '.name // empty')"
ASSET_URL="$(printf '%s' "${ASSET_JSON}" | jq -r '.url // empty')"
ASSET_SHA256="$(printf '%s' "${ASSET_JSON}" | jq -r '.sha256 // empty')"
if ! echo "${ASSET_NAME}" | grep -Eq '^syno-amdgpu-runtime-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?\.spk$' || \
   [ "${ASSET_URL##*/}" != "${ASSET_NAME}" ] || \
   ! echo "${ASSET_SHA256}" | grep -Eq '^[a-f0-9]{64}$'; then
  echo "[amdgpu] no matching verified SPK in the latest release" >&2
  exit 0
fi

mkdir -p "${ADDONS_DIR}"
TARGET="${ADDONS_DIR}/${ASSET_NAME}"
if ! curl -fL --retry 2 --connect-timeout 20 "${ASSET_URL}" -o "${TARGET}"; then
  rm -f "${TARGET}"
  echo "[amdgpu] package download failed" >&2
  exit 0
fi

if [ "$(sha256sum "${TARGET}" | awk '{print $1}')" != "${ASSET_SHA256}" ]; then
  rm -f "${TARGET}"
  echo "[amdgpu] package checksum mismatch" >&2
  exit 0
fi

printf '%s\n' "${ASSET_JSON}" > "${ADDONS_DIR}/amdgpu-driver.json"
echo "[amdgpu] staged ${ASSET_NAME} in ${ADDONS_DIR}"
