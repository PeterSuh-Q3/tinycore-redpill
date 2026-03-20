#!/bin/bash
# =============================================================================
# dts_mapping_menu.sh  —  Tinycore Linux 전용
#
# PCI/ATA 정보를 udevadm으로 추출:
#   udevadm info --query=all --name=/dev/sdX
#
# DEVPATH 예시:
#   /devices/pci0000:00/0000:00:11.0/0000:02:03.0/ata1/host0/target0:0:0/...
#
# 추출 규칙:
#   pciepath  : DEVPATH에서 PCI 주소 2개 → "root,DD.F" 형식
#   ata_port  : DEVPATH의 ataN  → N-1 (0-based)
#   driver    : ID_PATH의 pci-ADDR 패턴으로 ahci 기본, 혹은 lspci 보조
#   SATA 판별 : DEVPATH에 "/ata" 포함 여부
#   NVMe 판별 : DEVPATH에 "/nvme" 포함 여부
# =============================================================================

OUTPUT_DTS="./model.dts"
DTS_NODES=()

COMPATIBLE="Synology"
DTSMODEL=""
POWER_LIMIT="0"

backtitle() { echo "Synology DTS Mapping Generator"; }

# =============================================================================
# udevadm 출력에서 특정 키 값 추출
# _udev_get KEY /dev/sdX
# =============================================================================
_udev_get() {
  local KEY="${1}" DEV="${2}"
  udevadm info --query=all --name="${DEV}" 2>/dev/null \
    | awk -F= "/^E: ${KEY}=/{print \$2}"
}

_udev_get_P() {
  local DEV="${1}"
  udevadm info --query=all --name="${DEV}" 2>/dev/null \
    | awk '/^P:/{print $2}'
}

# =============================================================================
# pcie_root 구성
#
# DEVPATH: /devices/pci0000:00/0000:00:11.0/0000:02:03.0/ata1/...
#           → PCI 컴포넌트 추출: ["0000:00:11.0", "0000:02:03.0"]
#           → root = "0000:00:11.0"
#           → endpoint = "0000:02:03.0" → compact "03.0"
#           → pcie_root = "0000:00:11.0,03.0"
#
# 단일 PCI 주소만 있는 경우: "0000:00:11.0" 그대로 사용
#
# 커널 버전별 prefix 보정:
#   < 5.x  →  "0000:00:" 를 "00:" 로 축약
#   >= 5.x →  그대로 "0000:00:" 유지
# =============================================================================
_fix_pcie_prefix() {
  local IN="${1}"
  local KVER
  KVER=$(uname -r 2>/dev/null | cut -d. -f1)
  if [ "${KVER:-5}" -lt 5 ]; then
    echo "${IN}" | sed 's/^0000:00:/00:/;s/,0000:00:/,00:/g'
  else
    echo "${IN}" | sed 's/^00:/0000:00:/g;s/,00:/,0000:00:/g'
  fi
}

_build_pcie_root() {
  local DEVPATH="${1}"

  # DEVPATH에서 XXXX:XX:XX.X 패턴 모두 추출 (순서 유지)
  local PCI_LIST
  PCI_LIST=$(echo "${DEVPATH}" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]')
  local COUNT
  COUNT=$(echo "${PCI_LIST}" | grep -c .)

  if [ "${COUNT}" -eq 0 ]; then
    return 1
  elif [ "${COUNT}" -eq 1 ]; then
    _fix_pcie_prefix "${PCI_LIST}"
  else
    # 마지막 두 PCI 주소를 사용
    local ROOT EP EP_SHORT
    ROOT=$(echo "${PCI_LIST}" | tail -n2 | head -n1)
    EP=$(echo "${PCI_LIST}"   | tail -n1)
    # endpoint를 "DD.F" 형식으로 축약 (domain+bus 제거)
    EP_SHORT=$(echo "${EP}" | sed 's/^[0-9a-f]*:[0-9a-f]*://')
    _fix_pcie_prefix "${ROOT},${EP_SHORT}"
  fi
}

