#!/usr/bin/env bash

TMP_PATH=/tmp

set -u # Unbound variable errors are not allowed

[ "$(which mdadm)_" == "_" ] && tce-load -iw mdadm
DSMROOTS="$(sudo fdisk -l | grep -E "sd[a-z]{1,2}1" | grep "Linux raid autodetect" | grep -E '16785407|4982527' | awk '{print $1}')"

# assemble and mount md0
sudo rm -f "${TMP_PATH}/menuz"
sudo mkdir -p "${TMP_PATH}/mdX"
num=$(echo $DSMROOTS | wc -w)
sudo mdadm -C /dev/md0 -e 0.9 -amd -R -l1 --force -n$num $DSMROOTS
T="$(sudo blkid -o value -s TYPE /dev/md0)"
sudo tune2fs -O ^quota /dev/md0
#sleep 2
sudo mount -t "${T:-ext4}" /dev/md0 "${TMP_PATH}/mdX"

sudo ls -l ${TMP_PATH}/mdX/etc/shadow

  if [ -f "${TMP_PATH}/mdX/etc/shadow" ]; then
    while read -r L; do
      U=$(echo "${L}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") print $1;}')
      [ -z "${U}" ] && continue
      E=$(echo "${L}" | awk -F ':' '{if ($8 == "1") print "disabled"; else print "        ";}')
      grep -q "status=on" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/null
      [ $? -eq 0 ] && S="SecureSignIn" || S="            "
      printf "\"%-36s %-10s %-14s\"\n" "${U}" "${E}" "${S}" >>"${TMP_PATH}/menuz"
    done <<<"$(sudo cat "${TMP_PATH}/mdX/etc/shadow" 2>/dev/null)"
  fi

sudo umount "${TMP_PATH}/mdX"
sudo mdadm --stop /dev/md0
sudo rm -rf "${TMP_PATH}/mdX"

sudo cat ${TMP_PATH}/menuz

echo "Finished!"
