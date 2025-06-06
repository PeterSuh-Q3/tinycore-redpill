#!/bin/bash

TMP_PATH=/tmp

# 신호 처리 함수 정의
function cleanup() {
    echo -e "\n\e[33mScript interrupted. Cleaning up...\e[0m"
    exit 0
}

# SIGINT, SIGTERM 신호를 trap으로 처리
trap cleanup SIGINT SIGTERM

loaderdisk=""
# Get the loader disk using the UUID "6234-C863"
loaderdisk=$(sudo /sbin/blkid | grep "6234-C863" | cut -d ':' -f1 | sed 's/p\?3//g' | awk -F/ '{print $NF}' | head -n 1)
mount /dev/${loaderdisk}1

function defaultchange() {

  [ "$(mount | grep /dev/${loaderdisk}1 | wc -l)" -eq 0 ] && mount /dev/${loaderdisk}1

  # Get the list of boot entries and write to /tmp/menub
  grep -i menuentry /mnt/${loaderdisk}1/boot/grub/grub.cfg | awk -F \' '{print $2}' | sed 's/.*/"&"/' > /tmp/menub
  
  # Create an array of menu options with (*) for the default entry and index
  index=97 # ASCII code for 'a'
  echo "" > /tmp/menub2
  # Initialize default item
  default_item="a"
  
  while true; do
    # Get the default entry index from grub.cfg
    default_index=$(grep -m 1 -i "set default=" /mnt/${loaderdisk}1/boot/grub/grub.cfg | cut -d '=' -f2- | tr -d '[:space:]' | tr -d '"')
    
    # Update menu options with (*) for the default entry and index
    echo "" > /tmp/menub2
    
    while IFS= read -r line; do
        if [ $((index-97)) -eq $default_index ]; then
            echo "$(printf \\$(printf '%03o' $index)) \"(*) ${line:1:-1}\"" >> /tmp/menub2
        else
            echo "$(printf \\$(printf '%03o' $index)) \"${line:1:-1}\"" >> /tmp/menub2
        fi
        ((index++))
    done < /tmp/menub
    index=97 # Reset index for next iteration

    # Display the menu and get the selection
    dialog --clear --default-item ${default_item} --backtitle "Change GRUB boot entry default value" --colors \
    --menu "Choose a boot entry" 0 0 0 --file /${TMP_PATH}/menub2 \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    
    case `<"${TMP_PATH}/resp"` in
      a) sudo sed -i "/set default=/cset default=\"0\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg; default_item="a" ;;
      b) sudo sed -i "/set default=/cset default=\"1\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg; default_item="b" ;;
      c) sudo sed -i "/set default=/cset default=\"2\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg; default_item="c" ;;
      d) sudo sed -i "/set default=/cset default=\"3\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg; default_item="d" ;;
      e) sudo sed -i "/set default=/cset default=\"4\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg; default_item="e" ;;
      f) sudo sed -i "/set default=/cset default=\"5\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg; default_item="f" ;;
      g) sudo sed -i "/set default=/cset default=\"6\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg; default_item="g" ;;
      *) return;;
    esac
    
  done
  echo "GRUB configuration file modified successfully."
}

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
    
    # 파티션 타입 조회
    partition_type=$(sudo blkid -o value -s TYPE "${path}" 2>/dev/null)
    # 파티션 타입이 없는 경우 "unknown"으로 표시
    [ -z "$partition_type" ] && partition_type="unknown"
    
    # 메뉴에 볼륨명, 사이즈, 파티션 타입을 모두 표시
    lvm_volumes+=("$path" "$vol_name ($size - $partition_type)")
  done < <(sudo lvs -o lv_dm_path,lv_size 2>/dev/null | grep volume)
  
  if [ ${#lvm_volumes[@]} -eq 0 ]; then 
    echo "No Available Syno lvm Volume, press any key continue..."
    read -n 1 -s answer < /dev/tty || return 0
    return 0   
  fi

  # Change GRUB boot entry default value 메뉴 옵션 추가
  lvm_volumes+=("boot" "Change GRUB boot entry default value")
  # Exit 메뉴 옵션 추가
  lvm_volumes+=("exit" "Exit Menu")
  
  while true; do
    dialog --backtitle "Mount Syno Disks" --colors \
      --menu "Choose a Volume to mount.\Zn" 0 0 0 "${lvm_volumes[@]}" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return

    # GRUB boot entry 기본 값 변경 메뉴
    if [ "${resp}" = "boot" ]; then
      defaultchange
      continue
    fi
    
    # Exit 메뉴 선택 확인
    if [ "${resp}" = "exit" ]; then
      echo -e "\e[32mExiting menu...\e[0m"
      return 0
    fi
    
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
    
    # 백그라운드 프로세스에서 안전한 키보드 입력 처리
    read -n 1 -s answer < /dev/tty || break  # 오류 시 루프 종료
  done  
}

sudo modprobe btrfs
mountvol

# trap 해제
trap - SIGINT SIGTERM
