#!/bin/bash

set -u # Unbound variable errors are not allowed

##### INCLUDES ######################################################################################
# GitHub 일시 오류(404/400/rate-limit)로 받은 에러 본문이 스크립트를 덮어써 깨지는 것을 방지.
# 임시파일로 받아 (1)HTTP 성공(-f) (2)비어있지 않음 (3)sentinel 포함 (4)bash 문법 OK 일 때만 교체.
# 검증 실패 시 기존 파일을 보존(덮어쓰지 않음).
function safe_fetch() {
    local _url="$1" _dest="$2" _sentinel="$3"
    local _tmp="/dev/shm/.safe_fetch.$$"
    if curl -fskL --retry 3 --retry-delay 2 -o "${_tmp}" "${_url}" \
       && [ -s "${_tmp}" ] \
       && grep -q "${_sentinel}" "${_tmp}" \
       && bash -n "${_tmp}" 2>/dev/null; then
        mv -f "${_tmp}" "${_dest}"
        chmod +x "${_dest}" 2>/dev/null
        return 0
    fi
    echo "[!] safe_fetch: invalid/failed download, keeping existing ${_dest} (${_url})"
    rm -f "${_tmp}"
    return 1
}

# 자동 업데이트(safe_fetch) 대상 브랜치. functions.sh 소싱 전이라 is_alpine()이
# 아직 없으므로 동일 조건을 인라인으로 판별(Alpine에서 main으로 자기 자신을
# 덮어써 패치가 무력화되는 사고가 실측 확인되어(2026-07-12) 분리). main은
# v1.3.1.1에서 동결, alpine-redpill이 v1.4.0.0부터 이어받음(2026-07-15).
if [ -f /etc/alpine-release ]; then UPDATE_BRANCH="alpine-redpill"; else UPDATE_BRANCH="main"; fi

# functions.sh 가 비었거나(이전 GitHub 오류 다운로드로 깨짐) 문법이 깨졌으면 소싱 전 안전 재다운로드.
# (getloaderdisk 등 함수가 정의되지 않아 이후 'command not found'/'unbound variable' 로 죽는 것을 방지)
if [ ! -s /home/tc/functions.sh ] || ! grep -q 'rploaderver=' /home/tc/functions.sh 2>/dev/null || ! bash -n /home/tc/functions.sh 2>/dev/null; then
    echo "[!] /home/tc/functions.sh missing or corrupt - re-fetching from ${UPDATE_BRANCH}..."
    safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/functions.sh" "/home/tc/functions.sh" "rploaderver="
fi
. /home/tc/functions.sh
#####################################################################################################
if grep -q 'arpl' ~/.profile; then
  sed -i '/arpl/d' ~/.profile
  export PATH='/home/tc/.local/bin:/usr/local/sbin:/usr/local/bin:/apps/bin:/usr/sbin:/usr/bin:/sbin:/bin'
fi
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

# 바이너리 풀경로 해석. TinyCore 는 ip/ethtool 이 /usr/local/sbin 에 있는데
# sudo secure_path 에는 그 경로가 빠져 있어 이름만으론 'command not found'
# 로 조용히 실패한다. 모든 후보 경로를 직접 뒤져 절대경로를 반환한다.
function _find_bin() {
  local name="$1" p
  for p in /usr/local/sbin /usr/local/bin /sbin /usr/sbin /bin /usr/bin; do
    [ -x "${p}/${name}" ] && { echo "${p}/${name}"; return 0; }
  done
  return 1
}

