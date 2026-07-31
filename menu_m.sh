#!/usr/bin/env bash

set -u # Unbound variable errors are not allowed

##### INCLUDES #####################################################################################################
. /home/tc/functions.sh
. /home/tc/i18n.h
. /home/tc/dts_mapping.sh
#####################################################################################################
export PATH='/home/tc/.local/bin:/usr/local/sbin:/usr/local/bin:/apps/bin:/usr/sbin:/usr/bin:/sbin:/bin'

# Alpine 이식: /etc/init.d/tc-functions는 TinyCore 전용 복구 스크립트라 Alpine에 존재하지
#않는 게 정상이며, tinycorelinux.net에서 받아올 필요도 없음. is_alpine()이면 이 체크를 skip.
if ! is_alpine && [ ! -f "/etc/init.d/tc-functions" ]; then
  echo "/etc/init.d/tc-functions is missing recover file..."
  sudo /usr/local/bin/curl -kL https://raw.githubusercontent.com/tinycorelinux/Core-scripts/refs/heads/master/etc/init.d/tc-functions -o /etc/init.d/tc-functions
  source /etc/init.d/tc-functions
  sudo filetool.sh -b
  exit
fi

kver3explatforms="bromolow braswell cedarview"
kver5explatforms="epyc7002(DT) epyc7003ntb(DT) epyc7003(DT) icelaked(DT) v1000nk(DT) r1000nk(DT) geminilakenk(DT)"

# ── BMI2 CPU capability detection ─────────────────────────────────────────────
# all-modules 릴리즈에는 BMI2(mulx 등) 명령이 포함된 모듈이 있으므로
# BMI2 미지원 CPU(Ivy Bridge 이하 등)에서는 해당 모듈 선택을 제한한다.
HAS_BMI2="n"
if grep -qw "bmi2" /proc/cpuinfo 2>/dev/null; then
    HAS_BMI2="y"
fi

# 2026-07-25: BMI2 관련 두 임계값을 명시적 상수로 분리.
#   - BMI2_REQUIRED_FROM_DSM: all-modules가 DSM 몇 버전부터 BMI2(mulx 등)를
#     쓰기 시작하는지 (7.3.0). 이 버전부터는 BMI2 없는 CPU에서 all-modules
#     부팅이 안 됨.
#   - CUSTOM_MODULES_MAX_DSM: BMI2 없는 CPU용 대안인 custom-modules가 실제로
#     빌드되어 있는 최신 DSM 버전 (7.3.2). 이걸 넘는 버전(7.4.0+)은 BMI2 없는
#     CPU에서 쓸 수 있는 모듈팩이 전혀 없음(Synology가 DSM 7.4 GPL 소스를
#     아직 미공개).
# 즉 BMI2 없는 CPU에서 실제 사용 가능한 범위는 "< 7.3.0"(all-modules) +
# "7.3.0~7.3.2"(custom-modules) 이고, "7.4.0 이상"만 완전히 막힌다. 이전에는
# selectversion()만 이 경계를 하드코딩된 매직넘버(7004)로 반영했고,
# checkAndResetModuleName()/selectldrmode()는 "DSM>=7.3.0이면 custom-modules
# 가능"으로만 판단해 7.4.0+에서도 custom-modules를 있는 것처럼 다뤄 일관성이
# 없었다. 세 곳 모두 아래 공용 상수/헬퍼로 통일하고, 모델 선택 시점에도
# enforceBmi2VersionCap()으로 즉시 반영한다.
BMI2_REQUIRED_FROM_DSM_ZPAD="007003000"   # 7.3.0
CUSTOM_MODULES_MAX_DSM_ZPAD="007003002"   # 7.3.2

# "7.3.2-86009" / "7.3-69057" 같은 문자열을 major/minor/patch 9자리
# zero-pad 정수로 변환 (patch 필드가 없으면 0으로 처리)
function zpadDsmVersion() {
  local raw="${1:-}" maj min pat
  maj=$(echo "${raw}" | cut -d'.' -f1)
  min=$(echo "${raw}" | cut -d'.' -f2 | cut -d'-' -f1)
  pat=$(echo "${raw}" | cut -d'.' -f3 | cut -d'-' -f1)
  printf "%03d%03d%03d" "${maj:-0}" "${min:-0}" "${pat:-0}"
}

# 모델 선택 시점에 즉시 적용: 현재 플랫폼이 kver5platforms 이고 BMI2 미지원인데
# 저장된 general.version(DSM)이 CUSTOM_MODULES_MAX_DSM_ZPAD(7.3.2)를 초과하면
# (즉 7.4.0+ 이면, custom-modules 조차 없어 부팅 가능한 모듈팩이 전혀 없음)
# 해당 모델의 pats.json 지원 리비전 중 7.3.2 이하의 최신 리비전으로 즉시 되돌린다.
function enforceBmi2VersionCap() {
  local plat
  plat="$(resolveLiveKver)"; plat="${plat##*|}"
  [ "${HAS_BMI2}" = "n" ] || return 0
  echo "${kver5platforms}" | grep -qw "${plat}" || return 0

  local curBuild curZpadDsm
  curBuild=$(readConfigKey "general" "version")
  curZpadDsm=$(zpadDsmVersion "${curBuild}")
  [ "${curZpadDsm}" -gt "${CUSTOM_MODULES_MAX_DSM_ZPAD}" ] || return 0

  # pats.json 에서 이 모델의 리비전 중 7.3.2 이하 최신 버전을 조회
  local safeVersion
  safeVersion=$(jq -r ".\"${MODEL}\" | keys | map(split(\"-\") | .[0:2] | join(\"-\")) | reverse | .[]" "${configfile}" 2>/dev/null | while read -r v; do
    if [ "$(zpadDsmVersion "${v}")" -le "${CUSTOM_MODULES_MAX_DSM_ZPAD}" ]; then
      echo "${v}"
      break
    fi
  done)
  [ -n "${safeVersion}" ] || return 0

  echo "⚠ Stored DSM ${curBuild} needs BMI2 (not present on this CPU) and exceeds"
  echo "  custom-modules cap (7.3.2). Resetting version to ${safeVersion}..."
  writeConfigKey "general" "version" "${safeVersion}"
}
# ───────────────────────────────────────────────────────────────────────────────
# pats.json is kept at a persistent location (/home/tc) so a redpill-load
# clean/re-clone after a failed build does not wipe the DSM version source.
configfile="/home/tc/pats.json"
configfile_loader="/home/tc/redpill-load/config/pats.json"

# Function to be called on Ctrl+C or ESC
function ctrl_c() {
  echo ", Ctrl+C key pressed. Press Enter to return menu..."
}

function readanswer() {
    while true; do
        read answ
        case $answ in
            [Yy]* ) answer="$answ"; break;;
            [Nn]* ) answer="$answ"; break;;
            * ) echo "Please answer yY/nN.";;
        esac
    done
}

function read_with_timeout() {
    local prompt="$1"
    local varname="$2"
    local default="$3"
    
    eval "$varname="
    
    echo -n "$prompt"
    
    # 한 문자만 읽고 바로 처리 (y/Y/n/N)
    if read -t 7 -n 1 -r "$varname"; then
        local input
        input=$(eval echo \$$varname)
        case "$input" in
            [yY]) eval "$varname=Y"; echo "Y"; return 0 ;;
            [nN]) eval "$varname=N"; echo "N"; return 0 ;;
            *) echo ""; return 1 ;;  # 잘못된 입력
        esac
    else
        # 타임아웃
        eval "$varname=$default"
        echo " $default (timeout)"
        return 1
    fi
}

function chk_filetime_n_backup() {
  file1="$userconfigfile"
  file2="/mnt/${tcrppart}/user_config.json"

  # md5sum 계산
  md5_1=$(md5sum "$file1" | awk '{print $1}')
  md5_2=$(md5sum "$file2" | awk '{print $1}')

  echo "File 1 ($file1): $md5_1"
  echo "File 2 ($file2): $md5_2"  

  # 비교
  if [ "$md5_1" != "$md5_2" ]; then
    echo "$file1 and $file2 are differnt!, need to backup!"
    # Added a feature to immediately reflect changes to user_config.json (no need for loader build) 2025.03.29
    sudo cp $userconfigfile /mnt/${tcrppart}/user_config.json
    backuploader
  fi  
}
 
function restart() {
    chk_filetime_n_backup
    echo "A reboot is required. Press any key to reboot..."
    read -n 1 -s  # Wait for a key press
    clear
    writebackcache
    sudo reboot
}

function byebye() {
    chk_filetime_n_backup
    writebackcache 
    sudo poweroff
}

function writebackcache() {
    while true; do
        clear
        grep -E 'Dirty|Writeback:' /proc/meminfo
        echo "Writing data that has not yet been written to disk (data waiting in the cache)."
        
        dirty_kb=$(grep '^Dirty:' /proc/meminfo | awk '{print $2}')
        
        if [ "$dirty_kb" -le 5000 ]; then
            echo "Dirty cache is below 5000 kB: $dirty_kb kB, exiting loop."
            break
        fi
        
        sleep 1
    done
}

function installtcz() {
  tczpack="${1}"
  cd /mnt/${tcrppart}/cde/optional
  sudo curl -kLO# http://tinycorelinux.net/12.x/x86_64/tcz/${tczpack}
  sudo md5sum ${tczpack} > ${tczpack}.md5.txt
  echo "${tczpack}" >> /mnt/${tcrppart}/cde/onboot.lst
  cd ~
}

function restoresession() {
    lastsessiondir="/mnt/${tcrppart}/lastsession"
    if [ -d $lastsessiondir ]; then
        echo "Found last user session, restoring session..."
    if [ -d $lastsessiondir ] && [ -f ${lastsessiondir}/user_config.json ]; then
        echo "Copying last stored user_config.json"
        cp -f ${lastsessiondir}/user_config.json /home/tc
    fi
    else
        echo "There is no last session stored!!!"
    fi
}

if [ -f /home/tc/my.sh ]; then
  rm /home/tc/my.sh
fi
if [ -f /home/tc/myv.sh ]; then
  rm /home/tc/myv.sh
fi

# Prevent SataPortMap/DiskIdxMap initialization - loaded from user_config.json

# Trap Ctrl+C (SIGINT) signals and call ctrl_c function
trap ctrl_c INT

VERSION=v`cat /home/tc/functions.sh | grep rploaderver= | cut -d\" -f2`

getloaderdisk
if [ -z "${loaderdisk}" ]; then
    echo "Not Supported Loader BUS Type, program Exit!!!"
    echo "press any key to continue..."
    read answer    
    exit 99
fi
getBus "${loaderdisk}"

tcrppart="${loaderdisk}3"

if [[ "$(uname -a | grep -c tcrpfriend)" -gt 0 ]]; then
    FRKRNL="YES"
else
    FRKRNL="NO"
fi

# update tinycore 14.0 2023.12.18
# Alpine 이식: update_tinycore/update_motd 는 TC 14.0 자체 부트이미지(corepure64.gz/
# vmlinuz64)와 TC 전용 motd 배너를 대상으로 하는 순수 TinyCore 기능이라 skip.
if ! is_alpine && [ "$FRKRNL" = "NO" ]; then
    update_tinycore
    update_motd
fi

# restore user_config.json file from /mnt/sd#/lastsession directory 2023.10.21
#restoresession

TMP_PATH=/tmp
LOG_FILE="${TMP_PATH}/log.txt"

if [ ! -f "${userconfigfile}" ]; then
    echo "Not Found User config file, program Exit!!!"
    echo "press any key to continue..."
    read answer    
    exit 99
fi

MODEL=$(readConfigKey "general" "model")
BUILD=$(readConfigKey "general" "version")
SN=$(readConfigKey "extra_cmdline" "sn")
MACADDR1=$(readConfigKey "extra_cmdline" "mac1")
MACADDR2=$(readConfigKey "extra_cmdline" "mac2")
MACADDR3=$(readConfigKey "extra_cmdline" "mac3")
MACADDR4=$(readConfigKey "extra_cmdline" "mac4")
MACADDR5=$(readConfigKey "extra_cmdline" "mac5")
MACADDR6=$(readConfigKey "extra_cmdline" "mac6")
MACADDR7=$(readConfigKey "extra_cmdline" "mac7")
MACADDR8=$(readConfigKey "extra_cmdline" "mac8")
NETNUM="1"

LAYOUT=$(readConfigKey "general" "layout")
KEYMAP=$(readConfigKey "general" "keymap")

I915MODE=$(readConfigKey "general" "i915mode")
BFBAY=$(readConfigKey "general" "bay")
DMPM=$(readConfigKey "general" "devmod")
NVMES=$(readConfigKey "general" "nvmesystem")
VMTOOLS=$(readConfigKey "general" "vmtools")
LDRMODE=$(readConfigKey "general" "loadermode")
MDLNAME=$(readConfigKey "general" "modulename")
MLMETHOD=$(readConfigKey "general" "mlmethod")
ucode=$(readConfigKey "general" "ucode")
TCB=$(readConfigKey "general" "tcbautoupd")
FKC=$(readConfigKey "general" "friendautoupd")

if [ -z "${KEYMAP}" ]; then
    LAYOUT="qwerty"
    KEYMAP="us"
    writeConfigKey "general" "layout" "${LAYOUT}"
    writeConfigKey "general" "keymap" "${KEYMAP}"
fi

if [ -z "${I915MODE}" ]; then
    I915MODE="1"
    writeConfigKey "general" "i915mode" "${I915MODE}"
fi

if [ -z "${DMPM}" ]; then
    DMPM="DDSML"
    writeConfigKey "general" "devmod" "${DMPM}"          
fi

if [ "${BUS}" = "mmc"  ]; then
    DMPM="EUDEV"
    writeConfigKey "general" "devmod" "${DMPM}"          
fi

if [ -z "${NVMES}" ]; then
    NVMES="false"
    writeConfigKey "general" "nvmesystem" "${NVMES}"
fi

if [ -z "${VMTOOLS}" ]; then
    VMTOOLS="false"
    writeConfigKey "general" "vmtools" "${VMTOOLS}"
fi

# nvidiaMenu(최상위 g) 의 세 항목을 다른 설정들과 동일한 방식으로
# 전역변수화 + general.* 영구저장한다. 이전 버전은 .nvidia_driver /
# .nvidia_ffmpeg 를 writeConfigKey 컨벤션과 다르게 최상위(top-level)에
# 저장했다 - general 쪽이 비어 있고 구 최상위 키가 남아있으면 옮기고
# 구 키는 지운다(실기 box 152 에서 nvidia_driver=580.173.02,
# nvidia_ffmpeg=true 로 이렇게 저장돼 있던 것 확인).
NVIDIA_DRIVER=$(readConfigKey "general" "nvidia_driver")
if [ -z "${NVIDIA_DRIVER}" ]; then
    _legacy_nvd=$(jq -r '.nvidia_driver // empty' "${userconfigfile}" 2>/dev/null)
    if [ -n "${_legacy_nvd}" ]; then
        NVIDIA_DRIVER="${_legacy_nvd}"
        writeConfigKey "general" "nvidia_driver" "${NVIDIA_DRIVER}"
        jsonfile=$(jq 'del(.nvidia_driver)' "${userconfigfile}") && echo -E "${jsonfile}" | jq . > "${userconfigfile}"
    fi
fi

NVIDIA_FFMPEG=$(readConfigKey "general" "nvidia_ffmpeg")
if [ -z "${NVIDIA_FFMPEG}" ]; then
    _legacy_nvf=$(jq -r '.nvidia_ffmpeg // empty' "${userconfigfile}" 2>/dev/null)
    if [ -n "${_legacy_nvf}" ]; then
        NVIDIA_FFMPEG="${_legacy_nvf}"
    else
        NVIDIA_FFMPEG="false"
    fi
    writeConfigKey "general" "nvidia_ffmpeg" "${NVIDIA_FFMPEG}"
    jsonfile=$(jq 'del(.nvidia_ffmpeg)' "${userconfigfile}") && echo -E "${jsonfile}" | jq . > "${userconfigfile}"
fi

# NVIDIA 애드온의 enable/disable 은 다른 general.* 값들과 성격이 다르다.
# bay/VMTOOLS/NVMES 는 user_config.json 이 유일한 소비처라 저장값이 곧
# 진실이지만, 이 항목의 실제 소비처는 bundled-exts.json 이다 - 빌드(my())
# 가 "현재 bundled-exts 에는 있고 GitHub 기본값에는 없는 키" 를 골라
# merged-addons.json 으로 캡처한 뒤 재적용하기 때문에, 그 파일에 키가
# 없으면 general.nvidia_enabled 가 무엇이든 빌드에서 그냥 누락된다.
#
# 그래서 bundled-exts.json 을 진실의 원천으로 삼고 general.nvidia_enabled
# 는 표시용 거울값으로 매 실행마다 재동기화한다. 한때 이 재계산을
# "다른 항목과 컨벤션이 다르다" 는 이유로 제거했는데, 그게 사실은 두
# 파일의 드리프트를 자동 치유하던 안전장치였다 - 제거하자 box 152 에서
# general.nvidia_enabled=true 인데 bundled-exts 에는 키가 없어
# merged-addons.json 이 {} 가 되고 빌드에서 애드온이 통째로 빠지는 상태가
# 고착됐다.
NVIDIA_ENABLED_SAVED=$(readConfigKey "general" "nvidia_enabled")
NVIDIA_ENABLED=$(jq -r 'if has("nvidiadriver") then "true" else "false" end' ~/redpill-load/bundled-exts.json 2>/dev/null)
[ -z "${NVIDIA_ENABLED}" ] && NVIDIA_ENABLED="false"
# 자동 복구: 사용자가 메뉴에서 ENABLED 로 켜둔 기록(general.nvidia_enabled)
# 이 있는데 bundled-exts.json 에 키가 없다면 위와 같은 드리프트 상태다.
# 사용자의 의도는 "켜둔 것" 이므로 파일 쪽을 사용자 의도에 맞춘다.
if [ "${NVIDIA_ENABLED_SAVED}" = "true" ] && [ "${NVIDIA_ENABLED}" != "true" ]; then
    add-addons "nvidiadriver"
    NVIDIA_ENABLED="true"
fi
writeConfigKey "general" "nvidia_enabled" "${NVIDIA_ENABLED}"
unset NVIDIA_ENABLED_SAVED

[ "${NVMES}" = "false" ] && BLOCK_DDSML="N" || BLOCK_DDSML="Y"

# FIX FRIEND, No Jot Mode
LDRMODE="FRIEND"
writeConfigKey "general" "loadermode" "${LDRMODE}"   

if [ -z "${MDLNAME}" ]; then
    MDLNAME="all-modules"
    writeConfigKey "general" "modulename" "${MDLNAME}"          
fi

if [ -z "${MLMETHOD}" ]; then
    MLMETHOD="IML"
    writeConfigKey "general" "mlmethod" "${MLMETHOD}"          
fi

if [ -z "${TCB}" ]; then
    TCB="true"
    writeConfigKey "general" "tcbautoupd" "${TCB}"          
fi

if [ -z "${FKC}" ]; then
    FKC="true"
    writeConfigKey "general" "friendautoupd" "${FKC}"
fi

PREVENT_INIT=$(readConfigKey "general" "prevent_init")
if [ -z "${PREVENT_INIT}" ]; then
    PREVENT_INIT="OFF"
    writeConfigKey "general" "prevent_init" "${PREVENT_INIT}"
fi

lcode=$(echo $ucode | cut -c 4-)
BLOCK_EUDEV="N"
BLOCK_DDSML="N"

# for test gettext
#path_i="/usr/local/share/locale/ko_KR/LC_MESSAGES"
#sudo mkdir -p "${path_i}"
#cat "tcrp.po"
#msgfmt "tcrp.po" -o "tcrp.mo"
#sudo cp -vf "tcrp.mo" "${path_i}/tcrp.mo"


