#!/bin/bash

tag=${1}

# Get the loader disk using the UUID "6234-C863"
loaderdisk=$(sudo /sbin/blkid | grep "6234-C863" | cut -d ':' -f1 | sed 's/p\?3//g' | awk -F/ '{print $NF}' | head -n 1)
tcrppart="${loaderdisk}3"

# Output the loader disk
echo "tcrppart: $tcrppart"

cd /mnt/$tcrppart/

[[ -d /dev/shm/tcrp-addons ]] && sudo cp -rf /dev/shm/tcrp-addons/ /mnt/$tcrppart/.

rm -rf /dev/shm/tcrp-addons/

sudo rm /mnt/$tcrppart/xtcrp.tgz

rm -rf /dev/shm/tcrp-modules/
sudo rm -rf /mnt/$tcrppart/tcrp-modules

mkdir -p ./tcrp-modules/all-modules/releases
mkdir -p ./tcrp-modules/all-modules/src

mkdir -p ./tcrp-modules/eudev/releases
mkdir -p ./tcrp-modules/eudev/recipes

mkdir -p ./tcrp-modules/ddsml/releases
mkdir -p ./tcrp-modules/ddsml/recipes

curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/rpext-index.json -o ./tcrp-modules/all-modules/rpext-index.json
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/releases/epyc700272.json -o ./tcrp-modules/all-modules/releases/epyc700272.json
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/releases/firmware.tgz -o ./tcrp-modules/all-modules/releases/firmware.tgz
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/releases/firmwarei915.tgz -o ./tcrp-modules/all-modules/releases/firmwarei915.tgz
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/all-modules/src/install.sh -o ./tcrp-modules/all-modules/src/install.sh
curl -kL https://github.com/PeterSuh-Q3/arpl-modules/releases/download/${tag}/epyc7002-7.2-5.10.55.tgz -o ./tcrp-modules/all-modules/releases/epyc7002-7.2-5.10.55.tgz

curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/rpext-index.json -o ./tcrp-modules/eudev/rpext-index.json
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/recipes/universal.json -o ./tcrp-modules/eudev/recipes/universal.json
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/releases/eudev-7.1.tgz -o ./tcrp-modules/eudev/releases/eudev-7.1.tgz
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/eudev/releases/install.sh -o ./tcrp-modules/eudev/releases/install.sh

curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/ddsml/rpext-index.json -o ./tcrp-modules/ddsml/rpext-index.json
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/ddsml/recipes/universal.json -o ./tcrp-modules/ddsml/recipes/universal.json
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/ddsml/releases/check-all-modules.sh -o ./tcrp-modules/ddsml/releases/check-all-modules.sh
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/ddsml/releases/modules.alias.3.json.tgz -o ./tcrp-modules/ddsml/releases/modules.alias.3.json.tgz
curl -kL https://github.com/PeterSuh-Q3/tcrp-modules/raw/refs/heads/main/ddsml/releases/modules.alias.4.json.tgz -o ./tcrp-modules/ddsml/releases/modules.alias.4.json.tgz

sha256=$(sha256sum ./tcrp-modules/all-modules/releases/epyc7002-7.2-5.10.55.tgz | awk '{print $1}')
org=$(jq -r '.files[0].sha256' ./tcrp-modules/all-modules/releases/epyc700272.json)
sudo sed -i "s/$org/$sha256/g" ./tcrp-modules/all-modules/releases/epyc700272.json

