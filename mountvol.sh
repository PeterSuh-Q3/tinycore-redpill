#!/bin/bash

function mountvol () {

  # RAID 어레이가 이미 활성화되었는지 확인
  if ! grep -q "active" /proc/mdstat 2>/dev/null; then
    echo -e "\e[32mInitializing RAID/LVM...\e[0m"
    sudo mdadm --assemble --scan
    sudo pvscan # PV(Physical Volume) scan
    sudo vgscan # VG(Volume Group) scan
    sudo vgchange -ay # VG Avtivate (--activationmode degraded Option Retry)
  fi

  lvm_volumes=()
  while IFS= read -r line; do
    path=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    # 볼륨 이름만 추출하여 사용자 친화적 표시
    vol_name="${path##*/}"
    lvm_volumes+=("$path" "$vol_name ($size)")
  done < <(sudo lvs -o lv_dm_path,lv_size 2>/dev/null | grep volume)
  
  if [ ${#lvm_volumes[@]} -eq 0 ]; then 
    echo "No Available Syno lvm Volume, press any key continue..."
    read -n 1 -s answer                       
    return 0   
  fi
  
  dialog --backtitle "`backtitle`" --colors \
    --menu "Choose a Volume to mount.\Zn" 0 0 0 "${lvm_volumes[@]}" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  
  # 볼륨 이름 추출 (예: /dev/mapper/vg1000-lv → lv)
  vol_name="${resp##*-}"  # LV 이름만 추출
  mount_point="/mnt/${vol_name}"  # 마운트 경로 생성
  
  T=$(sudo blkid -o value -s TYPE "${resp}" 2>/dev/null)
  
  sudo mkdir -p "${mount_point}"
  if [ "$T" = "btrfs" ]; then
    sudo mount -t btrfs "${resp}" "${mount_point}" -o ro,degraded
  elif [ "$T" = "ext4" ]; then  
    sudo mount -t ext4 "${resp}" "${mount_point}"
  fi
  
  if mountpoint -q "${mount_point}"; then
    echo -e "\e[32mMount success: ${resp} -> ${mount_point}\e[0m, press any key to continue..."
  else
    echo "Mount failed! Check filesystem type."
  fi
  read -n 1 -s answer
  return 0
}

sudo modprobe btrfs
mountvol