###############################################################################
# Mounts backtitle dynamically
function backtitle() {
  BACKTITLE="TCRP-mshell ${VERSION}"
  BACKTITLE+=" ${DMPM}"
  BACKTITLE+=" ${ucode}"
  BACKTITLE+=" ${LDRMODE}"
  BACKTITLE+=" ${MDLNAME}"
  BACKTITLE+=" ${MLMETHOD}"
  
  [ -n "${MODEL}" ] && BACKTITLE+=" ${MODEL}" || BACKTITLE+=" (no model)"
  [ -n "${BUILD}" ] && BACKTITLE+=" ${BUILD}" || BACKTITLE+=" (no build)"
  [ -n "${SN}" ] && BACKTITLE+=" ${SN}" || BACKTITLE+=" (no SN)"
  [ -n "${IP}" ] && BACKTITLE+=" ${IP}" || BACKTITLE+=" (no IP)"

  for i in 1 2 3 4 5 6 7 8; do
    varname="MACADDR${i}"
    [[ -n "${!varname}" && "${!varname}" != "null" ]] && BACKTITLE+=" ${!varname}"
  done
  
  # 키맵(qwerty/us) 대신 저장소 패널 크기를 표시한다. bay 는 이미 전역
  # 변수로 관리되고 있다 - 모델 선택 시 모델별 기본값이 설정되고
  # (modelMenu 의 case 문), storagepanel() 에서 사용자가 바꾸면
  # user_config.json 의 general.bay 에 저장되며, 메인 루프가 매 반복
  # readConfigKey 로 다시 읽어들인다(box 152 실기 확인: "bay": "RACK_12_Bay").
  [ -n "${bay}" ] && BACKTITLE+=" (${bay})" || BACKTITLE+=" (no panel size)"
  echo ${BACKTITLE}
}

###############################################################################
# identify usb's pid vid
function usbidentify() {

    checkmachine

    if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "VMware" ]; then
        echo "Running on VMware, no need to set USB VID and PID, you should SATA shim instead"
    elif [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
        echo "Running on Proxmox/QEMU(KVM), If you are using USB shim, VID 0x46f4 and PID 0x0001 should work for you"
        vendorid="0x46f4"
        productid="0x0001"
        echo "Vendor ID : $vendorid Product ID : $productid"
        json="$(jq --arg var "$productid" '.extra_cmdline.pid = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
        json="$(jq --arg var "$vendorid" '.extra_cmdline.vid = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
    else            

        lsusb -v 2>&1 | grep -B 33 -A 1 SCSI >/tmp/lsusb.out

        usblist=$(grep -B 33 -A 1 SCSI /tmp/lsusb.out)
        vendorid=$(grep -B 33 -A 1 SCSI /tmp/lsusb.out | grep -i idVendor | awk '{print $2}')
        productid=$(grep -B 33 -A 1 SCSI /tmp/lsusb.out | grep -i idProduct | awk '{print $2}')

        if [ $(echo $vendorid | wc -w) -gt 1 ]; then
            echo "Found more than one USB disk devices."
        echo "Please leave it to the FRIEND kernel." 
            echo "Automatically obtains the VID/PID of the required bootloader USB."
        rm /tmp/lsusb.out
        else
            usbdevice="$(grep iManufacturer /tmp/lsusb.out | awk '{print $3}') $(grep iProduct /tmp/lsusb.out | awk '{print $3}') SerialNumber: $(grep iSerial /tmp/lsusb.out | awk '{print $3}')"
            if [ -n "$usbdevice" ] && [ -n "$vendorid" ] && [ -n "$productid" ]; then
                echo "Found $usbdevice"
                echo "Vendor ID : $vendorid Product ID : $productid"
                json="$(jq --arg var "$productid" '.extra_cmdline.pid = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
                json="$(jq --arg var "$vendorid" '.extra_cmdline.vid = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
            else
                echo "Sorry, no usb disk could be identified"
                rm /tmp/lsusb.out
            fi
        fi
    fi      
}

###############################################################################
# Shows available between DDSML and EUDEV
function seleudev() {
  
  eval "MSG27=\"\${MSG${tz}27}\""
  eval "MSG26=\"\${MSG${tz}26}\""
  eval "MSG40=\"\${MSG${tz}40}\""

  checkforsas

  if [ "${BLOCK_DDSML}" = "Y" ] || [ "${BUS}" = "mmc" ] || echo ${kver5explatforms} | grep -qw ${platform} || [[ "${platform}" == *"(DT)"* ]]; then
    menu_options=("e" "${MSG26}" "f" "${MSG40}")
  elif [ ${BLOCK_EUDEV} = "Y" ]; then  
    menu_options=("d" "${MSG27}" "f" "${MSG40}")
  else
    menu_options=("d" "${MSG27}" "e" "${MSG26}" "f" "${MSG40}")
  fi

  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 $(dlgmenuheight $((${#menu_options[@]}/2))) \
      "${menu_options[@]}" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "d" ]; then
      DMPM="DDSML"
      break
    elif [ "${resp}" = "e" ]; then
      DMPM="EUDEV"
      break
    elif [ "${resp}" = "f" ]; then
      DMPM="DDSML+EUDEV"
      break
    fi
  done

  del-addon "eudev"
  del-addon "ddsml"
  if [ "${DMPM}" = "DDSML" ]; then
      add-addons "ddsml"
  elif [ "${DMPM}" = "EUDEV" ]; then
      add-addons "eudev"
  elif [ "${DMPM}" = "DDSML+EUDEV" ]; then
      add-addons "ddsml"
      add-addons "eudev"
  fi
  
  #curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/bundled-exts.json -o /home/tc/redpill-load/bundled-exts.json
  sudo rm -rf /home/tc/redpill-load/custom/extensions/ddsml
  sudo rm -rf /home/tc/redpill-load/custom/extensions/eudev
  writeConfigKey "general" "devmod" "${DMPM}"

}

function resolveLiveKver() {
    local synomodel synoversion
    synomodel=$(readConfigKey "general" "model")
    synoversion=$(readConfigKey "general" "version")
    ( getvarsmshell "${synomodel}-${synoversion}" >/dev/null 2>&1; echo "${KVER}|${ORIGIN_PLATFORM}" )
}

# ── 새로운 헬퍼 함수 추가 ──────────────────────────────────────────
function checkAndResetModuleName() {
    local curMdlName
    curMdlName=$(readConfigKey "general" "modulename")

    # Derive the kernel version of the *currently selected* model live.
    local _gv kver origin_plat
    _gv="$(resolveLiveKver)"
    kver="${_gv%%|*}"
    origin_plat="${_gv##*|}"
    
    # kver = "5.10.55" → ZPADKVER = "5010055"
    local curZpadkver
    curZpadkver=$(echo "${kver}" | awk -F'.' '{printf "%d%03d%03d\n",$1,$2,$3}')

    local supported=false
    # 미지원 시 되돌릴 기본 fallback (분기별로 아래에서 덮어씀)
    local fallbackMdl="all-modules" fallbackMethod="IML"

    # DSM 버전 추출 (major/minor/patch 전체 정밀도)
    local curBuild curZpadDsm
    curBuild=$(readConfigKey "general" "version")
    curZpadDsm=$(zpadDsmVersion "${curBuild}")

    # ── 커널 구간 3단계 분기 ────────────────────────────────────────────────────
    if [ "${curZpadkver}" -ge 5010055 ]; then
        # ① 커널 >= 5.10.55
        if [ "${curZpadDsm}" -ge "${BMI2_REQUIRED_FROM_DSM_ZPAD}" ] && [ "${HAS_BMI2}" = "n" ]; then
            if [ "${curZpadDsm}" -gt "${CUSTOM_MODULES_MAX_DSM_ZPAD}" ]; then
                # DSM > 7.3.2 + BMI2 미지원: custom-modules 도 존재하지 않음.
                # 사용 가능한 모듈팩이 전혀 없는 상태이므로, 최소한 빌드가
                # 되도록 all-modules(IML) 로 되돌린다. (실제로는 이 DSM 버전 자체가
                # selectversion()/enforceBmi2VersionCap() 단계에서 이미 걸러져야 함)
                fallbackMdl="all-modules"; fallbackMethod="IML"
                supported=false
            else
                # DSM 7.3.0 ~ 7.3.2 + BMI2 미지원: custom-modules + anodrm-modules 만 허용.
                # all-modules(BMI2 포함)는 불가 → fallback 을 custom-modules(PML)로.
                # (기존 버그: all-modules 로 되돌려 잔존 all-modules 가 그대로 빌드됨)
                fallbackMdl="custom-modules"; fallbackMethod="PML"
                if [ "${curMdlName}" = "custom-modules" ] || [ "${curMdlName}" = "anodrm-modules" ]; then
                    supported=true
                fi
            fi
        else
            # BMI2 있거나 DSM < 7.3: all/custom/anodrm 모두 허용
            supported=true
        fi
    elif [ "${curZpadkver}" -ge 4004302 ]; then
        # ② 커널 4.4.302 이상 ~ 5.10.55 미만: custom-modules 미지원 → all-modules fallback
        if [ "${curMdlName}" != "custom-modules" ]; then
            supported=true
        fi
    else
        # ③ 커널 < 4.4.302: all-modules/anodrm-modules 만 지원 → all-modules fallback
        if [ "${curMdlName}" = "all-modules" ] || [ "${curMdlName}" = "anodrm-modules" ]; then
            supported=true
        fi
    fi
    # ─────────────────────────────────────────────────────────────────────────

    if [ "${supported}" = "false" ]; then
        echo "⚠ '${curMdlName}' is not supported (kver=${kver}, dsm=${curBuild}, bmi2=${HAS_BMI2})"
        echo "  → Resetting to ${fallbackMdl} (${fallbackMethod})..."
        MDLNAME="${fallbackMdl}"
        MLMETHOD="${fallbackMethod}"
        writeConfigKey "general" "modulename" "${MDLNAME}"
        writeConfigKey "general" "mlmethod"   "${MLMETHOD}"
        syncBundledExtsModule "${MDLNAME}"
    fi
}

###############################################################################
# Shows available between FRIEND and JOT
function selectldrmode() {
  #eval "MSG28=\"\${MSG${tz}28}\""
  MSG28="Intel iGPU i915 DRM Support"
  MSG99="i915 + AMDGPU dual DRM"
  MSGND="No DRM (general modules, no GPU)"
  # 5.10.55 / 4.4.302 platforms 에 대해 custom-modules 옵션 노출.
  # custom-modules 는 epyc7002 + geminilakenk 만 빌드되어 있다.
  # Derive the kernel version of the *currently selected* model live.
  local _gv kver origin_plat
  _gv="$(resolveLiveKver)"
  kver="${_gv%%|*}"
  origin_plat="${_gv##*|}"

  # kver = "5.10.55" → ZPADKVER = "5010055"
  local curZpadkver
  curZpadkver=$(echo "${kver}" | awk -F'.' '{printf "%d%03d%03d\n",$1,$2,$3}')

  # DSM 버전 추출 (major/minor/patch 전체 정밀도)
  local _build curZpadDsm
  _build=$(readConfigKey "general" "version")
  curZpadDsm=$(zpadDsmVersion "${_build}")

  # ── 커널 구간 3단계 분기 ──────────────────────────────────────────────────────
  # anodrm-modules(In-Memory:IML) 는 DRM/GPU 스택을 제외한 일반 모듈팩으로
  # 모든 커널(3.x / 4.4.x / 5.10.x)에 공통 대응하므로 전 분기에 노출한다.
  if [ "${curZpadkver}" -ge 5010055 ]; then
    # ① 커널 >= 5.10.55
    if [ "${curZpadDsm}" -ge "${BMI2_REQUIRED_FROM_DSM_ZPAD}" ] && [ "${HAS_BMI2}" = "n" ]; then
      if [ "${curZpadDsm}" -gt "${CUSTOM_MODULES_MAX_DSM_ZPAD}" ]; then
        # DSM > 7.3.2 + BMI2 미지원: custom-modules 도 존재하지 않음 → nodrm 만 노출
        menu_options=("n" "${MSGND}, anodrm-modules(In-Memory:IML)")
      else
        # DSM 7.3.0 ~ 7.3.2 + BMI2 미지원: custom-modules + nodrm 만 노출
        menu_options=("k" "${MSG99}, custom-modules(Persistent:PML)" \
                      "n" "${MSGND}, anodrm-modules(In-Memory:IML)")
      fi
    else
      # BMI2 있거나 DSM < 7.3: 전체 메뉴 (custom-modules 포함)
      menu_options=("j" "${MSG99}, all-modules(In-Memory:IML)" \
                    "f" "${MSG99}, all-modules(Persistent:PML)" \
                    "k" "${MSG99}, custom-modules(Persistent:PML)" \
                    "n" "${MSGND}, anodrm-modules(In-Memory:IML)")
    fi
  elif [ "${curZpadkver}" -ge 4004302 ]; then
    # ② 커널 4.4.302 이상 ~ 5.10.55 미만: dual DRM all-modules 지원
    menu_options=("j" "${MSG99}, all-modules(In-Memory:IML)" \
                  "f" "${MSG99}, all-modules(Persistent:PML)" \
                  "n" "${MSGND}, anodrm-modules(In-Memory:IML)")
  else
    # ③ 커널 < 4.4.302 (커널 4.4.180 이하 커널 3.x): all-modules 만
    menu_options=("j" "${MSG28}, all-modules(In-Memory:IML)" \
                  "f" "${MSG28}, all-modules(Persistent:PML)" \
                  "n" "${MSGND}, anodrm-modules(In-Memory:IML)")
  fi
  # ─────────────────────────────────────────────────────────────────────────────
  
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 $(dlgmenuheight $((${#menu_options[@]}/2))) \
      "${menu_options[@]}" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "f" ]; then
      MDLNAME="all-modules"
      MLMETHOD="PML"
      break
    elif [ "${resp}" = "j" ]; then
      MDLNAME="all-modules"
      MLMETHOD="IML"
      break
    elif [ "${resp}" = "k" ]; then
      MDLNAME="custom-modules"
      MLMETHOD="PML"
      break
    elif [ "${resp}" = "n" ]; then
      MDLNAME="anodrm-modules"
      MLMETHOD="IML"
      break
    fi
  done
  writeConfigKey "general" "loadermode" "${LDRMODE}"
  writeConfigKey "general" "modulename" "${MDLNAME}"
  writeConfigKey "general" "mlmethod" "${MLMETHOD}"

  # bundled-exts.json 의 *-modules 정의를 선택된 MDLNAME 으로 치환
  # 각 모듈 분기는 서로 다른 저장소를 가리킨다:
  #   all-modules    → tcrp-modules/main/all-modules/rpext-index.json
  #   custom-modules → tcrp-modules/main/custom-modules/rpext-index.json
  syncBundledExtsModule "${MDLNAME}"
}

# bundled-exts.json 의 *-modules 키를 ${1} 로 통일한다.
# selectldrmode() 와 functions_t.sh::my() 양쪽에서 호출해 두 경로의 동작을 일치시킨다.
function syncBundledExtsModule() {
  local mdlname="${1}"
  local bex="/home/tc/redpill-load/bundled-exts.json"
  [ -f "${bex}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local mdlurl
  case "${mdlname}" in
    all-modules)    mdlurl="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/all-modules/rpext-index.json" ;;
    custom-modules) mdlurl="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/custom-modules/rpext-index.json" ;;
    anodrm-modules)  mdlurl="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/anodrm-modules/rpext-index.json" ;;
    *) return 0 ;;
  esac
  local tmp
  tmp=$(jq --arg name "${mdlname}" --arg url "${mdlurl}" '
      del(.["all-modules"])
    | del(.["custom-modules"])
    | del(.["anodrm-modules"])
    | . + {($name): $url}
  ' "${bex}") && echo "${tmp}" | jq . > "${bex}"
}

###############################################################################
# Shows available dsm verwsion 
function selectversion () {

# 1. 최신순으로 최대 12개 결과 추출 (공백 한 개로 join)
pat_versions=$(jq -r ".\"${MODEL}\" | keys | map(split(\"-\") | .[0:2] | join(\"-\")) | reverse | .[:12] | join(\" \")" "${configfile}")
echo "PAT VERSIONS : $pat_versions"

# 2. 배열 변환
IFS=' ' read -ra versions <<< "$pat_versions"

# 2-1. BMI2 미지원 CPU 에서는 DSM 7.4.0 이상 버전을 선택 목록에서 제외한다.
#      (all-modules 의 BMI2(mulx 등) 명령 미지원으로 부팅 불가)
#      현재 시놀로지가 DSM 7.4 용 GPL 커널 소스를 아직 공개하지 않아
#      BMI2 명령을 제거한 custom-modules(PML) 커널을 빌드할 수 없으므로,
#      GPL 이 공개되기 전까지 BMI2 미지원 CPU 에서는 7.4 이상을 원천 차단한다.
#      단, 이 제한은 all-modules 에 BMI2 명령이 포함된 kver5platforms(커널 5.10.55)
#      플랫폼에만 적용한다. apollolake 등 커널 4.4.302/3.x 플랫폼의 all-modules 에는
#      BMI2 명령이 없어 BMI2 미지원 CPU 에서도 정상 부팅하므로 7.4 를 막지 않는다.
_bmi2_plat="$(resolveLiveKver)"; _bmi2_plat="${_bmi2_plat##*|}"
if [ "${HAS_BMI2}" = "n" ] && echo "${kver5platforms}" | grep -qw "${_bmi2_plat}"; then
  filtered=()
  for v in "${versions[@]}"; do
    vZpadDsm=$(zpadDsmVersion "${v}")
    if [ "${vZpadDsm}" -ge "${BMI2_REQUIRED_FROM_DSM_ZPAD}" ] && [ "${vZpadDsm}" -gt "${CUSTOM_MODULES_MAX_DSM_ZPAD}" ]; then
      echo "Excluding ${v} (DSM > 7.3.2 requires BMI2 CPU; custom-modules not built past 7.3.2)"
      continue
    fi
    filtered+=("${v}")
  done
  versions=("${filtered[@]}")
fi

# 결과 출력 (공백 구분)
echo "${versions[@]}"

# 선택 가능한 버전이 하나도 없으면(BMI2 미지원 + 7.4 이상만 존재) 안내 후 종료
if [ "${#versions[@]}" -eq 0 ]; then
  dialog --clear --backtitle "$(backtitle)" \
    --msgbox "No selectable DSM version for this CPU.\nDSM 7.4.0+ needs a BMI2-capable CPU (Synology has not released the DSM 7.4 GPL kernel source yet)." 9 70
  return
fi

# 3. TAG-ITEM 쌍 만들기
menu_items=()
tags=(a b c d e f g h i j k l)
for i in "${!versions[@]}"; do
  menu_items+=("${tags[$i]}" "${versions[$i]}")
done

while true; do
  dialog --clear --backtitle "$(backtitle)" \
    --menu "Choose a option" 0 0 $(dlgmenuheight $((${#menu_items[@]}/2))) \
    "${menu_items[@]}" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return

  # 동적으로 인덱스와 BUILD 매칭
  for i in "${!tags[@]}"; do
    if [[ "${resp}" == "${tags[$i]}" ]]; then
      BUILD="${versions[$i]}"
      break 2
    fi
  done
  echo "Invalid option"
done

writeConfigKey "general" "version" "${BUILD}"

checkAndResetModuleName

}

###############################################################################
# Shows available models to user choose one
function modelMenu() {

  # Set the path for the models.json file
  MODELS_JSON="/home/tc/models.json"
  
  # Define platform groups
  M_GRP1="epyc7002 epyc7003ntb epyc7003 icelaked v1000nk r1000nk geminilakenk broadwellnk"
  M_GRP2="broadwell broadwellnkv2 broadwellntbap purley bromolow avoton braswell cedarview"
  M_GRP3="denverton"
  M_GRP4="apollolake"
  M_GRP5="r1000"
  M_GRP6="v1000"
  M_GRP7="geminilake"
  
  RESTRICT=1
  
  # Initialize the mdl file
  > "${TMP_PATH}/mdl"
  
  # Determine which platforms to use based on AFTERHASWELL
  if [ "${AFTERHASWELL}" == "OFF" ]; then
    platforms="${M_GRP1} ${M_GRP5} ${M_GRP6} ${M_GRP2}"
  else
    platforms="${M_GRP1} ${M_GRP4} ${M_GRP7} ${M_GRP5} ${M_GRP6} ${M_GRP3} ${M_GRP2}"
    RESTRICT=0
  fi
  
  # Extract models for each platform and add them to the mdl file
  for platform in $platforms; do
    models=$(jq -r ".$platform.models[]" "$MODELS_JSON" 2>/dev/null)
    if [ -n "$models" ]; then
      echo "$models" >> "${TMP_PATH}/mdl"
    fi
  done
  
  # Add restriction release option if RESTRICT is 1
  if [ ${RESTRICT} -eq 1 ]; then
    echo "Release-model-restriction" >> "${TMP_PATH}/mdl"
  fi
  
  # Create the final model list with suggestions
  > "${TMP_PATH}/mdl_final"
  line_number=1
  model_list=$(tail -n +$line_number "${TMP_PATH}/mdl")
  while read -r model; do
    suggestion=$(setSuggest $model)
    echo "$model \"\Zb$suggestion\Zn\"" >> "${TMP_PATH}/mdl_final"
  done <<< "$model_list"

  eval "MSG00=\"\${MSG${tz}00}\""
  
  #header="Supported Models for your Hardware (v = supported / + = need Addons)\n$(printf "\Zb%-16s\Zn \Zb%-15s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-5s\Zn \Zb%-10s\Zn \Zb%-12s\Zn" "Model" "Platform" "DT" "iGPU" "HBA" "M.2 Cache" "M.2 Volume")"
  
  # Display dialog for model selection
  dialog --backtitle "`backtitle`" --default-item "${MODEL}" --colors \
    --menu "${MSG00} [Except SA6400]\n" 0 0 $(dlgmenuheight $(wc -l < "${TMP_PATH}/mdl_final")) \
    --file "${TMP_PATH}/mdl_final" 2>${TMP_PATH}/resp
  
  # Check for dialog exit status
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return
  
  # Handle the case when "Release-model-restriction" is selected
  if [ "${resp}" = "Release-model-restriction" ]; then
    RESTRICT=0
    # Additional actions can be performed here if needed
  fi
    
  MODEL="`<${TMP_PATH}/resp`"
  writeConfigKey "general" "model" "${MODEL}"
  setSuggest $MODEL

  enforceBmi2VersionCap

  if [[ "${platform}" == "epyc7002(DT)" || "${platform}" == "epyc7003ntb(DT)" || "${platform}" == "epyc7003(DT)" || "${platform}" == "icelaked(DT)" || "${platform}" == "geminilakenk(DT)" || "${platform}" == "v1000nk(DT)" || "${platform}" == "r1000nk(DT)" ]]; then
      echo "${platform} maintain ${MDLNAME}, ${MLMETHOD}"
  else
      MDLNAME="all-modules"
      writeConfigKey "general" "modulename" "${MDLNAME}"      
      MLMETHOD="IML"
      writeConfigKey "general" "mlmethod" "${MLMETHOD}"
      echo "${platform} change to ${MDLNAME}, ${MLMETHOD}"      
  fi

  if echo ${kver3explatforms} | grep -qw ${platform}; then
      MDLNAME="all-modules"
      writeConfigKey "general" "modulename" "${MDLNAME}"
  fi

  checkAndResetModuleName
  
  BUILD=$(jq -r ".\"${MODEL}\" | keys | max | split(\"-\") | .[0:2] | join(\"-\")" "${configfile}")
  writeConfigKey "general" "version" "${BUILD}"  

  if [ "${BLOCK_DDSML}" = "Y" ] || [ "${BUS}" = "mmc" ] || echo ${kver5explatforms} | grep -qw ${platform} || [[ "${platform}" == *"(DT)"* ]]; then
    if [ "$HBADETECT" = "ON" ]; then
        DMPM="DDSML+EUDEV"
    else
        DMPM="EUDEV"
    fi 
  else
    DMPM="DDSML"
  fi
  getip
  if [ "${R8168_YN}" = "Y" ] && echo "${kver5explatforms}" | grep -qw "${platform}"; then
    DMPM="DDSML+EUDEV"
  fi
  writeConfigKey "general" "devmod" "${DMPM}"
}

# Set Describe model-specific requirements or suggested hardware
function setSuggest() {

  case $1 in
    SA6400)      platform="epyc7002(DT)";bay="RACK_12_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    PAS7700)     platform="epyc7003ntb(DT)";bay="RACK_24_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    FS6420)      platform="epyc7003(DT)";bay="RACK_24_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    FS3420)      platform="icelaked(DT)";bay="RACK_20_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    RS1626xs+)   platform="icelaked(DT)";bay="RACK_4_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    RS3626xs)    platform="icelaked(DT)";bay="RACK_6_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    RS4826xs+)   platform="icelaked(DT)";bay="RACK_8_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    RS6426xs+)   platform="icelaked(DT)";bay="RACK_12_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS925+)      platform="v1000nk(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS1525+)     platform="v1000nk(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS1825+)     platform="v1000nk(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS725+)      platform="r1000nk(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS425+)      platform="geminilakenk(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;    
    DS225+)      platform="geminilakenk(DT)";bay="TOWER_2_Bay";mcpu="KERNEL 5.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;    
    DS1019+)     platform="apollolake";bay="TOWER_5_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS620slim)   platform="apollolake";bay="TOWER_6_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS218+)      platform="apollolake";bay="TOWER_2_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS418play)   platform="apollolake";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS718+)      platform="apollolake";bay="TOWER_2_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS918+)      platform="apollolake";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS1520+)     platform="geminilake(DT)";bay="TOWER_5_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DS220+)      platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS224+)      platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS420+)      platform="geminilake(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS423+)      platform="geminilake(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DS720+)      platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DS920+)      platform="geminilake(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DVA1622)     platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}, \${MSG${tz}21}\"";;
    DS1621xs+)   platform="broadwellnk";bay="TOWER_6_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3622xs+)   platform="broadwellnk";bay="TOWER_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS3600)      platform="broadwellnk";bay="RACK_24_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS1619xs+)   platform="broadwellnk";bay="RACK_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3621RPxs)  platform="broadwellnk";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3621xs+)   platform="broadwellnk";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS4021xs+)   platform="broadwellnk";bay="RACK_16_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3400)      platform="broadwellnk";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3600)      platform="broadwellnk";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3018xs)    platform="broadwellnk";bay="TOWER_6_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS1018)      platform="broadwellnk";bay="TOWER_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS1522+)     platform="r1000(DT)";bay="TOWER_5_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;    
    DS723+)      platform="r1000(DT)";bay="TOWER_2_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;
    DS923+)      platform="r1000(DT)";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;
    RS422+)      platform="r1000(DT)";bay="RACK_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;
    DS1621+)     platform="v1000(DT)";bay="TOWER_6_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    DS1821+)     platform="v1000(DT)";bay="TOWER_8_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1823xs+)   platform="v1000(DT)";bay="TOWER_8_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;            
    DS2422+)     platform="v1000(DT)";bay="TOWER_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    FS2500)      platform="v1000(DT)";bay="RACK_12_Bay_2";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS1221+)     platform="v1000(DT)";bay="RACK_8_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    RS1221RP+)   platform="v1000(DT)";bay="RACK_8_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    RS2421+)     platform="v1000(DT)";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2421RP+)   platform="v1000(DT)";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";; 
    RS2423+)     platform="v1000(DT)";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;        
    RS2423RP+)   platform="v1000(DT)";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2821RP+)   platform="v1000(DT)";bay="RACK_16_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS822+)      platform="v1000(DT)";bay="RACK_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS822RP+)    platform="v1000(DT)";bay="RACK_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1819+)     platform="denverton";bay="TOWER_8_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;
    DS2419+)     platform="denverton";bay="TOWER_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;  
    DS2419+II)   platform="denverton";bay="TOWER_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;
    DVA3219)     platform="denverton";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;    
    DVA3221)     platform="denverton";bay="TOWER_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";; 
    RS820+)      platform="denverton";bay="RACK_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS820RP+)    platform="denverton";bay="RACK_4_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    DS1618+)     platform="denverton";bay="TOWER_6_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;
    RS2418+)     platform="denverton";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS2418RP+)   platform="denverton";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS2818RP+)   platform="denverton";bay="RACK_16_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS3618xs)    platform="broadwell";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3617xs)    platform="broadwell";bay="TOWER_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3617xsII)  platform="broadwell";bay="TOWER_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS2017)      platform="broadwell";bay="RACK_24_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS3400)      platform="broadwell";bay="RACK_24_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;    
    RS18017xs+)  platform="broadwell";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3617RPxs)  platform="broadwell";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3617xs+)   platform="broadwell";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS4017xs+)   platform="broadwell";bay="RACK_16_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS3410)      platform="broadwellnkv2(DT)";bay="RACK_24_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3410)      platform="broadwellnkv2(DT)";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3610)      platform="broadwellnkv2(DT)";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3200D)     platform="broadwellntbap";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3400D)     platform="broadwellntbap";bay="RACK_12_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS6400)      platform="purley(DT)";bay="RACK_24_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    HD6500)      platform="purley(DT)";bay="RACK_60_Bay";mcpu="KERNEL 4.4";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS1515+)     platform="avoton";bay="TOWER_5_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1517+)     platform="avoton";bay="TOWER_5_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1815+)     platform="avoton";bay="TOWER_8_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1817+)     platform="avoton";bay="TOWER_8_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS2415+)     platform="avoton";bay="TOWER_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS415+)      platform="avoton";bay="TOWER_4_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS1219+)     platform="avoton";bay="RACK_8_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2416+)     platform="avoton";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2416RP+)   platform="avoton";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS815+)      platform="avoton";bay="RACK_4_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS815RP+)    platform="avoton";bay="RACK_4_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS818+)      platform="avoton";bay="RACK_8_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS818RP+)    platform="avoton";bay="RACK_8_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS713+)      platform="cedarview";bay="TOWER_2_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1513+)     platform="cedarview";bay="TOWER_5_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1813+)     platform="cedarview";bay="TOWER_8_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS2413+)     platform="cedarview";bay="TOWER_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2414+)     platform="cedarview";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2414RP+)   platform="cedarview";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS814+)      platform="cedarview";bay="RACK_4_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS814RP+)    platform="cedarview";bay="RACK_4_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS916+)      platform="braswell";bay="TOWER_4_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS716+)      platform="braswell";bay="TOWER_2_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS216+)      platform="braswell";bay="TOWER_2_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS416play)   platform="braswell";bay="TOWER_4_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS716+II)    platform="braswell";bay="TOWER_2_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS216+II)    platform="braswell";bay="TOWER_2_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS3615xs)    platform="bromolow";bay="TOWER_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RC18015xs+)  platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS10613xs+)  platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS18016xs+)  platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3413xs+)   platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3614rpxs)  platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3614xs+)   platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3614xs)    platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3617xs)    platform="bromolow";bay="RACK_12_Bay";mcpu="KERNEL 3.10";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    *)    platform="Any platform";bay="Any Bay";mcpu="KERNEL X.X";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
  esac

  #if [ $(echo ${platform} | grep "(DT)" | wc -l) -gt 0 ]; then
  #  eval "MSG00=\"\${MSG${tz}00}\""
  #else
  #  MSG00="\n"
  #fi  
  
  result="${desc}"
  echo "${platform} : ${bay} : ${mcpu}"
}

