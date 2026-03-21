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
# disks.sh와 동일하게 SATA/SAS/HBA 모두 "ahci" 고정
# Synology DSM은 컨트롤러 종류에 무관하게 ahci 블록을 사용한다.
# =============================================================================
_build_driver() {
  echo "ahci"
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
# SATA 컨트롤러별 전체 가용 포트 감지 (showsata 테크닉)
#
# lspci -d ::106  → SATA 컨트롤러 PCI 주소 열거
# /sys/class/scsi_host  → 컨트롤러별 활성 host(포트) 목록
# ahci_port_cmd = "0"   → dummy 포트 (BIOS 비활성)
# dmesg SATA link down  → 링크 단절 포트
# lsscsi -b             → 실제 디스크 연결 여부
#
# 출력: PCIEPATH|PCIADDR|PORT|STATUS
#   STATUS: active | empty | dummy | down | loader
# =============================================================================
detect_sata_ports() {
  _get_bootdisk_pci

  for PCIADDR in $(lspci -d ::106 2>/dev/null | awk '{print $1}'); do
    local PCIEPATH
    PCIEPATH=$(_build_pcie_root "/devices/pci0000:00/${PCIADDR}/ata1")
    [ -z "${PCIEPATH}" ] && PCIEPATH="0000:${PCIADDR}"

    local PORTS
    PORTS=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCIADDR}" |             awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    [ -z "${PORTS}" ] && continue

    for P in ${PORTS}; do
      local STATUS
      # 1. link down 체크 (dmesg)
      if dmesg 2>/dev/null | grep -q "ata$((P+1)):.*SATA link down"; then
        STATUS="down"
      # 2. dummy 포트 (ahci_port_cmd = 0)
      elif [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd 2>/dev/null)" = "0" ]; then
        STATUS="dummy"
      # 3. 실제 디스크 연결 여부 (lsscsi -b 로 host 번호 확인)
      elif lsscsi -b 2>/dev/null | grep -v -- '-' | grep -q "^\[${P}:"; then
        # 부트 디스크 판별: BOOTDISK_PCIEPATH + BOOTDISK_ATA 비교 (udevadm 기반)
        local ATA_PORT
        ATA_PORT=$(( P ))   # scsi host 번호 기반 ata port (0-based)
        if [ -n "${BOOTDISK_PCIEPATH}" ] &&            [ "${BOOTDISK_PCIEPATH}" = "${PCIEPATH}" ] &&            { [ -z "${BOOTDISK_ATA}" ] || [ "${BOOTDISK_ATA}" = "${ATA_PORT}" ]; }; then
          STATUS="loader"
        else
          STATUS="active"
        fi
      else
        STATUS="empty"
      fi

      echo "${PCIEPATH}|${PCIADDR}|${P}|${STATUS}"
    done
  done
}

