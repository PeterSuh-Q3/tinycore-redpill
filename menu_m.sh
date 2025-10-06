#!/usr/bin/env bash

set -u # Unbound variable errors are not allowed

##### INCLUDES #####################################################################################################
. /home/tc/functions.sh
. /home/tc/i18n.h
#####################################################################################################

kver3explatforms="bromolow braswell cedarview grantley"
kver5explatforms="epyc7002(DT) v1000nk(DT) r1000nk(DT) geminilakenk(DT)"
configfile="/home/tc/redpill-load/config/pats.json"

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
 
function restart() {
    (sync &)
    echo "A reboot is required. Press any key to reboot..."
    read -n 1 -s  # Wait for a key press
    clear
    writebackcache
    sudo reboot
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

# Prevent SataPortMap/DiskIdxMap initialization 2023.12.31
prevent_init="OFF"

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
if [ "$FRKRNL" = "NO" ]; then
    update_tinycore
    update_motd
fi

# restore user_config.json file from /mnt/sd#/lastsession directory 2023.10.21
#restoresession

TMP_PATH=/tmp
LOG_FILE="${TMP_PATH}/log.txt"
USER_CONFIG_FILE="/home/tc/user_config.json"
if [ ! -f "${USER_CONFIG_FILE}" ]; then
    echo "Not Found User config file, program Exit!!!"
    echo "press any key to continue..."
    read answer    
    exit 99
fi

MODEL=$(jq -r -e '.general.model' "$USER_CONFIG_FILE")
BUILD=$(jq -r -e '.general.version' "$USER_CONFIG_FILE")
SN=$(jq -r -e '.extra_cmdline.sn' "$USER_CONFIG_FILE")
MACADDR1="$(jq -r -e '.extra_cmdline.mac1' $USER_CONFIG_FILE)"
MACADDR2="$(jq -r -e '.extra_cmdline.mac2' $USER_CONFIG_FILE)"
MACADDR3="$(jq -r -e '.extra_cmdline.mac3' $USER_CONFIG_FILE)"
MACADDR4="$(jq -r -e '.extra_cmdline.mac4' $USER_CONFIG_FILE)"
MACADDR5="$(jq -r -e '.extra_cmdline.mac5' $USER_CONFIG_FILE)"
MACADDR6="$(jq -r -e '.extra_cmdline.mac6' $USER_CONFIG_FILE)"
MACADDR7="$(jq -r -e '.extra_cmdline.mac7' $USER_CONFIG_FILE)"
MACADDR8="$(jq -r -e '.extra_cmdline.mac8' $USER_CONFIG_FILE)"
NETNUM="1"

LAYOUT=$(jq -r -e '.general.layout' "$USER_CONFIG_FILE")
KEYMAP=$(jq -r -e '.general.keymap' "$USER_CONFIG_FILE")

I915MODE=$(jq -r -e '.general.i915mode' "$USER_CONFIG_FILE")
BFBAY=$(jq -r -e '.general.bay' "$USER_CONFIG_FILE")
DMPM=$(jq -r -e '.general.devmod' "$USER_CONFIG_FILE")
NVMES=$(jq -r -e '.general.nvmesystem' "$USER_CONFIG_FILE")
VMTOOLS=$(jq -r -e '.general.vmtools' "$USER_CONFIG_FILE")
LDRMODE=$(jq -r -e '.general.loadermode' "$USER_CONFIG_FILE")
MDLNAME=$(jq -r -e '.general.modulename' "$USER_CONFIG_FILE")
ucode=$(jq -r -e '.general.ucode' "$USER_CONFIG_FILE")

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
  [ -n "${MODEL}" ] && BACKTITLE+=" ${MODEL}" || BACKTITLE+=" (no model)"
  [ -n "${BUILD}" ] && BACKTITLE+=" ${BUILD}" || BACKTITLE+=" (no build)"
  [ -n "${SN}" ] && BACKTITLE+=" ${SN}" || BACKTITLE+=" (no SN)"
  [ -n "${IP}" ] && BACKTITLE+=" ${IP}" || BACKTITLE+=" (no IP)"
  [ ! -n "${MACADDR1}" ] && BACKTITLE+=" (no MAC1)" || BACKTITLE+=" ${MACADDR1}"
  [ ! -n "${MACADDR2}" ] && BACKTITLE+=" (no MAC2)" || BACKTITLE+=" ${MACADDR2}"
  [ ! -n "${MACADDR3}" ] && BACKTITLE+=" (no MAC3)" || BACKTITLE+=" ${MACADDR3}"
  [ ! -n "${MACADDR4}" ] && BACKTITLE+=" (no MAC4)" || BACKTITLE+=" ${MACADDR4}"  
  [ ! -n "${MACADDR5}" ] && BACKTITLE+=" (no MAC5)" || BACKTITLE+=" ${MACADDR5}"
  [ ! -n "${MACADDR6}" ] && BACKTITLE+=" (no MAC6)" || BACKTITLE+=" ${MACADDR6}"
  [ ! -n "${MACADDR7}" ] && BACKTITLE+=" (no MAC7)" || BACKTITLE+=" ${MACADDR7}"
  [ ! -n "${MACADDR8}" ] && BACKTITLE+=" (no MAC8)" || BACKTITLE+=" ${MACADDR8}"  
  [ -n "${KEYMAP}" ] && BACKTITLE+=" (${LAYOUT}/${KEYMAP})" || BACKTITLE+=" (qwerty/us)"
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

  if [ "${BLOCK_DDSML}" = "Y" ] || [ "${BUS}" = "mmc" ] || echo ${kver5explatforms} | grep -qw ${platform}; then
    menu_options=("e" "${MSG26}" "f" "${MSG40}")
  elif [ ${BLOCK_EUDEV} = "Y" ]; then  
    menu_options=("d" "${MSG27}" "f" "${MSG40}")
  else
    menu_options=("d" "${MSG27}" "e" "${MSG26}" "f" "${MSG40}")
  fi

  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 0 \
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

###############################################################################
# Shows available between FRIEND and JOT
function selectldrmode() {
  eval "MSG28=\"\${MSG${tz}28}\""
  eval "MSG29=\"\${MSG${tz}29}\""  

  if echo ${kver5explatforms} | grep -qw ${platform}; then
    menu_options=("f" "${MSG28}, all-modules(tcrp)" "j" "${MSG29}, all-modules(tcrp)")
  else  
    menu_options=("f" "${MSG28}, all-modules(tcrp)" "j" "${MSG29}, all-modules(tcrp)" "k" "${MSG28}, rr-modules" "l" "${MSG29}, rr-modules")
  fi
  
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 0 \
      "${menu_options[@]}" \
    2>${TMP_PATH}/resp
    [ $? -ne 0 ] && return
    resp=$(<${TMP_PATH}/resp)
    [ -z "${resp}" ] && return
    if [ "${resp}" = "f" ]; then
      LDRMODE="FRIEND"
      MDLNAME="all-modules"
      break
    elif [ "${resp}" = "j" ]; then
      LDRMODE="JOT"
      MDLNAME="all-modules"      
      break
    elif [ "${resp}" = "k" ]; then
      LDRMODE="FRIEND"
      MDLNAME="rr-modules"
      break
    elif [ "${resp}" = "l" ]; then
      LDRMODE="JOT"
      MDLNAME="rr-modules"
      break
    fi
  done

  writeConfigKey "general" "loadermode" "${LDRMODE}"
  writeConfigKey "general" "modulename" "${MDLNAME}"

}

###############################################################################
# Shows available dsm verwsion 
function selectversion () {

# 1. 최대 10개 결과 추출 (공백 한 개로 join)
pat_versions=$(jq -r ".\"${MODEL}\" | keys | map(.[0:11]) | .[:10] | reverse | join(\" \")" "${configfile}")
echo "PAT VERSIONS : $pat_versions"

# 2. 배열 변환
IFS=' ' read -ra versions <<< "$pat_versions"

# 결과 출력 (공백 구분)
echo "${versions[@]}"

# 3. TAG-ITEM 쌍 만들기
menu_items=()
tags=(a b c d e f g h i j)
for i in "${!versions[@]}"; do
  menu_items+=("${tags[$i]}" "${versions[$i]}")
done

while true; do
  dialog --clear --backtitle "$(backtitle)" \
    --menu "Choose a option" 0 0 0 \
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

}

###############################################################################
# Shows available models to user choose one
function modelMenu() {

  # Set the path for the models.json file
  MODELS_JSON="/home/tc/models.json"
  
  # Define platform groups
  M_GRP1="epyc7002 v1000nk r1000nk geminilakenk broadwellnk"
  M_GRP2="broadwell broadwellnkv2 broadwellntbap purley bromolow avoton braswell cedarview grantley"
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
    --menu "${MSG00} [Except SA6400]\n" 0 0 0 \
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

  if echo ${kver5explatforms} | grep -qw ${platform}; then
      MDLNAME="all-modules"
      writeConfigKey "general" "modulename" "${MDLNAME}"
  fi

  if echo ${kver3explatforms} | grep -qw ${platform}; then
      MDLNAME="all-modules"
      writeConfigKey "general" "modulename" "${MDLNAME}"
  fi
  BUILD=$(jq -r ".\"${MODEL}\" | keys | max | .[:11]" "${configfile}")
  writeConfigKey "general" "version" "${BUILD}"  

  if [ "${BLOCK_DDSML}" = "Y" ] || [ "${BUS}" = "mmc" ] || echo ${kver5explatforms} | grep -qw ${platform}; then
    if [ "$HBADETECT" = "ON" ]; then
        DMPM="DDSML+EUDEV"
    else
        DMPM="EUDEV"
    fi 
  else
    DMPM="DDSML"
  fi
  writeConfigKey "general" "devmod" "${DMPM}"
  
}

# Set Describe model-specific requirements or suggested hardware
function setSuggest() {

  case $1 in
    SA6400)      platform="epyc7002(DT)";bay="RACK_12_Bay";mcpu="AMD EPYC 7272";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS925+)      platform="v1000nk(DT)";bay="TOWER_4_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS1525+)     platform="v1000nk(DT)";bay="TOWER_4_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS1825+)     platform="v1000nk(DT)";bay="TOWER_4_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS725+)      platform="r1000nk(DT)";bay="TOWER_4_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
    DS425+)      platform="geminilakenk(DT)";bay="TOWER_4_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;    
    DS225+)      platform="geminilakenk(DT)";bay="TOWER_2_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;    
    DS1019+)     platform="apollolake";bay="TOWER_5_Bay";mcpu="Intel Celeron J3455";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS620slim)   platform="apollolake";bay="TOWER_6_Bay";mcpu="Intel Celeron J3355";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS218+)      platform="apollolake";bay="TOWER_2_Bay";mcpu="Intel Celeron J3355";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS418play)   platform="apollolake";bay="TOWER_4_Bay";mcpu="Intel Celeron J3355";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS718+)      platform="apollolake";bay="TOWER_2_Bay";mcpu="Intel Celeron J3455";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS918+)      platform="apollolake";bay="TOWER_4_Bay";mcpu="Intel Celeron J3455";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS1520+)     platform="geminilake(DT)";bay="TOWER_5_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DS220+)      platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS224+)      platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS420+)      platform="geminilake(DT)";bay="TOWER_4_Bay";mcpu="Intel Celeron J4025";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;
    DS423+)      platform="geminilake(DT)";bay="TOWER_4_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DS720+)      platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DS920+)      platform="geminilake(DT)";bay="TOWER_4_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}\"";;    
    DVA1622)     platform="geminilake(DT)";bay="TOWER_2_Bay";mcpu="Intel Celeron J4125";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}17}, \${MSG${tz}21}\"";;
    DS1621xs+)   platform="broadwellnk";bay="TOWER_6_Bay";mcpu="Intel Xeon D-1527";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3622xs+)   platform="broadwellnk";bay="TOWER_12_Bay";mcpu="Intel Xeon D-1531";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS3600)      platform="broadwellnk";bay="RACK_24_Bay";mcpu="Intel Xeon D-1567";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS1619xs+)   platform="broadwellnk";bay="RACK_4_Bay";mcpu="Intel Xeon D-1527";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3621RPxs)  platform="broadwellnk";bay="RACK_12_Bay";mcpu="Intel Xeon D-1531";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3621xs+)   platform="broadwellnk";bay="RACK_12_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS4021xs+)   platform="broadwellnk";bay="RACK_16_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3400)      platform="broadwellnk";bay="RACK_12_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3600)      platform="broadwellnk";bay="RACK_12_Bay";mcpu="Intel Xeon D-1567";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3018xs)    platform="broadwellnk";bay="TOWER_6_Bay";mcpu="Intel Pentium D1508";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS1018)      platform="broadwellnk";bay="TOWER_12_Bay";mcpu="Intel Pentium D1508";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS1522+)     platform="r1000(DT)";bay="TOWER_5_Bay";mcpu="AMD Ryzen R1600";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;    
    DS723+)      platform="r1000(DT)";bay="TOWER_2_Bay";mcpu="AMD Ryzen R1600";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;
    DS923+)      platform="r1000(DT)";bay="TOWER_4_Bay";mcpu="AMD Ryzen R1600";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;
    RS422+)      platform="r1000(DT)";bay="RACK_4_Bay";mcpu="AMD Ryzen R1600";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}20}\"";;
    DS1621+)     platform="v1000(DT)";bay="TOWER_6_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    DS1821+)     platform="v1000(DT)";bay="TOWER_8_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1823xs+)   platform="v1000(DT)";bay="TOWER_8_Bay";mcpu="AMD Ryzen V1780B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;            
    DS2422+)     platform="v1000(DT)";bay="TOWER_12_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    FS2500)      platform="v1000(DT)";bay="RACK_12_Bay_2";mcpu="AMD Ryzen V1780B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS1221+)     platform="v1000(DT)";bay="RACK_8_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    RS1221RP+)   platform="v1000(DT)";bay="RACK_8_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;    
    RS2421+)     platform="v1000(DT)";bay="RACK_12_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2421RP+)   platform="v1000(DT)";bay="RACK_12_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";; 
    RS2423+)     platform="v1000(DT)";bay="RACK_12_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;        
    RS2423RP+)   platform="v1000(DT)";bay="RACK_12_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2821RP+)   platform="v1000(DT)";bay="RACK_16_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS822+)      platform="v1000(DT)";bay="RACK_4_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS822RP+)    platform="v1000(DT)";bay="RACK_4_Bay";mcpu="AMD Ryzen V1500B";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1819+)     platform="denverton";bay="TOWER_8_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;
    DS2419+)     platform="denverton";bay="TOWER_12_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;  
    DS2419+II)   platform="denverton";bay="TOWER_12_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;
    DVA3219)     platform="denverton";bay="TOWER_4_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;    
    DVA3221)     platform="denverton";bay="TOWER_4_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";; 
    RS820+)      platform="denverton";bay="RACK_4_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS820RP+)    platform="denverton";bay="RACK_4_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    DS1618+)     platform="denverton";bay="TOWER_6_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}25}, \${MSG${tz}21}\"";;
    RS2418+)     platform="denverton";bay="RACK_12_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS2418RP+)   platform="denverton";bay="RACK_12_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS2818RP+)   platform="denverton";bay="RACK_16_Bay";mcpu="Intel Atom C3538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}23}, \${MSG${tz}24}, \${MSG${tz}21}\"";;
    RS3618xs)    platform="broadwell";bay="RACK_12_Bay";mcpu="Intel Xeon D-1521";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3617xs)    platform="broadwell";bay="TOWER_12_Bay";mcpu="Intel Xeon D-1527";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS3617xsII)  platform="broadwell";bay="TOWER_12_Bay";mcpu="Intel Xeon D-1527";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS2017)      platform="broadwell";bay="RACK_24_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS3400)      platform="broadwell";bay="RACK_24_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;    
    RS18017xs+)  platform="broadwell";bay="RACK_12_Bay";mcpu="Intel Xeon D-1531";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3617RPxs)  platform="broadwell";bay="RACK_12_Bay";mcpu="Intel Xeon D-1521";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS3617xs+)   platform="broadwell";bay="RACK_12_Bay";mcpu="Intel Xeon E3-1230v2";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    RS4017xs+)   platform="broadwell";bay="RACK_16_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS3410)      platform="broadwellnkv2(DT)";bay="RACK_24_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3410)      platform="broadwellnkv2(DT)";bay="RACK_12_Bay";mcpu="Intel Xeon D-1567";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3610)      platform="broadwellnkv2(DT)";bay="RACK_12_Bay";mcpu="Intel Xeon D-1567";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3200D)     platform="broadwellntbap";bay="RACK_12_Bay";mcpu="Intel Xeon D-1521";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    SA3400D)     platform="broadwellntbap";bay="RACK_12_Bay";mcpu="Intel Xeon D-1541";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    FS6400)      platform="purley(DT)";bay="RACK_24_Bay";mcpu="Intel Xeon® Silver 4110";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    HD6500)      platform="purley(DT)";bay="RACK_60_Bay";mcpu="Intel Xeon Silver 4210R";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}16}\"";;
    DS1515+)     platform="avoton";bay="TOWER_5_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1517+)     platform="avoton";bay="TOWER_5_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1815+)     platform="avoton";bay="TOWER_8_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1817+)     platform="avoton";bay="TOWER_8_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS2415+)     platform="avoton";bay="TOWER_12_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS415+)      platform="avoton";bay="TOWER_4_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS1219+)     platform="avoton";bay="RACK_8_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2416+)     platform="avoton";bay="RACK_12_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2416RP+)   platform="avoton";bay="RACK_12_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS815+)      platform="avoton";bay="RACK_4_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS815RP+)    platform="avoton";bay="RACK_4_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS818+)      platform="avoton";bay="RACK_8_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS818RP+)    platform="avoton";bay="RACK_8_Bay";mcpu="Intel Atom C2538";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS713+)      platform="cedarview";bay="TOWER_2_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1513+)     platform="cedarview";bay="TOWER_5_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS1813+)     platform="cedarview";bay="TOWER_8_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS2413+)     platform="cedarview";bay="TOWER_12_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2414+)     platform="cedarview";bay="RACK_12_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS2414RP+)   platform="cedarview";bay="RACK_12_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS814+)      platform="cedarview";bay="RACK_4_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS814RP+)    platform="cedarview";bay="RACK_4_Bay";mcpu="Intel Atom D2700";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS916+)      platform="braswell";bay="TOWER_4_Bay";mcpu="Intel Atom N3050";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    FS3017)      platform="grantley";bay="RACK_24_Bay";mcpu="Intel Xeon E5 v3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    DS3615xs)    platform="bromolow";bay="TOWER_12_Bay";mcpu="Intel Core i3-4130";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RC18015xs+)  platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3 QUAD";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS10613xs+)  platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS18016xs+)  platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3413xs+)   platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3614rpxs)  platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3614xs+)   platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3614xs)    platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    RS3617xs)    platform="bromolow";bay="RACK_12_Bay";mcpu="Intel Xeon E3";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu}, \${MSG${tz}22}\"";;
    *)    platform="Any platform";bay="Any Bay";mcpu="Intel or AMD";eval "desc=\"[${MODEL}]:${platform},${bay},${mcpu} \"";;
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
    --menu "Choose a Panel Size" 0 0 0 "TOWER_1_Bay" "TOWER_2_Bay" "TOWER_4_Bay" "TOWER_4_Bay_J" \
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
      --menu "Choose a option" 0 0 0 \
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
}