# =============================================================================
# ata_port: DEVPATH의 "ataN" 에서 N-1 추출
# /devices/.../ata1/host0/... → ata1 → port 0
# =============================================================================
_build_ata_port() {
  local DEVPATH="${1}"
  local ATA_NUM
  ATA_NUM=$(echo "${DEVPATH}" | grep -oE '/ata[0-9]+/' | grep -oE '[0-9]+' | head -1)
  [ -z "${ATA_NUM}" ] && return 1
  echo $(( ATA_NUM - 1 ))
}


# =============================================================================
# driver 추출
# DEVPATH 패턴으로 컨트롤러 종류 판별:
#   /ata[0-9]  → SATA (ahci)
#   /host/port → SAS  (mpt3sas / megaraid_sas)
# lspci가 있으면 PCI class로 정확하게 확인
# =============================================================================
_build_driver() {
  local DEVPATH="${1}"

  local PCI_ADDR
  PCI_ADDR=$(echo "${DEVPATH}" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | tail -1)

  # lspci로 PCI class 확인 (가능한 경우)
  if [ -n "${PCI_ADDR}" ] && command -v lspci &>/dev/null; then
    local PCI_CLASS
    PCI_CLASS=$(lspci -s "${PCI_ADDR}" -n 2>/dev/null | awk '{print $2}')
    case "${PCI_CLASS}" in
      0106) echo "ahci"        ; return ;; # SATA controller
      0104) echo "ahci"        ; return ;; # RAID bus controller
      0107) echo "mpt3sas"     ; return ;; # SAS controller
      0100) echo "mpt3sas"     ; return ;; # SCSI storage controller
    esac
  fi

  # DEVPATH 패턴으로 폴백 판별
  if echo "${DEVPATH}" | grep -q '/ata[0-9]'; then
    echo "ahci"
  elif echo "${DEVPATH}" | grep -qE '/host[0-9]+/port-'; then
    echo "mpt3sas"
  else
    echo "ahci"
  fi
}

# =============================================================================
# Boot disk 감지
# BOOTDISK_PCIEPATH, BOOTDISK_ATA, BOOTDISK_DEV 를 전역으로 설정
# =============================================================================
_get_bootdisk_pci() {
  BOOTDISK_PCIEPATH=""
  BOOTDISK_ATA=""
  BOOTDISK_DEV=""

  local BOOT_PART
  BOOT_PART="$(blkid -U "6234-C863" 2>/dev/null)"
  [ -z "${BOOT_PART}" ] && BOOT_PART="$(blkid -U "8765-4321" 2>/dev/null)"
  [ -z "${BOOT_PART}" ] && return

  local BOOT_DEV
  BOOT_DEV=$(lsblk -no PKNAME "${BOOT_PART}" 2>/dev/null | head -1)
  [ -z "${BOOT_DEV}" ] && return

  local DEVPATH
  DEVPATH=$(_udev_get_P "/dev/${BOOT_DEV}")
  [ -z "${DEVPATH}" ] && return

  BOOTDISK_PCIEPATH=$(_build_pcie_root "${DEVPATH}")
  BOOTDISK_ATA=$(_build_ata_port "${DEVPATH}")
  BOOTDISK_DEV="${BOOT_DEV}"
}

