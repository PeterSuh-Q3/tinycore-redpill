#!/usr/bin/env bash

# This file can be sourced by menu_m.sh or run directly to burn a loader image.

burnloader_part3() {
  lsblk -nrpo PATH,PARTN "$1" 2>/dev/null | awk '$2 == 3 { print $1; exit }'
}

burnloader_has_alpine_partition() {
  lsblk -nrpo LABEL "$1" 2>/dev/null | awk '$1 == "alpine" { found=1 } END { exit !found }'
}

burnloader_is_tinycore_loader() {
  local part3 uuid
  part3=$(burnloader_part3 "$1")
  [ -n "${part3}" ] || return 1
  uuid=$(/sbin/blkid -s UUID -o value "${part3}" 2>/dev/null)
  [ "${uuid}" = "6234-C863" ] && ! burnloader_has_alpine_partition "$1"
}

burnloader_backup_user_config() {
  local part3="$1" mount_dir="$2" backup_file="$3"

  sudo mkdir -p "${mount_dir}" || return 1
  sudo mount "${part3}" "${mount_dir}" || return 1
  if [ ! -f "${mount_dir}/user_config.json" ]; then
    sudo umount "${mount_dir}"
    return 1
  fi
  sudo cp "${mount_dir}/user_config.json" "${backup_file}" &&
    sudo chown "$(id -u):$(id -g)" "${backup_file}"
  local result=$?
  sudo umount "${mount_dir}"
  return "${result}"
}

burnloader_restore_user_config() {
  local part3="$1" mount_dir="$2" backup_file="$3"

  sudo mkdir -p "${mount_dir}" || return 1
  sudo mount "${part3}" "${mount_dir}" || return 1
  sudo cp "${backup_file}" "${mount_dir}/user_config.json"
  local result=$?
  sudo sync
  sudo umount "${mount_dir}"
  return "${result}"
}

