#!/usr/bin/env bash
# Builds the static Linux CLI and packs it into dist/.
# Usage: ./build.sh
# Needs g++ and a Debian-based system. No root: the dependencies are unpacked into build/linux/deps.

set -euo pipefail

VERSION=1.1
ARCHIVE="synoxtract-$VERSION-linux.tar.gz"

cd "$(dirname "$0")"

OUT=build/linux
DEPS="$OUT/deps"
rm -rf "$OUT"
mkdir -p "$DEPS/root" dist

(cd "$DEPS" && apt-get download libsodium-dev libmsgpack-cxx-dev)
for deb in "$DEPS"/*.deb; do
    dpkg -x "$deb" "$DEPS/root"
done

g++ -std=c++17 -O2 -Wall -Wextra -DMSGPACK_NO_BOOST \
    -I"$DEPS/root/usr/include" main.cpp \
    -L"$DEPS/root/usr/lib/$(gcc -dumpmachine)" -lsodium \
    -static -s -o "$OUT/synoxtract"

"$OUT/synoxtract" --help > /dev/null

tar -C "$OUT" --owner=0 --group=0 --mode=755 --mtime=@0 -cf - synoxtract | gzip -n > "dist/$ARCHIVE"
(cd dist && sha256sum "$ARCHIVE" | tee "$ARCHIVE.sha256sum")
