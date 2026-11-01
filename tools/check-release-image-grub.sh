#!/usr/bin/env bash
# Check the GRUB binaries in the final raw image, not an intermediate mount.
# The loader-build checker handles addon binaries in initrd-dsm separately.
set -euo pipefail

image=${1:?usage: check-release-image-grub.sh FINAL_IMAGE.img}
[[ -f "$image" ]] || { echo "Image not found: $image" >&2; exit 1; }
for tool in losetup mount umount sha256sum; do
  command -v "$tool" >/dev/null || { echo "Required tool missing: $tool" >&2; exit 1; }
done

before=$(sha256sum "$image" | awk '{print $1}')
work=$(mktemp -d)
loop=
mounted=0
cleanup() {
  result=$?
  trap - EXIT
  if [[ "$mounted" == 1 ]]; then
    if umount "$work/p1"; then
      mounted=0
    else
      echo "Could not unmount read-only image P1: $work/p1" >&2
      result=1
    fi
  fi
  if [[ "$mounted" == 0 && -n "$loop" ]]; then
    losetup -d "$loop" || result=1
  fi
  if [[ "$mounted" == 0 ]]; then
    rmdir "$work/p1" "$work" || result=1
  fi
  exit "$result"
}
trap cleanup EXIT

mkdir "$work/p1"
loop=$(losetup --find --show --read-only --partscan "$image")
attempt=0
while [[ ! -b "${loop}p1" && "$attempt" -lt 20 ]]; do
  sleep 0.2
  attempt=$((attempt + 1))
done
[[ -b "${loop}p1" ]] || { echo "P1 block device not found: ${loop}p1" >&2; exit 1; }
mount -o ro,nosuid,nodev,noexec "${loop}p1" "$work/p1"
mounted=1

bash "$(dirname "$0")/check-grub-x86-baseline.sh" "$work/p1"

after=$(sha256sum "$image" | awk '{print $1}')
[[ "$before" == "$after" ]] || { echo "Image changed during read-only check: $image" >&2; exit 1; }
echo "Release image GRUB baseline: PASSED; image SHA-256=$after; image=$image"
echo 'Scope: installed EFI files and GRUB modules; compressed BIOS core and embedded EFI module blobs are not fully disassembled.'