# Set Storage Panel Size
function storagepanel() {

  BAYSIZE="${bay}"
  dialog --backtitle "`backtitle`" --default-item "${BAYSIZE}" --no-items \
    --menu "Choose a Panel Size" 0 0 $(dlgmenuheight 13) "TOWER_1_Bay" "TOWER_2_Bay" "TOWER_4_Bay" "TOWER_4_Bay_J" \
        "TOWER_4_Bay_S" "TOWER_5_Bay" "TOWER_6_Bay" "TOWER_8_Bay" "TOWER_12_Bay" \
        "RACK_2_Bay" "RACK_4_Bay" "RACK_8_Bay" "RACK_10_Bay" \
                "RACK_12_Bay" "RACK_12_Bay_2" "RACK_16_Bay" "RACK_20_Bay" "RACK_24_Bay" "RACK_60_Bay" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return 

  BAYSIZE="`<${TMP_PATH}/resp`"
  writeConfigKey "general" "bay" "${BAYSIZE}"
  bay="${BAYSIZE}"
  
}

###############################################################################
# Shows menu to user type one or generate randomly
function serialMenu() {
  eval "MSG30=\"\${MSG${tz}30}\""
  eval "MSG31=\"\${MSG${tz}31}\""  
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 $(dlgmenuheight 2) \
      a "${MSG30}" \
      m "${MSG31}" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "m" ]; then
      while true; do
        dialog --backtitle "`backtitle`" \
          --inputbox "Please enter a serial number " 0 0 "" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        SERIAL=`cat ${TMP_PATH}/resp`
        if [ -z "${SERIAL}" ]; then
          return
        else
          break
        fi
      done
      break
    elif [ "${resp}" = "a" ]; then
      SERIAL=`./sngen.sh "${MODEL}"-"${BUILD}"`
      break
    fi
  done
  SN="${SERIAL}"
  writeConfigKey "extra_cmdline" "sn" "${SN}"
  sudo cp $userconfigfile /mnt/${tcrppart}/user_config.json
}

###############################################################################
# Shows menu to generate randomly or to get realmac
function macMenu() {
  eval "MSG32=\"\${MSG${tz}32}\""
  eval "MSG33=\"\${MSG${tz}33}\""
  eval "MSG34=\"\${MSG${tz}34}\""  
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 $(dlgmenuheight 3) \
      c "${MSG32}" \
      d "${MSG33}" \
      m "${MSG34}" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "d" ]; then
      MACADDR=`./macgen.sh "randommac" $1 ${MODEL}`
      break
    elif [ "${resp}" = "c" ]; then
      MACADDR=`./macgen.sh "realmac" $1 ${MODEL}`
      break
    elif [ "${resp}" = "m" ]; then
      while true; do
        dialog --backtitle "`backtitle`" \
          --inputbox "Please enter a mac address " 0 0 "" \
          2>${TMP_PATH}/resp
        [ $? -ne 0 ] && return
        MACADDR=`cat ${TMP_PATH}/resp`
        if [ -z "${MACADDR}" ]; then
          return
        else
          break
        fi
      done
      break
    fi
  done
  
  if [ "$1" = "eth0" ]; then
      MACADDR1="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac1" "${MACADDR1}"
  fi
  
  if [ "$1" = "eth1" ]; then
      MACADDR2="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac2" "${MACADDR2}"
      writeConfigKey "extra_cmdline" "netif_num" "2"
  fi
  
  if [ "$1" = "eth2" ]; then
      MACADDR3="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac3" "${MACADDR3}"
      writeConfigKey "extra_cmdline" "netif_num" "3"
  fi

  if [ "$1" = "eth3" ]; then
      MACADDR4="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac4" "${MACADDR4}"
      writeConfigKey "extra_cmdline" "netif_num" "4"
  fi

  if [ "$1" = "eth4" ]; then
      MACADDR5="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac5" "${MACADDR5}"
      writeConfigKey "extra_cmdline" "netif_num" "5"
  fi
  
  if [ "$1" = "eth5" ]; then
      MACADDR6="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac6" "${MACADDR6}"
      writeConfigKey "extra_cmdline" "netif_num" "6"
  fi
  
  if [ "$1" = "eth6" ]; then
      MACADDR7="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac7" "${MACADDR7}"
      writeConfigKey "extra_cmdline" "netif_num" "7"
  fi

  if [ "$1" = "eth7" ]; then
      MACADDR8="${MACADDR}"
      writeConfigKey "extra_cmdline" "mac8" "${MACADDR8}"
      writeConfigKey "extra_cmdline" "netif_num" "8"
  fi

  sudo cp $userconfigfile /mnt/${tcrppart}/user_config.json
}