###############################################################################
# Shows menu to generate randomly or to get realmac
function macMenu() {
  eval "MSG32=\"\${MSG${tz}32}\""
  eval "MSG33=\"\${MSG${tz}33}\""
  eval "MSG34=\"\${MSG${tz}34}\""  
  while true; do
    dialog --clear --backtitle "`backtitle`" \
      --menu "Choose a option" 0 0 0 \
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

}

function prevent() {

    prevent_init="ON"
    echo "Enable SataPortMap/DiskIdxMap initialization protection"
    echo "press any key to continue..."
    read answer
  
}

###############################################################################
# Permits user edit the user config
function editUserConfig() {
  while true; do
    dialog --backtitle "`backtitle`" --title "Edit with caution" \
      --editbox "${USER_CONFIG_FILE}" 0 0 2>"${TMP_PATH}/userconfig"
    
    [ $? -ne 0 ] && return

    # JSON format validation
    if jq . "${TMP_PATH}/userconfig" > /dev/null 2>&1; then
        mv "${TMP_PATH}/userconfig" "${USER_CONFIG_FILE}"
        [ $? -eq 0 ] && break
    else
        dialog --backtitle "`backtitle`" --title "Invalid JSON format" --msgbox "The JSON format is invalid." 0 0
    fi
  done

  sudo cp /home/tc/user_config.json /mnt/${tcrppart}/user_config.json

  MODEL="$(jq -r -e '.general.model' $USER_CONFIG_FILE)"
  SN="$(jq -r -e '.extra_cmdline.sn' $USER_CONFIG_FILE)"
  MACADDR1="$(jq -r -e '.extra_cmdline.mac1' $USER_CONFIG_FILE)"
  MACADDR2="$(jq -r -e '.extra_cmdline.mac2' $USER_CONFIG_FILE)"
  MACADDR3="$(jq -r -e '.extra_cmdline.mac3' $USER_CONFIG_FILE)"
  MACADDR4="$(jq -r -e '.extra_cmdline.mac4' $USER_CONFIG_FILE)"
  MACADDR5="$(jq -r -e '.extra_cmdline.mac5' $USER_CONFIG_FILE)"
  MACADDR6="$(jq -r -e '.extra_cmdline.mac6' $USER_CONFIG_FILE)"
  MACADDR7="$(jq -r -e '.extra_cmdline.mac7' $USER_CONFIG_FILE)"
  MACADDR8="$(jq -r -e '.extra_cmdline.mac8' $USER_CONFIG_FILE)"
  NETNUM"=$(jq -r -e '.extra_cmdline.netif_num' $USER_CONFIG_FILE)"
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

  netif_num=$(jq -r -e '.extra_cmdline.netif_num' $USER_CONFIG_FILE)
  netif_num_cnt=$(cat $USER_CONFIG_FILE | grep \"mac | wc -l)
                    
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

  if [ "${prevent_init}" = "OFF" ]; then
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

function writexsession() {

  echo "Inject urxvt menu.sh into /home/tc/.xsession."

  sed -i "/locale/d" .xsession
  sed -i "/utf8/d" .xsession
  sed -i "/UTF-8/d" .xsession
  sed -i "/aterm/d" .xsession
  sed -i "/urxvt/d" .xsession

  echo "export LANG=${ucode}.UTF-8" >> .xsession
  echo "export LC_ALL=${ucode}.UTF-8" >> .xsession
  echo "[ ! -d /usr/lib/locale ] && sudo mkdir /usr/lib/locale &" >> .xsession
  echo "sudo localedef -c -i ${ucode} -f UTF-8 ${ucode}.UTF-8" >> .xsession
  echo "sudo localedef -f UTF-8 -i ${ucode} ${ucode}.UTF-8" >> .xsession

  echo "urxvt -geometry 78x32+10+0 -fg orange -title \"TCRP-mshell urxvt Menu\" -e /home/tc/menu.sh &" >> .xsession  
  sed -i "/rploader/d" .xsession
  echo "aterm -geometry 78x32+525+0 -fg yellow -title \"TCRP Monitor\" -e /home/tc/monitor.sh &" >> .xsession
  echo "aterm -geometry 78x25+10+430 -title \"TCRP Build Status\" -e /home/tc/ntp.sh &" >> .xsession
  echo "aterm -geometry 78x25+525+430 -fg green -title \"TCRP Extra Terminal\" &" >> .xsession

  echo "Checking if 'ttyd' pattern exists in /opt/bootlocal.sh ..."
  sed -i "/ttyd/d" .xsession
  # Check if 'ttyd' pattern exists in /opt/bootlocal.sh
  if ! grep -q "ttyd" /opt/bootlocal.sh; then
    echo "'ttyd' pattern not found. Adding necessary lines to /opt/bootlocal.sh"

    # Add the required lines to .xsession
    [ -f lsz ] && sudo cp -f lsz /usr/sbin/sz
    [ -f lrz ] && sudo cp -f lrz /usr/sbin/rz
    echo 'sudo /home/tc/ttyd login -f tc 2>/dev/null &' >> /opt/bootlocal.sh

    # Notify the user about the changes and prompt for reboot
    echo "The 'ttyd' configuration has been added to /opt/bootlocal.sh"
    echo "The system needs to reboot. Press any key to continue..."

    echo 'Y'|rploader backup
    restart
  else
    echo "'ttyd' pattern already exists in /opt/bootlocal.sh"
    sudo sed -i "/ttyd/d" /opt/bootlocal.sh
    sudo sed -i "/mountvol/d" /opt/bootlocal.sh
    echo 'sudo /home/tc/ttyd login -f tc 2>/dev/null &' >> /opt/bootlocal.sh
    echo '[ $(/bin/uname -r | /bin/grep 4.14.10 | /usr/bin/wc -l) -eq 1 ] && {( sleep 5; sudo openvt -c 2 -s bash -c "/home/tc/mountvol.sh; exec sudo login -f tc") & }' >> /opt/bootlocal.sh
  fi

}

###############################################################################
# Shows available language to user choose one
function langMenu() {

  dialog --backtitle "`backtitle`" --default-item "${LAYOUT}" --no-items \
    --menu "Choose a language" 0 0 0 "English" "한국어" "日本語" "中文" "Русский" \
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
    中文) tz="CN"; ucode="zh_CN";;
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

  export LANG=${ucode}.UTF-8
  export LC_ALL=${ucode}.UTF-8
  set -o allexport
  
  [ ! -d /usr/lib/locale ] && sudo mkdir /usr/lib/locale
  sudo localedef -c -i ${ucode} -f UTF-8 ${ucode}.UTF-8 > /dev/null 2>&1
  sudo localedef -f UTF-8 -i ${ucode} ${ucode}.UTF-8 > /dev/null 2>&1
  
  writeConfigKey "general" "ucode" "${ucode}"  
  [ "$FRKRNL" = "NO" ] && writexsession

  tz="ZZ"
  load_zz
  
  setSuggest $MODEL
  
  return 0

}

###############################################################################
# Shows available keymaps to user choose one
function keymapMenu() {
  dialog --backtitle "`backtitle`" --default-item "${LAYOUT}" --no-items \
    --menu "Choose a layout" 0 0 0 "azerty" "colemak" \
    "dvorak" "fgGIod" "olpc" "qwerty" "qwertz" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && return
  LAYOUT="`<${TMP_PATH}/resp`"
  OPTIONS=""
  while read KM; do
    OPTIONS+="${KM::-5} "
  done < <(cd /usr/share/kmap/${LAYOUT}; ls *.kmap)
  dialog --backtitle "`backtitle`" --no-items --default-item "${KEYMAP}" \
    --menu "Choice a keymap" 0 0 0 ${OPTIONS} \
    2>/tmp/resp
  [ $? -ne 0 ] && return
  resp=`cat /tmp/resp 2>/dev/null`
  [ -z "${resp}" ] && return
  KEYMAP=${resp}
  writeConfigKey "general" "layout" "${LAYOUT}"
  writeConfigKey "general" "keymap" "${KEYMAP}"
  sed -i "/loadkmap/d" /opt/bootsync.sh
  echo "loadkmap < /usr/share/kmap/${LAYOUT}/${KEYMAP}.kmap &" >> /opt/bootsync.sh
  echo 'Y'|rploader backup
  
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
    --menu "Choose a USB Stick, SSD or NVMe for New Loader\n\Z1(Caution!) In the case of SSD(include NVMe), be sure to check whether it is a cache or data disk.\Zn" 0 0 0 "${listusb[@]}" \
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

  echo "Downloading TCRP-mshell ${imgversion} img file..."  
  if [ -f /tmp/tinycore-redpill.${imgversion}.m-shell.img ]; then
    echo "TCRP-mshell ${imgversion} img file already exists. Skip download..."  
  else
    curl -kL# https://github.com/PeterSuh-Q3/tinycore-redpill/releases/download/${imgversion}/tinycore-redpill.${imgversion}.m-shell.img.gz -o /tmp/tinycore-redpill.${imgversion}.m-shell.img.gz
    gunzip /tmp/tinycore-redpill.${imgversion}.m-shell.img.gz
  fi

  echo "Please wait a moment. Burning ${imgversion} image is in progress..."  
  sudo dd if=/tmp/tinycore-redpill.${imgversion}.m-shell.img of=${loaderdev} status=progress bs=4M
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
    --menu "Choose a USB Stick or SSD for Clone Loader\n\Z1(Caution!) In the case of SSD, be sure to check whether it is a cache or data disk.\Zn" 0 0 0 "${listusb[@]}" \
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
    jsonfile=$(jq ". |= .+ {\"${1}\": \"https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${1}/rpext-index.json\"}" /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json    
    return 0
  else
    return 1
  fi
}

function del-addon() {
  jsonfile=$(jq "del(.[\"${1}\"])" ~/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > ~/redpill-load/bundled-exts.json
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
    echo 'Y'|rploader backup
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
  echo 'Y'|rploader backup
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

function changesatadom() {
  rm -f "${TMP_PATH}/menub"
  {
    echo "0 \"Disable SATA DOM\""
    echo "1 \"Native SATA DOM(SYNO)\""
    echo "2 \"Fake SATA DOM(Redpill)\""
  } >"${TMP_PATH}/menub"
  dialog --clear --default-item "${SATADOM}" --backtitle "`backtitle`" --colors --menu "Choose a mode(Only supported for kernel version 4)" 0 0 0 --file /${TMP_PATH}/menub  2>${TMP_PATH}/resp
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
  eval "MSG52=\"\${MSG${tz}52}\""
  eval "MSG53=\"\${MSG${tz}53}\""
  eval "MSG54=\"\${MSG${tz}54}\""
  eval "MSG55=\"\${MSG${tz}55}\""
  eval "MSG11=\"\${MSG${tz}11}\""  
  eval "MSG60=\"\${MSG${tz}60}\""
  eval "MSG61=\"\${MSG${tz}61}\""
  eval "MSG62=\"\${MSG${tz}62}\""
  eval "MSG63=\"\${MSG${tz}63}\""

  default_resp="l"

  while true; do
    eval "echo \"l \\\"${MSG60}\\\"\"" > "${TMP_PATH}/menua"
    eval "echo \"a \\\"${spoof} ${MSG50}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"y \\\"${dbgutils} dbgutils Addon\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"j \\\"Change Satadom Option (${DOMKIND}) \\\"\"" >> "${TMP_PATH}/menua"
    [ "${platform}" = "geminilake(DT)" ]||[ "${platform}" = "apollolake" ] && eval "echo \"z \\\"${DISPLAYI915} i915 module \\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"b \\\"${MSG51}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"c \\\"${MSG52}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"d \\\"${MSG53}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"e \\\"${MSG54}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"f \\\"${MSG55}\\\"\"" >> "${TMP_PATH}/menua"
    [ "$FRKRNL" = "NO" ] && [ "${platform}" != "epyc7002(DT)" ] && eval "echo \"h \\\"${MSG61}${SHR_EX_TEXT}\\\"\"" >> "${TMP_PATH}/menua"
    [ "$FRKRNL" = "NO" ] && [ "${platform}" != "epyc7002(DT)" ] && eval "echo \"m \\\"${MSG62}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"i \\\"${MSG63}\\\"\"" >> "${TMP_PATH}/menua"
    eval "echo \"k \\\"${MSG11}\\\"\"" >> "${TMP_PATH}/menua"    
    dialog --clear --default-item ${default_resp} --backtitle "`backtitle`" --colors \
      --menu "Choose a option" 0 0 0 --file "${TMP_PATH}/menua" \
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
    c) showsata; default_resp="c";;
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

  while true; do
    eval "echo \"a \\\"${MSG08}\\\"\""                  > "${TMP_PATH}/menuc"
    eval "echo \"b \\\"${MSG09}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"c \\\"${MSG19}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"d \\\"${MSG64}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"e \\\"${MSG12}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"f \\\"${MSG65}\\\"\""                  >> "${TMP_PATH}/menuc"
    eval "echo \"g \\\"${MSG66}\\\"\""                  >> "${TMP_PATH}/menuc"
    dialog --clear --default-item ${default_resp} --backtitle "`backtitle`" --colors \
      --menu "Choose a option" 0 0 0 --file "${TMP_PATH}/menuc" \
    2>${TMP_PATH}/respc
    [ $? -ne 0 ] && return

    case `<"${TMP_PATH}/respc"` in
    a) changeDSMPassword; default_resp="a" ;;
    b) addNewDSMUser; default_resp="b" ;;
    c) CleanSystemPart; default_resp="c" ;;
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
    *) return;;
    esac
    
  done
}

