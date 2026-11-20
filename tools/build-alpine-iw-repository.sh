#!/bin/sh
# Build additions to the existing Alpine 3.24 P4 repository. The image's
# existing signed APKINDEX must already list these exact package versions.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/mshell-iw-repo.XXXXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
mkdir -p "$temp_dir/repo-iw/x86_64"
docker run --rm --platform linux/amd64 -v "$temp_dir/repo-iw/x86_64:/out" alpine:3.24 sh -ec '
  apk update
  apk fetch --recursive --output /out iw
  wget -q -O /out/APKINDEX.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/APKINDEX.tar.gz
'
# Check that the downloaded package set installs with standard signature
# verification and no network before packaging it.
docker run --rm --platform linux/amd64 --network none -v "$temp_dir/repo-iw:/repo:ro" alpine:3.24 \
  sh -ec 'apk add --no-network --repository /repo iw && iw --version'
mkdir -p "$temp_dir/repo-main/x86_64"
cp "$temp_dir"/repo-iw/x86_64/iw-*.apk "$temp_dir/repo-main/x86_64/"
cp "$temp_dir"/repo-iw/x86_64/libnl3-*.apk "$temp_dir/repo-main/x86_64/"
tar -czf "$temp_dir/iw-repository.tar.gz" -C "$temp_dir" repo-main
mv "$temp_dir/iw-repository.tar.gz" "$root/alpine/iw-repository.tar.gz"
echo "Built alpine/iw-repository.tar.gz"