# MAC 주소 선택 하위메뉴 - 최대 8개(eth0~eth7) 인터페이스를 순차가 아니라
# 목록에서 골라 설정한다. 문자키(a f g h i o t d)와 안내문(MSG${tz}04)은
# 기존 메인메뉴에서 쓰던 것을 그대로 재사용 - MSGID 변경 없음. 실제
# 네트워크 인터페이스가 있는 것만 나열하고(핫플러그 없는 환경이라 진입
# 시점 스냅샷이면 충분), 하나 처리한 뒤에는 다시 이 목록으로 돌아와
# 여러 개를 연달아 설정할 수 있다. ESC/Cancel 로 메인메뉴로 복귀.
function macAddressMenu() {
  local LETTERS="abcdefgh"
  while true; do
    eval "MSG04=\"\${MSG${tz}04}\""
    eval "MSG73=\"\${MSG${tz}73}\""
    # 인덱스는 a 부터 순차 증가(eth 번호와 무관하게 목록에 실제로 올라간
    # 순서대로 a,b,c...) - 최대 8개(eth0~eth7). eth0 은 항상 포함, 나머지는
    # 실제 존재하는 것만.
    local -a keys=() targets=()
    keys+=("${LETTERS:0:1}"); targets+=("eth0")
    local n
    for n in 1 2 3 4 5 6 7; do
      [ $(/sbin/ifconfig | grep "eth${n}" | wc -l) -gt 0 ] || continue
      keys+=("${LETTERS:${#keys[@]}:1}")
      targets+=("eth${n}")
    done
    set --
    local i=0
    while [ $i -lt ${#keys[@]} ]; do
      set -- "$@" "${keys[$i]}" "${MSG04} $((i+1))"
      i=$((i+1))
    done
    set -- "$@" x "${MSG73}"
    dialog --clear --backtitle "`backtitle`" \
      --menu "${MSG04}" 0 0 $(dlgmenuheight $(($#/2))) \
      "$@" \
      2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    [ "${resp}" = "x" ] && return
    i=0
    while [ $i -lt ${#keys[@]} ]; do
      if [ "${resp}" = "${keys[$i]}" ]; then
        macMenu "${targets[$i]}"
        break
      fi
      i=$((i+1))
    done
  done
}

function prevent() {
    if [ "${PREVENT_INIT}" = "OFF" ]; then
        PREVENT_INIT="ON"
        echo "SataPortMap/DiskIdxMap initialization protection: Enabled"
    else
        PREVENT_INIT="OFF"
        echo "SataPortMap/DiskIdxMap initialization protection: Disabled"
    fi
    writeConfigKey "general" "prevent_init" "${PREVENT_INIT}"
    echo "press any key to continue..."
    read answer
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "`backtitle`" --title "Edit with caution" \
      --editbox "${userconfigfile}" 0 0 2>"${TMP_PATH}/userconfig"
    
    [ $? -ne 0 ] && return

    # JSON format validation
    if jq . "${TMP_PATH}/userconfig" > /dev/null 2>&1; then
        mv "${TMP_PATH}/userconfig" "${userconfigfile}"
        [ $? -eq 0 ] && break
    else
        dialog --backtitle "`backtitle`" --title "Invalid JSON format" --msgbox "The JSON format is invalid." 0 0
    fi
  done

  sudo cp /home/tc/user_config.json /mnt/${tcrppart}/user_config.json

  MODEL=$(readConfigKey "general" "model")
  SN=$(readConfigKey "extra_cmdline" "sn")
  MACADDR1=$(readConfigKey "extra_cmdline" "mac1")
  MACADDR2=$(readConfigKey "extra_cmdline" "mac2")
  MACADDR3=$(readConfigKey "extra_cmdline" "mac3")
  MACADDR4=$(readConfigKey "extra_cmdline" "mac4")
  MACADDR5=$(readConfigKey "extra_cmdline" "mac5")
  MACADDR6=$(readConfigKey "extra_cmdline" "mac6")
  MACADDR7=$(readConfigKey "extra_cmdline" "mac7")
  MACADDR8=$(readConfigKey "extra_cmdline" "mac8")
  NETNUM=$(readConfigKey "extra_cmdline" "netif_num")
  
}

###############################################################################
# view linuxrc.syno.log file with textbox
function viewerrorlog() {

  if [ -f "/mnt/${loaderdisk}1/logs/jr/linuxrc.syno.log" ]; then

    while true; do
      dialog --backtitle "`backtitle`" --title "View linuxrc.syno.log file" \
        --textbox "/mnt/${loaderdisk}1/logs/jr/linuxrc.syno.log" 0 0 
      [ $? -eq 0 ] && break
    done
    
  else

    echo "/mnt/${loaderdisk}1/logs/jr/linuxrc.syno.log file not found!"
    echo "press any key to continue..."
    read answer
  
  fi

  return 0
}

function checkUserConfig() {

  if [ ! -n "${SN}" ]; then
    #eval "echo \${MSG${tz}36}"
    #eval "echo \${MSG${tz}35}"
    #read answer
    #return 1     
    SN=`./sngen.sh "${MODEL}"-"${BUILD}"`
    writeConfigKey "extra_cmdline" "sn" "${SN}"
  fi
  
  if [ ! -n "${MACADDR1}" ]; then
    #eval "echo \${MSG${tz}37}"
    #eval "echo \${MSG${tz}35}"
    #read answer
    #return 1     
    MACADDR1=`./macgen.sh "realmac" "eth0" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac1" "${MACADDR1}"
  fi

  if [ $(/sbin/ifconfig | grep eth1 | wc -l) -gt 0 ] && [ ! -n "${MACADDR2}" ]; then
    MACADDR2=`./macgen.sh "realmac" "eth1" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac2" "${MACADDR2}"
  fi

  if [ $(/sbin/ifconfig | grep eth2 | wc -l) -gt 0 ] && [ ! -n "${MACADDR3}" ]; then
    MACADDR3=`./macgen.sh "realmac" "eth2" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac3" "${MACADDR3}"
  fi

  if [ $(/sbin/ifconfig | grep eth3 | wc -l) -gt 0 ] && [ ! -n "${MACADDR4}" ]; then
    MACADDR4=`./macgen.sh "realmac" "eth3" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac4" "${MACADDR4}"
  fi

  if [ $(/sbin/ifconfig | grep eth4 | wc -l) -gt 0 ] && [ ! -n "${MACADDR5}" ]; then
    MACADDR5=`./macgen.sh "realmac" "eth4" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac5" "${MACADDR5}"
  fi

  if [ $(/sbin/ifconfig | grep eth5 | wc -l) -gt 0 ] && [ ! -n "${MACADDR6}" ]; then
    MACADDR6=`./macgen.sh "realmac" "eth5" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac6" "${MACADDR6}"
  fi

  if [ $(/sbin/ifconfig | grep eth6 | wc -l) -gt 0 ] && [ ! -n "${MACADDR7}" ]; then
    MACADDR7=`./macgen.sh "realmac" "eth6" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac7" "${MACADDR7}"
  fi

  if [ $(/sbin/ifconfig | grep eth7 | wc -l) -gt 0 ] && [ ! -n "${MACADDR8}" ]; then
    MACADDR8=`./macgen.sh "realmac" "eth7" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac8" "${MACADDR8}"
  fi

  netif_num=$(readConfigKey "extra_cmdline" "netif_num")
  netif_num_cnt=$(cat $userconfigfile | grep \"mac | wc -l)
                    
  if [ $netif_num != $netif_num_cnt ]; then
    echo "netif_num = ${netif_num}"
    echo "number of mac addresses = ${netif_num_cnt}"       
    eval "echo \${MSG${tz}38}"
    eval "echo \${MSG${tz}35}"
    read answer
    return 1     
  fi  

  if [ "$netif_num" -ge 1 ] && [ "$netif_num" -le 8 ]; then
      declare -A mac_array
      duplicate_found=false
    
      # Loop through all MAC addresses
      for i in $(seq 1 $netif_num); do
        mac_var="MACADDR$i"
        mac_value="${!mac_var}"
        
        # Check if the MAC address is not NULL
        if [ -n "$mac_value" ]; then
          # Check if this MAC address already exists in our array
          if [ -n "${mac_array[$mac_value]+x}" ]; then
            duplicate_found=true
            break
          else
            # If not, add it to the array
            mac_array[$mac_value]=$i
          fi
        fi
      done
    
      # If a duplicate was found, print an error message and return
      if $duplicate_found; then
        echo "Duplicate MAC addresses found among the interfaces."
        read answer
        return 1
      fi
  else
    # If netif_num is out of valid range, print an error message and return
    echo "netif_num must be between 1 and 8."
    read answer
    return 1
  fi

}

###############################################################################
# Where the magic happens!
function make() {

  checkUserConfig 
  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error loader building" 0 0 #--textbox "${LOG_FILE}" 0 0      
    return 1  
  fi

  #if [ "${BUS}" != "usb" ] && [ ${platform} = "apollolake" ] && [ "$HYPERVISOR" = "KVM" ]; then
  #    echo "When using SATA/NVMe type loader + Apollolake + proxmox(kvm)/qemu(kvm), loader build is not possible. KP occurs in versions after lkm 24.8.29..."
  #    echo "press any key to continue..."
  #    read answer
  #    return 1
  #fi

  usbidentify
  clear

  if [ "${PREVENT_INIT}" = "OFF" ]; then
    my "${MODEL}"-"${BUILD}" noconfig "${1}" | tee "/home/tc/zlastbuild.log"
  else
    my "${MODEL}"-"${BUILD}" noconfig "${1}" prevent_init | tee "/home/tc/zlastbuild.log"
  fi 

  if  [ -f /home/tc/custom-module/redpill.ko ]; then
    echo "Removing redpill.ko ..."
    sudo rm -rf /home/tc/custom-module/redpill.ko
  fi

  if [ $? -ne 0 ]; then
    dialog --backtitle "`backtitle`" --title "Error loader building" 0 0 #--textbox "${LOG_FILE}" 0 0    
    return 1
  fi

st "finishloader" "Loader build status" "Finished building the loader"  
  msgnormal "The loader was created successfully!!!"
  echo "press any key to continue..."
  read answer
  rm -f /home/tc/buildstatus  
  return 0
}

###############################################################################
# Post Update for jot mode 
function postupdate() {
  my "${MODEL}" postupdate | tee "/home/tc/zpostupdate.log"
  echo "press any key to continue..."
  read answer
  return 0
}

###############################################################################
# Shows available language to user choose one
function langMenu() {

  dialog --backtitle "`backtitle`" --default-item "${LAYOUT}" --no-items \
    --menu "Choose a language" 0 0 $(dlgmenuheight 18) "English" "한국어" "日本語" "简体中文" "正體中文" "Русский" \
    "Français" "Deutsch" "Español" "Italiano" "brasileiro" \
    "Magyar" "bahasa_Indonesia" "Türkçe" "हिंदी" "عربي" \
    "አማርኛ" "ไทย" \
    2>${TMP_PATH}/resp
    
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return  
  
  case `<"${TMP_PATH}/resp"` in
    English) tz="US"; ucode="en_US";;
    한국어) tz="KR"; ucode="ko_KR";;
    日本語) tz="JP"; ucode="ja_JP";;
    简体中文) tz="CN"; ucode="zh_CN";;
    正體中文) tz="TW"; ucode="zh_TW";;
    Русский) tz="RU"; ucode="ru_RU";;
    Français) tz="FR"; ucode="fr_FR";;
    Deutsch) tz="DE"; ucode="de_DE";;
    Español) tz="ES"; ucode="es_ES";;
    Italiano) tz="IT"; ucode="it_IT";;
    brasileiro) tz="BR"; ucode="pt_BR";;
    Magyar) tz="HU"; ucode="hu_HU";;
    bahasa_Indonesia) tz="ID"; ucode="id_ID";;
    Türkçe) tz="TR"; ucode="tr_TR";;
    हिंदी) tz="IN"; ucode="hi_IN";;
    عربي) tz="EG"; ucode="ar_EG";;
    አማርኛ) tz="ET"; ucode="am_ET";;
    ไทย) tz="TH"; ucode="th_TH";;
  esac
  
  [ ! -d /usr/lib/locale ] && sudo mkdir /usr/lib/locale
  sudo localedef -c -i ${ucode} -f UTF-8 ${ucode}.UTF-8 > /dev/null 2>&1
  sudo localedef -f UTF-8 -i ${ucode} ${ucode}.UTF-8 > /dev/null 2>&1

  export LANG=${ucode}.UTF-8
  export LC_ALL=${ucode}.UTF-8
  set -o allexport
  
  writeConfigKey "general" "ucode" "${ucode}"  

  tz="ZZ"
  load_zz
  
  setSuggest $MODEL
  
  return 0

}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "`backtitle`" --default-item "${LAYOUT}" --no-items \
    --menu "Choose a layout" 0 0 $(dlgmenuheight 7) "azerty" "colemak" \
    "dvorak" "fgGIod" "olpc" "qwerty" "qwertz" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  LAYOUT="`<${TMP_PATH}/resp`"
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-5} "
  done < <(cd /usr/share/kmap/${LAYOUT}; ls *.kmap)
  dialog --backtitle "`backtitle`" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 $(dlgmenuheight $(echo ${OPTIONS} | wc -w)) ${OPTIONS} \
    2>/tmp/resp
  [ $? -ne 0 ] && return
  resp=`cat /tmp/resp 2>/dev/null`
  [ -z "${resp}" ] && return
  KEYMAP=${resp}
  writeConfigKey "general" "layout" "${LAYOUT}"
  writeConfigKey "general" "keymap" "${KEYMAP}"
  sed -i "/loadkmap/d" /opt/bootsync.sh
  echo "loadkmap < /usr/share/kmap/${LAYOUT}/${KEYMAP}.kmap &" >> /opt/bootsync.sh
  backuploader
  
  echo
  echo "Since the keymap has been changed,"
  restart
}

function backup() {

  echo "Cleaning redpill-load/cache directory for backup!"
  if [ -d /home/tc/old ]; then
    rm -rf /home/tc/old
  fi
  if [ -f /home/tc/oldpat.tar.gz ]; then
    rm -f /home/tc/oldpat.tar.gz
  fi  
  if [ -d /home/tc/redpill-load/cache ]; then
    rm -f /home/tc/redpill-load/cache/*
  fi  
  if [ -f /home/tc/custom-module ]; then
    rm -f /home/tc/custom-module
  fi

  echo "y"|rploader backup
  echo "press any key to continue..."
  read answer
  return 0
}

function burnloader() {

  tcrpdev=/dev/$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)
  listusb=()
  # 2024.07.06 Add NVMe
  listusb+=( $(lsblk -o PATH,ROTA,TRAN | grep -E '/dev/(sd|nvme)' | grep -v ${tcrpdev} | grep -E '(1 usb|0 sata|0 nvme)' | awk '{print $1}' ) )

  if [ ${#listusb[@]} -eq 0 ]; then 
    echo "No Available USB,SSD or NVMe, press any key continue..."
    read answer                       
    return 0   
  fi

  dialog --backtitle "`backtitle`" --no-items --colors \
    --menu "Choose a USB Stick, SSD or NVMe for New Loader\n\Z1(Caution!) In the case of SSD(include NVMe), be sure to check whether it is a cache or data disk.\Zn" 0 0 $(dlgmenuheight ${#listusb[@]}) "${listusb[@]}" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return 

  loaderdev="`<${TMP_PATH}/resp`"

  #leftshm=$(df --block-size=1 | grep /dev/shm | awk '{print $4}')
  #if [ 0${leftshm} -gt 02147483648 ]; then
    imgversion="${VERSION}"
  #else
  #  imgversion="v1.0.1.0"
  #fi

  # alpine-redpill 브랜치는 alpine-redpill 릴리즈 자산만 사용한다.
  imgprefix="alpine-redpill"

  dialog --title "IMG Size Selection" --menu "Select img file size to download:" 10 50 2 \
    "DEFAULT" "Standard 3GB image" \
    "5GB" "Large 5GB image" 2>/tmp/imgsize_selection.txt
  imgsize=$(cat /tmp/imgsize_selection.txt)
  rm -f /tmp/imgsize_selection.txt

  if [ "${imgsize}" = "5GB" ]; then
    imgsuffix="m-shell-5GB"
  else
    imgsuffix="m-shell"
  fi

  echo "Downloading TCRP-mshell ${imgversion} img file..."
  if [ -f /tmp/${imgprefix}.${imgversion}.${imgsuffix}.img ]; then
    echo "TCRP-mshell ${imgversion} img file already exists. Skip download..."
  else
    curl -kL# https://github.com/PeterSuh-Q3/tinycore-redpill/releases/download/${imgversion}/${imgprefix}.${imgversion}.${imgsuffix}.img.gz -o /tmp/${imgprefix}.${imgversion}.${imgsuffix}.img.gz
    gunzip /tmp/${imgprefix}.${imgversion}.${imgsuffix}.img.gz
  fi

  echo "Please wait a moment. Burning ${imgversion} image is in progress..."
  sudo dd if=/tmp/${imgprefix}.${imgversion}.${imgsuffix}.img of=${loaderdev} status=progress bs=4M
  echo "Burning Image ${imgversion} completed, press any key to continue..."
  read answer
  return 0
}

function showsata () {
      MSG=""
      NUMPORTS=0
      [ $(lspci -d ::106 | wc -l) -gt 0 ] && MSG+="\nATA:\n"
      for PCI in $(lspci -d ::106 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        MSG+="\Zb${NAME}\Zn\nPorts: "
        PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
        for P in ${PORTS}; do
        # Skip for Unused Port
          if [ "$(dmesg | grep 'SATA link down' | grep ata$((${P} + 1)): | wc -l)" -eq 0 ]; then          
            DUMMY="$([ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ] && echo 1 || echo 2)"
            if [ "$(cat /sys/class/scsi_host/host${P}/ahci_port_cmd)" = "0" ]; then
              MSG+="\Z1$(printf "%02d" ${P})\Zn "
            else
              if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
                MSG+="\Z2$(printf "%02d" ${P})\Zn "
              else
                MSG+="$(printf "%02d" ${P}) "
              fi
            fi  
          fi
          NUMPORTS=$((${NUMPORTS} + 1))
        done
        MSG+="\n"
      done
      [ $(lspci -d ::107 | wc -l) -gt 0 ] && MSG+="\nLSI:\n"
      for PCI in $(lspci -d ::107 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
        PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
        MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
        NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
      done
      [ $(ls -l /sys/class/scsi_host | grep usb | wc -l) -gt 0 ] && MSG+="\nUSB:\n"
      for PCI in $(lspci -d ::c03 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        PORT=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
        PORTNUM=$(lsscsi -b | grep -v - | grep "\[${PORT}:" | wc -l)
        [ ${PORTNUM} -eq 0 ] && continue
        MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
        NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
      done
      [ $(lspci -d ::108 | wc -l) -gt 0 ] && MSG+="\nNVME:\n"
      for PCI in $(lspci -d ::108 | awk '{print $1}'); do
        NAME=$(lspci -s "${PCI}" | sed "s/\ .*://")
        PORT=$(ls -l /sys/class/nvme | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/nvme//' | sort -n)
        PORTNUM=$(lsscsi -b | grep -v - | grep "\[N:${PORT}:" | wc -l)
        MSG+="\Zb${NAME}\Zn\nNumber: ${PORTNUM}\n"
        NUMPORTS=$((${NUMPORTS} + ${PORTNUM}))
      done
      MSG+="\n"
      MSG+="$(printf "\nTotal of ports: %s\n")" "${NUMPORTS}"
      MSG+="\nPorts with color \Z1red\Zn as DUMMY, color \Z2\Zbgreen\Zn has drive connected."
      dialog --backtitle "$(backtitle)" --colors --title "Show SATA(s) # ports and drives" \
        --msgbox "${MSG}" 0 0
}

function cloneloader() {

  tcrpdev=/dev/$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)
  listusb=()
  listusb+=( $(lsblk -o PATH,ROTA,TRAN | grep '/dev/sd' | grep -v ${tcrpdev} | grep -E '(1 usb|0 sata)' | awk '{print $1}' ) )

  if [ ${#listusb[@]} -eq 0 ]; then 
    echo "No Available USB or SSD, press any key continue..."
    read answer                       
    return 0   
  fi

  dialog --backtitle "`backtitle`" --no-items --colors \
    --menu "Choose a USB Stick or SSD for Clone Loader\n\Z1(Caution!) In the case of SSD, be sure to check whether it is a cache or data disk.\Zn" 0 0 $(dlgmenuheight ${#listusb[@]}) "${listusb[@]}" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp=$(<${TMP_PATH}/resp)
  [ -z "${resp}" ] && return 

  loaderdev="`<${TMP_PATH}/resp`"

  echo "Backup Current TCRP-mshell loader to img file..."  
  sudo dd if=${tcrpdev}1 of=${TMP_PATH}/tinycore-redpill.backup_p1.img status=progress bs=4M
  sudo dd if=${tcrpdev}2 of=${TMP_PATH}/tinycore-redpill.backup_p2.img status=progress bs=4M
  sudo dd if=${tcrpdev}3 of=${TMP_PATH}/tinycore-redpill.backup_p3.img status=progress bs=4M
  
  echo "Please wait a moment. Cloning is in progress..."  
  sudo dd if=${TMP_PATH}/tinycore-redpill.backup_p1.img of=${loaderdev}1 status=progress bs=4M
  sudo dd if=${TMP_PATH}/tinycore-redpill.backup_p2.img of=${loaderdev}2 status=progress bs=4M
  sudo dd if=${TMP_PATH}/tinycore-redpill.backup_p3.img of=${loaderdev}3 status=progress bs=4M
  
  echo "Cloning completed, press any key to continue..."
  read answer
  return 0
}

function add-addon() {

  [ "${1}" = "mac-spoof" ] && echo -n "(Warning) Enabling mac-spoof may compromise San Manager and VMM. Do you still want to add it? [yY/nN] : "
  [ "${1}" = "nvmesystem" ] && echo -n "Would you like to add nvmesystem? [yY/nN] : "
  if [ "${1}" = "vmtools" ]; then 
    if [ "${DMPM}" = "DDSML" ]; then
      echo "vmtools requires EUDEV or DDSML+EUDEV mode. Aborting the add addon."
      echo "press any key to continue..."
      read answer
      return 1
    fi
    echo -n "Would you like to add vmtools? [yY/nN] : "
  fi
  [ "${1}" = "dbgutils" ] && echo -n "Would you like to add dbgutils for error analysis? [yY/nN] : "

  readanswer
  if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then    
    jsonfile=$(jq ". |= .+ {\"${1}\": \"https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/${1}/rpext-index.json\"}" /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json    
    return 0
  else
    return 1
  fi
}

function del-addon() {
  jsonfile=$(jq "del(.[\"${1}\"])" ~/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > ~/redpill-load/bundled-exts.json
}

###############################################################################
# NVIDIA H/W transcoding driver — version selection submenu.
# Writes user's choice to user_config.json (nvidia_driver / nvidia_ffmpeg);
# functions.sh bakes it to /addons/nvidia.conf and install.sh (junior) reads it.
# Auto = leave nvidia_driver unset -> install.sh detects the GPU at boot.
function nvidiaMenu() {
  # $1 = 현재 선택된 모델의 커널버전(예: 5.10.55 / 4.4.302 / 4.4.180),
  # resolveLiveKver 로 호출부(메인 루프)에서 이미 계산해 전달한다. index 의
  # 같은 플랫폼이라도 커널마다 발행 브랜치가 다르므로(커널 4.4 는 550 만)
  # 이 값으로 kernels[$k].drivers 를 우선 조회해야 정확한 목록이 나온다.
  local mykver="${1:-}"
  eval "MSG77=\"\${MSG${tz}77}\""
  eval "MSG78=\"\${MSG${tz}78}\""
  eval "MSG79=\"\${MSG${tz}79}\""
  eval "MSG80=\"\${MSG${tz}80}\""
  eval "MSG81=\"\${MSG${tz}81}\""
  eval "MSG82=\"\${MSG${tz}82}\""
  eval "MSG83=\"\${MSG${tz}83}\""
  eval "MSG84=\"\${MSG${tz}84}\""
  eval "MSG85=\"\${MSG${tz}85}\""
  local RAW="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/nvidiadriver/src"
  local plat="${platform%%(*}" idx=/tmp/nv-index.json sup=/tmp/nv-support.json
  # tcrp-addons 의 nvidia-index.json 과 동일한 해석 규칙: 플랫폼이 커널별
  # 'kernels' 맵을 가지면 그 커널의 drivers 를 쓰고(예: 4.4 계열은 550 만
  # 존재), 없으면(kver5 플랫폼) 기존 평면 drivers 를 그대로 쓴다.
  local DQ='(.platforms[$p].kernels[$k].drivers // .platforms[$p].drivers)'
  curl -skL "${RAW}/nvidia-index.json"       -o "$idx" 2>/dev/null
  curl -skL "${RAW}/nvidia-gpu-support.json" -o "$sup" 2>/dev/null

  # detect NVIDIA GPU on this box (= target for TCRP) via sysfs
  local gpuid=""
  for d in /sys/bus/pci/devices/*; do
    [ "$(cat "$d/vendor" 2>/dev/null)" = "0x10de" ] || continue
    case "$(cat "$d/class" 2>/dev/null)" in 0x0300*|0x0302*)
      gpuid="10de:$(sed 's/^0x//' "$d/device" 2>/dev/null)"; break ;; esac
  done
  local gname="Unknown" branch=""
  if [ -s "$sup" ]; then
    branch=$(jq -r '.default_branch' "$sup" 2>/dev/null)
    [ -n "$gpuid" ] && {
      gname=$(jq -r --arg g "$gpuid" '.gpus[$g].name // "Unknown"' "$sup")
      branch=$(jq -r --arg g "$gpuid" '.gpus[$g].branches[0] // .default_branch' "$sup")
    }
  fi
  local vers=""
  [ -s "$idx" ] && vers=$(jq -r --arg p "$plat" --arg k "$mykver" "$DQ"' | keys | reverse[]' "$idx" 2>/dev/null)
  local autover; autover=$(echo "$vers" | grep "^${branch}" | head -1)

  local LETTERS="abcdefghijklmnopqrstuvwxy"   # z 는 Exit 전용으로 예약
  while true; do
    local cur ffon has
    # bay/VMTOOLS/NVMES 등과 동일한 방식 - 매번 파일을 다시 읽지 않고
    # 시작 시점에 초기화해둔 전역변수(NVIDIA_DRIVER/NVIDIA_FFMPEG/
    # NVIDIA_ENABLED)를 그대로 쓴다. 변경 시에도 이 전역변수를 갱신하고
    # writeConfigKey 로 general.* 에 영구저장한다(아래 dispatch 참고).
    cur="${NVIDIA_DRIVER}"
    ffon="Off"; [ "${NVIDIA_FFMPEG}" = "true" ] && ffon="On"
    # enable/disable 상태만은 전역변수가 아니라 bundled-exts.json 을 직접
    # 본다 - 이 파일이 빌드가 실제로 읽는 곳이라 여기가 진실이고, 전역변수를
    # 믿었다가 둘이 어긋나면 "메뉴엔 ENABLED 인데 빌드엔 누락" 이 된다.
    has="no"
    [ "$(jq 'has("nvidiadriver")' ~/redpill-load/bundled-exts.json 2>/dev/null)" = "true" ] && has="yes"
    NVIDIA_ENABLED="false"; [ "$has" = "yes" ] && NVIDIA_ENABLED="true"

    local autolbl autosel=""
    [ -z "$cur" ] && autosel=" *"
    if [ -n "$gpuid" ]; then
      autolbl="$(printf "${MSG79}" "${gname}" "${gpuid}" "${autover:-none}")${autosel}"
    else
      autolbl="$(printf "${MSG78}" "${branch:-535}")${autosel}"
    fi

    # 문자키를 버전 문자열 자체가 아니라 목록에 오르는 순서대로 a,b,c...
    # 순차 부여(macAddressMenu 와 동일한 방식). kind[] 로 각 항목의 실제
    # 의미(auto/버전 고정값/ffmpeg 토글/enable-disable)를 함께 기록해두고
    # 응답을 받은 뒤 배열을 순회해 매칭한다.
    local -a keys=() labels=() kind=() verval=()
    keys+=("${LETTERS:0:1}"); labels+=("${autolbl}"); kind+=("auto"); verval+=("")
    local v mk sel
    for v in ${vers}; do
      mk=""
      [ -n "$gpuid" ] && [ "$(jq -r --arg g "$gpuid" --arg v "$v" '(.gpus[$g].verified // []) | index($v)' "$sup" 2>/dev/null)" != "null" ] && mk=" (verified)"
      [ -z "$mk" ] && [ -n "$gpuid" ] && [ "$(jq -r --arg g "$gpuid" --arg v "$v" '(.gpus[$g].build_ok // []) | index($v)' "$sup" 2>/dev/null)" != "null" ] && mk=" (build-ok)"
      sel=""; [ "$v" = "$cur" ] && sel=" *"
      keys+=("${LETTERS:${#keys[@]}:1}"); labels+=("${v}${mk}${sel}"); kind+=("ver"); verval+=("$v")
    done
    keys+=("${LETTERS:${#keys[@]}:1}"); labels+=("$(printf "${MSG80}" "${ffon}")"); kind+=("ffmpeg"); verval+=("")
    if [ "$has" = "yes" ]; then
      keys+=("${LETTERS:${#keys[@]}:1}"); labels+=("${MSG81}")
    else
      keys+=("${LETTERS:${#keys[@]}:1}"); labels+=("${MSG82}")
    fi
    kind+=("toggle"); verval+=("")
    # Exit 는 위치와 무관하게 항상 z 고정, 문구도 언어별 MSGID 를 쓰지 않고
    # "Exit" 리터럴로만 표기한다(요청사항).
    keys+=("z"); labels+=("Exit"); kind+=("exit"); verval+=("")

    > "${TMP_PATH}/menun"
    local i=0
    while [ $i -lt ${#keys[@]} ]; do
      echo "${keys[$i]} \"${labels[$i]}\"" >> "${TMP_PATH}/menun"
      i=$((i+1))
    done

    local status
    if [ "$has" = "yes" ]; then
      status="\Z2ENABLED\Zn — $(printf "${MSG84}" "${cur:-Auto}" "${ffon}")"
    else
      status="\Z1DISABLED\Zn — $(printf "${MSG84}" "${cur:-Auto}" "${ffon}")  ${MSG85}"
    fi
    # 표준 OK/Cancel 방식(--no-cancel 미사용) - Cancel 버튼과 ESC 모두
    # 아래 [ $? -ne 0 ] 로 잡혀 상위 메뉴로 복귀한다. 목록 맨 아래 z(Exit)
    # 항목은 같은 동작을 명시적 메뉴 항목으로도 제공한다(가시성 목적).
    # --no-tags 를 빼서 a/b/c...z 태그 열을 화면에 그대로 보여준다. 이걸
    # 켜두면 태그값은 내부적으론 살아있지만 화면엔 안 보이고, 대신 dialog
    # 가 설명 문구의 첫 글자를 임의로 강조 표시해 인덱스가 아예 없는
    # 것처럼 보인다(실측 확인).
    dialog --clear --backtitle "`backtitle`" --colors \
      --menu "${MSG77}\n  ${MSG83}: ${status}" 0 0 \
      $(dlgmenuheight $(wc -l < "${TMP_PATH}/menun")) --file "${TMP_PATH}/menun" \
      2>${TMP_PATH}/respn
    [ $? -ne 0 ] && return
    local r; r=$(<${TMP_PATH}/respn); [ -z "$r" ] && return

    local matched="" i=0
    while [ $i -lt ${#keys[@]} ]; do
      if [ "$r" = "${keys[$i]}" ]; then
        matched="${kind[$i]}"
        case "$matched" in
          # version / Auto / ffmpeg = preference only (user_config); they do
          # NOT change the Status. Only Enable/Disable toggles the addon.
          # 다른 설정들(bay/vmtools/nvmesystem 등)과 동일하게 전역변수를
          # 갱신하고 writeConfigKey 로 general.* 에 영구저장한다.
          auto)   NVIDIA_DRIVER=""; writeConfigKey "general" "nvidia_driver" "${NVIDIA_DRIVER}" ;;
          ver)    NVIDIA_DRIVER="${verval[$i]}"; writeConfigKey "general" "nvidia_driver" "${NVIDIA_DRIVER}" ;;
          ffmpeg) if [ "${NVIDIA_FFMPEG}" = "true" ]; then NVIDIA_FFMPEG="false"; else NVIDIA_FFMPEG="true"; fi
                  writeConfigKey "general" "nvidia_ffmpeg" "${NVIDIA_FFMPEG}" ;;
          toggle) if [ "$has" = "yes" ]; then
                    del-addon "nvidiadriver"; NVIDIA_ENABLED="false"          # Disable
                  else
                    add-addons "nvidiadriver"; NVIDIA_ENABLED="true"         # Enable (stays in submenu to show new Status)
                  fi
                  writeConfigKey "general" "nvidia_enabled" "${NVIDIA_ENABLED}" ;;
          exit)   return ;;
        esac
        break
      fi
      i=$((i+1))
    done
    # exit 항목만 위에서 직접 return 하고, 나머지는 전부 루프 맨 위로
    # 돌아가 같은 하위메뉴를 갱신된 상태로 다시 그린다(요청사항) - 매번
    # 상위 메뉴로 튕겨나가 g 를 다시 눌러야 했던 것을 없앴다.
  done
}

function packing_loader() {

    echo "Would you like to pack your loader for a remote TCRP? [Yy/Nn] "
    readanswer
    if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
        mkdir -p /dev/shm/p1
        mkdir -p /dev/shm/p2
        mkdir -p /dev/shm/p3
        cp -vf /mnt/${loaderdisk}1/GRUB_VER /mnt/${loaderdisk}1/zImage /dev/shm/p1
        cp -vf /mnt/${loaderdisk}2/GRUB_VER /mnt/${loaderdisk}2/zImage /mnt/${loaderdisk}2/rd.gz /mnt/${loaderdisk}2/grub_cksum.syno /dev/shm/p2
        cp -vf /mnt/${loaderdisk}3/custom.gz /mnt/${loaderdisk}3/initrd-dsm /mnt/${loaderdisk}3/rd.gz /mnt/${loaderdisk}3/zImage-dsm /mnt/${loaderdisk}3/user_config.json /dev/shm/p3
        tar -zcvf /home/tc/remote.updatepack.${MODEL}-${BUILD}.tgz -C /dev/shm ./p1 ./p2 ./p3
    else
        echo "OK, the package has been canceled."
    fi    
    returnto "The entire process of packing the boot loader has been completed! Press any key to continue..." && return    

}

function satadom_edit() {
    sed -i "s/synoboot_satadom=[^ ]*/synoboot_satadom=${1}/g" /home/tc/user_config.json
    sudo cp /home/tc/user_config.json /mnt/${tcrppart}/user_config.json
    backuploader
}