function build-pre-option() {

  default_resp="z"

  MSG64="vmtools(with qemu-guest-agent) addon"

  while true; do
    eval "echo \"a \\\"\${MSG${tz}06} (${LDRMODE}, ${MDLNAME})\\\"\""   > "${TMP_PATH}/menud"
    eval "echo \"b \\\"\${MSG${tz}56}\\\"\""                            >> "${TMP_PATH}/menud"
    eval "echo \"c \\\"\${MSG${tz}41} (${bay})\\\"\""                   >> "${TMP_PATH}/menud"
    eval "echo \"d \\\"${nvmeaction} \${MSG${tz}57}\\\"\""              >> "${TMP_PATH}/menud"
    eval "echo \"e \\\"${vmtoolsaction} \${MSG64}\\\"\""                >> "${TMP_PATH}/menud"
    echo "z exit"                                                       >> "${TMP_PATH}/menud"
    
    dialog --clear --default-item ${default_resp} --backtitle "`backtitle`" --colors \
      --menu "Choose a option" 0 0 0 --file "${TMP_PATH}/menud" \
    2>${TMP_PATH}/respd
    [ $? -ne 0 ] && return

    case `<"${TMP_PATH}/respd"` in
    a) selectldrmode ;    NEXT="z" ;;
    b) remapsata     ;    NEXT="z" ;;
    c) storagepanel;      NEXT="z" ;;    
    d) 
      if [ "${NVMES}" = "false" ]; then 
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
    e)       
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
  sudo timeout 10s udhcpc
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

  fdisk_path="/sbin/fdisk"

  [ "$FRKRNL" = "NO" ] && fdisk_path="/usr/local${fdisk_path}"

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
      --checklist "${TITLE}" 0 0 0 --file "${TMP_PATH}/opts" \
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

