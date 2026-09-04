#!/bin/bash

set -u # Unbound variable errors are not allowed

# 2026-07-22: 이 환경의 sshd가 pty-req의 TERM 협상을 제대로 하지 않아, SSH로
# 접속한 세션은 (실제 pty를 요청해도) TERM=dumb으로 떨어지는 것을 실측 확인.
# TERM=dumb에서는 dialog가 terminfo를 못 찾아 "Error opening terminal: unknown"
# 으로 즉시 실패하는데, menu_m.sh의 메인 루프는 dialog 실패 시 화면에 아무
# 표시 없이 조용히 재시도만 반복해("[ dlgret -ne 0 ] && continue") 마치 메뉴가
# 멈춘 것처럼 보인다("다이얼로그 팝업이 안 뜬다" 증상, 152 실기로 재현/확정).
# 시리얼(ttyS0)/tty1은 정상적으로 TERM=linux를 받으므로 SSH 세션에서만
# 나타나는 문제. dialog 호출 전에 안전한 값으로 보정.
if [ -z "${TERM:-}" ] || [ "${TERM}" = "dumb" ]; then
    export TERM=linux
fi

##### INCLUDES ######################################################################################
# raw.githubusercontent.com 은 경로 기준으로 최대 5분(max-age=300) CDN 캐싱한다.
# push 직후 재빌드하면 방금 고친 로직 대신 구버전이 그대로 내려와 디버깅을
# 헷갈리게 만드는 사고가 실측 확인되어(2026-08-18), curl 을 감싸는 함수를 두고
# raw.githubusercontent.com 을 향하는 모든 curl 호출(functions_t.sh 안의 .pat/
# extractor/friend 다운로드 포함, 61곳+)에 요청마다 바뀌는 쿼리스트링을 자동으로
# 붙여 캐시를 우회한다(쿼리스트링이 다르면 캐시 키가 달라져 항상 MISS 로 최신을
# 받아옴을 실측 확인). 다른 도메인(GitHub API, 릴리즈 자산 등)은 건드리지 않는다.
# 실제 curl 바이너리는 `command curl` 로 그대로 호출되므로 옵션/동작은 동일하다.
function curl() {
    local _args=() _a
    for _a in "$@"; do
        case "${_a}" in
            *raw.githubusercontent.com*)
                if [[ "${_a}" == *\?* ]]; then
                    _a="${_a}&_cb=$(date +%s%N 2>/dev/null || date +%s)"
                else
                    _a="${_a}?_cb=$(date +%s%N 2>/dev/null || date +%s)"
                fi
                ;;
        esac
        _args+=("${_a}")
    done
    command curl "${_args[@]}"
}

# Bootstrap GitHub access before functions.sh can be refreshed.  This must run
# before safe_fetch(), otherwise users in networks where GitHub/raw DNS is
# blocked cannot reach the menu to select DoH mode in the first place.
function cleanup_mshell_doh_overrides() {
    # Only remove records created by MSHELL.  Never erase a resolver or host
    # record that a user created independently.
    sudo sed -i '/[[:space:]]# MSHELL DoH$/d' /etc/hosts 2>/dev/null
    sudo sed -i '/^[[:space:]]*nameserver[[:space:]]\+1\.1\.1\.1[[:space:]]\+# MSHELL DoH$/d' /etc/resolv.conf 2>/dev/null
}

function bootstrap_github_access() {
    local cfg mode fallback_dns domain ip
    cfg="/mnt/tcrp/user_config.json"
    [ -f "${cfg}" ] || cfg="/home/tc/user_config.json"
    mode=$(command jq -r '.github_access.mode // "standard"' "${cfg}" 2>/dev/null || echo standard)
    if [ "${mode}" != "doh" ]; then
        cleanup_mshell_doh_overrides
        return 0
    fi
    fallback_dns="1.1.1.1"
    grep -qF "nameserver ${fallback_dns}" /etc/resolv.conf 2>/dev/null || \
        printf 'nameserver %s # MSHELL DoH\n' "${fallback_dns}" | sudo tee -a /etc/resolv.conf >/dev/null
    for domain in github.com raw.githubusercontent.com api.github.com release-assets.githubusercontent.com; do
        ip=$(command curl -fsSkL --connect-timeout 5 \
          "https://cloudflare-dns.com/dns-query?name=${domain}&type=A" \
          -H 'accept: application/dns-json' 2>/dev/null | \
          command jq -r '.Answer[]? | select(.type == 1) | .data' 2>/dev/null | head -n 1)
        if echo "${ip}" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' && \
           ! grep -qE "[[:space:]]${domain}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
            printf '%s\t%s\t# MSHELL DoH\n' "${ip}" "${domain}" | sudo tee -a /etc/hosts >/dev/null
        fi
    done
}