function i915_edit() {

  if [ "${I915MODE}" == "1" ]; then
      jsonfile=$(jq '.general.usb_line += " i915.modeset=0 "' /home/tc/user_config.json) && echo $jsonfile | jq . > /home/tc/user_config.json
      jsonfile=$(jq '.general.sata_line += " i915.modeset=0 "' /home/tc/user_config.json) && echo $jsonfile | jq . > /home/tc/user_config.json    
      I915MODE="0"
      DISPLAYI915="Enable" 
  else
      sed -i "s/i915.modeset=0//g" /home/tc/user_config.json  
      I915MODE="1"
      DISPLAYI915="Disable" 
  fi
  
  writeConfigKey "general" "i915mode" "${I915MODE}"
  sudo cp /home/tc/user_config.json /mnt/${tcrppart}/user_config.json  
  backuploader
}

function defaultchange() {

  [ "$(mount | grep /dev/${loaderdisk}1 | wc -l)" -eq 0 ] && mount /dev/${loaderdisk}1
  [ "$(mount | grep /dev/${loaderdisk}2 | wc -l)" -eq 0 ] && mount /dev/${loaderdisk}2

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
    dialog --clear --default-item ${default_item} --backtitle "`backtitle`" --colors \
    --menu "Choose a boot entry" 0 0 $(dlgmenuheight $(wc -l < /${TMP_PATH}/menub2)) --file /${TMP_PATH}/menub2 \
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

function changesatadom() {
  rm -f "${TMP_PATH}/menub"
  {
    echo "0 \"Disable SATA DOM\""
    echo "1 \"Native SATA DOM(SYNO)\""
    echo "2 \"Fake SATA DOM(Redpill)\""
  } >"${TMP_PATH}/menub"
  dialog --clear --default-item "${SATADOM}" --backtitle "`backtitle`" --colors --menu "Choose a mode(Only supported for kernel version 4)" 0 0 $(dlgmenuheight $(wc -l < "${TMP_PATH}/menub")) --file /${TMP_PATH}/menub  2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  resp="$(cat "${TMP_PATH}/resp" 2>/dev/null)"
  [ -z "${resp}" ] && return
  satadom_edit "${resp}"
  
  SATADOM="${resp}"
  if [ "${SATADOM}" = "0" ]; then
    DOMKIND="Disable"
  elif [ "${SATADOM}" = "1" ]; then
    DOMKIND="Native"
  else
    DOMKIND="Fake"
  fi
}

function additional() {

  [ $(cat ~/redpill-load/bundled-exts.json | jq 'has("mac-spoof")') = true ] && spoof="Remove" || spoof="Add"
  [ $(cat ~/redpill-load/bundled-exts.json | jq 'has("dbgutils")') = true ] && dbgutils="Remove" || dbgutils="Add"
  SATADOM=$(jq -r '.general.sata_line | split(" ")[] | select(startswith("synoboot_satadom=")) | ltrimstr("synoboot_satadom=") | .[0:1]' /home/tc/user_config.json)
  if [ "${SATADOM}" = "0" ]; then
    DOMKIND="Disable"
  elif [ "${SATADOM}" = "1" ]; then
    DOMKIND="Native"
  else
    DOMKIND="Fake"
  fi
  
  [ "${I915MODE}" == "1" ] && DISPLAYI915="Disable" || DISPLAYI915="Enable"

  eval "MSG50=\"\${MSG${tz}50}\""
  eval "MSG51=\"\${MSG${tz}51}\""
  eval "MSG53=\"\${MSG${tz}53}\""
  eval "MSG54=\"\${MSG${tz}54}\""
  eval "MSG55=\"\${MSG${tz}55}\""
  eval "MSG11=\"\${MSG${tz}11}\""  
  eval "MSG60=\"\${MSG${tz}60}\""
  eval "MSG61=\"\${MSG${tz}61}\""
  eval "MSG62=\"\${MSG${tz}62}\""
  eval "MSG63=\"\${MSG${tz}63}\""
  eval "MSG121=\"\${MSG${tz}121}\""
  eval "MSG122=\"\${MSG${tz}122}\""
  eval "MSG123=\"\${MSG${tz}123}\""

  default_resp="l"

  while true; do
    [ "${PREVENT_INIT}" = "ON" ] && PREVENT_STATUS="Enabled" || PREVENT_STATUS="Disabled"
    # dtsmapping(구 c) 은 최상위 z(build-pre-option) 하위메뉴 3번 항목으로
    # 이동했다 - 여기서는 제거.
    eval "echo \"l \\\"${MSG60}\\\"\"" > "${TMP_PATH}/menua"
    eval "echo \"a \\\"${spoof} ${MSG50}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"y \\\"${dbgutils} ${MSG121}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"j \\\"$(printf "${MSG122}" "${DOMKIND}") \\\"\"" >> "${TMP_PATH}/menua"
    [ "${platform}" = "geminilake(DT)" ]||[ "${platform}" = "apollolake" ] && eval "echo \"z \\\"$(printf "${MSG123}" "${DISPLAYI915}") \\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"b \\\"${MSG51}: ${PREVENT_STATUS}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"d \\\"${MSG53}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"e \\\"${MSG54}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"f \\\"${MSG55}\\\"\"" >> "${TMP_PATH}/menua"
    [ "$FRKRNL" = "NO" ] && [ "${platform}" != "epyc7002(DT)" ] && [ "${platform}" != "epyc7003ntb(DT)" ] && [ "${platform}" != "epyc7003(DT)" ] && [ "${platform}" != "icelaked(DT)" ] && eval "echo \"h \\\"${MSG61}${SHR_EX_TEXT}\\\"\"" >> "${TMP_PATH}/menua"
    [ "$FRKRNL" = "NO" ] && [ "${platform}" != "epyc7002(DT)" ] && [ "${platform}" != "epyc7003ntb(DT)" ] && [ "${platform}" != "epyc7003(DT)" ] && [ "${platform}" != "icelaked(DT)" ] && eval "echo \"m \\\"${MSG62}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"i \\\"${MSG63}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"k \\\"${MSG11}\\\"\"" >> "${TMP_PATH}/menua"    
    dialog --clear --default-item ${default_resp} --backtitle "`backtitle`" --colors \
      --menu "Choose a option" 0 0 $(dlgmenuheight $(wc -l < "${TMP_PATH}/menua")) --file "${TMP_PATH}/menua" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return

    case `<"${TMP_PATH}/resp"` in
    l) defaultchange; default_resp="l";;
    a) 
      [ "${spoof}" = "Add" ] && add-addon "mac-spoof" || del-addon "mac-spoof"
      [ $(cat ~/redpill-load/bundled-exts.json | jq 'has("mac-spoof")') = true ] && spoof="Remove" || spoof="Add"
      default_resp="a"
      ;;
    y) 
      [ "${dbgutils}" = "Add" ] && add-addon "dbgutils" || del-addon "dbgutils"
      [ $(cat ~/redpill-load/bundled-exts.json | jq 'has("dbgutils")') = true ] && dbgutils="Remove" || dbgutils="Add"
      default_resp="y"
      ;;
    j) changesatadom; default_resp="j";;
    z)
      #[ "$MACHINE" = "VIRTUAL" ] && echo "VIRTUAL Machine is not supported..." && read answer && continue
      i915_edit
      default_resp="z"
      ;;
    b) prevent; default_resp="b";;
    d) viewerrorlog; default_resp="d";;
    e) burnloader; default_resp="e";;
    f) cloneloader; default_resp="f";;
    h) inject_loader && chk_shr_ex; default_resp="h";;
    m) remove_loader && chk_shr_ex; default_resp="m";;
    i) packing_loader; default_resp="i";;
    k) keymapMenu; default_resp="k";;
    *) return;;
    esac
    
  done
}

function synopart() {

  default_resp="a"
  cfg_file="/mnt/${loaderdisk}1/boot/grub/grub.cfg"
  entry_title="menuentry 'Mount Syno BTRFS Vol Rescue (with Tinycore version 9.0)'"

  eval "MSG08=\"\${MSG${tz}08}\""
  eval "MSG09=\"\${MSG${tz}09}\""
  eval "MSG19=\"\${MSG${tz}19}\""
  eval "MSG64=\"\${MSG${tz}64}\""
  eval "MSG12=\"\${MSG${tz}12}\""  
  eval "MSG65=\"\${MSG${tz}65}\""
  eval "MSG66=\"\${MSG${tz}66}\""
  eval "MSG68=\"\${MSG${tz}68}\""
  eval "MSG69=\"\${MSG${tz}124}\""

  while true; do
    eval "echo \"a \\\"${MSG08}\\\"\""                  > "${TMP_PATH}/menuc"
    eval "echo \"b \\\"${MSG09}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"c \\\"${MSG19}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"d \\\"${MSG64}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"e \\\"${MSG12}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"f \\\"${MSG65}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"g \\\"${MSG66}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"h \\\"${MSG68}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"i \\\"${MSG69}\\\"\""                  >> "${TMP_PATH}/menuc"
    dialog --clear --default-item ${default_resp} --backtitle "`backtitle`" --colors \
      --menu "Choose a option" 0 0 $(dlgmenuheight $(wc -l < "${TMP_PATH}/menuc")) --file "${TMP_PATH}/menuc" \
    2>${TMP_PATH}/respc
    [ $? -ne 0 ] && return

    case `<"${TMP_PATH}/respc"` in
    a) changeDSMPassword; default_resp="a" ;;
    b) addNewDSMUser; default_resp="b" ;;
    c) CleanSystemPart clean; default_resp="c" ;;
    d) fixBootEntry; default_resp="d" ;;
    e) formatDisks; default_resp="e";;
    f) mountvol; default_resp="f";;
    g) 
       if ! grep -qF "$entry_title" "$cfg_file"; then
         tinyentry9 | sudo tee --append "$cfg_file"
       fi
       get_tinycore9
       default_resp="g"
       ;;
    h) CleanSystemPart format; default_resp="h" ;;
    i) checkExpandMd0; default_resp="i" ;;
    *) return;;
    esac
    
  done
}

