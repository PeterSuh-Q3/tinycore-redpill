#!/bin/bash

set -u # Unbound variable errors are not allowed

##### INCLUDES ######################################################################################
. /home/tc/functions.sh
#####################################################################################################


# lock
#exec 304>"/tmp/menu.lock"
#flock -n 304 || {
#  MSG="The menu.sh instance is already running in another terminal. To avoid conflicts, please operate in one instance only."
#  dialog --colors --aspect 50 --title "$(TEXT "Error")" --msgbox "${MSG}" 0 0
#  exit 1
#}
#trap 'flock -u 304; rm -f "/tmp/menu.lock"' EXIT INT TERM HUP


function check_internet() {
  ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1
  return $?
}

function gitclone() {
    git clone -b master --single-branch --depth=1 https://github.com/PeterSuh-Q3/redpill-load.git
}

function gitdownload() {

    cd /home/tc
    git config --global http.sslVerify false    
    if [ -d /home/tc/redpill-load ]; then
        echo "Loader sources already downloaded, pulling latest"
        cd /home/tc/redpill-load
        git pull
        if [ $? -ne 0 ]; then
           cd /home/tc
           rploader clean
           gitclone    
        fi   
        cd /home/tc
    else
        gitclone
    fi
    
}

function mmc_modprobe() {
  echo "excute modprobe for mmc(include sd)..."
  sudo /sbin/modprobe mmc_block
  sudo /sbin/modprobe mmc_core
  sudo /sbin/modprobe rtsx_pci
  sudo /sbin/modprobe rtsx_pci_sdmmc
  sudo /sbin/modprobe sdhci
  sudo /sbin/modprobe sdhci_pci
  sleep 1
  if [ `/sbin/lsmod |grep -i mmc|wc -l` -gt 0 ] ; then
      echo "Module mmc loaded succesfully!!!"
  else
      echo "Module mmc failed to load successfully!!!"
  fi
}

