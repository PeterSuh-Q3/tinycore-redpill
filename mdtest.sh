#!/usr/bin/env bash

TMP_PATH=/tmp

[ "$(which mdadm)_" == "_" ] && tce-load -iw mdadm
DSMROOTS="$(sudo fdisk -l | grep -E "sd[a-z]{1,2}1" | grep "Linux raid autodetect" | grep -E '16785407|4982527' | awk '{print $1}')"

# assemble and mount md0
sudo rm -f "${TMP_PATH}/menuz"
sudo mkdir -p "${TMP_PATH}/mdX"
num=$(echo $DSMROOTS | wc -w)
sudo mdadm -C /dev/md0 -e 0.9 -amd -R -l1 --force -n$num $DSMROOTS 2>/dev/null
T="$(sudo blkid -o value -s TYPE /dev/md0 2>/dev/null)"
[ "$FRKRNL" = "NO" ] && sudo tune2fs -O ^quota /dev/md0
sudo mount -t "${T:-ext4}" /dev/md0 "${TMP_PATH}/mdX"

ll "${TMP_PATH}/mdX/etc/shadow"