function build-pre-option() {

  # a(selectldrmode), b(seleudev) 는 최상위 메뉴의 k/c 가 여기로 종속된
  # 것이다 - 문구(MSG06/MSG01)는 원래 최상위에서 쓰던 것을 그대로 재사용
  # (MSGID 변경 없음). 최초 진입 시 a(구 k)가 디폴트 인덱스로 선택된다.
  # 나머지 항목(구 b/c/d/e)은 앞으로 두 칸씩 밀려 c/d/e/f 로 재배치.
  default_resp="a"

  MSG64="vmtools(with qemu-guest-agent) addon"

  while true; do
    eval "echo \"a \\\"\${MSG${tz}06} (${drmmode}, ${MDLNAME}:${MLMETHOD})\\\"\""  > "${TMP_PATH}/menud"
    eval "echo \"b \\\"\${MSG${tz}01}, (${DMPM})\\\"\""                          >> "${TMP_PATH}/menud"
    # c(dtsmapping) 는 additional() 메뉴(n) 의 1번 항목이었던 것이 여기 3번
    # 항목으로 옮겨온 것 - 문구(MSG52) 그대로 재사용, MSGID 변경 없음.
    eval "echo \"c \\\"\${MSG${tz}52}\\\"\""                                    >> "${TMP_PATH}/menud"
    # DT (Device-tree) 모델은 sata_remap 미지원 → SataPort remap 메뉴 비노출
    if ! echo "${platform}" | grep -q "(DT)"; then
      eval "echo \"d \\\"\${MSG${tz}56}\\\"\""                                  >> "${TMP_PATH}/menud"
    fi
    eval "echo \"e \\\"\${MSG${tz}41} (${bay})\\\"\""                           >> "${TMP_PATH}/menud"
    eval "echo \"f \\\"${nvmeaction} \${MSG${tz}57}\\\"\""                      >> "${TMP_PATH}/menud"
    eval "echo \"g \\\"${vmtoolsaction} \${MSG64}\\\"\""                       >> "${TMP_PATH}/menud"
    echo "z exit"                                                               >> "${TMP_PATH}/menud"

    dialog --clear --default-item ${default_resp} --backtitle "`backtitle`" --colors \
      --menu "Choose a option" 0 0 $(dlgmenuheight $(wc -l < "${TMP_PATH}/menud")) --file "${TMP_PATH}/menud" \
    2>${TMP_PATH}/respd
    [ $? -ne 0 ] && return

    case `<"${TMP_PATH}/respd"` in
    a) selectldrmode ;    NEXT="z" ;;
    b) seleudev      ;    NEXT="z" ;;
    c) dtsmapping    ;    NEXT="z" ;;
    d) remapsata     ;    NEXT="z" ;;
    e) storagepanel;      NEXT="z" ;;
    f)
      if [ "${NVMES}" = "false" ]; then
        dialog --colors --title "\Z1WARNING - EXPERIMENTAL FEATURE\Zn" --yesno \
          "\Z1\ZbUsing NVMe as a STANDALONE (single) volume is still EXPERIMENTAL and HIGHLY RISKY.\Zn\n\n\
This configuration is NOT officially supported and may cause data loss or boot failure.\n\n\
\Z1\ZbFor a STABLE setup, it is STRONGLY RECOMMENDED to install at least ONE additional SATA disk.\Zn\n\n\
Do you really want to continue enabling nvmesystem?" 0 0
        if [ $? -ne 0 ]; then
          continue
        fi
        if add-addon "nvmesystem"; then
          NVMES="true"
          BLOCK_DDSML="Y"
          DMPM="EUDEV"
        fi
      else
        del-addon "nvmesystem"
        NVMES="false"
        BLOCK_DDSML="N"
        DMPM="DDSML"
      fi
      writeConfigKey "general" "nvmesystem" "${NVMES}"
      writeConfigKey "general" "devmod" "${DMPM}"
      NEXT="z" ;;
    g)
      if [ "${VMTOOLS}" = "false" ]; then
        add-addon "vmtools" && VMTOOLS="true" || VMTOOLS="false"
      else
        del-addon "vmtools" && VMTOOLS="false"
      fi
      writeConfigKey "general" "vmtools" "${VMTOOLS}"
      NEXT="z" ;;
    z) return;;
    *) return;;
    esac

  done

}

function dtsmapping() {
  dts_init
  platform_fix="${platform%(DT)}"
  DTSMODEL="synology_${platform_fix}_${MODEL}"
  COMPATIBLE="Synology"
  OUTPUT_DTS="/home/tc/model.dts"
  main_menu
}

function sortnetif() {
  ETHLIST=""
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) # real network cards list

  # Set ETHX as an array separated by spaces
  set -- ${ETHX}

  # Check the number of arguments
  [ $# -eq 1 ] && return
  
  for ETH in ${ETHX}; do
    MAC="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
    BUSINFO=$(ethtool -i ${ETH} 2>/dev/null | grep bus-info | awk '{print $2}')
    ETHLIST="${ETHLIST}${BUSINFO} ${MAC} ${ETH}\n"
  done
  
  ETHLIST="$(echo -e "${ETHLIST}" | sort)"
  ETHLIST="$(echo -e "${ETHLIST}" | grep -v '^$')"
  
  echo -e "${ETHLIST}" >/tmp/ethlist
  cat /tmp/ethlist
  
  # sort
  IDX=0
  while true; do
    cat /tmp/ethlist
    [ ${IDX} -ge $(wc -l </tmp/ethlist) ] && break
    ETH=$(cat /tmp/ethlist | sed -n "$((${IDX} + 1))p" | awk '{print $3}')
    echo "ETH: ${ETH}"
    if [ -n "${ETH}" ] && [ ! "${ETH}" = "eth${IDX}" ]; then
      echo "change ${ETH} <=> eth${IDX}"
        sudo ip link set dev eth${IDX} down
        sudo ip link set dev ${ETH} down
        sleep 1
        sudo ip link set dev eth${IDX} name tmp
        sudo ip link set dev ${ETH} name eth${IDX}
        sudo ip link set dev tmp name ${ETH}
        sleep 1
        sudo ip link set dev eth${IDX} up
        sudo ip link set dev ${ETH} up
        sleep 1
        sed -i "s/eth${IDX}/tmp/" /tmp/ethlist
        sed -i "s/${ETH}/eth${IDX}/" /tmp/ethlist
        sed -i "s/tmp/${ETH}/" /tmp/ethlist
        sleep 1
    fi
    IDX=$((${IDX} + 1))
  done
  # ── 멀티 NIC default route metric 차등 ────────────────────────────────
  # 기존: eth0 에 단발 udhcpc 만 수행 → DHCP 안 되는 NIC 이 있어도 그 포트로
  #       default route 가 걸려 인터넷이 새는 문제.
  # 개선: 인터페이스별로 개별 DHCP 시도 후, 성공한 NIC 은 낮은 metric(우선
  #       순위 높음), 실패한 NIC 은 높은 metric(우선순위 낮음)을 default
  #       route 에 부여한다. 실패 NIC 은 default route 자체가 없거나 큰
  #       metric 이라 정상 NIC 이 항상 우선 선택된다. (sortnetif 은 NIC 이
  #       2개 이상일 때만 여기까지 도달 — 위에서 단일 NIC 은 early return)
  IDX=0
  for ETH in $(ls /sys/class/net/ 2>/dev/null | grep -E '^eth' | sort); do
    # 재취득 전 해당 NIC 의 stale default route 제거
    while sudo ip route del default dev ${ETH} 2>/dev/null; do :; done
    echo "DHCP request on ${ETH} ..."
    if sudo timeout 12s udhcpc -i ${ETH} -n -q -t 4 -T 2 >/dev/null 2>&1; then
      METRIC=$(( 100 + IDX ))      # 성공 → 우선순위 높음
      STATE="OK"
    else
      METRIC=$(( 1000 + IDX ))     # 실패 → 우선순위 낮음
      STATE="FAIL"
    fi
    # udhcpc 가 추가한 default route 의 gateway 를 읽어 metric 을 재지정.
    # (DHCP 실패 시 gateway 가 없으므로 default route 미생성 = 최저 우선순위)
    GW=$(sudo ip route show default dev ${ETH} 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
    if [ -n "${GW}" ]; then
      while sudo ip route del default dev ${ETH} 2>/dev/null; do :; done
      sudo ip route add default via ${GW} dev ${ETH} metric ${METRIC} 2>/dev/null
      echo "  ${ETH}: DHCP ${STATE} -> default via ${GW} metric ${METRIC} ($([ ${STATE} = OK ] && echo 'priority HIGH' || echo 'priority LOW'))"
    else
      echo "  ${ETH}: DHCP ${STATE} -> no default route (priority LOWEST)"
    fi
    IDX=$(( IDX + 1 ))
  done
  echo "=== resulting default routes (lower metric = preferred) ==="
  sudo ip route show default 2>/dev/null
  rm -f /tmp/ethlist
}

function remapsata() {
  CON=""
  remap=""

  for PCI in $(lspci -d ::106 | awk '{print $1}'); do
    PORTS=$(ls -l /sys/class/scsi_host | grep "${PCI}" | awk -F'/' '{print $NF}' | sed 's/host//' | sort -n)
    for P in ${PORTS}; do
      if [ "$(dmesg | grep 'SATA link down' | grep ata$((${P} + 1)): | wc -l)" -eq 0 ]; then          
        if lsscsi -b | grep -v - | grep -q "\[${P}:"; then
          CON+="$(printf "%d" ${P}) "
        fi
      fi
    done
  done

  #echo $CON

  CON_ARR=($CON)
  PORTS_ARR=($PORTS)
  len=${#CON_ARR[@]}

  for ((i=0; i<$len; i++)); do
    remap+="${CON_ARR[i]}\\\\>${PORTS_ARR[i]}"
    if [ $i -lt $((len-1)) ]; then
      remap+=":"
    fi
  done
  
  #echo $remap
  writeConfigKey "extra_cmdline" "sata_remap" "${remap}"
}

function chk_diskcnt() {

  DISKCNT=0

  # functions.sh 의 $FDISK(Alpine: /sbin/fdisk, TC: 아래 FRKRNL 분기)를 재사용.
  fdisk_path="${FDISK:-/sbin/fdisk}"
  ! is_alpine && [ "$FRKRNL" = "NO" ] && fdisk_path="/usr/local/sbin/fdisk"

  for edisk in $(sudo ${fdisk_path} -l | grep "Disk /dev/sd" | awk '{print $2}' | sed 's/://'); do
    if [ $(sudo ${fdisk_path} -l | grep "83 Linux" | grep ${edisk} | wc -l) -gt 0 ]; then
        continue
    else
        DISKCNT=$((DISKCNT+1))
    fi    
  done

  echo "Disk count: $DISKCNT"

}

function formatDisks() {
  local RESTRICT_DISK=1  # 초기에는 디스크만 표시하도록 제한
  
  while true; do
    rm -f "${TMP_PATH}/opts"
    local KNAME SIZE TYPE VENDOR MODEL SERIAL TRAN
    
    while read -r KNAME SIZE TYPE VENDOR MODEL SERIAL TRAN; do
      [ "${KNAME}" = "N/A" ] || [ "${SIZE:0:1}" = "0" ] && continue
      [ "${KNAME:0:7}" = "/dev/md" ] && continue
      [ "${KNAME:0:9}" = "/dev/loop" ] && continue
      [ "${KNAME:0:9}" = "/dev/zram" ] && continue
      [[ "${KNAME}" == "/dev/${loaderdisk}"* ]] && continue
      
      # RESTRICT_DISK가 1이면 디스크만 표시, 0이면 모든 장치 표시
      if [ ${RESTRICT_DISK} -eq 1 ] && [ "${TYPE}" != "disk" ]; then
        continue
      fi
      
      printf "\"%s\" \"%-6s %-4s %s %s %s %s %s\" \"off\"\n" "${KNAME}" "${SIZE}" "${TYPE}" "${SERIAL}" "${TRAN}" "${VENDOR}" "${MODEL}" >>"${TMP_PATH}/opts"
    done <<<"$(lsblk -Jpno KNAME,SIZE,TYPE,VENDOR,MODEL,SERIAL,TRAN 2>/dev/null | sed 's|null|"N/A"|g' | jq -r '.blockdevices[] | "\(.kname) \(.size) \(.type) \(.vendor) \(.model) \(.serial) \(.tran)"' 2>/dev/null | sort)"
    
    # 제한 해제 옵션 추가
    if [ ${RESTRICT_DISK} -eq 1 ]; then
      echo "\"Release-disk-restriction\" \"Show all disks and partitions\" \"off\"" >> "${TMP_PATH}/opts"
    fi
    
    if [ ! -f "${TMP_PATH}/opts" ]; then
      dialog --title "Format Disks" --msgbox "No disk found!" 0 0
      return
    fi
    
    # 제한 상태에 따른 제목 변경
    if [ ${RESTRICT_DISK} -eq 1 ]; then
      TITLE="Select Disks (To release, select Release-disk-restriction and click OK)"
    else
      TITLE="Select Disks/Partitions"
    fi
    
    dialog --title "Format Disks" \
      --checklist "${TITLE}" 0 0 $(dlgmenuheight $(wc -l < "${TMP_PATH}/opts")) --file "${TMP_PATH}/opts" \
      2>"${TMP_PATH}/format_resp"
    
    [ $? -ne 0 ] && return
    resp="$(cat "${TMP_PATH}/format_resp" 2>/dev/null)"
    [ -z "${resp}" ] && return
    
    # 제한 해제 옵션이 선택되었는지 확인
    if echo "${resp}" | grep -q "Release-disk-restriction"; then
      RESTRICT_DISK=0
      # Release-disk-restriction을 응답에서 제거
      resp=$(echo "${resp}" | sed 's/Release-disk-restriction//g' | sed 's/  / /g' | sed 's/^ *//g' | sed 's/ *$//g')
      # 아무것도 선택되지 않았으면 다시 메뉴로
      [ -z "${resp}" ] && continue
    fi
    
    # 실제 장치가 선택되었으면 포맷 진행
    if [ -n "${resp}" ]; then
      break
    fi
  done
  
  # 포맷 확인 및 실행
  dialog --title "Format Disks" --yesno "Warning:\nThis operation is irreversible. Please backup important data. Do you want to continue?" 0 0
  [ $? -ne 0 ] && return
  
  for I in ${resp}; do
    if [ "${I:0:8}" = "/dev/mmc" ]; then
      sudo mkfs.ext4 -F -T largefile4 -E nodiscard "${I}"
    else
      sudo mkfs.ext4 -F -T largefile4 "${I}"
    fi
  done 2>&1 | dialog --title "Format Disks" --progressbox "Formatting ..." 20 100
  dialog --title "Format Disks" --msgbox "Formatting is complete." 0 0
  return
}

function chk_shr_ex()
{
  [ $(/sbin/blkid | grep "1234-5678" | wc -l) -eq 1 ] && SHR_EX_TEXT=" (Existence)" || SHR_EX_TEXT=""
}

select_and_run_menu() {

    local MEM_MB
    MEM_MB=$(cat /proc/meminfo | grep MemTotal | awk '{printf "%.0f", $2 / 1000}')

    # 6094 >= 6GB 판단
    local MIN_MB=6094

    # ucode 기반 언어 설정 먼저 해서 메시지 분기에 사용
    if [ "${ucode}" = "ko_KR" ]; then
        local LANG_KR=true
    else
        local LANG_KR=false
    fi

    if [ "$MEM_MB" -lt "$MIN_MB" ]; then
        eval "MSG125=\"\${MSG${tz}125}\""
        eval "MSG126=\"\${MSG${tz}126}\""
        eval "MSG35=\"\${MSG${tz}35}\""
        echo "${MSG125}"
        echo "$(printf "${MSG126}" "${MEM_MB}")"
        echo -n "${MSG35}"
        # 아무 키 입력 대기
        read -r -n1 _
        echo
        return
    fi
    
    # TAG / DATE / DESC_EN / DESC_KR
    local TAGS=(
        "v1.2.9.2" "2026-05-01" "Supports Insyde BIOS-based models in lkm"                            "lkm에서 Insyde BIOS 기반 모델 지원"
        "v1.2.9.1" "2026-04-19" "Correct display of HBA disk firmware version in Disk Manager"        "디스크 관리자 HBA 디스크 펌웨어 버전 정상 표시"
        "v1.2.9.0" "2026-04-14" "HBA controller support begins on geminilake, r1000, v1000"           "Geminilake, R1000, V1000 HBA 컨트롤러 지원 시작"    
        "v1.2.8.9" "2026-04-12" "Separating and stabilizing lkm by platform and DSM ver"              "플랫폼 및 DSM 버전에 따른 lkm 분리 및 안정화"
        "v1.2.8.8" "2026-04-03" "Fixed missing firmware inclusion in PML method"                      "PML 메서드에서 펌웨어 포함이 누락된 문제를 수정"
        "v1.2.8.7" "2026.03.28" "Change loading method for the last Junior Grub boot entry"           "비활성화된 Junior Grub 부팅 항목의 로딩 방식을 변경"
        "v1.2.8.6" "2026-03-25" "Added menu to block automatic updates for TCB / FKC"                 "TCB/FKC 자동 업데이트를 차단하는 메뉴를 추가"    
        "v1.2.8.5" "2026-03-24" "Added menu to revert to previous version build"                      "이전 버전으로 되돌리는 메뉴를 추가"    
        "v1.2.8.4" "2026-03-20" "Supports two distinct menus for IML / PML module loading"            "IML / PML 두 가지 모듈 로딩 메뉴 지원"
        "v1.2.8.3" "2026-03-19" "Added user DTS file mapping feature"                                 "사용자 DTS 파일 매핑 기능 추가"
        "v1.2.8.2" "2026-03-19" "Switch all-modules loading from dynamic to static (like RR/ARC)"     "all-modules 로딩 방식 dynamic→static 전환"
        "v1.2.8.0" "2026-03-15" "Discontinued Jot, standardized to Direct-Boot"                       "Jot 용어 폐기, Direct-Boot으로 표준화"
        "v1.2.7.9" "2026-03-10" "Switch initrd-dsm compression from zstd to xz(lzma2)"                "initrd-dsm 압축 방식 zstd→xz(lzma2) 변경"
        "v1.2.7.8" "2026-03-08" "Support RS18016xs+ (bromolow DSM 7.3.x) and Traditional Chinese"     "RS18016xs+ (bromolow DSM 7.3.x) 및 번체중국어 지원"
        "v1.2.7.7" "2026-03-06" "Use static firmware and module loading for custom modules"           "custom modules 사용 시 static 펌웨어/모듈 로딩"
    )

    # 컬럼 수 (tag / date / desc_en / desc_kr)
    local COLS=4
    local MENU_ITEMS=()
    local i=1

    for (( j=0; j<${#TAGS[@]}; j+=COLS )); do
        local tag="${TAGS[$j]}"
        local date="${TAGS[$j+1]}"
        local desc_en="${TAGS[$j+2]}"
        local desc_kr="${TAGS[$j+3]}"

        if [ "${LANG_KR}" = true ]; then
            local label="[${date}] ${desc_kr}"
        else
            local label="[${date}] ${desc_en}"
        fi

        MENU_ITEMS+=("$i" "${tag}  ${label}")
        (( i++ ))
    done

    # 타이틀/프롬프트 언어 분기
    if [ "${LANG_KR}" = true ]; then
        local TITLE="TCRP 릴리즈 태그 선택"
        local PROMPT="실행할 릴리즈 태그를 선택하세요:"
        local MSG_CANCEL="취소되었습니다."
        local MSG_RUN="menu.sh 실행 중..."
    else
        local TITLE="TCRP Release Tag Selection"
        local PROMPT="Select a release tag to run:"
        local MSG_CANCEL="Cancelled."
        local MSG_RUN="Running menu.sh ..."
    fi

    local CHOICE
    CHOICE=$(dialog --clear \
        --title "${TITLE}" \
        --menu "${PROMPT}" 28 90 20 \
        "${MENU_ITEMS[@]}" \
        2>&1 >/dev/tty)

    local EXIT_CODE=$?
    clear

    if [ $EXIT_CODE -ne 0 ] || [ -z "$CHOICE" ]; then
        echo "${MSG_CANCEL}"
        return 1
    fi

    local IDX=$(( (CHOICE - 1) * COLS ))
    local SELECTED_TAG="${TAGS[$IDX]}"

    echo ">>> ${SELECTED_TAG}  ${MSG_RUN}"
    if is_alpine; then
        # X11 유지 + lxterminal 로 urxvt 대체
        lxterminal --geometry=78x32+10+0 --title="TCRP-mshell Menu" --command="/home/tc/menu.sh ${SELECTED_TAG}"
        return 0
    fi
    urxvt -geometry 78x32+10+0 -fg orange -title \"TCRP-mshell urxvt Menu\" -e /home/tc/menu.sh "${SELECTED_TAG}"
}

function addon_gitdown()
{
# add git download 2023.10.18
# Improved: timeout / retry / mirror-rotation 2025.06.09
 
  local MAX_RETRY=4          # 최대 재시도 횟수 (미러 × 2)
  local HARD_TIMEOUT=90      # git clone 최대 허용 시간(초) - 이 시간 초과 시 강제 중단
  local LOW_SPEED=1024       # 저속 판정 임계값 (bytes/sec)
  local LOW_SPEED_TIME=20    # 저속 지속 허용 시간(초) - 이 속도 미만 지속 시 중단
  local WAIT_SEC=5           # 재시도 간 대기 시간(초)
 
  # 미러 목록: 순서대로 번갈아 시도
  local mirrors=(
    "https://github.com/PeterSuh-Q3/tcrp-addons.git"
  )
  local mirror_count=${#mirrors[@]}
 
  rm -rf /dev/shm/tcrp-addons
  mkdir -p /dev/shm/tcrp-addons
 
  local attempt mirror_idx mirror ret
  for (( attempt=1; attempt<=MAX_RETRY; attempt++ )); do
 
    # 시도 횟수에 따라 미러를 순환 (0→GitHub, 1→Gitea, 2→GitHub, ...)
    mirror_idx=$(( (attempt - 1) % mirror_count ))
    mirror="${mirrors[$mirror_idx]}"
 
    echo "[addon_gitdown] Attempt ${attempt}/${MAX_RETRY} → ${mirror}"
 
    # GIT_HTTP_LOW_SPEED_*: 지정 속도 미만이 지정 시간 이상 지속되면 중단
    # timeout: 전체 작업 최대 시간 하드 캡
    GIT_HTTP_LOW_SPEED_LIMIT=${LOW_SPEED} \
    GIT_HTTP_LOW_SPEED_TIME=${LOW_SPEED_TIME} \
      timeout ${HARD_TIMEOUT} \
      git clone --depth 1 --filter=blob:none "${mirror}" /dev/shm/tcrp-addons
    ret=$?
 
    if [ ${ret} -eq 0 ]; then
      echo "[addon_gitdown] Download succeeded on attempt ${attempt}."
      return 0
    fi
 
    # timeout(124) 또는 git 오류 구분 메시지
    if [ ${ret} -eq 124 ]; then
      echo "[addon_gitdown] Attempt ${attempt} timed out after ${HARD_TIMEOUT}s."
    else
      echo "[addon_gitdown] Attempt ${attempt} failed (exit=${ret})."
    fi
 
    # 다음 시도 전 임시 디렉터리 초기화
    rm -rf /dev/shm/tcrp-addons
    mkdir -p /dev/shm/tcrp-addons
 
    if [ ${attempt} -lt ${MAX_RETRY} ]; then
      echo "[addon_gitdown] Waiting ${WAIT_SEC}s before next attempt..."
      sleep ${WAIT_SEC}
    fi
  done
 
  echo "[addon_gitdown] !! All ${MAX_RETRY} attempts failed. Check network and retry."
  return 1
}

# ON/OFF 라벨 반환
function getLabel() {
  [ "$1" = "true" ] && echo "ON" || echo "OFF"
}

# ─── 메인 메뉴 함수 ──────────────────────────────────────────────
function showAutoUpdateMenu() {

  eval "MSG109=\"\${MSG${tz}109}\""
  eval "MSG110=\"\${MSG${tz}110}\""
  eval "MSG111=\"\${MSG${tz}111}\""
  eval "MSG112=\"\${MSG${tz}112}\""
  eval "MSG113=\"\${MSG${tz}113}\""
  eval "MSG114=\"\${MSG${tz}114}\""
  eval "MSG115=\"\${MSG${tz}115}\""
  eval "MSG116=\"\${MSG${tz}116}\""
  eval "MSG117=\"\${MSG${tz}117}\""
  eval "MSG118=\"\${MSG${tz}118}\""
  eval "MSG119=\"\${MSG${tz}119}\""
  eval "MSG120=\"\${MSG${tz}120}\""
  eval "MSG127=\"\${MSG${tz}127}\""
  eval "MSG128=\"\${MSG${tz}128}\""
  eval "MSG129=\"\${MSG${tz}129}\""
  eval "MSG130=\"\${MSG${tz}130}\""

  # 누락 시 기본값 ON
  [[ "$TCB" != "true" && "$TCB" != "false" ]] && TCB="true"
  [[ "$FKC" != "true" && "$FKC" != "false" ]] && FKC="true"

  while true; do
    local TCB_LABEL FKC_LABEL CHOICE EXIT_CODE
    TCB_LABEL=$(getLabel "$TCB")
    FKC_LABEL=$(getLabel "$FKC")

    CHOICE=$(dialog \
      --clear \
      --backtitle "${MSG109}" \
      --title "${MSG127}" \
      --ok-label "${MSG128}" \
      --cancel-label "${MSG129}" \
      --menu "\n${MSG130}\n" \
      14 60 4 \
      "a" "${MSG110}  [ ${TCB_LABEL} ]" \
      "b" "${MSG111}    [ ${FKC_LABEL} ]" \
      "c" "${MSG112}" \
      "d" "${MSG113}" \
      3>&1 1>&2 2>&3)

    EXIT_CODE=$?

    # Save & Exit (Cancel 버튼 또는 ESC)
    if [ ${EXIT_CODE} -ne 0 ]; then
      writeConfigKey "general" "tcbautoupd"    "${TCB}"
      writeConfigKey "general" "friendautoupd" "${FKC}"
      dialog --infobox "${MSG114}" 3 25
      sleep 1
      backuploader
      clear
      return 0
    fi

    # 토글 처리 → 즉시 파일에 반영
    case "${CHOICE}" in
      a)
        [ "$TCB" = "true" ] && TCB="false" || TCB="true"
        writeConfigKey "general" "tcbautoupd" "${TCB}"
        ;;
      b)
        [ "$FKC" = "true" ] && FKC="false" || FKC="true"
        writeConfigKey "general" "friendautoupd" "${FKC}"
        ;;
      c)
        getlatestmshell "noask"
        local retval=$?
        case $retval in
          0)
            dialog --msgbox "${MSG115}" 6 40
            ;;
          1)
            dialog --msgbox "\n${MSG116}" 9 50
            clear
            sudo reboot
            ;;
          2)
            dialog --msgbox "${MSG117}" 6 40
            ;;
          3)
            dialog --msgbox "$(printf "${MSG118}" "$retval")" 7 45
            ;;
        esac
        ;;
      d)
        bringoverfriend
        local retval=$?
        case $retval in
          0)
            dialog --msgbox "${MSG115}" 6 40
            ;;
          1)
            dialog --msgbox "${MSG119}" 9 50
            ;;
          2|3)
            dialog --msgbox "$(printf "${MSG120}" "$retval")" 7 45
            ;;
        esac
        ;;
    esac  # ← 이 `case "${CHOICE}"` 의 종료
  done    # ← 이 `while true` 의 종료
}