bootstrap_github_access

# Ask about the UI language before the normal repository checkout.  The main
# menu used to do this only after cloning redpill-load and the addon/module
# repositories, which made the first-run language choice arrive far too late.
function offer_detected_locale_early() {
    local cfg ucode country target_ucode locale_prompt lang_archive
    cfg="/mnt/tcrp/user_config.json"
    [ -f "${cfg}" ] || cfg="/home/tc/user_config.json"
    [ -f "${cfg}" ] || return 0
    ucode=$(command jq -r '.general.ucode // "en_US"' "${cfg}" 2>/dev/null || echo en_US)
    [ "${ucode}" = "en_US" ] || return 0

    if [ -n "${MSHELL_TEST_COUNTRY:-}" ]; then
        country="${MSHELL_TEST_COUNTRY^^}"
    else
        country=$(command curl -fsSkL --connect-timeout 5 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]')
    fi
    case "${country}" in
      KR) target_ucode=ko_KR ;; JP) target_ucode=ja_JP ;;
      CN) target_ucode=zh_CN ;; TW) target_ucode=zh_TW ;;
      RU) target_ucode=ru_RU ;; FR) target_ucode=fr_FR ;;
      DE) target_ucode=de_DE ;; ES) target_ucode=es_ES ;;
      IT) target_ucode=it_IT ;; BR) target_ucode=pt_BR ;;
      EG) target_ucode=ar_EG ;; IN) target_ucode=hi_IN ;;
      HU) target_ucode=hu_HU ;; ID) target_ucode=id_ID ;;
      TR) target_ucode=tr_TR ;;
      *) return 0 ;;
    esac

    # lang.tgz is normally persisted by the loader.  Use it when available
    # so this very first question is rendered in the detected language, but
    # never fetch it here: this path must remain usable before GitHub/DoH is
    # configured.
    lang_archive=/home/tc/lang.tgz
    [ -f "${lang_archive}" ] || lang_archive=lang.tgz
    if [ -f "${lang_archive}" ]; then
        sudo mkdir -p /usr/local/share/locale 2>/dev/null
        gunzip -c "${lang_archive}" | sudo tar -xf - -C /usr/local/share/locale >/dev/null 2>&1
    fi
    locale_prompt=$(LANGUAGE="${target_ucode}" TEXTDOMAINDIR=/usr/local/share/locale \
      gettext "tcrp" "Country code %s detected. Change the menu language to %s?" 2>/dev/null)
    [ -n "${locale_prompt}" ] || locale_prompt="Country code %s detected. Change the menu language to %s?"
    locale_prompt=$(printf "${locale_prompt}" "${country}" "${country}")
    if command dialog --clear --yesno "${locale_prompt}" 0 0 2>/dev/null; then
        command jq --arg ucode "${target_ucode}" '.general.ucode = $ucode' "${cfg}" > "/tmp/mshell-locale.$$.json" 2>/dev/null || return 0
        sudo cp "/tmp/mshell-locale.$$.json" "${cfg}" 2>/dev/null
        rm -f "/tmp/mshell-locale.$$.json"
    fi
}

offer_detected_locale_early
export MSHELL_LOCALE_PROMPT_DONE=true