function extract_old_shell() {

  local TAG="${1}"
  local REPO="PeterSuh-Q3/tinycore-redpill"
  local WORK_DIR="/dev/shm"
  local DEST="/home/tc"
  local FILES=("menu.sh" "menu_m.sh" "functions.sh" "i18n.h")

  if [ -z "$TAG" ]; then
    echo "Usage: fetch_tcredpill <tag>  (예: fetch_tcredpill v1.2.8.0)"
    return 1
  fi

  local VER="${TAG#v}"
  local REPONAME="tinycore-redpill"
  local FILENAME="${REPONAME}-${VER}.zip"
  local URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.zip"
  local TMP_ZIP="${WORK_DIR}/${FILENAME}"
  local EXTRACT_DIR="${WORK_DIR}/${REPONAME}-${VER}"

  echo "[*] TAG     : ${TAG}"
  echo "[*] VERSION : ${VER}"
  echo "[*] URL     : ${URL}"
  echo "[*] WORK    : ${WORK_DIR}"
  echo "[*] DEST    : ${DEST}"
  echo ""

  echo "[+] Downloading ${FILENAME} ..."
  curl -kL --retry 3 --retry-delay 2 -o "${TMP_ZIP}" "${URL}"

  if [ $? -ne 0 ] || [ ! -s "${TMP_ZIP}" ]; then
    echo "[!] Download failed or file is empty: ${URL}"
    return 1
  fi

  echo "[+] Extracting to ${EXTRACT_DIR} ..."
  unzip -o "${TMP_ZIP}" -d "${WORK_DIR}" 2>/dev/null

  if [ $? -ne 0 ]; then
    echo "[!] Extraction failed."
    rm -f "${TMP_ZIP}"
    return 1
  fi

  echo "[+] Copying files to ${DEST} ..."
  for f in "${FILES[@]}"; do
    if [ -f "${EXTRACT_DIR}/${f}" ]; then
      cp -v "${EXTRACT_DIR}/${f}" "${DEST}/"
    else
      echo "[!] Not found: ${f}"
    fi
  done
  chmod +x "${DEST}"/*.sh 2>/dev/null

  rm -f "${TMP_ZIP}"
  rm -rf "${EXTRACT_DIR}"

  echo ""
  echo "[+] Done. Copied files in ${DEST}:"
  for f in "${FILES[@]}"; do
    ls -lh "${DEST}/${f}" 2>/dev/null
  done
}

if [ $(/sbin/blkid | grep "6234-C863" | wc -l) -ge 2 ]; then
    if [ $(/sbin/blkid | grep "1234-5678" | wc -l) -eq 1 ]; then
        echo "There is Synodisk Injected Bootloader..."
    else
        echo "There is two more bootloder exists, program Exit!!!"
        read answer
        exit 99
    fi    
fi

mmc_modprobe

getloaderdisk

if [ -z "${loaderdisk}" ]; then
    echo "Not Supported Loader BUS Type, program Exit!!!"
    read answer
    exit 99
fi

getBus "${loaderdisk}" 

tcrppart="${loaderdisk}3"

if [ -d /mnt/${tcrppart}/tcrp-addons/ ] && [ -d /mnt/${tcrppart}/tcrp-modules/ ]; then
    echo "Repositories for offline loader building have been confirmed. Copy the repositories to the required location..."
    echo "Press any key to continue..."    
    read answer
    cp -rf /mnt/${tcrppart}/redpill-load/ ~/
    mv -f /mnt/${tcrppart}/tcrp-addons/ /dev/shm/
    mv -f /mnt/${tcrppart}/tcrp-modules/ /dev/shm/
    echo "Go directly to the menu. Press any key to continue..."
    read answer
else
    # Record the start time.
    start_time=$(date +%s)
    while true; do
      if check_internet; then
        [ -z "${1-}" ] && getlatestmshell "noask"
        break
      fi
      # Calculate the elapsed time and exit the loop if it exceeds 15 seconds.
      current_time=$(date +%s)
      elapsed=$(( current_time - start_time ))
      if [ $elapsed -ge 30 ]; then
        echo "Internet connection wait time exceeded 30 seconds"
        break
      fi
      sleep 2
      echo "Waiting for internet connection by checking 8.8.8.8 (Google DNS)..."
    done
    echo -n "Checking GitHub Access -> "
    curl --insecure -L -s https://raw.githubusercontent.com/about.html -O 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "Error: GitHub is unavailable. Please try again later."
        read answer
        exit 99
    fi
    gitdownload
fi

if [ -z "${1-}" ]; then
  [ -f /tmp/test_mode ] && rm -f /tmp/test_mode
  oldver="unknown"  # 또는 원하는 기본값
else
  if [ "$1" = "test" ]; then
    rm -f /tmp/test_mode && touch /tmp/test_mode
    oldver="test"
  else
    oldver="$1"
  fi
fi

if [ -f /dev/shm/offline ]; then
    offline="YES"
else
    offline="NO"
fi  

if [ "${offline}" = "NO" ]; then
    curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/models.json
    if [ "$oldver" = "test" ]; then
      cecho g "###############################  This is Test Mode  ############################"
      curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/functions_t.sh -o functions.sh
      curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/menu_m.sh
      chmod +x /home/tc/redpill-load/*.sh
      /bin/cp -vf /home/tc/redpill-load/build-loader_t.sh /home/tc/redpill-load/build-loader.sh
      /bin/cp -vf /home/tc/redpill-load/ext-manager_t.sh /home/tc/redpill-load/ext-manager.sh
      /bin/cp -vf /home/tc/redpill-load/config/pats_t.json /home/tc/redpill-load/config/pats.json
    elif [ "$oldver" = "unknown" ]; then
      curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/functions.sh
    else
      cecho g "###############################  This is for version ${oldver} ############################"
      extract_old_shell "$oldver"
      if [ $? -ne 0 ]; then
        echo "[!] extract_old_shell failed. Falling back to master functions.sh ..."
        curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/functions.sh
        curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/menu_m.sh
      fi      
      sleep 2
    fi

    # 다운로드 후 새로 받아온 파일을 다시 소싱하여 현재 환경에 즉시 반영 26.03.11
    # 재소싱 전 파일 존재 확인
    if [ -f /home/tc/functions.sh ]; then
      . /home/tc/functions.sh
    else
      echo "[!] functions.sh not found, cannot source."
      exit 1
    fi
fi
if [ ! -f /home/tc/menu_m.sh ]; then
  echo "[!] menu_m.sh not found, cannot execute."
  exit 1
fi
/home/tc/menu_m.sh
exit 0