# Main loop ###########################################################################################

# Fix bug /opt/bootlocal.sh ownership 2025.09.15
# Alpine엔 이 TC 전용 부팅훅 파일이 없음(대신 /etc/local.d/*.start 사용) → 존재할 때만.
[ -f /opt/bootlocal.sh ] && sudo chown tc:118 /opt/bootlocal.sh

chk_diskcnt
writeConfigKey "general" "diskcount" "${DISKCNT}"
CHKDISK=$(readConfigKey "general" "check_diskcnt")
[ -z "${CHKDISK}" ] && writeConfigKey "general" "check_diskcnt" "false"

# add git download 2023.10.18
addon_gitdown

#if [ -d /dev/shm/tcrp-modules ]; then
#  echo "tcrp-modules already downloaded!"    
#else    
#  git clone --depth=1 "https://github.com/PeterSuh-Q3/tcrp-modules.git"
#  if [ $? -ne 0 ]; then
#    git clone --depth=1 "https://gitea.com/PeterSuh-Q3/tcrp-modules.git"
#  fi    
#fi
cd /home/tc

#Start Locale Setting process
#Get Langugae code & country code
echo "current ucode = ${ucode}"

config_ucode="${ucode}"

# ipinfo.io 는 http→https 301 리다이렉트하므로 https 로 직접 조회한다.
# (기존 http 요청은 301 빈 본문이 와서 country 가 비어버려, lcode 와
#  불일치로 판정되어 ko_KR 처럼 이미 일치하는 언어에서도 오프롬프트 발생)
country=$(curl -s -m 8 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]')

if [ -z "${ucode}" ]; then
  # 저장된 언어가 없으면(최초 실행) 감지된 국가를 채택
  [ -n "${country}" ] && lcode="${country}"
elif [ "${ucode}" = "en_US" ]; then
  # 기본값(en_US)일 때만 변경 여부를 묻는다. 유효한 다른 국가가 감지된 경우만.
  # 무입력 시 N 으로 넘어가 en_US 가 그대로 유지된다.
  if [ -n "${country}" ] && [ "${lcode}" != "${country}" ]; then
    answer=""
    read_with_timeout "Country code ${country} has been detected. Do you want to change your locale settings to ${country}? [yY/nN] : " answer "N"
    if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then
      lcode="${country}"
    fi
  fi
fi
# ucode 가 이미 en_US 가 아닌 특정 언어(예: ko_KR)면 그대로 존중 → 프롬프트 없음

tz="${lcode}"

case "${lcode}" in
US) ucode="en_US";;
KR) ucode="ko_KR";;
JP) ucode="ja_JP";;
CN) ucode="zh_CN";;
TW) ucode="zh_TW";;
RU) ucode="ru_RU";;
FR) ucode="fr_FR";;
DE) ucode="de_DE";;
ES) ucode="es_ES";;
IT) ucode="it_IT";;
BR) ucode="pt_BR";;
EG) ucode="ar_EG";;
IN) ucode="hi_IN";;
HU) ucode="hu_HU";;
ID) ucode="id_ID";;
TR) ucode="tr_TR";;

*) lcode="US"; ucode="en_US";;
esac
writeConfigKey "general" "ucode" "${ucode}"

echo "current lcode = ${lcode}"

if [ -f ~/.dialogrc ]; then
  sed -i "s/screen_color = (CYAN,GREEN,ON)/screen_color = (CYAN,BLUE,ON)/g" ~/.dialogrc
else
  echo "screen_color = (CYAN,BLUE,ON)" > ~/.dialogrc
fi


# Alpine 이식: gettext는 이미 apk 매핑에서 설치되지만, 이 블록은 TC 전용
# onboot.lst/cde 파티션 영속화 + backuploader+restart(재부팅)까지 포함하는
# TinyCore 고유 흐름이라 is_alpine이면 skip. 실측 발견(2026-07-12): 가드
# 누락으로 tce-load shim이 gettext apk 설치를 성공시켜 exit 0 -> 조건 충족
# -> 불필요한 backuploader+재부팅이 실제로 발생함(menu.sh 대화형 실행 중 확인).
if ! is_alpine && [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep gettext | wc -w) -eq 0 ]; then
    tce-load -wi gettext
    if [ $? -eq 0 ]; then
        echo "Download gettext.tcz OK, Permanent installation progress !!!"
        sudo cp -f /tmp/tce/optional/* /mnt/${tcrppart}/cde/optional
        sudo echo "" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "gettext.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "ncursesw.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        backuploader
        echo "You have finished installing TC gettext package."
        restart
     fi
fi

#if [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep dejavu-fonts-ttf | wc -w) -eq 0 ]; then
#    tce-load -wi dejavu-fonts-ttf notosansdevanagari-fonts-ttf setfont
#    if [ $? -eq 0 ]; then
#        echo "Download dejavu-fonts-ttf.tcz, notosansdevanagari-fonts-ttf, setfont OK, Permanent installation progress !!!"
#        sudo cp -f /tmp/tce/optional/* /mnt/${tcrppart}/cde/optional
#        sudo echo "" >> /mnt/${tcrppart}/cde/onboot.lst
#        sudo echo "dejavu-fonts-ttf.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
#        sudo echo "notosansdevanagari-fonts-ttf.tcz" >> /mnt/${tcrppart}/cde/onboot.lst     
#        sudo echo "setfont.tcz" >> /mnt/${tcrppart}/cde/onboot.lst     
#        backuploader
#        echo "You have finished installing TC dejavu-fonts-ttf package."
#        restart
#     fi
#fi

# Alpine 이식: glibc_apps/glibc_i18n_locale/unifont/rxvt(tcz) 대신 apk lxterminal +
# musl-locales 설치. lxterminal은 Pango+fontconfig로 CJK를 렌더링해 glibc 로케일이
# 불필요 (X11 자체는 유지, urxvt만 교체).
if is_alpine; then
    sudo apk add lxterminal musl-locales musl-locales-lang xorg-server mesa-dri-gallium mesa-gl mesa-egl mesa-gbm >/dev/null 2>&1
    echo "lxterminal + musl-locales installed (urxvt replacement)."
fi

if ! is_alpine && [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep rxvt | wc -w) -eq 0 ]; then
    tce-load -wi glibc_apps glibc_i18n_locale unifont rxvt
    if [ $? -eq 0 ]; then
        echo "Download glibc_apps.tcz and glibc_i18n_locale.tcz OK, Permanent installation progress !!!"
        sudo cp -f /tmp/tce/optional/* /mnt/${tcrppart}/cde/optional
        sudo echo "" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "glibc_apps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "glibc_i18n_locale.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "unifont.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "rxvt.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        backuploader

        echo
        echo "You have finished installing TC Unicode package and urxvt."
        restart
    else
        echo "Download glibc_apps.tcz, glibc_i18n_locale.tcz FAIL !!!"
    fi
fi

# for 2Byte Language
[ ! -d /usr/lib/locale ] && sudo mkdir /usr/lib/locale

# Alpine: ~/.Xdefaults의 URxvt.* 리소스 설정과 localedef(glibc 전용)는 lxterminal에는
# 적용되지 않으므로(GTK 설정은 ~/.config/lxterminal/lxterminal.conf) 전체 skip.
if ! is_alpine && [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep rxvt | wc -w) -gt 0 ]; then

  sudo localedef -c -i ${ucode} -f UTF-8 ${ucode}.UTF-8
  sudo localedef -f UTF-8 -i ${ucode} ${ucode}.UTF-8

  if [ $(cat ~/.Xdefaults|grep "URxvt.background: black" | wc -w) -eq 0 ]; then
    echo "URxvt.background: black"  >> ~/.Xdefaults
  fi
  if [ $(cat ~/.Xdefaults|grep "URxvt.foreground: white" | wc -w) -eq 0 ]; then    
    echo "URxvt.foreground: white"  >> ~/.Xdefaults
  fi
  if grep -q "^URxvt.transparent:" ~/.Xdefaults; then
    sed -i 's/^URxvt.transparent:.*/URxvt.transparent: false/' ~/.Xdefaults
  else
    echo "URxvt.transparent: false" >> ~/.Xdefaults
  fi
  if [ $(cat ~/.Xdefaults|grep "URxvt\*encoding: UTF-8" | wc -w) -eq 0 ]; then    
    echo "URxvt*encoding: UTF-8"  >> ~/.Xdefaults
  else
    sed -i "/URxvt\*encoding:/d" ~/.Xdefaults
    echo "URxvt*encoding: UTF-8"  >> ~/.Xdefaults  
  fi
  if [ $(cat ~/.Xdefaults|grep "URxvt\*inputMethod: ibus" | wc -w) -eq 0 ]; then    
    echo "URxvt*inputMethod: ibus"  >> ~/.Xdefaults
  fi
  if [ $(cat ~/.Xdefaults|grep "URxvt\*locale:" | wc -w) -eq 0 ]; then    
    echo "URxvt*locale: ${ucode}.UTF-8"  >> ~/.Xdefaults
  else
    sed -i "/URxvt\*locale:/d" ~/.Xdefaults
    echo "URxvt*locale: ${ucode}.UTF-8"  >> ~/.Xdefaults
  fi
fi

export LANG=${ucode}.UTF-8
export LC_ALL=${ucode}.UTF-8
set -o allexport


#gettext
[ ! -f /home/tc/lang.tgz ] && curl -kLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/lang.tgz > /dev/null 2>&1
[ ! -d "/usr/local/share/locale" ] && sudo mkdir -p "/usr/local/share/locale"
gunzip -c lang.tgz | sudo tar -xvf - -C /usr/local/share/locale > /dev/null 2>&1
locale > /dev/null 2>&1
#End Locale Setting process
export TEXTDOMAINDIR="/usr/local/share/locale"
set -o allexport
tz="ZZ"
load_zz

if [ "$FRKRNL" = "NO" ] && [ "${ucode}" != "${config_ucode}" ]; then
  # 언어 변경 감지 시: 새 urxvt 창을 덧띄우지 않고 현재 창(이미 UTF-8 +
  # unifont 폴백으로 CJK 렌더 가능)에서 exec 로 프로세스를 교체한다.
  # 새 LANG/LC_ALL 로 menu.sh 가 fresh 재시작되어 gettext 카탈로그가
  # 새 언어로 로드되고, 창은 단일 유지되어 창 누적(trick) 이 사라진다.
  # 단, X(urxvt) 안에서 실행 중일 때만 exec; 아니면 기존 urxvt 방식 폴백.
  if [ -n "${DISPLAY:-}" ] && [ -n "${WINDOWID:-}" ]; then
    exec /home/tc/menu.sh
  else
    urxvt -geometry 78x32+10+0 -fg orange -title "TCRP-mshell urxvt Menu" -e /home/tc/menu.sh
  fi
fi

# Download ethtool
# tce-load(shim)는 Alpine에서도 apk로 정상 설치하므로 유지, onboot.lst(TC 전용
# cde 파티션 기록)만 skip.
if [ "$FRKRNL" = "NO" ] && [ "$(which ethtool)_" == "_" ]; then
   echo "ethtool does not exist, install from tinycore"
   tce-load -iw ethtool iproute2 2>&1 >/dev/null
   if ! is_alpine; then
     sudo echo "ethtool.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
     sudo echo "iproute2.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
   fi
fi

sortnetif

# Alpine엔 onboot.lst 자체가 없어 grep이 항상 0을 반환해 자연히 비활성화되지만
# backuploader+restart(재부팅)를 포함하므로 명시적으로도 가드.
if ! is_alpine && [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep "kmaps.tczglibc_apps.tcz" | wc -w) -gt 0 ]; then
    sudo sed -i "/kmaps.tczglibc_apps.tcz/d" /mnt/${tcrppart}/cde/onboot.lst    
    sudo echo "glibc_apps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
    sudo echo "kmaps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
    backuploader
    
    echo
    echo "We have finished bug fix for /mnt/${tcrppart}/cde/onboot.lst."
    restart
fi    


# Get actual IP
IP="$(/sbin/ifconfig | grep -i "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -c 6- )"

if [ -z "${MACADDR1}" ]; then
    MACADDR1=$(./macgen.sh "realmac" "eth0" "${MODEL}")
    writeConfigKey "extra_cmdline" "mac1" "${MACADDR1}"
fi

if [ $(/sbin/ifconfig | grep eth1 | wc -l) -gt 0 ]; then
    MACADDR2=$(readConfigKey "extra_cmdline" "mac2")
    NETNUM="2"
    if [ -z "${MACADDR2}" ]; then
        MACADDR2=$(./macgen.sh "realmac" "eth1" "${MODEL}")
        writeConfigKey "extra_cmdline" "mac2" "${MACADDR2}"
    fi
fi