function offer_doh_fallback() {
    local cfg="/mnt/tcrp/user_config.json" mode answer msg
    [ -e /tmp/mshell-doh-prompted ] && return 1
    : > /tmp/mshell-doh-prompted
    [ -f "${cfg}" ] || cfg="/home/tc/user_config.json"
    mode=$(command jq -r '.github_access.mode // "standard"' "${cfg}" 2>/dev/null || echo standard)
    [ "${mode}" = "standard" ] || return 1
    msg="GitHub access is unavailable. Use DoH bypass mode (for China) now?"
    case "${LANG:-}" in zh_CN*|zh_SG*) msg="GitHub访问不稳定。现在启用DoH绕过模式（中国用户）吗？" ;; esac
    command dialog --clear --yesno "${msg}" 0 0 2>/dev/null || return 1
    command jq '.github_access.mode = "doh"' "${cfg}" > /tmp/mshell-user-config.json.$$ 2>/dev/null || return 1
    sudo cp /tmp/mshell-user-config.json.$$ "${cfg}" 2>/dev/null || return 1
    rm -f /tmp/mshell-user-config.json.$$
    bootstrap_github_access
    return 0
}

# GitHub 일시 오류(404/400/rate-limit)로 받은 에러 본문이 스크립트를 덮어써 깨지는 것을 방지.
# 임시파일로 받아 (1)HTTP 성공(-f) (2)비어있지 않음 (3)sentinel 포함 (4)bash 문법 OK 일 때만 교체.
# 검증 실패 시 기존 파일을 보존(덮어쓰지 않음).
function safe_fetch() {
    local _url="$1" _dest="$2" _sentinel="$3"
    local _tmp="/dev/shm/.safe_fetch.$$"
    # functions.sh:19의 curl() 캐시버스팅 오버라이드는 여기선 아직 적용 전이다
    # (safe_fetch가 그 functions.sh 자체를 받아오는 데도 쓰이므로) - 그래서
    # raw.githubusercontent.com의 CDN이 방금 푸시한 새 버전을 못 받고 몇 분
    # 지난 캐시를 서빙하는 문제가 있었다(실기 45.34, 2026-08-23 재현: 푸시
    # 직후 menu.sh test로 받았는데 구버전 그대로였음). 여기서도 직접
    # _cb=타임스탬프를 붙여 우회한다.
    case "${_url}" in
        *raw.githubusercontent.com*)
            if [[ "${_url}" == *\?* ]]; then
                _url="${_url}&_cb=$(date +%s%N 2>/dev/null || date +%s)"
            else
                _url="${_url}?_cb=$(date +%s%N 2>/dev/null || date +%s)"
            fi
            ;;
    esac
    if curl -fskL --retry 3 --retry-delay 2 -o "${_tmp}" "${_url}" \
       && [ -s "${_tmp}" ] \
       && grep -q "${_sentinel}" "${_tmp}" \
       && bash -n "${_tmp}" 2>/dev/null; then
        mv -f "${_tmp}" "${_dest}"
        chmod +x "${_dest}" 2>/dev/null
        return 0
    fi
    if offer_doh_fallback; then
        curl -fskL --retry 2 --retry-delay 1 -o "${_tmp}" "${_url}" \
          && [ -s "${_tmp}" ] && grep -q "${_sentinel}" "${_tmp}" \
          && bash -n "${_tmp}" 2>/dev/null && mv -f "${_tmp}" "${_dest}" && chmod +x "${_dest}" 2>/dev/null && return 0
    fi
    echo "[!] safe_fetch: invalid/failed download, keeping existing ${_dest} (${_url})"
    rm -f "${_tmp}"
    return 1
}

# 자동 업데이트(safe_fetch) 대상 브랜치. functions.sh 소싱 전이라 is_alpine()이
# 아직 없으므로 동일 조건을 인라인으로 판별(Alpine에서 main으로 자기 자신을
# 덮어써 패치가 무력화되는 사고가 실측 확인되어(2026-07-12) 분리). main은
# v1.3.1.1에서 동결, alpine-redpill이 v1.4.0.0부터 이어받음(2026-07-15).
UPDATE_BRANCH="alpine-redpill"

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