# =============================================================================
# USB port enumeration (disks.sh getUsbPorts — 변경 없음)
# =============================================================================
_get_usb_ports() {
  for F in $(LC_ALL=C printf '%s\n' /sys/bus/usb/devices/usb* 2>/dev/null | sort -V); do
    [ ! -e "${F}" ] && continue
    [ ! "$(cat "${F}/bDeviceClass" 2>/dev/null)" = "09" ] && continue
    local SPD
    SPD=$(cat "${F}/speed" 2>/dev/null)
    [ "${SPD:-0}" -lt 480 ] && continue

    local RCHILDS RBUS HAVE_CHILD
    RCHILDS=$(cat "${F}/maxchild" 2>/dev/null)
    RBUS=$(cat "${F}/busnum"     2>/dev/null)
    HAVE_CHILD=0

    for C in $(seq 1 "${RCHILDS:-0}"); do
      local CHILD="${F}/${RBUS:-0}-${C}"
      [ ! -d "${CHILD}" ] && continue
      [ ! "$(cat "${CHILD}/bDeviceClass" 2>/dev/null)" = "09" ] && continue
      local CSPD
      CSPD=$(cat "${CHILD}/speed" 2>/dev/null)
      [ "${CSPD:-0}" -lt 480 ] && continue
      HAVE_CHILD=1
      local CHILDS
      CHILDS=$(cat "${CHILD}/maxchild" 2>/dev/null)
      for N in $(seq 1 "${CHILDS:-0}"); do printf '%s\n' "${RBUS:-0}-${C}.${N}"; done
    done
    [ "${HAVE_CHILD}" -eq 0 ] && \
      for N in $(seq 1 "${RCHILDS:-0}"); do printf '%s\n' "${RBUS:-0}-${N}"; done
  done
}

# =============================================================================
# SATA / SAS 감지
# /dev/sd* 순회 → udevadm → DEVPATH 패턴으로 SATA/SAS 판별
#
#   SATA: DEVPATH에 /ata[0-9] 포함  → protocol_type = sata, port = ata_port
#   SAS : DEVPATH에 /host/port-    포함  → protocol_type = sas,  port = port index
#
# MODE: "show" → 부트 디스크 포함, FLAG=loader 표기
#        "map" → 부트 디스크 제외 (기본값)
#
# 출력: PCIEPATH|PORT|DRIVER|DEVNAME|FLAG|PROTO
#   FLAG  : active | loader
#   PROTO : sata | sas
# =============================================================================
detect_sata() {
  local MODE="${1:-map}"
  _get_bootdisk_pci

  for DEV in $(ls /dev/sd? /dev/sd?? 2>/dev/null | sort -V); do
    local DEVNAME
    DEVNAME=$(basename "${DEV}")

    local UDEV_OUT
    UDEV_OUT=$(udevadm info --query=all --name="${DEV}" 2>/dev/null)
    [ -z "${UDEV_OUT}" ] && continue

    local DEVPATH
    DEVPATH=$(echo "${UDEV_OUT}" | awk '/^P:/{print $2}')
    [ -z "${DEVPATH}" ] && continue

    # SATA / SAS 판별
    local PROTO=""
    echo "${DEVPATH}" | grep -q '/ata[0-9]' && PROTO="sata"
    [ -z "${PROTO}" ] && echo "${DEVPATH}" | grep -qE '/host[0-9]+/port-' && PROTO="sas"
    [ -z "${PROTO}" ] && continue   # USB 등 해당 없는 장치 제외

    # 사이즈 0 제외 (빈 슬롯)
    local SIZE
    SIZE=$(cat "/sys/block/${DEVNAME}/size" 2>/dev/null)
    [ "${SIZE:-0}" -eq 0 ] && continue

    local PCIEPATH PORT DRIVER
    PCIEPATH=$(_build_pcie_root "${DEVPATH}")
    [ -z "${PCIEPATH}" ] && continue
    DRIVER=$(_build_driver "${DEVPATH}")

    if [ "${PROTO}" = "sata" ]; then
      PORT=$(_build_ata_port "${DEVPATH}")
    else
      # SAS: port-HOST:IDX の IDX を ata_port と同様に使用
      PORT=$(echo "${DEVPATH}" | grep -oE '/port-[0-9]+:[0-9]+/' | head -1 | grep -oE ':[0-9]+/' | tr -d ':/')
    fi

    # 부트 디스크 판별
    local IS_LOADER=0
    if [ -n "${BOOTDISK_PCIEPATH}" ] && [ "${BOOTDISK_PCIEPATH}" = "${PCIEPATH}" ]; then
      if [ -z "${BOOTDISK_ATA}" ] || [ "${BOOTDISK_ATA}" = "${PORT}" ]; then
        IS_LOADER=1
      fi
    fi

    if [ "${IS_LOADER}" -eq 1 ]; then
      [ "${MODE}" = "show" ] && echo "${PCIEPATH}|${PORT}|${DRIVER}|${DEVNAME}|loader|${PROTO}"
      continue
    fi

    echo "${PCIEPATH}|${PORT}|${DRIVER}|${DEVNAME}|active|${PROTO}"
  done
}

