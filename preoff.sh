#!/bin/bash

tag=${1}

# Get the loader disk using the UUID "6234-C863"
loaderdisk=$(sudo /sbin/blkid | grep "6234-C863" | cut -d ':' -f1 | sed 's/p\?3//g' | awk -F/ '{print $NF}' | head -n 1)
tcrppart="${loaderdisk}3"

# Output the loader disk
echo "tcrppart: $tcrppart"

cd /mnt/$tcrppart/

mv -vrf /dev/shm/tcrp-addons/ /mnt/$tcrppart/.
git clone -b master --single-branch --depth=1 https://github.com/PeterSuh-Q3/redpill-load.git

mkdir -p ./tcrp-modules/all-modules/releases
mkdir -p ./tcrp-modules/all-modules/src

mkdir -p ./tcrp-modules/eudev/releases
mkdir -p ./tcrp-modules/eudev/recipes

curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/rpext-index.json -o ./tcrp-modules/all-modules
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/releases/firmware.tgz -o ./tcrp-modules/all-modules/releases
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/releases/firmwarei915.tgz -o ./tcrp-modules/all-modules/releases
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/releases/epyc700272.json -o ./tcrp-modules/all-modules/releases
curl -kL https://github.com/PeterSuh-Q3/arpl-modules/releases/download/${tag}/epyc7002-7.2-5.10.55.tgz -o ./tcrp-modules/all-modules/releases

curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/rpext-index.json -o ./tcrp-modules/eudev
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/releases/eudev-7.1.tgz -o ./tcrp-modules/eudev/releases
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/releases/install.sh -o ./tcrp-modules/eudev/releases
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/recipes/universal.json -o ./tcrp-modules/eudev/recipes

sha256=$(sha256sum ./tcrp-modules/all-modules/releases/epyc7002-7.2-5.10.55.tgz
org=$(jq -r '.files[0].sha256' ./tcrp-modules/all-modules/releases/epyc700272.json)
sed -i "s/$org/$sha256/" ./tcrp-modules/all-modules/releases/epyc700272.json