burnloader() {
  local listusb=() loaderdev imgversion imgprefix imgsuffix imgsize image_file image_gz
  local target_part3 mount_dir backup_file=""

  # Only an Alpine loader is excluded. A legacy TinyCore loader has the same
  # UUID on partition 3, but no partition labelled "alpine" and is a valid target.
  while read -r disk; do
    [ -n "${disk}" ] || continue
    if burnloader_has_alpine_partition "${disk}"; then
      continue
    fi
    listusb+=("${disk}")
  done < <(lsblk -dnpo PATH,ROTA,TRAN | awk '$1 ~ /^\/dev\/(sd|nvme|mmcblk)/ && (($2 == 1 && $3 == "usb") || ($2 == 0 && ($3 == "sata" || $3 == "nvme"))) { print $1 }')

  if [ "${#listusb[@]}" -eq 0 ]; then
    dialog --backtitle "$(backtitle)" --msgbox "No available USB, SSD, or NVMe target disk was found." 0 0
    return 1
  fi

  dialog --backtitle "$(backtitle)" --no-items --colors \
    --menu "Choose a USB Stick, SSD or NVMe for New Loader\n\Z1(Caution!) The selected disk will be overwritten.\Zn" 0 0 "$(dlgmenuheight "${#listusb[@]}")" "${listusb[@]}" \
    2>"${TMP_PATH}/resp" || return 0
  loaderdev=$(<"${TMP_PATH}/resp")
  [ -n "${loaderdev}" ] || return 0

  if ! dialog --backtitle "$(backtitle)" --yesno "All data on ${loaderdev} will be overwritten.\n\nFor a TinyCore loader (UUID 6234-C863 without an alpine partition), user_config.json on partition 3 will be backed up and restored." 0 0; then
    return 0
  fi

  if burnloader_is_tinycore_loader "${loaderdev}"; then
    target_part3=$(burnloader_part3 "${loaderdev}")
    mount_dir=$(mktemp -d "${TMP_PATH}/burnloader.XXXXXX") || return 1
    backup_file=$(mktemp "${TMP_PATH}/user_config.json.XXXXXX") || {
      rmdir "${mount_dir}"
      return 1
    }
    if ! burnloader_backup_user_config "${target_part3}" "${mount_dir}" "${backup_file}"; then
      rm -f "${backup_file}"
      rmdir "${mount_dir}"
      dialog --backtitle "$(backtitle)" --msgbox "Could not back up ${target_part3}/user_config.json. The disk was not overwritten." 0 0
      return 1
    fi
  fi

  imgversion="${VERSION}"
  imgprefix="alpine-redpill"
  dialog --title "IMG Size Selection" --menu "Select img file size to download:" 10 50 2 \
    "DEFAULT" "Standard 3GB image" \
    "5GB" "Large 5GB image" 2>"${TMP_PATH}/imgsize_selection.txt" || {
      rm -f "${backup_file}"
      [ -n "${mount_dir}" ] && rmdir "${mount_dir}"
      return 0
    }
  imgsize=$(<"${TMP_PATH}/imgsize_selection.txt")
  rm -f "${TMP_PATH}/imgsize_selection.txt"
  [ "${imgsize}" = "5GB" ] && imgsuffix="m-shell-5GB" || imgsuffix="m-shell"

  image_file="${TMP_PATH}/${imgprefix}.${imgversion}.${imgsuffix}.img"
  image_gz="${image_file}.gz"
  if [ ! -f "${image_file}" ]; then
    if ! curl -kL# "https://github.com/PeterSuh-Q3/tinycore-redpill/releases/download/${imgversion}/${imgprefix}.${imgversion}.${imgsuffix}.img.gz" -o "${image_gz}" ||
      ! gunzip -f "${image_gz}"; then
      rm -f "${backup_file}"
      [ -n "${mount_dir}" ] && rmdir "${mount_dir}"
      dialog --backtitle "$(backtitle)" --msgbox "Image download or decompression failed. The disk was not overwritten." 0 0
      return 1
    fi
  fi

  if ! sudo dd if="${image_file}" of="${loaderdev}" status=progress bs=4M conv=fsync; then
    dialog --backtitle "$(backtitle)" --msgbox "Image writing failed." 0 0
    return 1
  fi

  if [ -n "${backup_file}" ]; then
    if ! sudo partprobe "${loaderdev}" || ! sudo udevadm settle; then
      dialog --backtitle "$(backtitle)" --msgbox "The image was written, but its partition table could not be refreshed. Backup retained at ${backup_file}." 0 0
      return 1
    fi
    target_part3=$(burnloader_part3 "${loaderdev}")
    if [ -z "${target_part3}" ] || ! burnloader_restore_user_config "${target_part3}" "${mount_dir}" "${backup_file}"; then
      dialog --backtitle "$(backtitle)" --msgbox "The image was written, but user_config.json could not be restored. Backup retained at ${backup_file}." 0 0
      return 1
    fi
    rm -f "${backup_file}"
    rmdir "${mount_dir}"
  fi

  dialog --backtitle "$(backtitle)" --msgbox "Burning Image ${imgversion} completed." 0 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -u
  SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  if [ -f /home/tc/functions.sh ]; then
    . /home/tc/functions.sh
    FUNCTIONS_FILE=/home/tc/functions.sh
  else
    . "${SCRIPT_DIR}/functions.sh"
    FUNCTIONS_FILE="${SCRIPT_DIR}/functions.sh"
  fi
  TMP_PATH="${TMP_PATH:-/tmp}"
  VERSION="${VERSION:-v$(grep 'rploaderver=' "${FUNCTIONS_FILE}" | head -n 1 | cut -d'"' -f2)}"
  [ -n "${VERSION}" ] || VERSION="latest"
  backtitle() { echo "TCRP Loader Burner ${VERSION}"; }
  burnloader
fi