# =============================================================================
# NVMe 감지
# /dev/nvme*n* 순회 → udevadm → DEVPATH에서 PCI 주소 추출 (SATA와 동일 규칙)
#
# udevadm 출력 예:
#   P: /devices/pci0000:00/0000:00:15.0/0000:03:00.0/nvme/nvme0/nvme0n1
#
# _build_pcie_root(DEVPATH) 적용:
#   ROOT = 0000:00:15.0
#   EP   = 0000:03:00.0  →  compact "00.0"
#   결과 = "0000:00:15.0,00.0"   ← SATA와 동일한 "root,DD.F" 형식
#
# 출력: PCIEPATH|DEVNAME  (컨트롤러별 dedup)
# =============================================================================
detect_nvme() {
  _get_bootdisk_pci

  local SEEN_PCI=" "
  for DEV in $(ls /dev/nvme?n? 2>/dev/null | sort -V); do
    local DEVNAME
    DEVNAME=$(basename "${DEV}")

    local UDEV_OUT
    UDEV_OUT=$(udevadm info --query=all --name="${DEV}" 2>/dev/null)
    [ -z "${UDEV_OUT}" ] && continue

    # DEVPATH 추출 및 NVMe 장치 검증
    local DEVPATH
    DEVPATH=$(echo "${UDEV_OUT}" | awk '/^P:/{print $2}')
    echo "${DEVPATH}" | grep -q '/nvme' || continue

    # SATA와 동일하게 DEVPATH에서 "root,DD.F" 형식으로 pcie_root 추출
    local PCIEPATH
    PCIEPATH=$(_build_pcie_root "${DEVPATH}")
    [ -z "${PCIEPATH}" ] && continue

    # 부트 디스크 제외
    [ -n "${BOOTDISK_PCIEPATH}" ] && [ "${BOOTDISK_PCIEPATH}" = "${PCIEPATH}" ] && continue

    # 컨트롤러별 dedup
    echo "${SEEN_PCI}" | grep -qF "${PCIEPATH}" && continue
    SEEN_PCI="${SEEN_PCI}${PCIEPATH} "

    echo "${PCIEPATH}|${DEVNAME}"
  done
}

# =============================================================================
# 감지된 장치 목록 표시
# =============================================================================
show_devices() {
  local MSG="" COUNT=0

  local SATA_LIST LOADER_ATA LOADER_DEV
  SATA_LIST=$(detect_sata show)
  if [ -n "${SATA_LIST}" ]; then
    MSG+="\n\Z4=== SATA / SAS ===\Zn\n"
    local PREV_PCI=""
    while IFS='|' read -r PCI PORT DRV DEV FLAG PROTO; do
      if [ "${PCI}" != "${PREV_PCI}" ]; then
        [ -n "${PREV_PCI}" ] && MSG+="\n"
        MSG+="\Zb${DRV}\Zn [${PROTO}]  ${PCI}\nDisks: "
        PREV_PCI="${PCI}"
      fi
      local PORT_LABEL
      PORT_LABEL="ata${PORT}"
      if [ "${FLAG}" = "loader" ]; then
        MSG+="\Z3${DEV}(${PORT_LABEL}:LOADER)\Zn "
      else
        MSG+="\Z2${DEV}\Zn(${PORT_LABEL}) "
        COUNT=$((COUNT+1))
      fi
    done <<< "${SATA_LIST}"
    MSG+="\n"
  fi

  local NVME_LIST
  NVME_LIST=$(detect_nvme)
  if [ -n "${NVME_LIST}" ]; then
    MSG+="\n\Z4=== NVMe ===\Zn\n"
    while IFS='|' read -r PCI DEV; do
      MSG+="\Z2${DEV}\Zn  ${PCI}\n"
      COUNT=$((COUNT+1))
    done <<< "${NVME_LIST}"
  fi

  local USB_LIST
  USB_LIST=$(_get_usb_ports)
  if [ -n "${USB_LIST}" ]; then
    MSG+="\n\Z4=== USB ===\Zn\n"
    while read -r PORT; do
      MSG+="port: \Z2${PORT}\Zn\n"
      COUNT=$((COUNT+1))
    done <<< "${USB_LIST}"
  fi

  [ -z "${SATA_LIST}" ] && [ -z "${NVME_LIST}" ] && [ -z "${USB_LIST}" ] && \
    MSG="\Z1No storage devices detected.\Zn"

  MSG+="\n$(printf 'Total: %d mappable device(s) detected' "${COUNT}")"
  MSG+="\n\Z2Green\Zn = mappable   \Z3Yellow\Zn = boot loader disk (excluded)"

  dialog --backtitle "$(backtitle)" --colors \
    --title "Detected Storage Devices" \
    --msgbox "${MSG}" 0 0
}