# Alpine loader-build fallback only.  Keep the configured resolver first and
# add Cloudflare as a secondary resolver without changing user_config.json.
function ensure_build_dns() {
  local fallback_dns="1.1.1.1"
  local mode
  mode=$(jq -r '.github_access.mode // "standard"' "${userconfigfile:-/home/tc/user_config.json}" 2>/dev/null)
  [ "${mode}" = "doh" ] || return 0
  if ! grep -qF "nameserver ${fallback_dns}" /etc/resolv.conf 2>/dev/null; then
    printf 'nameserver %s # MSHELL DoH\n' "${fallback_dns}" | sudo tee -a /etc/resolv.conf >/dev/null
  fi
  for domain in github.com raw.githubusercontent.com api.github.com release-assets.githubusercontent.com; do
    ip=$(curl -fsSkL --connect-timeout 5 "https://cloudflare-dns.com/dns-query?name=${domain}&type=A" \
      -H 'accept: application/dns-json' 2>/dev/null | jq -r '.Answer[]? | select(.type == 1) | .data' 2>/dev/null | head -n 1)
    if echo "${ip}" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' && ! grep -qE "[[:space:]]${domain}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
      printf '%s\t%s\t# MSHELL DoH\n' "${ip}" "${domain}" | sudo tee -a /etc/hosts >/dev/null
    fi
  done
}

ensure_build_dns