# Main loop

# Fix bug /opt/bootlocal.sh ownership 2025.09.15
sudo chown tc:118 /opt/bootlocal.sh

chk_diskcnt
writeConfigKey "general" "diskcount" "${DISKCNT}"
CHKDISK=$(jq -r -e '.general.check_diskcnt' "$USER_CONFIG_FILE")
[ -n "${CHKDISK}" ] && writeConfigKey "general" "check_diskcnt" "false"

# add git download 2023.10.18
cd /dev/shm
if [ -d /dev/shm/tcrp-addons ]; then
  echo "tcrp-addons already downloaded!"    
else    
  git clone --depth=1 "https://github.com/PeterSuh-Q3/tcrp-addons.git"
  if [ $? -ne 0 ]; then
    git clone --depth=1 "https://gitea.com/PeterSuh-Q3/tcrp-addons.git"
    git clone --depth=1 "https://gitea.com/PeterSuh-Q3/tcrp-modules.git"
  fi    
fi
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

country=$(curl -s ipinfo.io | grep country | awk '{print $2}' | cut -c 2-3 )

if [ "${ucode}" == "null" ]; then 
  lcode="${country}"
else
  if [ "${lcode}" != "${country}" ]; then
    echo -n "Country code ${country} has been detected. Do you want to change your locale settings to ${country}? [yY/nN] : "
    readanswer    
    if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then    
      lcode="${country}"
    fi
  fi    