# =============================================================================
# DTS Header
# =============================================================================
get_dts_header() {
  local FORM_OUT
  FORM_OUT=$(dialog --backtitle "$(backtitle)" --colors \
    --title "DTS Header" \
    --form "Enter global .dts header values:" 11 62 3 \
    "compatible:"   1 1 "${COMPATIBLE}"   1 16 35 0 \
    "model:"        2 1 "${DTSMODEL}"        2 16 50 0 \
    "power_limit:"  3 1 "${POWER_LIMIT}"  3 16 10 0 \
    3>&1 1>&2 2>&3) || return 1

  COMPATIBLE=$(printf '%s' "${FORM_OUT}" | sed -n '1p' | xargs)
  DTSMODEL=$(printf '%s'       "${FORM_OUT}" | sed -n '2p' | xargs)
  POWER_LIMIT=$(printf '%s' "${FORM_OUT}" | sed -n '3p' | xargs)
}

# =============================================================================
# SATA → internal_slot@N
# =============================================================================
map_sata_nodes() {
  local SATA_LIST
  SATA_LIST=$(detect_sata map)

  if [ -z "${SATA_LIST}" ]; then
    dialog --backtitle "$(backtitle)" --title "Info" \
      --msgbox $'No SATA/SAS disks detected.\n(Boot disk and empty slots are excluded)' 7 55
    return
  fi

  local DISK_COUNT
  DISK_COUNT=$(printf '%s\n' "${SATA_LIST}" | wc -l)
  dialog --backtitle "$(backtitle)" --title "SATA / SAS Mapping" \
    --msgbox $'Detected SATA/SAS disks: '"${DISK_COUNT}"$'\n(via udevadm DEVPATH, boot disk excluded)\n\nLeave pcie_root empty to skip a slot.' 9 60 || return

  local SLOT_IDX=1
  while IFS='|' read -r PCIEPATH ATAPORT DRIVER DEVNAME FLAG PROTO; do
    local PORT_LABEL
    PORT_LABEL="ata_port (0-based):"

    local FORM_OUT
    FORM_OUT=$(dialog --backtitle "$(backtitle)" --colors \
      --title "SATA/SAS -> internal_slot@${SLOT_IDX}  [/dev/${DEVNAME}]" \
      --form $'\Zb'"${DRIVER}"$'\Zn ['"${PROTO}"$']  pcie_root: '"${PCIEPATH}"$'\nata_port: '"${ATAPORT:-?}"$'  device: /dev/'"${DEVNAME}"$'\n\nSlot: '"${SLOT_IDX}"$'  (Leave pcie_root empty to skip)' \
      16 72 4 \
      "pcie_root:"    1 1 "${PCIEPATH}"   1 16 46 0 \
      "${PORT_LABEL}" 2 1 "${ATAPORT}"    2 16 5  0 \
      "driver node:"  3 1 "${DRIVER}"     3 16 20 0 \
      "internal_mode:" 4 1 "y"            4 16 3  0 \
      3>&1 1>&2 2>&3) || { SLOT_IDX=$((SLOT_IDX+1)); continue; }

    local PCI PORT DRV IMODE
    PCI=$(printf '%s'   "${FORM_OUT}" | sed -n '1p' | xargs)
    PORT=$(printf '%s'  "${FORM_OUT}" | sed -n '2p' | xargs)
    DRV=$(printf '%s'   "${FORM_OUT}" | sed -n '3p' | xargs)
    IMODE=$(printf '%s' "${FORM_OUT}" | sed -n '4p' | xargs | tr '[:upper:]' '[:lower:]')

    if [ -z "${PCI}" ]; then
      SLOT_IDX=$((SLOT_IDX+1)); continue
    fi

    local NODE
    NODE="    internal_slot@${SLOT_IDX} {\n"
    NODE+="        reg = <$(printf '0x%02X' "${SLOT_IDX}") 0x00>;\n"
    NODE+="        protocol_type = \"sata\";\n"
    NODE+="        ${DRV} {\n"
    NODE+="            pcie_root = \"${PCI}\";\n"
    [ -n "${PORT}" ] && \
    NODE+="            ata_port = <$(printf '0x%02X' "${PORT}")>;\n"
    [ "${IMODE}" = "y" ] && \
    NODE+="            internal_mode;\n"
    NODE+="        };\n"
    NODE+="    };"

    DTS_NODES+=("${NODE}")
    SLOT_IDX=$((SLOT_IDX+1))
  done <<< "${SATA_LIST}"
}