# 지금까지는 인터넷 3회 연속 미응답 뒤 사용자가 그 자리에서 새로 입력한
# 고정 IP만 반영했다 - 이미 이전 세션에서 저장해 둔 고정 IP 설정이 있어도,
# 재부팅해서 menu.sh가 다시 뜨면 그 값을 쓰지 않고 매번 처음부터 DHCP
# 대기/재시도를 반복했다. 이 함수는 그 저장된 값이 있으면 DHCP 루프를
# 돌기 전에 먼저 이 로더 자신의 살아있는 세션에 그대로 적용한다.
#
# 2026-08-29: ipsettings가 멀티 NIC(최대 8포트) 배열로 바뀐 뒤 이 함수만
# 옛날 flat object 스키마(.ipsettings.ipset 등)를 그대로 읽고 있어서,
# 배열에서는 항상 null이 나와 매번 조용히 실패하는 회귀가 있었다(사용자
# 지적으로 발견) - 저장된 고정 IP가 있어도 재부팅마다 불필요한 DHCP
# 대기를 반복하고 있었다. functions.sh의 apply_static_ip_now()와 동일한
# 스키마(배열 순회, primary만 기본 라우트 소유, DNS/프록시는 전역
# netdns.ipdns/netproxy.ipproxy)로 다시 맞췄다.
function apply_saved_static_ip() {
  local cfg="${userconfigfile}"
  migrate_ipsettings_schema "${cfg}"

  local count applied=0
  count=$(jq -r '(.ipsettings // [] | length)' "${cfg}" 2>/dev/null)
  case "${count}" in ''|*[!0-9]*) count=0 ;; esac
  if [ "${count}" -eq 0 ]; then
    # Remove only the policy lines managed by MSHELL so a subsequent pure
    # DHCP boot regains its normal gateway and DNS behaviour.
    configure_udhcpc_static_policy ""
    clear_udhcpc_source_route_hook
    return 1
  fi

  local proxy dns
  proxy="$(jq -r '.netproxy.ipproxy // empty' "${cfg}" 2>/dev/null)"
  if [ -n "${proxy}" ]; then
    export http_proxy="${proxy}" https_proxy="${proxy}"
  fi
  dns="$(jq -r '.netdns.ipdns // empty' "${cfg}" 2>/dev/null)"
  [ -n "${dns}" ] && printf 'nameserver %s\n' "${dns}" | sudo tee /etc/resolv.conf >/dev/null

  # Keep non-static NICs on DHCP. Alpine's standard udhcpc policy supports
  # NO_GATEWAY and NO_DNS: addresses/leases continue to renew, but DHCP never
  # competes with the configured primary static route or overwrites its DNS.
  local live_iface static_ifaces dhcp_ifaces=""
  static_ifaces=$(jq -r '.ipsettings[]?.ipiface // empty' "${cfg}" 2>/dev/null)
  for live_iface in /sys/class/net/*; do
    live_iface="${live_iface##*/}"
    case "${live_iface}" in eth[0-7]) ;; *) continue ;; esac
    if printf '%s\n' "${static_ifaces}" | grep -qx "${live_iface}"; then
      # Only a static NIC must relinquish its DHCP lease.
      stop_dhcp_client_for_iface "${live_iface}"
    else
      dhcp_ifaces="${dhcp_ifaces} ${live_iface}"
    fi
  done
  dhcp_ifaces="${dhcp_ifaces# }"
  configure_udhcpc_static_policy "${dns}" ${dhcp_ifaces}
  configure_udhcpc_source_route_hook ${dhcp_ifaces}

  # Build a per-source routing table for each currently leased DHCP address.
  # The udhcpc post-bound/post-renew hooks installed above maintain these when
  # a lease later changes.
  local dhcp_addr dhcp_gw
  for live_iface in ${dhcp_ifaces}; do
    dhcp_addr=$(ip -4 -o addr show dev "${live_iface}" scope global 2>/dev/null | awk '{print $4; exit}')
    dhcp_gw=$(ip -4 route show default dev "${live_iface}" 2>/dev/null | awk '/via / {print $3; exit}')
    [ -n "${dhcp_addr}" ] && configure_source_route_for_iface "${live_iface}" "${dhcp_addr}" "${dhcp_gw}"
  done

  local i iface addr gw isprimary primary_iface="" primary_gw="" primary_addr
  for ((i = 0; i < count; i++)); do
    iface="$(jq -r ".ipsettings[${i}].ipiface // empty" "${cfg}" 2>/dev/null)"
    addr="$(jq -r ".ipsettings[${i}].ipaddr // empty" "${cfg}" 2>/dev/null)"
    gw="$(jq -r ".ipsettings[${i}].ipgw // empty" "${cfg}" 2>/dev/null)"
    isprimary="$(jq -r ".ipsettings[${i}].primary // false" "${cfg}" 2>/dev/null)"

    if ! echo "${iface}" | grep -qE '^eth[0-7]$' || \
       ! echo "${addr}" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
      echo "[!] Saved static IP entry looks invalid (iface=${iface} addr=${addr}); skipping."
      continue
    fi

    echo "Static IP is configured (${iface} ${addr}) - applying it to this loader session before any DHCP wait..."
    sudo ip link set "${iface}" up 2>/dev/null
    sudo ip addr flush dev "${iface}" 2>/dev/null
    sudo ip addr add "${addr}" dev "${iface}" 2>/dev/null
    if [ "${isprimary}" = "true" ] && [ -n "${gw}" ]; then
      primary_iface="${iface}"
      primary_gw="${gw}"
    fi
    applied=$((applied + 1))
  done

  # A DHCP route from another NIC may already exist.  Remove every default
  # route only after all static addresses are in place, then install exactly
  # one route owned by the configured primary NIC.
  if [ "${applied}" -gt 0 ] && [ -n "${primary_iface}" ] && [ -n "${primary_gw}" ]; then
    stabilize_static_primary_route "${primary_iface}" "${primary_gw}"
    primary_addr=$(ip -4 -o addr show dev "${primary_iface}" scope global 2>/dev/null | awk '{print $4; exit}')
    [ -n "${primary_addr}" ] && configure_source_route_for_iface "${primary_iface}" "${primary_addr}" "${primary_gw}"
  fi

  [ "${applied}" -gt 0 ]
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
#
# 예전엔 모든 물리 NIC를 무조건 kick했는데, 이러면 (a) 이미 정상 IP를
# 받은 NIC까지 불필요하게 링크를 끊었다 올리고, (b) 케이블 자체가 안
# 꽂힌(carrier=0) NIC에도 매번 3초짜리 udhcpc 타임아웃을 낭비했다.
# carrier=0인 인터페이스는 down/up을 해봤자 반대편과 실제 신호 교환이
# 없어 PHY 재협상 자체가 일어나지 않으므로(admin state만 토글) 아예
# 손대지 않는다. 169.254.0.0/16(IPv4LL/APIPA)만으로는 "DHCP 대기중"과
# "링크 없음"을 구분할 수 없어 캐리어를 별도로 확인해야 한다(2026-08-22
# 실기 로그에서 이미 정상 IP를 받은 eth1까지 매번 kick되는 것을 보고 발견).
function nic_link_kick() {
  local ifaces dev IP ETHTOOL IFCONFIG UDHCPC carrier curip
  # 호출자가 "실제로 뭔가 kick했는지"를 알 수 있도록 전역으로 보고한다 -
  # 전부 스킵됐다면(캐리어 없음/이미 정상 IP) 아무것도 안 바뀔 게 뻔하므로,
  # 호출자는 그 attempt의 긴 폴링 대기를 건너뛸 수 있다.
  NIC_KICKED="false"
  IP=$(_find_bin ip)
  ETHTOOL=$(_find_bin ethtool)
  IFCONFIG=$(_find_bin ifconfig)
  UDHCPC=$(_find_bin udhcpc)
  # loopback/가상 인터페이스 제외, 물리 NIC 만 대상
  ifaces=$(ls /sys/class/net 2>/dev/null | grep -E '^(eth|en|em|p[0-9]+p)')
  [ -z "${ifaces}" ] && return 0
  for dev in ${ifaces}; do
    carrier="$(cat "/sys/class/net/${dev}/carrier" 2>/dev/null)"
    if [ "${carrier}" != "1" ]; then
      echo "NIC '${dev}': no carrier (cable unplugged?), skipping kick."
      continue
    fi

    if [ -n "${IP}" ]; then
      curip="$(${IP} -4 -o addr show dev "${dev}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
    elif [ -n "${IFCONFIG}" ]; then
      curip="$(${IFCONFIG} "${dev}" 2>/dev/null | grep -oE 'inet (addr:)?[0-9.]+' | awk '{print $NF}' | head -1)"
    fi
    case "${curip}" in
      169.254.*|"") ;;
      *)
        echo "NIC '${dev}': already has address ${curip}, skipping kick."
        continue
        ;;
    esac

    echo "Kicking NIC '${dev}' (link down/up + DHCP renew) to wake slow bare-metal link..."
    NIC_KICKED="true"
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
    # 이미 저장된 고정 IP 설정이 있으면 그걸 이 로더 세션에 바로 적용하고,
    # DHCP 대기/재시도 루프 자체를 건너뛴다 - static 위에 DHCP 임대가 얹혀
    # 충돌할 이유가 없고, 어차피 DHCP가 응답할 네트워크가 아니라서
    # link-kick/폴링을 반복해봤자 무의미하다.
    net_ok="false"
    static_ip_applied="false"
    if apply_saved_static_ip; then
      static_ip_applied="true"
      ensure_build_dns
      check_internet && net_ok="true"
    fi

    # 인터넷 체크: 1차 30초 시도, 실패 시 NIC 강제 link-kick 후
    # 20초 단위로 최대 2회 더 재시도(총 3회). 베어메탈의 느린 NIC 대응.
    # 1차 진입 직후 1회 즉시 체크 → 이미 되면 link-kick 자체를 건너뛰어
    # 가상랜에 불필요한 단절/지연을 주지 않고, 안 될 때만 선제 link-kick
    # 으로 베어메탈의 30초 대기를 줄인다.
    attempt=1
    max_attempt=3
    while [ "${static_ip_applied}" != "true" ] && [ ${attempt} -le ${max_attempt} ]; do
      if [ ${attempt} -eq 1 ]; then
        timeout=30
        # 이미 연결돼 있으면 link-kick 없이 즉시 통과
        # (getlatestmshell 은 루프 종료 후 net_ok 블록에서 1회만 호출)
        ensure_build_dns
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
      if [ "${NIC_KICKED}" = "true" ]; then
        # 백그라운드로 udhcpc가 돌아가고 있는 NIC가 있을 때만 결과가
        # 바뀔 수 있으므로, 이때만 timeout 동안 2초 간격으로 폴링한다.
        start_time=$(date +%s)
        while true; do
          ensure_build_dns
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
      else
        # 이번 attempt에서 kick한 NIC가 하나도 없다면(전부 carrier 없음
        # 또는 이미 정상 IP) 아무것도 바뀌지 않았을 것이 확실하므로,
        # timeout 동안 헛되이 폴링하지 않고 즉시 한 번만 확인한다.
        echo "No NIC needed kicking this attempt; checking once instead of waiting ${timeout}s."
        ensure_build_dns
        check_internet && net_ok="true"
      fi
      [ "${net_ok}" = "true" ] && break
      attempt=$(( attempt + 1 ))
    done
    if [ "${net_ok}" = "true" ]; then
      [[ -z "${1-}" && "$TCB" = "true" ]] && getlatestmshell "noask"
    elif [ "${static_ip_applied}" = "true" ]; then
      # 저장된 고정 IP를 이미 적용했는데도 인터넷이 안 되는 상태 - 새로
      # 값을 입력받는 FORCE_STATIC_IP_SETUP 오프라인 설정 다이얼로그는
      # 지금 막 적용한 값과 같은 걸 다시 물어보는 셈이라 띄우지 않는다.
      echo "Saved static IP was applied, but internet is still unreachable. Continuing anyway."
    else
      echo "Internet connection failed after ${max_attempt} attempts."
      # The static-IP menu must remain usable when this loader has no DHCP or
      # Internet access yet.  Do not try to download anything in this branch:
      # pass a one-shot flag to menu_m.sh, which will write user_config.json
      # directly and offer an immediate reboot after the values are saved.
      if dialog --clear --backtitle "Network setup" \
          --yesno "Internet was not found after ${max_attempt} attempts.\n\nDo you want to configure a static IP now?" 0 0; then
        export FORCE_STATIC_IP_SETUP="true"
      fi
    fi
    # A static-IP setup is intentionally offline.  Skip the GitHub probe and
    # continue into menu_m.sh so the saved settings can be applied on reboot.
    if [ "${FORCE_STATIC_IP_SETUP:-false}" != "true" ]; then
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
fi