# =============================================================================
# SAS HBA 컨트롤러별 전체 가용 포트 감지
# lspci -d ::107 → SAS 컨트롤러
# 출력: PCIEPATH|PCIADDR|PORT|STATUS
# =============================================================================
detect_sas_ports() {
  _get_bootdisk_pci

  for PCIADDR in $(lspci -d ::107 2>/dev/null | awk '{print $1}'); do
    local PCIEPATH
    PCIEPATH=$(_build_pcie_root "/devices/pci0000:00/${PCIADDR}/host0/port-0:0")
    [ -z "${PCIEPATH}" ] && PCIEPATH="0000:${PCIADDR}"

    # SAS: port-H:N 패턴으로 포트 열거
    local HOSTS
    HOSTS=$(ls -l /sys/class/scsi_host 2>/dev/null | grep "${PCIADDR}" |             awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    [ -z "${HOSTS}" ] && continue

    for H in ${HOSTS}; do
      # port-H:N 디렉토리 순회
      local PORT_DIRS
      PORT_DIRS=$(ls /sys/class/scsi_host/host${H}/../ 2>/dev/null | grep -E '^port-' | sort -V)
      if [ -z "${PORT_DIRS}" ]; then
        # port 정보 없으면 host 단위로 처리
        local STATUS="empty"
        lsscsi -b 2>/dev/null | grep -v -- '-' | grep -q "^\[${H}:" && STATUS="active"
        echo "${PCIEPATH}|${PCIADDR}|${H}|${STATUS}"
        continue
      fi
      for PDIR in ${PORT_DIRS}; do
        local PIDX
        PIDX=$(echo "${PDIR}" | grep -oE ':[0-9]+$' | tr -d ':')
        local STATUS="empty"
        lsscsi -b 2>/dev/null | grep -v -- '-' | grep -q "^\[${H}:" && STATUS="active"
        echo "${PCIEPATH}|${PCIADDR}|${PIDX}|${STATUS}"
      done
    done
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
# 감지된 장치 목록 표시 (showsata 테크닉 적용)
# lspci 기반 전체 가용 포트 현황 + NVMe + USB
# =============================================================================
show_devices() {
  local MSG="" MAPPABLE=0

  # ── SATA ──────────────────────────────────────────────────────────────────
  local SATA_PORTS
  SATA_PORTS=$(detect_sata_ports)
  if [ -n "${SATA_PORTS}" ]; then
    MSG+="\n\Z4=== SATA ===\Zn\n"
    local PREV_PCI=""
    while IFS='|' read -r PCI PCIADDR PORT STATUS; do
      if [ "${PCI}" != "${PREV_PCI}" ]; then
        [ -n "${PREV_PCI}" ] && MSG+="\n"
        local CTRLNAME
        CTRLNAME=$(lspci -s "${PCIADDR}" 2>/dev/null | sed "s/ .*://")
        MSG+="\Zb${CTRLNAME}\Zn\nPorts: "
        PREV_PCI="${PCI}"
      fi
      case "${STATUS}" in
        active) MSG+="\Z2$(printf "%02d" "${PORT}")\Zn " ; MAPPABLE=$((MAPPABLE+1)) ;;
        loader) MSG+="\Z3$(printf "%02d" "${PORT}"):LOADER\Zn " ;;
        dummy)  MSG+="\Z1$(printf "%02d" "${PORT}"):DUMMY\Zn " ;;
        down)   MSG+="\Z1$(printf "%02d" "${PORT}"):DOWN\Zn " ;;
        empty)  MSG+="$(printf "%02d" "${PORT}") " ;;
      esac
    done <<< "${SATA_PORTS}"
    MSG+="\n"
  fi

  # ── SAS ───────────────────────────────────────────────────────────────────
  local SAS_PORTS
  SAS_PORTS=$(detect_sas_ports)
  if [ -n "${SAS_PORTS}" ]; then
    MSG+="\n\Z4=== SAS (HBA) ===\Zn\n"
    local PREV_PCI=""
    while IFS='|' read -r PCI PCIADDR PORT STATUS; do
      if [ "${PCI}" != "${PREV_PCI}" ]; then
        [ -n "${PREV_PCI}" ] && MSG+="\n"
        local CTRLNAME
        CTRLNAME=$(lspci -s "${PCIADDR}" 2>/dev/null | sed "s/ .*://")
        MSG+="\Zb${CTRLNAME}\Zn\nPorts: "
        PREV_PCI="${PCI}"
      fi
      case "${STATUS}" in
        active) MSG+="\Z2$(printf "%02d" "${PORT}")\Zn " ; MAPPABLE=$((MAPPABLE+1)) ;;
        *)      MSG+="$(printf "%02d" "${PORT}") " ;;
      esac
    done <<< "${SAS_PORTS}"
    MSG+="\n"
  fi

  # ── NVMe ──────────────────────────────────────────────────────────────────
  local NVME_LIST
  NVME_LIST=$(detect_nvme)
  if [ -n "${NVME_LIST}" ]; then
    MSG+="\n\Z4=== NVMe ===\Zn\n"
    while IFS='|' read -r PCI DEV; do
      MSG+="\Z2${DEV}\Zn  ${PCI}\n"
      MAPPABLE=$((MAPPABLE+1))
    done <<< "${NVME_LIST}"
  fi

  # ── USB ───────────────────────────────────────────────────────────────────
  local USB_LIST
  USB_LIST=$(_get_usb_ports)
  if [ -n "${USB_LIST}" ]; then
    MSG+="\n\Z4=== USB ===\Zn\n"
    while read -r PORT; do
      MSG+="port: \Z2${PORT}\Zn\n"
      MAPPABLE=$((MAPPABLE+1))
    done <<< "${USB_LIST}"
  fi

  [ -z "${SATA_PORTS}" ] && [ -z "${SAS_PORTS}" ] && [ -z "${NVME_LIST}" ] && [ -z "${USB_LIST}" ] &&     MSG="\Z1No storage devices detected.\Zn"

  MSG+="\n$(printf 'Mappable: %d  (boot loader excluded)' "${MAPPABLE}")"
  MSG+="\n\Z2Green\Zn=active  Gray=empty  \Z3Yellow\Zn=LOADER  \Z1Red\Zn=DUMMY/DOWN"

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
# _pick_slot TOTAL USED INFO
#
# TOTAL : 전체 슬롯 수 (1..TOTAL 범위)
# USED  : 이미 선택된 슬롯 번호 목록 (공백 구분 문자열)
# INFO  : dialog 상단에 표시할 디바이스 정보
#
# 사용 가능한 슬롯만 menu 항목으로 표시.
# 선택한 번호를 stdout으로 출력. Cancel 시 return 1.
# =============================================================================
_pick_slot() {
  local TOTAL="${1}"
  local USED="${2}"
  local INFO="${3}"

  local MENU_ARGS=()
  local N
  for N in $(seq 1 "${TOTAL}"); do
    echo "${USED}" | grep -qw "${N}" && continue
    MENU_ARGS+=("${N}" "slot@${N}")
  done

  if [ ${#MENU_ARGS[@]} -eq 0 ]; then
    dialog --backtitle "$(backtitle)" --title "Warning"       --msgbox $'All slots are already assigned.' 6 42
    return 1
  fi

  local PICKED
  PICKED=$(dialog --backtitle "$(backtitle)" \
    --title "Select Bay Slot" \
    --menu "${INFO}" 18 52 10 \
    "${MENU_ARGS[@]}" \
    3>&1 1>&2 2>&3) || return 1

  echo "${PICKED}"
}
# =============================================================================
# _pick_slot_type SLOT_NUM INFO
#
# 슬롯 타입 선택 radiolist:
#   internal  →  internal_slot@N   (기본값)
#   esata     →  esata_port@N
#
# stdout: "internal" 또는 "esata"
# Cancel 시 return 1
# =============================================================================
_pick_slot_type() {
  local SLOT_NUM="${1}"   # 현재 미사용, 호환성 유지
  local INFO="${2}"

  local PICKED
  PICKED=$(dialog --backtitle "$(backtitle)" \
    --title "Select Slot Type" \
    --radiolist "${INFO}" 13 55 2 \
    "internal" "internal_slot  (default)" "on" \
    "esata"    "esata_port     (eSATA)"   "off" \
    3>&1 1>&2 2>&3) || return 1

  # 아무것도 선택 안 한 경우 기본값
  [ -z "${PICKED}" ] && PICKED="internal"
  echo "${PICKED}"
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

  # 가용 슬롯 상한: lspci 기반 전체 포트 수 (빈 포트 포함, dummy/down 제외)
  local AVAIL_SATA AVAIL_SAS AVAIL_TOTAL
  AVAIL_SATA=$(detect_sata_ports | grep -cv "|dummy\||down" || true)
  AVAIL_SAS=$(detect_sas_ports   | grep -cv "|dummy\||down" || true)
  AVAIL_TOTAL=$((AVAIL_SATA + AVAIL_SAS))
  # 실제 디스크 수보다 작으면 디스크 수 사용
  [ "${AVAIL_TOTAL}" -lt "${DISK_COUNT}" ] && AVAIL_TOTAL="${DISK_COUNT}"

  dialog --backtitle "$(backtitle)" --title "SATA / SAS Mapping" \
    --msgbox $'Detected disks: '"${DISK_COUNT}"$'  /  Available ports: '"${AVAIL_TOTAL}"$'\n(boot disk excluded)\n\nStep 1: select slot type  Step 2: select bay number.' 9 62 || return

  # ==========================================================================
  # 1패스: 각 디스크의 슬롯 타입을 먼저 수집
  # → 타입별 실제 개수를 파악해 슬롯 번호 풀 상한 결정
  # ==========================================================================
  local TYPE_LIST=""   # "internal|sata|sda" 형식으로 누적
  while IFS='|' read -r PCIEPATH ATAPORT DRIVER DEVNAME FLAG PROTO; do
    local SLOT_INFO
    SLOT_INFO=$(printf '[%s] /dev/%s\npcie_root: %s\nata_port : %s' \
      "${PROTO}" "${DEVNAME}" "${PCIEPATH}" "${ATAPORT:-?}")
    local SLOT_TYPE
    SLOT_TYPE=$(_pick_slot_type "?" "${SLOT_INFO}") || {
      TYPE_LIST="${TYPE_LIST}skip|${PCIEPATH}|${ATAPORT}|${DEVNAME}|${PROTO}\n"
      continue
    }
    TYPE_LIST="${TYPE_LIST}${SLOT_TYPE}|${PCIEPATH}|${ATAPORT}|${DEVNAME}|${PROTO}\n"
  done <<< "${SATA_LIST}"

  # 타입별 개수 집계
  local COUNT_INTERNAL COUNT_ESATA
  COUNT_INTERNAL=$(printf "%b" "${TYPE_LIST}" | grep -c "^internal|" || true)
  COUNT_ESATA=$(printf "%b" "${TYPE_LIST}"    | grep -c "^esata|"    || true)

  # ==========================================================================
  # 2패스: 타입별 상한으로 슬롯 번호 선택
  # ==========================================================================
  local USED_INTERNAL="" USED_ESATA=""
  while IFS='|' read -r SLOT_TYPE PCIEPATH ATAPORT DEVNAME PROTO; do
    [ "${SLOT_TYPE}" = "skip" ] && continue

    local SLOT_INFO
    SLOT_INFO=$(printf '[%s] /dev/%s\npcie_root: %s\nata_port : %s' \
      "${PROTO}" "${DEVNAME}" "${PCIEPATH}" "${ATAPORT:-?}")

    local SLOT_NAME USED_REF SLOT_TOTAL
    if [ "${SLOT_TYPE}" = "esata" ]; then
      SLOT_NAME="esata_port"
      USED_REF="${USED_ESATA}"
      SLOT_TOTAL="${COUNT_ESATA}"
    else
      SLOT_NAME="internal_slot"
      USED_REF="${USED_INTERNAL}"
      SLOT_TOTAL="${COUNT_INTERNAL}"
    fi

    local PICKED
    PICKED=$(_pick_slot "${SLOT_TOTAL}" "${USED_REF}" "${SLOT_INFO}") || continue

    if [ "${SLOT_TYPE}" = "esata" ]; then
      USED_ESATA="${USED_ESATA} ${PICKED}"
    else
      USED_INTERNAL="${USED_INTERNAL} ${PICKED}"
    fi

    local NODE
    NODE="    ${SLOT_NAME}@${PICKED} {\n"
    NODE+="        reg = <$(printf '0x%02X' "${DTS_REG_COUNTER}") 0x00>;\n"
    NODE+="        protocol_type = \"sata\";\n"
    NODE+="        ahci {\n"
    NODE+="            pcie_root = \"${PCIEPATH}\";\n"
    [ -n "${ATAPORT}" ] && \
    NODE+="            ata_port = <$(printf '0x%02X' "${ATAPORT}")>;\n"
    [ "${SLOT_TYPE}" = "internal" ] && \
    NODE+="            internal_mode;\n"
    NODE+="        };\n"
    NODE+="    };"

    DTS_NODES+=("${NODE}")
    DTS_REG_COUNTER=$((DTS_REG_COUNTER+1))
  done <<< "$(printf "%b" "${TYPE_LIST}")"
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
    --msgbox $'Detected NVMe controllers: '"${DEV_COUNT}"$'\n(via udevadm DEVPATH, deduplicated per controller)\n\nSelect bay slot for each controller.' 9 60 || return

  local USED_SLOTS=""
  while IFS='|' read -r PCIEPATH DEVNAME; do
    local SLOT_INFO
    SLOT_INFO=$(printf '[nvme] /dev/%s\npcie_root: %s\nport_type: ssdcache' \
      "${DEVNAME}" "${PCIEPATH}")
    local PICKED
    PICKED=$(_pick_slot "${DEV_COUNT}" "${USED_SLOTS}" "${SLOT_INFO}") || continue

    USED_SLOTS="${USED_SLOTS} ${PICKED}"

    local NODE
    NODE="    nvme_slot@${DTS_IDX_NVME} {\n"
    NODE+="        reg = <$(printf '0x%02X' "${DTS_REG_COUNTER}") 0x00>;\n"
    NODE+="        pcie_root = \"${PCIEPATH}\";\n"
    NODE+="        port_type = \"ssdcache\";\n"
    NODE+="    };"

    DTS_NODES+=("${NODE}")
    DTS_REG_COUNTER=$((DTS_REG_COUNTER+1))
    DTS_IDX_NVME=$((DTS_IDX_NVME+1))
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
    --msgbox $'Detected USB ports: '"${PORT_COUNT}"$'\n(via /sys/bus/usb/devices hub traversal)\n\nSelect bay slot for each USB port.' 9 55 || return

  local USED_SLOTS=""
  while read -r USBPORT; do
    local SLOT_INFO
    SLOT_INFO=$(printf '[usb] port: %s' "${USBPORT}")
    local PICKED
    PICKED=$(_pick_slot "${PORT_COUNT}" "${USED_SLOTS}" "${SLOT_INFO}") || continue

    USED_SLOTS="${USED_SLOTS} ${PICKED}"

    local NODE
    NODE="    usb_slot@${DTS_IDX_USB} {\n"
    NODE+="        reg = <$(printf '0x%02X' "${DTS_REG_COUNTER}") 0x00>;\n"
    NODE+="        usb2 {\n"
    NODE+="            usb_port = \"${USBPORT}\";\n"
    NODE+="        };\n"
    NODE+="        usb3 {\n"
    NODE+="            usb_port = \"${USBPORT}\";\n"
    NODE+="        };\n"
    NODE+="    };"

    DTS_NODES+=("${NODE}")
    DTS_REG_COUNTER=$((DTS_REG_COUNTER+1))
    DTS_IDX_USB=$((DTS_IDX_USB+1))
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
  DTS_REG_COUNTER=1
  DTS_IDX_INTERNAL=1
  DTS_IDX_ESATA=1
  DTS_IDX_NVME=1
  DTS_IDX_USB=1
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
  DTS_REG_COUNTER=1
  DTS_IDX_INTERNAL=1
  DTS_IDX_ESATA=1
  DTS_IDX_NVME=1
  DTS_IDX_USB=1
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