# =============================================================================
# NVMe → nvme_slot@N
# =============================================================================
map_nvme_nodes() {
  local NVME_LIST
  NVME_LIST=$(detect_nvme)

  if [ -z "${NVME_LIST}" ]; then
    dialog --backtitle "$(backtitle)" --title "Info" \
      --msgbox $'No NVMe devices detected.\n(Boot disk is automatically excluded)' 7 52
    return
  fi

  local DEV_COUNT
  DEV_COUNT=$(printf '%s\n' "${NVME_LIST}" | wc -l)
  dialog --backtitle "$(backtitle)" --title "NVMe Mapping" \
    --msgbox $'Detected NVMe controllers: '"${DEV_COUNT}"$'\n(via udevadm DEVPATH, deduplicated per controller)' 8 58 || return

  local SLOT_IDX=1
  while IFS='|' read -r PCIEPATH DEVNAME; do
    local FORM_OUT
    FORM_OUT=$(dialog --backtitle "$(backtitle)" --colors \
      --title "NVMe -> nvme_slot@${SLOT_IDX}  [/dev/${DEVNAME}]" \
      --form $'pcie_root: '"${PCIEPATH}"$'  device: /dev/'"${DEVNAME}"$'\nSlot: '"${SLOT_IDX}"$'  (Leave pcie_root empty to skip)' \
      12 70 2 \
      "pcie_root:"  1 1 "${PCIEPATH}"  1 14 46 0 \
      "port_type:"  2 1 "ssdcache"     2 14 20 0 \
      3>&1 1>&2 2>&3) || { SLOT_IDX=$((SLOT_IDX+1)); continue; }

    local PCI PTYPE
    PCI=$(printf '%s'   "${FORM_OUT}" | sed -n '1p' | xargs)
    PTYPE=$(printf '%s' "${FORM_OUT}" | sed -n '2p' | xargs)

    if [ -z "${PCI}" ]; then
      SLOT_IDX=$((SLOT_IDX+1)); continue
    fi

    local NODE
    NODE="    nvme_slot@${SLOT_IDX} {\n"
    NODE+="        reg = <$(printf '0x%02X' "${SLOT_IDX}") 0x00>;\n"
    NODE+="        pcie_root = \"${PCI}\";\n"
    [ -n "${PTYPE}" ] && \
    NODE+="        port_type = \"${PTYPE}\";\n"
    NODE+="    };"

    DTS_NODES+=("${NODE}")
    SLOT_IDX=$((SLOT_IDX+1))
  done <<< "${NVME_LIST}"
}