if [ $(/sbin/ifconfig | grep eth2 | wc -l) -gt 0 ]; then
    MACADDR3=$(readConfigKey "extra_cmdline" "mac3")
    NETNUM="3"
    if [ -z "${MACADDR3}" ]; then
        MACADDR3=$(./macgen.sh "realmac" "eth2" "${MODEL}")
        writeConfigKey "extra_cmdline" "mac3" "${MACADDR3}"
    fi
fi

if [ $(/sbin/ifconfig | grep eth3 | wc -l) -gt 0 ]; then
    MACADDR4=$(readConfigKey "extra_cmdline" "mac4")
    NETNUM="4"
    if [ -z "${MACADDR4}" ]; then
        MACADDR4=$(./macgen.sh "realmac" "eth3" "${MODEL}")
        writeConfigKey "extra_cmdline" "mac4" "${MACADDR4}"
    fi
fi

if [ $(/sbin/ifconfig | grep eth4 | wc -l) -gt 0 ]; then
    MACADDR5=$(readConfigKey "extra_cmdline" "mac5")
    NETNUM="5"
    if [ -z "${MACADDR5}" ]; then
        MACADDR5=$(./macgen.sh "realmac" "eth4" "${MODEL}")
        writeConfigKey "extra_cmdline" "mac5" "${MACADDR5}"
    fi
fi

if [ $(/sbin/ifconfig | grep eth5 | wc -l) -gt 0 ]; then
    MACADDR6=$(readConfigKey "extra_cmdline" "mac6")
    NETNUM="6"
    if [ -z "${MACADDR6}" ]; then
        MACADDR6=$(./macgen.sh "realmac" "eth5" "${MODEL}")
        writeConfigKey "extra_cmdline" "mac6" "${MACADDR6}"
    fi
fi

if [ $(/sbin/ifconfig | grep eth6 | wc -l) -gt 0 ]; then
    MACADDR7=$(readConfigKey "extra_cmdline" "mac7")
    NETNUM="7"
    if [ -z "${MACADDR7}" ]; then
        MACADDR7=$(./macgen.sh "realmac" "eth6" "${MODEL}")
        writeConfigKey "extra_cmdline" "mac7" "${MACADDR7}"
    fi
fi

if [ $(/sbin/ifconfig | grep eth7 | wc -l) -gt 0 ]; then
    MACADDR8=$(readConfigKey "extra_cmdline" "mac8")
    NETNUM="8"
    if [ -z "${MACADDR8}" ]; then
        MACADDR8=$(./macgen.sh "realmac" "eth7" "${MODEL}")
        writeConfigKey "extra_cmdline" "mac8" "${MACADDR8}"
    fi
fi

CURNETNUM=$(readConfigKey "extra_cmdline" "netif_num")

if [ $CURNETNUM != $NETNUM ]; then
  if [ $NETNUM -ge 1 ] && [ $NETNUM -le 8 ]; then
    for i in $(seq 8 -1 $((NETNUM + 1))); do
      DeleteConfigKey "extra_cmdline" "mac$i"
    done
  else
    echo "NETNUM must be between 1 and 8."
    exit 1
  fi
  writeConfigKey "extra_cmdline" "netif_num" "$NETNUM"
fi

checkmachine
checkcpu

echo  "download original pats.json file..."
[ -f /tmp/test_mode ] && VERBOSE_MODE=ON
if { [[ "$MACHINE" = "VIRTUAL" && "$HYPERVISOR" = "KVM" ]] || [ -f /tmp/test_mode ]; }; then
  curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/config/pats_t.json -o $configfile
else
  curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/config/pats.json -o $configfile
fi
# mirror the persistent copy into redpill-load/config for the loader build
[ -s "$configfile" ] && [ -d /home/tc/redpill-load/config ] && cp -f "$configfile" "$configfile_loader"

if [ $tcrppart == "mmc3" ]; then
    tcrppart="mmcblk0p3"
fi    

# Download dialog
if is_alpine; then
    # apk dialog로 직접 설치 - TC .tcz/cde/optional 다운로드 경로는 불필요.
    [ "$(which dialog)_" == "_" ] && sudo apk add dialog >/dev/null 2>&1
elif [ "$FRKRNL" = "NO" ] && [ "$(which dialog)_" == "_" ]; then
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/tce/optional/dialog.tcz -o /mnt/${tcrppart}/cde/optional/dialog.tcz
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/tce/optional/dialog.tcz.dep -o /mnt/${tcrppart}/cde/optional/dialog.tcz.dep
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/tce/optional/dialog.tcz.md5.txt -o /mnt/${tcrppart}/cde/optional/dialog.tcz.md5.txt
    tce-load -i dialog
    if [ $? -eq 0 ]; then
        echo "Install dialog OK !!!"
    else
        tce-load -iw dialog
    fi
    sudo echo "dialog.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download ntpclient
# Alpine 이식: ntpclient -> chrony 매핑(tce-load shim)이라 `which ntpclient`가
# 항상 비어있어 재진입하지만, onboot.lst(TC 전용 cde 파티션)에 쓰는 부분만
# 실패했음(실측, 2026-07-12). tce-load는 shim이 이미 idempotent 처리하므로
# onboot.lst 기록만 skip.
if [ "$FRKRNL" = "NO" ] && [ "$(which ntpclient)_" == "_" ]; then
   echo "ntpclient does not exist, install from tinycore"
   tce-load -iw ntpclient
   ! is_alpine && sudo echo "ntpclient.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download mdadm
if [ "$FRKRNL" = "NO" ] && [ "$(which mdadm)_" == "_" ]; then
    echo "mdadm does not exist, install from tinycore"
    tce-load -iw mdadm
    ! is_alpine && sudo echo "mdadm.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download sqlite3-bin
if [ "$FRKRNL" = "NO" ] && [ "$(which sqlite3)_" == "_" ]; then
    echo "sqlite3 does not exist, install from tinycore"
    tce-load -iw sqlite3-bin
    ! is_alpine && sudo echo "sqlite3-bin.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download pigz
if is_alpine; then
    [ "$(which pigz)_" == "_" ] && sudo apk add pigz >/dev/null 2>&1
elif [ "$FRKRNL" = "NO" ] && [ "$(which pigz)_" == "_" ]; then
    echo "pigz does not exist, bringing over from repo"
    curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/tools/pigz
    chmod 700 pigz
    sudo mv -vf pigz /usr/local/bin/
    backuploader
fi

#if [ "$FRKRNL" = "YES" ]; then
    #overwrite GNU tar and patch for friend
#    sudo rm /usr/bin/tar
#    sudo curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/main/tools/tar -o /usr/bin/tar
#    sudo chmod +x /usr/bin/tar
    
#    sudo rm /usr/bin/patch
#    sudo curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/main/tools/patch -o /usr/bin/patch
#    sudo chmod +x /usr/bin/patch
#fi    

# Download dtc, Don't used anymore 24.9.13
#if [ "$(which dtc)_" == "_" ]; then
#    echo "dtc dos not exist, Downloading dtc binary"
#    curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/main/tools/dtc
#    chmod 700 dtc
#    sudo mv -vf dtc /usr/local/bin/
#fi   

# Download bspatch
getbspatch

# Download kmaps
# Alpine: 콘솔 keymap이 아니라 X11(xorg)이 키보드 입력을 담당하므로 kmaps.tcz
# 자체가 불필요 - 전체 skip.
if ! is_alpine && [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep kmaps | wc -w) -eq 0 ]; then
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/tce/optional/kmaps.tcz -o /mnt/${tcrppart}/cde/optional/kmaps.tcz
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/tce/optional/kmaps.tcz.md5.txt -o /mnt/${tcrppart}/cde/optional/kmaps.tcz.md5.txt
    tce-load -i kmaps
    if [ $? -eq 0 ]; then
        echo "Install kmaps OK !!!"
    else
        tce-load -iw kmaps
    fi
    sudo echo "kmaps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download firmware-broadcom_bnx2x
# Alpine: apk linux-firmware-broadcom 대응이 별도 필요한 하드웨어 특수 케이스라
# 현재 범위 밖 - 전체 skip(문서화 필요 시 별도 작업).
if ! is_alpine && [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep firmware-broadcom_bnx2x | wc -w) -eq 0 ]; then
    installtcz "firmware-broadcom_bnx2x.tcz"
    echo "Install firmware-broadcom_bnx2x OK !!!"
    backuploader
fi

# Download btrfs-progs
if [ "$FRKRNL" = "NO" ] && [ "$(which mkfs.btrfs)_" == "_" ]; then
    echo "btrfs-progs does not exist, install from tinycore"
    tce-load -iw btrfs-progs
    ! is_alpine && sudo echo "btrfs-progs.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download lvm2
if [ "$FRKRNL" = "NO" ] && [ "$(which lvm)_" == "_" ]; then
    echo "lvm2 does not exist, install from tinycore"
    tce-load -iw lvm2
    ! is_alpine && sudo echo "lvm2.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download zstd
#if [ "$FRKRNL" = "NO" ] && [ "$(which zstd)_" == "_" ]; then  
#    echo "zstd does not exist, install from tinycore"
#    tce-load -iw zstd 
#    sudo echo "zstd.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
#fi

# copy tinycore pack and backup, except scsi-6.1.2-tinycore64.tcz
# Alpine: /tmp/tce(TC tce-load 스테이징 영역) 자체가 없어 skip.
if ! is_alpine && [ $(ls /tmp/tce/optional/ 2>/dev/null | grep -v scsi-6.1.2-tinycore64.tcz | wc -l) -gt 0 ]; then
    sudo cp -f /tmp/tce/optional/* /mnt/${tcrppart}/cde/optional
    backuploader
fi

# Download scsi-6.1.2-tinycore64.tcz
# Alpine 이식: TinyCore 커널(6.1.2-tinycore64) 전용 .tcz라 apk 대응 없음. Alpine 커널의
# scsi 모듈은 커널 패키지에 내장되므로 이 블록은 skip. (docs/alpine-migration-plan.md 착수 체크리스트 §kernel)
if ! is_alpine && [ "$FRKRNL" = "NO" ] && [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    tce-load -iw scsi-6.1.2-tinycore64.tcz
fi

NEXT="m"
setSuggest $MODEL
bfbay=$(readConfigKey "general" "bay")
if [ -z "${bfbay}" ]; then
  bay=${bfbay}
fi
writeConfigKey "general" "bay" "${bay}"

chk_shr_ex

# Until urxtv is available, Korean menu is used only on remote terminals.
_gv=""; kver=""; origin_plat=""; drmmode=""
while true; do
  _gv="$(resolveLiveKver)"
  kver="${_gv%%|*}"
  if [ "${MDLNAME}" = "all-modules" ]; then
    if [[ "$kver" = "5.10.55" || "$kver" = "4.4.302" ]]; then
      drmmode="i915+AMD dual DRM"
    else
      drmmode="Intel DRM"
    fi
  elif [ "${MDLNAME}" = "custom-modules" ]; then
    drmmode="i915+AMD dual DRM"
  elif [ "${MDLNAME}" = "anodrm-modules" ]; then
    drmmode="No DRM"
  else
    drmmode="Unknown DRM"
  fi
  [ "${NVMES}" = "false" ] && nvmeaction="Add" || nvmeaction="Remove"
  [ "${VMTOOLS}" = "false" ] && vmtoolsaction="Add" || vmtoolsaction="Remove"
  eval "MSG74=\"\${MSG${tz}74}\""
  eval "MSG75=\"\${MSG${tz}75}\""
  eval "MSG76=\"\${MSG${tz}76}\""
  if [ "${NVIDIA_ENABLED}" = "true" ]; then
    nvsel="${NVIDIA_DRIVER:-Auto}"
    [ "${NVIDIA_FFMPEG}" = "true" ] && nvsel="${nvsel}+ffmpeg"
    nvlabel="$(printf "${MSG74}" "${nvsel}")"
  else
    nvlabel="${MSG75}"
  fi
  # 커널별 NVIDIA 메뉴 가용성. 이 프로젝트가 다루는 세 커널 계열:
  #   5.10.x - 470/535/550/580 전부 발행 (nvidiaMenu 내부에서 자동 판별)
  #   4.4.x  - 550 만 발행. nvidiaMenu 는 이제 커널을 인자로 받아 index 의
  #            kernels[$k].drivers 를 우선 조회하므로 자동으로 550 만 뜬다
  #   3.10.x - NVIDIA 드라이버 자체가 이 커널로 빌드된 적이 없음. 메인메뉴
  #            라벨부터 (Not Supported) 로 표기하고 하위메뉴 진입을 막는다
  #            (nvidiaMenu 를 열어봐야 빈 목록만 보고 오해하게 두지 않음)
  case "${kver}" in
    5.10.*|4.4.*) nv_locked="no" ;;
    3.10.*)       nv_locked="yes"; nvlabel="${MSG76}" ;;
    *)            nv_locked="hide" ;;
  esac
  # ===== Main ===== (로더 빌드 워크플로 — 순차 진행 항목)
  echo '1 "=============== Main ==============="'                              > "${TMP_PATH}/menu"
  eval "echo \"m \\\"\${MSG${tz}02}, (${MODEL})\\\"\""     >> "${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    eval "echo \"j \\\"\${MSG${tz}05} (${BUILD})\\\"\""  >> "${TMP_PATH}/menu"
    eval "echo \"s \\\"\${MSG${tz}03}\\\"\""             >> "${TMP_PATH}/menu"
    eval "echo \"a \\\"\${MSG${tz}72}\\\"\""             >> "${TMP_PATH}/menu"
    eval "echo \"z \\\"\${MSGZZ67}\\\"\""                >> "${TMP_PATH}/menu"
    [ "${nv_locked}" != "hide" ] && eval "echo \"g \\\"${nvlabel}\\\"\"" >> "${TMP_PATH}/menu"
    # k(selectldrmode) 와 c(seleudev) 는 최상위에서 빠지고 z(build-pre-option)
    # 의 하위메뉴 1·2번 항목으로 종속됐다 - 아래 build-pre-option() 참고.
    eval "echo \"p \\\"\${MSG${tz}18} (${BUILD}, ${drmmode}, ${MDLNAME}:${MLMETHOD})\\\"\""   >> "${TMP_PATH}/menu"
  else
    # 'c' only *moved* - it does not depend on MODEL (seleudev just sets DMPM and
    # swaps the ddsml/eudev addons), so keep it reachable before a model is
    # picked instead of hiding it along with the build-workflow items above.
    eval "echo \"c \\\"\${MSG${tz}01}, (${DMPM})\\\"\""      >> "${TMP_PATH}/menu"
  fi
  [ "$FRKRNL" = "YES" ] && \
  eval "echo \"y \\\"\${MSG${tz}58}\\\"\""               >> "${TMP_PATH}/menu"

  # ===== Environment ===== (설정/환경 옵션)
  echo '2 "=============== Environment ==============="'                     >> "${TMP_PATH}/menu"
  eval "echo \"u \\\"\${MSG${tz}10}\\\"\""               >> "${TMP_PATH}/menu"
  eval "MSG86=\"\${MSG${tz}86}\""
  eval "echo \"v \\\"$(printf "${MSG86}" "${VERBOSE_MODE}")\\\"\""   >> "${TMP_PATH}/menu"
  eval "echo \"l \\\"\${MSG${tz}39}\\\"\""               >> "${TMP_PATH}/menu"

  # ===== Misc ===== (유지보수/시스템)
  echo '3 "=============== Misc ==============="'                            >> "${TMP_PATH}/menu"
  eval "echo \"n \\\"\${MSG${tz}59}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"x \\\"\${MSG${tz}07}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"b \\\"\${MSG${tz}13}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"w \\\"\${MSG${tz}87}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"q \\\"\${MSG${tz}88}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"r \\\"\${MSG${tz}14}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"e \\\"\${MSG${tz}15}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"o \\\"\${MSG${tz}73}\\\"\""               >> "${TMP_PATH}/menu"
  # 화면 크기에 맞춰 박스를 1행(backtitle 아래)부터 꽉 차게 그려 중앙배치
  # 여백/그림자 제거. (footer 버튼행은 dialog --menu 구조상 필수라 제거 불가,
  # 빈 여백만 최소화하고 그만큼 리스트 표시 행을 늘림)
  SCR_H=$(tput lines 2>/dev/null); SCR_W=$(tput cols 2>/dev/null)
  [ -z "${SCR_H}" ] && SCR_H=$(stty size 2>/dev/null | awk '{print $1}')
  [ -z "${SCR_W}" ] && SCR_W=$(stty size 2>/dev/null | awk '{print $2}')
  [ -z "${SCR_H}" ] && SCR_H=24; [ -z "${SCR_W}" ] && SCR_W=80
  BOX_H=$(( SCR_H - 1 )); [ ${BOX_H} -lt 10 ] && BOX_H=10   # backtitle(0행) 보존
  MENU_H=$(( BOX_H - 8 )); [ ${MENU_H} -lt 3 ] && MENU_H=3
  dialog --clear --default-item ${NEXT} --backtitle "`backtitle`" --colors \
    --begin 1 0 --no-shadow \
    --menu "${result}" ${BOX_H} ${SCR_W} ${MENU_H} --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  dlgret=$?
  # 실측 확인(2026-07-16): 이 dialog 빌드(1.3-20260107)는 ESC와 Cancel
  # 버튼을 종료 코드로 구분하지 않음(--no-cancel, DIALOG_ESC 환경변수 모두
  # 무시하고 둘 다 1 반환). 종료는 메뉴의 별도 항목(e: byebye)으로만
  # 하도록 하고, ESC/Cancel은 메뉴를 다시 그리기만 함(프로그램 종료 안 함).
  [ ${dlgret} -ne 0 ] && continue
  case `<"${TMP_PATH}/resp"` in
    # 카테고리 구분선 — 선택 시 해당 그룹 첫 실제 항목으로 포커스 이동
    1) NEXT="m" ;;   # ===== Main =====        → m (첫 항목: c 가 p 앞으로 이동)
    2) NEXT="u" ;;   # ===== Environment ===== → u
    3) NEXT="n" ;;   # ===== Misc =====        → n
    c) seleudev;        NEXT="p" ;;   # c 는 이제 p 바로 위 → 다음은 빌드
    m) modelMenu;       NEXT="j" ;;
    j) selectversion ;    NEXT="s" ;;     
    s) serialMenu;      NEXT="a" ;;
    a) # NIC 1개(eth0 뿐)면 목록 하위메뉴를 거칠 이유가 없다 - 고를 대상이
       # 하나뿐이므로 바로 최하단 메뉴(macMenu, real/random/manual 선택)로
       # 진입한다. NIC 이 2개 이상일 때만 macAddressMenu 목록을 연다.
       if [ $(/sbin/ifconfig | grep eth1 | wc -l) -gt 0 ]; then
         macAddressMenu
       else
         macMenu "eth0"
       fi
       NEXT="p" ;;
    z) build-pre-option ; NEXT="p" ;;
    g) [ "${nv_locked}" = "yes" ] || nvidiaMenu "${kver}"; NEXT="g" ;;
    p) # epyc7003ntb (PAS7700): 단일(single) standalone 방식으로 통일 —
       # 이중 컨트롤러 역할 선택 다이얼로그(ntbfsdn)는 제거했다. 피어가 없으므로
       # 두 번째 박스도 불필요하며, 설치는 misc addon 의 단일 노드 우회로 진행된다.
       if [ "${LDRMODE}" == "FRIEND" ]; then
         make_with_progress "fri" "${PREVENT_INIT}"
       #else  
       #  make_with_progress "jot" "${PREVENT_INIT}"
       fi  
       if [ "$FRKRNL" = "YES" ]; then
         NEXT="y"
       else
         NEXT="r"
       fi  
       ;;
    v)
        # Verbose Mode Toggle
        toggle_verbose_menu
        NEXT="p"
        ;;           
    y) sudo /root/boot.sh normal ;;
    n) additional;      NEXT="p" ;;
    x) synopart;        NEXT="r" ;;
    u) editUserConfig;  NEXT="p" ;;
    l) langMenu ;;
    b) backuploader;   NEXT="r" ;;
    w) select_and_run_menu; NEXT="r" ;;
    q) showAutoUpdateMenu; NEXT="r" ;;
    r) restart ;;
    e) byebye ;;
    o) break ;;
  esac
done

clear
echo -e "Call \033[1;32m./menu.sh\033[0m to return to menu"