# 베어메탈 물리 NIC 는 가상랜 대비 링크 협상(auto-negotiation)/DHCP 응답이
# 느린 경우가 많다. 물리 인터페이스를 강제로 link down/up 시켜 재협상을
# 유발하고, DHCP 임대를 갱신해 인터넷 체크 성공 확률을 높인다.
function nic_link_kick() {
  local ifaces dev IP ETHTOOL IFCONFIG UDHCPC
  IP=$(_find_bin ip)
  ETHTOOL=$(_find_bin ethtool)
  IFCONFIG=$(_find_bin ifconfig)
  UDHCPC=$(_find_bin udhcpc)
  # loopback/가상 인터페이스 제외, 물리 NIC 만 대상
  ifaces=$(ls /sys/class/net 2>/dev/null | grep -E '^(eth|en|em|p[0-9]+p)')
  [ -z "${ifaces}" ] && return 0
  for dev in ${ifaces}; do
    echo "Kicking NIC '${dev}' (link down/up + DHCP renew) to wake slow bare-metal link..."
    if [ -n "${IP}" ]; then
      sudo "${IP}" link set "${dev}" down 2>/dev/null
      sleep 1
      sudo "${IP}" link set "${dev}" up   2>/dev/null
    elif [ -n "${IFCONFIG}" ]; then
      sudo "${IFCONFIG}" "${dev}" down 2>/dev/null
      sleep 1
      sudo "${IFCONFIG}" "${dev}" up   2>/dev/null
    fi
    # 일부 PHY 는 down/up 만으로 부족 → autoneg 재시작 시도(있을 때만)
    [ -n "${ETHTOOL}" ] && sudo "${ETHTOOL}" -r "${dev}" 2>/dev/null
    # DHCP 재요청(udhcpc 가 있을 때만, 백그라운드로)
    [ -n "${UDHCPC}" ] && sudo "${UDHCPC}" -i "${dev}" -n -q -t 3 -T 3 2>/dev/null &
  done
  # 링크업 후 캐리어 안정화 대기
  sleep 3
}

function gitclone() {
    git clone -b master --single-branch --depth 1 --filter=blob:none https://github.com/PeterSuh-Q3/redpill-load.git
}

# redpill-load의 확장(extension) 다운로드 함수 rpt_download_remote()는
# include/file.sh 안에서 curl -kns ...(-n = --netrc)를 쓰는데, Alpine의
# musl-curl(8.21.0 실측)은 ~/.netrc 파일이 없으면 이를 무시하지 않고
# CURLE_READ_ERROR(exit 26)로 즉시 실패시킴 - glibc curl과 다른 동작.
# --retry를 아무리 늘려도 매 시도가 동일하게 즉시 실패하므로 재시도로는
# 해결 안 되고 -n 자체를 제거해야 함(2026-07-12 실측: -n 있으면 매번
# exit 26, 제거하면 즉시 성공 확인). --retry-all-errors도 함께 강화해
# 이 문제 외의 다른 순간적 네트워크 오류에 대한 재시도 커버리지를 높인다.
# TC(glibc curl 7.67.0, box 실측)에도 ~/.netrc가 없어 -n이 원래도 사실상
# no-op이었을 가능성이 높지만, "아마 무해하다"에 기대지 않고 TC 동작을
# 그대로 보존하기 위해 is_alpine일 때만 패치를 적용한다.
function patch_rpt_download_retry() {
    is_alpine || return 0
    local f="/home/tc/redpill-load/include/file.sh"
    [ -f "$f" ] || return 0
    sed -i 's/-kns --location/-ks --location/' "$f"
    sed -i 's/--retry 5 /--retry 8 --retry-delay 3 --retry-all-errors /' "$f"
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
    patch_rpt_download_retry
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
  local FILES=("menu_m.sh" "functions.sh" "i18n.h" "my.sh.gz")

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
  # 함수 호출부 주석 처리 (실제 함수명: addon_gitdown)
  sed -i 's/^\(\s*\)addon_gitdown\b/\1# addon_gitdown  # disabled/' /home/tc/menu_m.sh
  sed -i 's/offline="YES"/offline="NO"/g' /home/tc/functions.sh
 
}