# =============================================================================
# USB → usb_slot@N
# =============================================================================
map_usb_nodes() {
  local USB_LIST
  USB_LIST=$(_get_usb_ports)

  if [ -z "${USB_LIST}" ]; then
    dialog --backtitle "$(backtitle)" --title "Info" \
      --msgbox $'No USB hub (speed >= 480 Mbps) detected.' 6 52
    return
  fi

  local PORT_COUNT
  PORT_COUNT=$(printf '%s\n' "${USB_LIST}" | wc -l)
  dialog --backtitle "$(backtitle)" --title "USB Mapping" \
    --msgbox $'Detected USB ports: '"${PORT_COUNT}"$'\n(via /sys/bus/usb/devices hub traversal)\n\nLeave usb2_port empty to skip a slot.' 9 52 || return

  local SLOT_IDX=1
  while read -r USBPORT; do
    local FORM_OUT
    FORM_OUT=$(dialog --backtitle "$(backtitle)" --colors \
      --title "USB -> usb_slot@${SLOT_IDX}  [${USBPORT}]" \
      --form $'Detected USB port: '"${USBPORT}"$'\nSlot: '"${SLOT_IDX}"$'  (Leave usb2_port empty to skip)' \
      11 60 2 \
      "usb2_port:" 1 1 "${USBPORT}"  1 14 12 0 \
      "usb3_port:" 2 1 "${USBPORT}"  2 14 12 0 \
      3>&1 1>&2 2>&3) || { SLOT_IDX=$((SLOT_IDX+1)); continue; }

    local USB2 USB3
    USB2=$(printf '%s' "${FORM_OUT}" | sed -n '1p' | xargs)
    USB3=$(printf '%s' "${FORM_OUT}" | sed -n '2p' | xargs)

    if [ -z "${USB2}" ]; then
      SLOT_IDX=$((SLOT_IDX+1)); continue
    fi

    local NODE
    NODE="    usb_slot@${SLOT_IDX} {\n"
    NODE+="        reg = <$(printf '0x%02X' "${SLOT_IDX}") 0x00>;\n"
    NODE+="        usb2 {\n"
    NODE+="            usb_port = \"${USB2}\";\n"
    NODE+="        };\n"
    NODE+="        usb3 {\n"
    NODE+="            usb_port = \"${USB3}\";\n"
    NODE+="        };\n"
    NODE+="    };"

    DTS_NODES+=("${NODE}")
    SLOT_IDX=$((SLOT_IDX+1))
  done <<< "${USB_LIST}"
}

# =============================================================================
# .dts 생성
# =============================================================================
write_dts() {
  local OUTFILE="${1:-${OUTPUT_DTS}}"
  {
    echo "// Generated by dts_mapping_menu.sh  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "/dts-v1/;"
    echo "/ {"
    echo "    #address-cells = <1>;"
    echo "    #size-cells = <1>;"
    echo "    compatible = \"${COMPATIBLE}\";"
    echo "    model = \"${DTSMODEL}\";"
    echo "    version = <0x01>;"
    echo "    power_limit = \"${POWER_LIMIT}\";"
    for NODE in "${DTS_NODES[@]}"; do
      echo ""
      echo -e "${NODE}"
    done
    echo "};"
  } > "${OUTFILE}"
}

