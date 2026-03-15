#!/bin/bash

if grep </proc/cmdline -q "debug"; then
  # TODO add ttyd and lrzsz, first need some nic driver
  echo "Debug mode, you will stay at the first kernel"
  exit 0
fi

# Args: $1 vid $2 pid $3 synoboot_satadom $4 dom_szmax
get_synoboot() {
  local usbfs
  if [[ ${3:-"0"} = "0" ]]; then
    dev=$(udevadm trigger -v -n -s block -p ID_VENDOR_ID="$1" -p ID_MODEL_ID="$2" | head -n 1)
    if [[ ! "${dev}" = "" ]]; then
      usbfs=/dev/"${dev##*/}"
    fi
  else
    # satadom size <= 1024 MB or dom_szmax
    devs=$(find /sys/block/sd*)
    for dev in $devs; do
      if [[ $(cat "$dev"/size) -le $((${4:-1024} * 1024 * 1024 / 512)) ]]; then
        usbfs=/dev/"${dev##*/}"
        break
      fi
    done
  fi
  echo "$usbfs"
}

CMDLINE=$(cat /proc/cmdline)
vid=$(for x in $CMDLINE; do
  [[ $x = vid=* ]] || continue
  echo "${x#vid=}" | cut -b 3-6
done)
pid=$(for x in $CMDLINE; do
  [[ $x = pid=* ]] || continue
  echo "${x#pid=}" | cut -b 3-6
done)
synoboot_satadom=$(for x in $CMDLINE; do
  [[ $x = synoboot_satadom=* ]] || continue
  echo "${x#synoboot_satadom=}"
done)
dom_szmax=$(for x in $CMDLINE; do
  [[ $x = dom_szmax=* ]] || continue
  echo "${x#dom_szmax=}"
done)

# found synoboot
usbfs=$(get_synoboot "$vid" "$pid" "$synoboot_satadom" "$dom_szmax")
wait_time=30
time_counter=0
while [ "${usbfs}" = "" ] && [ $time_counter -lt $wait_time ]; do
  sleep 1
  usbfs=$(get_synoboot "$vid" "$pid" "$synoboot_satadom" "$dom_szmax")
  echo "Still waiting for boot device (waited $((time_counter = time_counter + 1)) of ${wait_time} seconds)"
done
echo "usbfs=${usbfs}"

cd "$(dirname "$0")" || exit
mkdir /p1
mkdir /p2

mount "${usbfs}"1 /p1
mount "${usbfs}"2 /p2

echo "patch zImage"
# patch zImage
./bzImage-to-vmlinux.sh /p2/zImage vmlinux
./kpatch vmlinux vmlinux-mod
./vmlinux-to-bzImage.sh vmlinux-mod zImage-mod
rm -f vmlinux vmlinux-mod

echo "patch ramdisk"
mkdir "ramdisk"
cd "ramdisk" || exit
unlzma </p2/rd.gz | cpio -idmuv
unlzma </p1/custom.gz | cpio -idmuv
# rd.gz + custom.gz
#find . 2>/dev/null | cpio -o -H newc -R root:root | xz -9 --format=lzma >../rd.gz
find . 2>/dev/null | cpio -o -H newc -R root:root >../rd.gz
cd ..
rm -rf ramdisk

umount /p1
umount /p2

echo "kexec dsm"
echo ${CMDLINE}
# start
kexec -l ./zImage-mod --initrd ./rd.gz --reuse-cmdline
kexec -f -e
