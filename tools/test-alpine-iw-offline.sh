#!/bin/sh
# Verify the exact image repositories and overlay without Internet access.
set -eu
[ "$#" -eq 1 ] && [ -f "$1" ] || {
  echo "Usage: sh tools/test-alpine-iw-offline.sh /path/to/alpine-partition.tar.gz" >&2
  exit 2
}
archive=$(CDPATH= cd -- "$(dirname "$1")" && pwd)/$(basename "$1")
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
docker run --rm --platform linux/amd64 --network none \
  -v "$archive:/source/alpine-partition.tar.gz:ro" \
  -v "$root:/workspace:ro" alpine:3.24 sh -ec '
    mkdir -p /mnt/alpine /run/mshell-iw /usr/local/sbin
    tar -xzf /source/alpine-partition.tar.gz -C /mnt/alpine ./repo-main ./repo-community
    tar -xzf /workspace/alpine/iw-repository.tar.gz -C /mnt/alpine
    tar -xOzf /workspace/localhost.apkovl.tar.gz ./etc/apk/world > /etc/apk/world
    grep -qx iw /etc/apk/world
    apk --root /run/mshell-iw --initdb --keys-dir /etc/apk/keys \
      --repositories-file /dev/null --repository /mnt/alpine/repo-main \
      --repository /mnt/alpine/repo-community --no-network --no-scripts add iw
    tar -xOzf /workspace/localhost.apkovl.tar.gz ./usr/local/sbin/iw > /usr/local/sbin/iw
    chmod 755 /usr/local/sbin/iw
    /usr/local/sbin/iw --version
    su -s /bin/sh nobody -c "/usr/local/sbin/iw --version"
    echo "PASS: signed local repository and iw wrapper work without network"
  '