preview_dts() {
  if [ ${#DTS_NODES[@]} -eq 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Warning" \
      --msgbox $'No nodes mapped yet.\nPlease run steps 3-5 first.' 7 45
    return
  fi
  local TMP
  TMP=$(mktemp /tmp/dts_preview_XXXXXX.dts)
  write_dts "${TMP}"
  dialog --backtitle "$(backtitle)" --colors \
    --title "Preview → ${OUTPUT_DTS}" \
    --textbox "${TMP}" 0 0
  rm -f "${TMP}"
}

reset_nodes() {
  dialog --backtitle "$(backtitle)" --title "Confirm Reset" \
    --yesno $'Clear all mapped nodes and reset reg counter?' 6 50 || return
  DTS_NODES=()
  dialog --backtitle "$(backtitle)" --title "Reset" \
    --msgbox $'All nodes cleared. reg counter reset to 0x01.' 6 52
}

show_result() {
  dialog --backtitle "$(backtitle)" --title "Done" \
    --msgbox "$(printf '.dts file generated\n\nFile: %s\ncompatible: %s\nmodel: %s\nTotal nodes: %d' \
      "${OUTPUT_DTS}" "${COMPATIBLE}" "${DTSMODEL}" "${#DTS_NODES[@]}")" 12 52
}

# =============================================================================
# Main menu
# next_item: 메뉴 실행 후 다음 번호가 자동 선택됨
# 순서: 1→2→3→4→5→6→7→8  (9/0은 유지)
# =============================================================================
_next_item() {
  case "${1}" in
    1) echo "2" ;;
    2) echo "3" ;;
    3) echo "4" ;;
    4) echo "5" ;;
    5) echo "6" ;;
    6) echo "7" ;;
    7) echo "7" ;;
    *) echo "${1}" ;;   # 8/9/0 은 그대로 유지
  esac
}

main_menu() {
  local DEFAULT_ITEM="1"
  while true; do
    local NODE_COUNT="${#DTS_NODES[@]}"
    local CHOICE
    CHOICE=$(dialog --backtitle "$(backtitle)" --colors \
      --title "Synology DTS Mapping Generator" \
      --default-item "${DEFAULT_ITEM}" \
      --menu "Mapped nodes: \Z2${NODE_COUNT}\Zn   Output: ${OUTPUT_DTS}" 20 65 10 \
      "1" "Show detected storage devices" \
      "2" "Set DTS header (compatible / model)" \
      "3" "Map SATA/SAS  ->  internal_slot@N" \
      "4" "Map NVMe  ->  nvme_slot@N" \
      "5" "Map USB   ->  usb_slot@N" \
      "6" "Preview .dts output" \
      "7" "Generate .dts file" \
      "8" "Reset all nodes" \
      "9" "Exit" \
      3>&1 1>&2 2>&3) || break

    case "${CHOICE}" in
      1) show_devices ;;
      2) get_dts_header ;;
      3) map_sata_nodes ;;
      4) map_nvme_nodes ;;
      5) map_usb_nodes ;;
      6) preview_dts ;;
      7)
        if [ ${#DTS_NODES[@]} -eq 0 ]; then
          dialog --backtitle "$(backtitle)" --title "Warning" \
            --msgbox $'No nodes mapped yet.\nPlease run steps 3-5 first.' 7 45
        else
          write_dts "${OUTPUT_DTS}"
          show_result
        fi
        ;;
      8) reset_nodes ;;
      9) break ;;
    esac

    DEFAULT_ITEM=$(_next_item "${CHOICE}")
  done
  clear
  echo "Done. Output: ${OUTPUT_DTS}"
}

# =============================================================================
# Initializer
#
# [직접 실행]
#   ./dts_mapping_menu.sh          -- dts_run() 자동 호출
#
# [source 인클루드 후 호출]
#   source ./dts_mapping_menu.sh   -- 함수 정의만 로드, 실행 없음
#   dts_init                       -- 변수 초기화
#   main_menu                      -- TUI 실행
#
# [한 번에]
#   source ./dts_mapping_menu.sh
#   dts_run                        -- init + main_menu
# =============================================================================
dts_init() {
  command -v dialog  &>/dev/null || { echo "Error: 'dialog' not installed.";  return 1; }
  command -v udevadm &>/dev/null || { echo "Error: 'udevadm' not installed."; return 1; }
  DTS_NODES=()
  OUTPUT_DTS="./model.dts"
  COMPATIBLE="Synology"
  DTSMODEL=""
  POWER_LIMIT="0"
}

dts_run() {
  dts_init || return 1
  main_menu
}

# 직접 실행 시에만 자동 시작 (source 시에는 실행되지 않음)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  dts_run
fi