fi

tz="${lcode}"

case "${lcode}" in
US) ucode="en_US";;
KR) ucode="ko_KR";;
JP) ucode="ja_JP";;
CN) ucode="zh_CN";;
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

[ "$FRKRNL" = "NO" ] && writexsession

if [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep gettext | wc -w) -eq 0 ]; then
    tce-load -wi gettext
    if [ $? -eq 0 ]; then
        echo "Download gettext.tcz OK, Permanent installation progress !!!"
        sudo cp -f /tmp/tce/optional/* /mnt/${tcrppart}/cde/optional
        sudo echo "" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "gettext.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "ncursesw.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        echo 'Y'|rploader backup
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
#        echo 'Y'|rploader backup
#        echo "You have finished installing TC dejavu-fonts-ttf package."
#        restart
#     fi
#fi

if [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep rxvt | wc -w) -eq 0 ]; then
    tce-load -wi glibc_apps glibc_i18n_locale unifont rxvt
    if [ $? -eq 0 ]; then
        echo "Download glibc_apps.tcz and glibc_i18n_locale.tcz OK, Permanent installation progress !!!"
        sudo cp -f /tmp/tce/optional/* /mnt/${tcrppart}/cde/optional
        sudo echo "" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "glibc_apps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "glibc_i18n_locale.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "unifont.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        sudo echo "rxvt.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
        echo 'Y'|rploader backup

        echo
        echo "You have finished installing TC Unicode package and urxvt."
        restart
    else
        echo "Download glibc_apps.tcz, glibc_i18n_locale.tcz FAIL !!!"
    fi
fi

# for 2Byte Language
[ ! -d /usr/lib/locale ] && sudo mkdir /usr/lib/locale
export LANG=${ucode}.UTF-8
export LC_ALL=${ucode}.UTF-8
set -o allexport

if [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep rxvt | wc -w) -gt 0 ]; then
  
  sudo localedef -c -i ${ucode} -f UTF-8 ${ucode}.UTF-8
  sudo localedef -f UTF-8 -i ${ucode} ${ucode}.UTF-8

  if [ $(cat ~/.Xdefaults|grep "URxvt.background: black" | wc -w) -eq 0 ]; then
    echo "URxvt.background: black"  >> ~/.Xdefaults
  fi
  if [ $(cat ~/.Xdefaults|grep "URxvt.foreground: white" | wc -w) -eq 0 ]; then    
    echo "URxvt.foreground: white"  >> ~/.Xdefaults
  fi
  if [ $(cat ~/.Xdefaults|grep "URxvt.transparent: true" | wc -w) -eq 0 ]; then    
    echo "URxvt.transparent: true"  >> ~/.Xdefaults
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

#gettext
[ ! -f /home/tc/lang.tgz ] && curl -kLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/lang.tgz > /dev/null 2>&1
[ ! -d "/usr/local/share/locale" ] && sudo mkdir -p "/usr/local/share/locale"
gunzip -c lang.tgz | sudo tar -xvf - -C /usr/local/share/locale > /dev/null 2>&1
locale > /dev/null 2>&1
#End Locale Setting process
export TEXTDOMAINDIR="/usr/local/share/locale"
set -o allexport
tz="ZZ"
load_zz

if [ "${ucode}" != "${config_ucode}" ]; then
  urxvt -geometry 78x32+10+0 -fg orange -title \"TCRP-mshell urxvt Menu\" -e /home/tc/menu.sh
fi

# Download ethtool
if [ "$FRKRNL" = "NO" ] && [ "$(which ethtool)_" == "_" ]; then
   echo "ethtool does not exist, install from tinycore"
   tce-load -iw ethtool iproute2 2>&1 >/dev/null
   sudo echo "ethtool.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
   sudo echo "iproute2.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

sortnetif

if [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep "kmaps.tczglibc_apps.tcz" | wc -w) -gt 0 ]; then
    sudo sed -i "/kmaps.tczglibc_apps.tcz/d" /mnt/${tcrppart}/cde/onboot.lst    
    sudo echo "glibc_apps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
    sudo echo "kmaps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
    echo 'Y'|rploader backup
    
    echo
    echo "We have finished bug fix for /mnt/${tcrppart}/cde/onboot.lst."
    restart
fi    

if [ "${KEYMAP}" = "null" ]; then
    LAYOUT="qwerty"
    KEYMAP="us"
    writeConfigKey "general" "layout" "${LAYOUT}"
    writeConfigKey "general" "keymap" "${KEYMAP}"
fi

if [ "${I915MODE}" = "null" ]; then
    I915MODE="1"
    writeConfigKey "general" "i915mode" "${I915MODE}"
fi

if [ "${DMPM}" = "null" ]; then
    DMPM="DDSML"
    writeConfigKey "general" "devmod" "${DMPM}"          
fi

if [ "${BUS}" = "mmc"  ]; then
    DMPM="EUDEV"
    writeConfigKey "general" "devmod" "${DMPM}"          
fi

if [ "${NVMES}" = "null"  ]; then
    NVMES="false"
    writeConfigKey "general" "nvmesystem" "${NVMES}"
fi

if [ "${VMTOOLS}" = "null"  ]; then
    VMTOOLS="false"
    writeConfigKey "general" "vmtools" "${VMTOOLS}"
fi

[ "${NVMES}" = "false" ] && BLOCK_DDSML="N" || BLOCK_DDSML="Y"

if [ "${LDRMODE}" = "null" ]; then
    LDRMODE="FRIEND"
    writeConfigKey "general" "loadermode" "${LDRMODE}"          
fi

if [ "${MDLNAME}" = "null" ]; then
    MDLNAME="all-modules"
    writeConfigKey "general" "modulename" "${MDLNAME}"          
fi

# Get actual IP
IP="$(/sbin/ifconfig | grep -i "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -c 6- )"

  if [ ! -n "${MACADDR1}" ]; then
    MACADDR1=`./macgen.sh "realmac" "eth0" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac1" "${MACADDR1}"
  fi
if [ $(/sbin/ifconfig | grep eth1 | wc -l) -gt 0 ]; then
  MACADDR2="$(jq -r -e '.extra_cmdline.mac2' $USER_CONFIG_FILE)"
  NETNUM="2"
  if [ ! -n "${MACADDR2}" ]; then
    MACADDR2=`./macgen.sh "realmac" "eth1" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac2" "${MACADDR2}"
  fi
fi  
if [ $(/sbin/ifconfig | grep eth2 | wc -l) -gt 0 ]; then
  MACADDR3="$(jq -r -e '.extra_cmdline.mac3' $USER_CONFIG_FILE)"
  NETNUM="3"
  if [ ! -n "${MACADDR3}" ]; then
    MACADDR3=`./macgen.sh "realmac" "eth2" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac3" "${MACADDR3}"
  fi
fi  
if [ $(/sbin/ifconfig | grep eth3 | wc -l) -gt 0 ]; then
  MACADDR4="$(jq -r -e '.extra_cmdline.mac4' $USER_CONFIG_FILE)"
  NETNUM="4"
  if [ ! -n "${MACADDR4}" ]; then
    MACADDR4=`./macgen.sh "realmac" "eth3" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac4" "${MACADDR4}"
  fi
fi  

if [ $(/sbin/ifconfig | grep eth4 | wc -l) -gt 0 ]; then
  MACADDR5="$(jq -r -e '.extra_cmdline.mac5' $USER_CONFIG_FILE)"
  NETNUM="5"
  if [ ! -n "${MACADDR5}" ]; then
    MACADDR5=`./macgen.sh "realmac" "eth4" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac5" "${MACADDR5}"
  fi
fi  
if [ $(/sbin/ifconfig | grep eth5 | wc -l) -gt 0 ]; then
  MACADDR6="$(jq -r -e '.extra_cmdline.mac6' $USER_CONFIG_FILE)"
  NETNUM="6"
  if [ ! -n "${MACADDR6}" ]; then
    MACADDR6=`./macgen.sh "realmac" "eth5" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac6" "${MACADDR6}"
  fi
fi  
if [ $(/sbin/ifconfig | grep eth6 | wc -l) -gt 0 ]; then
  MACADDR7="$(jq -r -e '.extra_cmdline.mac7' $USER_CONFIG_FILE)"
  NETNUM="7"
  if [ ! -n "${MACADDR7}" ]; then
    MACADDR7=`./macgen.sh "realmac" "eth6" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac7" "${MACADDR7}"
  fi
fi  
if [ $(/sbin/ifconfig | grep eth7 | wc -l) -gt 0 ]; then
  MACADDR8="$(jq -r -e '.extra_cmdline.mac8' $USER_CONFIG_FILE)"
  NETNUM="8"
  if [ ! -n "${MACADDR8}" ]; then
    MACADDR8=`./macgen.sh "realmac" "eth7" ${MODEL}`
    writeConfigKey "extra_cmdline" "mac8" "${MACADDR8}"
  fi
fi  


CURNETNUM="$(jq -r -e '.extra_cmdline.netif_num' $USER_CONFIG_FILE)"
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

if [ $tcrppart == "mmc3" ]; then
    tcrppart="mmcblk0p3"
fi    

# Download dialog
if [ "$FRKRNL" = "NO" ] && [ "$(which dialog)_" == "_" ]; then
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tce/optional/dialog.tcz -o /mnt/${tcrppart}/cde/optional/dialog.tcz
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tce/optional/dialog.tcz.dep -o /mnt/${tcrppart}/cde/optional/dialog.tcz.dep
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tce/optional/dialog.tcz.md5.txt -o /mnt/${tcrppart}/cde/optional/dialog.tcz.md5.txt
    tce-load -i dialog
    if [ $? -eq 0 ]; then
        echo "Install dialog OK !!!"
    else
        tce-load -iw dialog
    fi
    sudo echo "dialog.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download ntpclient
if [ "$FRKRNL" = "NO" ] && [ "$(which ntpclient)_" == "_" ]; then
   echo "ntpclient does not exist, install from tinycore"
   tce-load -iw ntpclient 
   sudo echo "ntpclient.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download mdadm
if [ "$FRKRNL" = "NO" ] && [ "$(which mdadm)_" == "_" ]; then  
    echo "mdadm does not exist, install from tinycore"
    tce-load -iw mdadm 
    sudo echo "mdadm.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download sqlite3-bin
if [ "$FRKRNL" = "NO" ] && [ "$(which sqlite3)_" == "_" ]; then 
    echo "sqlite3 does not exist, install from tinycore"
    tce-load -iw sqlite3-bin 
    sudo echo "sqlite3-bin.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi    

# Download pigz
if [ "$FRKRNL" = "NO" ] && [ "$(which pigz)_" == "_" ]; then
    echo "pigz does not exist, bringing over from repo"
    curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tools/pigz
    chmod 700 pigz
    sudo mv -vf pigz /usr/local/bin/
    echo 'Y'|rploader backup
fi

#if [ "$FRKRNL" = "YES" ]; then
    #overwrite GNU tar and patch for friend
#    sudo rm /usr/bin/tar
#    sudo curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tools/tar -o /usr/bin/tar
#    sudo chmod +x /usr/bin/tar
    
#    sudo rm /usr/bin/patch
#    sudo curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tools/patch -o /usr/bin/patch
#    sudo chmod +x /usr/bin/patch
#fi    

# Download dtc, Don't used anymore 24.9.13
#if [ "$(which dtc)_" == "_" ]; then
#    echo "dtc dos not exist, Downloading dtc binary"
#    curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tools/dtc
#    chmod 700 dtc
#    sudo mv -vf dtc /usr/local/bin/
#fi   

# Download bspatch
getbspatch

# Download kmaps
if [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep kmaps | wc -w) -eq 0 ]; then
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tce/optional/kmaps.tcz -o /mnt/${tcrppart}/cde/optional/kmaps.tcz
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/tce/optional/kmaps.tcz.md5.txt -o /mnt/${tcrppart}/cde/optional/kmaps.tcz.md5.txt
    tce-load -i kmaps
    if [ $? -eq 0 ]; then
        echo "Install kmaps OK !!!"
    else
        tce-load -iw kmaps
    fi
    sudo echo "kmaps.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download firmware-broadcom_bnx2x
if [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep firmware-broadcom_bnx2x | wc -w) -eq 0 ]; then
    installtcz "firmware-broadcom_bnx2x.tcz"
    echo "Install firmware-broadcom_bnx2x OK !!!"
    echo 'Y'|rploader backup
fi

# Download btrfs-progs
if [ "$FRKRNL" = "NO" ] && [ $(cat /mnt/${tcrppart}/cde/onboot.lst|grep btrfs-progs | wc -w) -eq 0 ]; then
    echo "btrfs-progs does not exist, install from tinycore"
    tce-load -iw btrfs-progs
    sudo echo "btrfs-progs.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# Download lvm2
if [ "$FRKRNL" = "NO" ] && [ "$(which lvm)_" == "_" ]; then
    echo "lvm2 does not exist, install from tinycore"
    tce-load -iw lvm2
    sudo echo "lvm2.tcz" >> /mnt/${tcrppart}/cde/onboot.lst
fi

# copy tinycore pack and backup, except scsi-6.1.2-tinycore64.tcz
if [ $(ls /tmp/tce/optional/ | grep -v scsi-6.1.2-tinycore64.tcz | wc -l) -gt 0 ]; then
    sudo cp -f /tmp/tce/optional/* /mnt/${tcrppart}/cde/optional
    echo 'Y'|rploader backup
fi

# Download scsi-6.1.2-tinycore64.tcz
if [ "$FRKRNL" = "NO" ] && [ $(lspci -d ::107 | wc -l) -gt 0 ]; then
    tce-load -iw scsi-6.1.2-tinycore64.tcz
fi

NEXT="m"
setSuggest $MODEL
bfbay=$(jq -r -e '.general.bay' "$USER_CONFIG_FILE")
if [ -n "${bfbay}" ]; then
  bay=${bfbay}
fi
writeConfigKey "general" "bay" "${bay}"

chk_shr_ex

# Until urxtv is available, Korean menu is used only on remote terminals.
while true; do
  [ "${NVMES}" = "false" ] && nvmeaction="Add" || nvmeaction="Remove"
  [ "${VMTOOLS}" = "false" ] && vmtoolsaction="Add" || vmtoolsaction="Remove"
  eval "echo \"c \\\"\${MSG${tz}01}, (${DMPM})\\\"\""     > "${TMP_PATH}/menu" 
  eval "echo \"m \\\"\${MSG${tz}02}, (${MODEL})\\\"\""   >> "${TMP_PATH}/menu"
  if [ -n "${MODEL}" ]; then
    eval "echo \"j \\\"\${MSG${tz}05} (${BUILD})\\\"\""  >> "${TMP_PATH}/menu"  
    eval "echo \"s \\\"\${MSG${tz}03}\\\"\""             >> "${TMP_PATH}/menu"
    eval "echo \"a \\\"\${MSG${tz}04} 1\\\"\""           >> "${TMP_PATH}/menu"
    [ $(/sbin/ifconfig | grep eth1 | wc -l) -gt 0 ] && eval "echo \"f \\\"\${MSG${tz}04} 2\\\"\""         >> "${TMP_PATH}/menu"
    [ $(/sbin/ifconfig | grep eth2 | wc -l) -gt 0 ] && eval "echo \"g \\\"\${MSG${tz}04} 3\\\"\""         >> "${TMP_PATH}/menu"
    [ $(/sbin/ifconfig | grep eth3 | wc -l) -gt 0 ] && eval "echo \"h \\\"\${MSG${tz}04} 4\\\"\""         >> "${TMP_PATH}/menu"
    [ $(/sbin/ifconfig | grep eth4 | wc -l) -gt 0 ] && eval "echo \"i \\\"\${MSG${tz}04} 5\\\"\""         >> "${TMP_PATH}/menu"
    [ $(/sbin/ifconfig | grep eth5 | wc -l) -gt 0 ] && eval "echo \"o \\\"\${MSG${tz}04} 6\\\"\""         >> "${TMP_PATH}/menu"
    [ $(/sbin/ifconfig | grep eth6 | wc -l) -gt 0 ] && eval "echo \"t \\\"\${MSG${tz}04} 7\\\"\""         >> "${TMP_PATH}/menu"
    [ $(/sbin/ifconfig | grep eth7 | wc -l) -gt 0 ] && eval "echo \"v \\\"\${MSG${tz}04} 8\\\"\""         >> "${TMP_PATH}/menu"
    eval "echo \"z \\\"\${MSGZZ67}\\\"\""                >> "${TMP_PATH}/menu"
    eval "echo \"p \\\"\${MSG${tz}18} (${BUILD}, ${LDRMODE}, ${MDLNAME})\\\"\""   >> "${TMP_PATH}/menu"      
  fi
  [ "$FRKRNL" = "YES" ] && 
  eval "echo \"y \\\"\${MSG${tz}58}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"n \\\"\${MSG${tz}59}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"x \\\"\${MSG${tz}07}\\\"\""               >> "${TMP_PATH}/menu"  
  eval "echo \"u \\\"\${MSG${tz}10}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"l \\\"\${MSG${tz}39}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"b \\\"\${MSG${tz}13}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"r \\\"\${MSG${tz}14}\\\"\""               >> "${TMP_PATH}/menu"
  eval "echo \"e \\\"\${MSG${tz}15}\\\"\""               >> "${TMP_PATH}/menu"
  dialog --clear --default-item ${NEXT} --backtitle "`backtitle`" --colors \
    --menu "${result}" 0 0 0 --file "${TMP_PATH}/menu" \
    2>${TMP_PATH}/resp
  [ $? -ne 0 ] && break
  case `<"${TMP_PATH}/resp"` in
    c) seleudev;        NEXT="m" ;;  
    m) modelMenu;       NEXT="j" ;;
    j) selectversion ;    NEXT="s" ;;     
    s) serialMenu;      NEXT="a" ;;
    a) macMenu "eth0"
    [ $(/sbin/ifconfig | grep eth1 | wc -l) -gt 0 ] && NEXT="f" || NEXT="p" ;;
    f) macMenu "eth1"
    [ $(/sbin/ifconfig | grep eth2 | wc -l) -gt 0 ] && NEXT="g" || NEXT="p" ;;
    g) macMenu "eth2"
    [ $(/sbin/ifconfig | grep eth3 | wc -l) -gt 0 ] && NEXT="h" || NEXT="p" ;;
    h) macMenu "eth3"
    [ $(/sbin/ifconfig | grep eth4 | wc -l) -gt 0 ] && NEXT="i" || NEXT="p" ;;
    i) macMenu "eth4"
    [ $(/sbin/ifconfig | grep eth5 | wc -l) -gt 0 ] && NEXT="o" || NEXT="p" ;;
    o) macMenu "eth5"
    [ $(/sbin/ifconfig | grep eth6 | wc -l) -gt 0 ] && NEXT="t" || NEXT="p" ;;
    t) macMenu "eth6"
    [ $(/sbin/ifconfig | grep eth7 | wc -l) -gt 0 ] && NEXT="v" || NEXT="p" ;;
    v) macMenu "eth7";    NEXT="p" ;; 
    z) build-pre-option ; NEXT="p" ;;
    p) if [ "${LDRMODE}" == "FRIEND" ]; then
         make "fri" "${prevent_init}" 
       else  
         make "jot" "${prevent_init}"
       fi  
       if [ "$FRKRNL" = "YES" ]; then
         NEXT="y"
       else
         NEXT="r"
       fi  
       ;;
    y) sudo /root/boot.sh normal ;;
    n) additional;      NEXT="p" ;;
    x) synopart;        NEXT="r" ;;
    u) editUserConfig;  NEXT="p" ;;
    l) langMenu ;;
    b) backup ;;
    r) restart ;;
    e) sync && writebackcache && sudo poweroff ;;
  esac
done

clear
echo -e "Call \033[1;32m./menu.sh\033[0m to return to menu"