function get_dep_hashes() {
  local TAG="${1}"
  local REPO="PeterSuh-Q3/tinycore-redpill"
  local API_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"

  # 릴리즈 노트 body 가져오기
  local BODY
  BODY=$(curl -skL "${API_URL}" | jq -r '.body')

  if [ -z "${BODY}" ] || [ "${BODY}" = "null" ]; then
    echo "[!] Release notes not found for tag: ${TAG}"
    return 1
  fi

  # 첫 번째 라인 = tcrp-addons 해시
  local ADDONS_HASH
  ADDONS_HASH=$(echo "${BODY}" | sed -n '1p' | tr -d '[:space:]')

  # 두 번째 라인 = tcrp-modules 해시
  local MODULES_HASH
  MODULES_HASH=$(echo "${BODY}" | sed -n '2p' | tr -d '[:space:]')

  # 세 번째 라인 = redpill-load 해시
  local LOAD_HASH
  LOAD_HASH=$(echo "${BODY}" | sed -n '3p' | tr -d '[:space:]')

  if [ -z "${ADDONS_HASH}" ] || [ -z "${MODULES_HASH}" ] || [ -z "${LOAD_HASH}" ]; then
    echo "[!] Hash values are empty. Check release notes format."
    return 1
  fi

  echo "[*] tcrp-addons  hash : ${ADDONS_HASH}"
  echo "[*] tcrp-modules hash : ${MODULES_HASH}"
  echo "[*] redpill-load hash : ${LOAD_HASH}"

  # 전역 변수로 export (호출부에서 사용 가능)
  addons_hash="${ADDONS_HASH}"
  modules_hash="${MODULES_HASH}"
  load_hash="${LOAD_HASH}"
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

TCB=$(readConfigKey "general" "tcbautoupd")
if [ -z "${TCB}" ]; then
    TCB="true"
    writeConfigKey "general" "tcbautoupd" "${TCB}"
fi

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
    # 인터넷 체크: 1차 30초 시도, 실패 시 NIC 강제 link-kick 후
    # 20초 단위로 최대 2회 더 재시도(총 3회). 베어메탈의 느린 NIC 대응.
    # 1차 진입 직후 1회 즉시 체크 → 이미 되면 link-kick 자체를 건너뛰어
    # 가상랜에 불필요한 단절/지연을 주지 않고, 안 될 때만 선제 link-kick
    # 으로 베어메탈의 30초 대기를 줄인다.
    net_ok="false"
    attempt=1
    max_attempt=3
    while [ ${attempt} -le ${max_attempt} ]; do
      if [ ${attempt} -eq 1 ]; then
        timeout=30
        # 이미 연결돼 있으면 link-kick 없이 즉시 통과
        # (getlatestmshell 은 루프 종료 후 net_ok 블록에서 1회만 호출)
        if check_internet; then
          net_ok="true"
          break
        fi
        # 1차도 실패 시점이면 선제 link-kick 으로 느린 NIC 협상을 앞당김
        echo ""
        echo ">>> Internet not ready. Pre-kicking NIC then waiting ${timeout}s (attempt ${attempt}/${max_attempt})..."
        nic_link_kick
      else
        timeout=20
        echo ""
        echo ">>> Internet not ready. Retry ${attempt}/${max_attempt} for ${timeout}s (after NIC link-kick)..."
        nic_link_kick
      fi
      start_time=$(date +%s)
      while true; do
        if check_internet; then
          net_ok="true"
          break
        fi
        current_time=$(date +%s)
        elapsed=$(( current_time - start_time ))
        if [ ${elapsed} -ge ${timeout} ]; then
          echo "Internet connection wait time exceeded ${timeout} seconds (attempt ${attempt}/${max_attempt})"
          break
        fi
        sleep 2
        echo "Waiting for internet connection by checking 8.8.8.8 (Google DNS)... [attempt ${attempt}/${max_attempt}]"
      done
      [ "${net_ok}" = "true" ] && break
      attempt=$(( attempt + 1 ))
    done
    if [ "${net_ok}" = "true" ]; then
      [[ -z "${1-}" && "$TCB" = "true" ]] && getlatestmshell "noask"
    else
      echo "Internet connection failed after ${max_attempt} attempts."
    fi
    echo -n "Checking GitHub Access -> "
    curl --insecure -L -s https://raw.githubusercontent.com/about.html -O 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "Error: GitHub is unavailable. Please try again later."
        read answer
        exit 99
    fi
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
    curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/models.json
    if [ "$oldver" = "test" ]; then
      gitdownload
      cecho g "###############################  This is Test Mode  ############################"
      safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/functions_t.sh" "/home/tc/functions.sh" "rploaderver="
      safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/menu_m.sh" "/home/tc/menu_m.sh" "kver5explatforms"
      chmod +x /home/tc/redpill-load/*.sh
      /bin/cp -vf /home/tc/redpill-load/build-loader_t.sh /home/tc/redpill-load/build-loader.sh
      /bin/cp -vf /home/tc/redpill-load/ext-manager_t.sh /home/tc/redpill-load/ext-manager.sh
      /bin/cp -vf /home/tc/redpill-load/config/pats_t.json /home/tc/redpill-load/config/pats.json
      /bin/cp -vf /home/tc/redpill-load/bundled-exts_t.json /home/tc/redpill-load/bundled-exts.json
    elif [ "$oldver" = "unknown" ]; then
      gitdownload
      #echo "this is normal case not unknown parameter !!!"
      safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/functions.sh" "/home/tc/functions.sh" "rploaderver="
    else
      cecho g "###############################  This is for version ${oldver} ############################"
      extract_old_shell "$oldver"
      if [ $? -ne 0 ]; then
        echo "[!] extract_old_shell failed. Falling back to ${UPDATE_BRANCH} functions.sh ..."
        safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/functions.sh" "/home/tc/functions.sh" "rploaderver="
        safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/menu_m.sh" "/home/tc/menu_m.sh" "kver5explatforms"
      fi

      get_dep_hashes "$oldver"

      echo "addons  : ${addons_hash}"
      echo "modules : ${modules_hash}"
      echo "load    : ${load_hash}"
      
      #/dev/shm 공간 2.5GB 확보, 메뉴빌드전 6GB 이상요구, 3GB /dev/shm 확보완료.
      #sudo umount /dev/shm
      #sudo mount -t tmpfs -o size=2684354560 tmpfs /dev/shm
      
      rm -rf /dev/shm/tcrp-addons
      mkdir -p /dev/shm/tcrp-addons
      git clone --depth 1 --filter=blob:none "https://github.com/PeterSuh-Q3/tcrp-addons.git" /dev/shm/tcrp-addons
      cd /dev/shm/tcrp-addons
      git fetch origin "${addons_hash}"
      git checkout "${addons_hash}"
  
      rm -rf /dev/shm/tcrp-modules
      mkdir -p /dev/shm/tcrp-modules
      git clone --depth 1 --filter=blob:none "https://github.com/PeterSuh-Q3/tcrp-modules.git" /dev/shm/tcrp-modules
      cd /dev/shm/tcrp-modules
      git fetch origin "${modules_hash}"
      git checkout "${modules_hash}"

      rm -rf /home/tc/redpill-load
      mkdir -p /home/tc/redpill-load
      git clone --depth 1 --filter=blob:none "https://github.com/PeterSuh-Q3/redpill-load.git" /home/tc/redpill-load
      cd /home/tc/redpill-load
      git fetch origin "${load_hash}"
      git checkout "${load_hash}"
  
      df -h /dev/shm
      cd /home/tc
      echo "press any key to continue..."
      read answer
      
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

chmod +x /home/tc/menu_m.sh
/home/tc/menu_m.sh
[ -d /dev/shm/tcrp-modules/ ] && rm -rf /dev/shm/tcrp-modules/
exit 0