# Static-IP recovery is deliberately independent of the repository checkout.
# Do not enter the normal models/git clone path after the offline prompt.
if [ "${FORCE_STATIC_IP_SETUP:-false}" = "true" ]; then
    chmod +x /home/tc/menu_m.sh 2>/dev/null
    /home/tc/menu_m.sh
    exit $?
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
    # functions.sh를 아직 안 거친 시점이라 curl() 캐시버스팅 오버라이드가
    # 없다 - safe_fetch()와 동일한 이유로 직접 _cb를 붙인다. -O 대신 -o로
    # 저장 파일명을 명시(쿼리스트링이 붙으면 -O가 "models.json?_cb=..."
    # 같은 엉뚱한 파일명으로 저장할 수 있어 curl 버전에 기대지 않음).
    curl -skL# -o models.json "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/models.json?_cb=$(date +%s%N 2>/dev/null || date +%s)"
    if [ "$oldver" = "test" ]; then
      gitdownload
      cecho g "###############################  This is Test Mode  ############################"
      safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/functions_t.sh" "/home/tc/functions.sh" "rploaderver="
      safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/menu_m.sh" "/home/tc/menu_m.sh" "kver5explatforms"
      safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/burnloader.sh" "/home/tc/burnloader.sh" "burnloader()"
      # i18n.h 도 함께 갱신 - menu_m.sh 가 참조하는 MSGID 는 늘어나는데
      # i18n.h 를 안 당겨오면 새 MSGID(예: MSGZZ72)가 로컬 파일에 없어
      # load_zz() 에서 정의되지 않고, set -u 환경에서 "unbound variable"
      # 로 죽는다(menu_m.sh 만 최신화하고 i18n.h 는 구버전으로 남는 상태).
      safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/i18n.h" "/home/tc/i18n.h" "function load_zz"
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
        safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/burnloader.sh" "/home/tc/burnloader.sh" "burnloader()"
        safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/i18n.h" "/home/tc/i18n.h" "function load_zz"
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

if [ ! -f /home/tc/burnloader.sh ]; then
  safe_fetch "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${UPDATE_BRANCH}/burnloader.sh" "/home/tc/burnloader.sh" "burnloader()"
fi

chmod +x /home/tc/menu_m.sh
/home/tc/menu_m.sh
[ -d /dev/shm/tcrp-modules/ ] && rm -rf /dev/shm/tcrp-modules/
exit 0
