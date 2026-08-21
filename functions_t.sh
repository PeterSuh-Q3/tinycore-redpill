#!/usr/bin/env bash

set -u # Unbound variable errors are not allowed

rploaderver="1.4.3.2"
builddate="2026.08.19"
redpillmake="prod"

# raw.githubusercontent.com 은 경로 기준으로 최대 5분(max-age=300) CDN 캐싱한다.
# push 직후 재빌드하면 방금 고친 로직 대신 구버전이 그대로 내려와 디버깅을
# 헷갈리게 만드는 사고가 실측 확인되어(2026-08-18), curl 을 감싸는 함수를 두고
# raw.githubusercontent.com 을 향하는 모든 curl 호출(.pat/extractor/friend
# 다운로드 등 이 파일 안의 60여 곳 포함)에 요청마다 바뀌는 쿼리스트링을 자동으로
# 붙여 캐시를 우회한다(쿼리스트링이 다르면 캐시 키가 달라져 항상 MISS 로 최신을
# 받아옴을 실측 확인). 다른 도메인(GitHub API, 릴리즈 자산 등)은 건드리지 않는다.
# menu.sh 에도 동일 정의가 있다(중복 정의는 무해 - bash 는 마지막 정의를 쓴다);
# 이 파일이 menu.sh 를 거치지 않고(menu_t.sh/menu_m.sh 등에서) 직접 소싱되는
# 경로도 있어 이 파일 자체에도 넣어 항상 보장한다.
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

# Alpine(musl) 이식 판별. ttyd 단일화 전략(docs/alpine-migration-plan.md §4)에 따라
# X11/urxvt/glibc 로케일 스택과 TinyCore 커널 전용 .tcz(scsi-*-tinycore64 등) 분기를
# Alpine 환경에서 건너뛰기 위해 사용.
is_alpine() {
  [ -f /etc/alpine-release ]
}

# 2026-08-16 (테스트 트랙 전용): /home/tc/user_config.json 과
# /mnt/${loaderdisk}3/user_config.json 이 별개 파일로 관리되어 온
# 문제에 대한 개선. 지금까지는 xtcrp.tgz 에 번들된(빌드 시점 기준,
# 최신이 아닐 수 있는) 사본이 매 세션 /home/tc 로 풀리고, 이후
# lastsessiondir 복원이나 mshell_auto_rebuild()의 cp+backuploader()
# 처럼 곳곳에서 수동으로 두 파일을 맞춰줘야 했다 - 그중 한 지점이라도
# 빠지면 두 사본이 어긋난다(오늘 MSHELL Manager auto-rebuild 개발
# 중에도 usb_line 재동기화 누락으로 실제로 겪은 문제).
#
# functions.sh(안정 트랙)에는 넣지 않는다 - 이 심볼릭 링크 전환은
# functions.sh/menu_m.sh 전역의 $userconfigfile(/home/tc/user_config.json)
# 참조 지점이 실제로 심볼릭 링크를 문제없이 다루는지 충분히 검증되기
# 전까지는 안정 트랙 사용자에게 영향이 가면 안 된다.
#
# 실기 확인(Alpine 부팅 환경 - tcrpfriend 자체의 TinyCore boot.sh 와는
# 완전히 별개): 이 파티션은 rebuildfstab 이 만들어 둔
# noauto,users,umask=000 fstab 항목만 있고 자동 마운트되지 않는다.
# 그래서 존재 여부만 확인하고 넘어가면 안 되고, 이 파일의 다른
# 호출부(예: my() 안의 "Mounting partition N" 단계)와 동일하게
# ensure_loader_partition_mounted() 로 직접 마운트를 보장해야 한다
# (umask=000 라 uid= 를 따로 안 줘도 tc 가 바로 쓸 수 있다).
mshellSymlinkUserConfig() {
  # set -u trips on ${loaderdisk} itself (not just a downstream use of
  # an empty value) if the variable has never been assigned at all in
  # this shell - the :- form is required here, plain [ -z "${var}" ]
  # is not safe for a truly-undeclared variable under set -u.
  [ -z "${loaderdisk:-}" ] && getloaderdisk
  [ -z "${loaderdisk:-}" ] && return 0
  # nvme/mmc/block disks need a trailing "p" before the partition
  # number (nvme0n1p3, not nvme0n13) - that correction only happens as
  # a side effect of getBus() (functions.sh:3137-3139), not inside
  # getloaderdisk() itself. Skipping this left ${loaderdisk}3 pointing
  # at a path that was never actually mounted on those bus types.
  getBus "${loaderdisk}" >/dev/null

  # This environment (Alpine, confirmed on real hardware - not
  # tcrpfriend's own TinyCore boot.sh, a completely separate boot
  # environment) never auto-mounts partition 3: rebuildfstab only
  # writes a noauto,users,umask=000 fstab line for it, the actual
  # `mount` still has to happen explicitly. A plain existence/-w check
  # here silently no-ops before that mount ever occurs (confirmed the
  # hard way - functions.sh sourcing happens well before it), so this
  # has to actively ensure the mount the same way every other caller
  # in this file already does, not just check for it. As a side effect
  # this also (re)points /mnt/tcrp at the current /mnt/${loaderdisk}3
  # (see _sync_tcrp_alias()) - this call must run on EVERY invocation,
  # even when /home/tc/user_config.json is already a symlink below,
  # because maintaining /mnt/tcrp is this call's job, not something the
  # early-return-if-already-linked check further down should skip.
  # (Confirmed the hard way: with the early return placed before this
  # call, a device that was symlinked before /mnt/tcrp existed would
  # never create it - functions.sh sourcing kept short-circuiting here.)
  ensure_loader_partition_mounted "3" || return 0

  [ -L /home/tc/user_config.json ] && return 0

  local part_cfg="/mnt/tcrp/user_config.json"

  if [ ! -f "${part_cfg}" ]; then
    # First run against this partition (or an image predating this
    # change) - the RAM copy is still the only record, so it becomes
    # the seed for the partition copy rather than being discarded.
    [ -f /home/tc/user_config.json ] || return 0
    cp -f /home/tc/user_config.json "${part_cfg}" 2>/dev/null || return 0
  fi

  rm -f /home/tc/user_config.json
  ln -s "${part_cfg}" /home/tc/user_config.json
}

# dialog(cdialog)의 "--menu/--checklist ... height width 0"(menu-height 자동) 계산이
# 신버전(Alpine, 1.3-20260107 계열)에서 항목이 여러 개여도 1줄만 보여주고
# 나머지를 스크롤 뒤로 숨기는 회귀가 있음(TC의 구버전 1.3-20171209는 정상).
# 세 번째 인자(menu-height)를 실제 항목 수(인자 $1) 기준으로 계산해 대체.
# 항목 수를 모르는 호출부는 인자 생략 시 5로 대체(고정 큰 값으로 박스가
# 쓸데없이 커지는 것을 피하기 위함).
dlgmenuheight() {
  local n="${1:-5}"
  local rows
  rows=$(tput lines 2>/dev/null) || rows=24
  local max=$((rows - 10))
  [ "$max" -lt 3 ] && max=3
  [ "$n" -lt 1 ] && n=1
  [ "$n" -gt "$max" ] && n="$max"
  echo "$n"
}

# fdisk 절대경로. alpine-redpill은 항상 Alpine 위에서 도는 구조라
# is_alpine 분기가 불필요 - Alpine의 util-linux는 /sbin/fdisk에 설치됨.
# 하드코딩된 경로가 "command not found"로 조용히 실패하던 것을 실측
# 확인(2026-07-12)해 동적 해석으로 교체.
FDISK="$(command -v fdisk 2>/dev/null || echo /sbin/fdisk)"

# gdisk 절대경로. 2TB 초과 디스크(GPT) 주입 경로가 TinyCore 시절의
# /usr/local/sbin/gdisk 를 하드코딩하고 있었는데, Alpine의 gptfdisk 패키지는
# /usr/bin/gdisk 에 설치한다. 게다가 그 호출들은 전부 출력을 /dev/null 로
# 버려서(> /dev/null 2>&1) "command not found"가 보이지도 않고, 파티션이
# 안 만들어진 채 다음 단계(blockdev --rereadpt, mount)에서 엉뚱하게 실패했다.
# FDISK 와 동일하게 동적 해석으로 교체(2026-08-21 실기 확인).
GDISK="$(command -v gdisk 2>/dev/null || echo /usr/sbin/gdisk)"

# 자동 업데이트(safe_fetch/git clone) 대상 브랜치. main은 v1.3.1.1에서 동결
# (더 이상 업데이트 없음), alpine-redpill이 v1.4.0.0부터 이어받았다(2026-07-15).
# 2026-07-22: is_alpine()으로 분기하던 것을 제거 - mshell(Alpine)뿐 아니라
# xTCRP(Buildroot friend 커널, is_alpine()이 거짓)도 이제 alpine-redpill
# 브랜치로 관리되는데, 이 분기 때문에 xTCRP가 my.sh.gz/modules.alias.*를
# 계속 stale main에서 받아와 "menu.sh test 실행 시 v1.3.1.1로 회귀"하는
# 사고가 실측 확인됨(152 실기, menu.sh의 UPDATE_BRANCH와 동일한 버그 패턴).
build="alpine-redpill"

modalias4="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/modules.alias.4.json.gz"
modalias3="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/modules.alias.3.json.gz"

timezone="UTC"
ntpserver="pool.ntp.org"
userconfigfile="/home/tc/user_config.json"
# pats.json is kept at a persistent location (/home/tc) so that a redpill-load
# directory clean/re-clone (e.g. after a failed build) does not remove the DSM
# version source. It is mirrored into redpill-load/config for the loader build.
configfile="/home/tc/pats.json"
configfile_loader="/home/tc/redpill-load/config/pats.json"

gitdomain="raw.githubusercontent.com"
mshellgz="my.sh.gz"
mshtarfile="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/my.sh.gz"

#Defaults
smallfixnumber="0"

kver3platforms="bromolow braswell avoton cedarview"
kver5platforms="epyc7002 epyc7003ntb epyc7003 icelaked v1000nk r1000nk geminilakenk"
nosas5platforms="bromolow broadwellntbap broadwellnkv2 purley"
dsm6notsupported="broadwellntbap"

# 전역 변수로 플래그 설정 (한번 Y면 영구 유지)
R8168_YN="N"
R8168_DETECTED="N"  # 한번만 체크하는 플래그

#Check if FRIEND kernel exists
if [[ "$(uname -a | grep -c tcrpfriend)" -gt 0 ]]; then
    FRKRNL="YES"
else
    FRKRNL="NO"
fi

BIOS_CNT="$(sudo fdisk -l | grep "BIOS" | wc -l )"
[ $BIOS_CNT -eq 0 ] && BIOS_CNT="$(sudo fdisk -l | grep "EFI" | grep "127M" | wc -l )"
[ $BIOS_CNT -eq 0 ] && BIOS_CNT="$(sudo fdisk -l | grep "*" | grep "83" | grep "127M" | wc -l )"

 
function history() {
    cat <<'EOF'
    --------------------------------------------------------------------------------------
    0.7.0.0 Added build for version greater than 42218
    0.7.0.1 Added required extension parsing adding and downloading
    0.7.0.2 Added usb patch in patchdtc
    0.7.0.3 Added portnumber on patchdtc
    0.7.0.4 Make sure that local cache folder is created early in the process
    0.7.0.5 Enabled interactive
    0.7.0.6 Added save/restore session functions
    0.7.0.7 Added a check date function
    0.7.0.8 Added the ability to use local dtb file
    0.7.0.9 Added flyride satamap review
    0.7.1.0 Added the history, version and enhanced patchdtc function
    0.7.1.1 Added a syntaxcheck function
    0.7.1.2 Added sync time with NTP server : pool.ntp.org (Set timezone and ntpserver variables accordingly )
    0.7.1.3 Added the option to create JUN mod loader (By Jumkey)
    0.7.1.4 Added the use of the additional custom_config_jun.json for JUN mod loader creation
    0.7.1.5 Updated satamap function to support higher the 9 port counts per HBA.
    0.7.1.6 Updated satamap function to fix the broken q35 KVM controller, and to stop scanning for CD-ROM's
    0.7.1.7 Updated serialgen function to include the option for using the realmac
    0.7.1.8 Updated satamap function to fine tune SATA port identification and identify SATABOOT
    0.7.1.9 Updated patchdtc function to fix wrong port identification for VMware hosted systems
    0.8.0.0 Stable version. All new features will be moved to develop repo
    0.8.0.0 Stable version. All new features will be moved to develop repo
    0.8.0.1 Updated postupdate to facilitate update to update2
    0.8.0.2 Updated satamap to support DUMMY PORT detection 
    0.8.0.3 Updated satamap to avoid the use of 0 in first controller that cause KP
    0.9.0.0 Development version. Moving all new features to development build
    0.9.0.1 Updated postupdate to facilitate update to update2
    0.9.0.2 Added system monitor function 
    0.9.0.3 Updated satamap to support DUMMY PORT detection 
    0.9.0.4 More satamap fixes
    0.9.0.5 Added the option to get grub variables into user_config.json
    0.9.0.6 Experimental DVA1622 (geminilake) addition
    0.9.0.7 Experimental DVA1622 serialgen
    0.9.0.8 Experimental DVA1622 increase disk count to 16
    0.9.0.9 Fixed missing bspatch
    0.9.1.0 Added dtc depth patch
    0.9.1.1 Default action for DTB system is to use the dtbpatch by fbelavenuto
    0.9.1.2 Fixed a jq issue in listextension
    0.9.1.3 Fixed bsdiff not found issue
    0.9.1.4 Fixed overlaping downloadextractor processes
    0.9.1.5 Enhanced postupdate process to update user_config.json to new format
    0.9.1.6 Fixed compressed non-compressed RAMDISK issue 
    0.9.1.7 Enhanced build process to update user_config.json during build process 
    0.9.1.8 Enhanced build process to create friend files
    0.9.1.9 Further enhanced build process 
    0.9.2.0 Introducing TCRP Friend
    0.9.2.1 If TCRP Friend is used then default option will be TCRP Friend
    0.9.2.2 Upgrade your system by adding TCRP Friend with command bringfriend
    0.9.2.3 Adding experimental DS2422+ support
    0.9.2.4 Added the redpillmake variable to select between prod and dev modules
    0.9.2.5 Adding experimental RS4021xs+ support
    0.9.2.6 Added the downloadupgradepat action **experimental
    0.9.2.7 Added setting the static network configuration for TCRP Friend
    0.9.2.8 Changed all  calls to use the -k flag to avoid expired certificate issues
    0.9.2.9 Added the smallfixnumber key in user_config.json and changed the platform ids to model ids
    0.9.3.0 Changed set root entry to search for FS UUID
    0.9.4.3-1 Multilingual menu support 
    0.9.5.0 Add storage panel size selection menu
    0.9.6.0 To prevent partition space shortage, rd.gz is no longer used in partition 1
    0.9.7.0 Improved build processing speed (removed pat file download process)
    0.9.7.1 Back to DSM Pat Handle Method
    1.0.0.0 Kernel patch process improvements
    1.0.0.1 Improved platform release ID identification method
    1.0.0.2 Setplatform() function converted to custom_config.json reference method
    1.0.0.3 To prevent partition space shortage, custom.gz is no longer used in partition 1
    1.0.0.4 Prevents kernel panic from occurring due to rp-lkm.zip download failure 
            when ramdisk patching occurs without internet.
    1.0.0.5 Add offline loader build function
    1.0.1.0 Upgrade from Tinycore version 12.0 (kernel 5.10.3) to 14.0 (kernel 6.1.2) to improve compatibility with the latest devices.
    1.0.1.1 Fix monitor fuction about ethernet infomation
    1.0.1.2 Fix for SA6400
    1.0.2.0 Remove restrictions on use of DT-based models when using HBA (apply mpt3sas blacklist instead)
    1.0.2.1 Changed extension file organization method
    1.0.2.2 Recycle initrd-dsm instead of custom.gz (extract /exts), The priority starts from custom.gz
    1.0.2.3 Added RedPill bootloader hard disk porting function
    1.0.2.4 Added NVMe bootloader support
    1.0.2.5 Provides menu option to disable i915 module loading to prevent console blackout in ApolloLake (DS918+), GeminiLake (DS920+), and Epyc7002 (SA6400)
    1.0.2.6 Added multilingual support languages (locales) (Arabic, Hindi, Hungarian, Indonesian, Turkish)
    1.0.2.7 dbgutils Addon Add/Delete selection menu
    1.0.2.8 Added multilingual support languages (locales) (Amharic-Ethiopian, Thai)
    1.0.2.9 Release img image with gettext.tgz
    1.0.3.0 Integrate my, rploader.sh, myfunc.h into functions.sh, optimize distribution
    1.0.3.1 Added loader file packing menu for remote update
    1.0.3.2 Added dom_szmax for jot mode
    1.0.3.3 Boot entry order for jot mode synchronized with Friend's order, remove custom_config_jun.json
    1.0.3.4 Maintain boot-wait addon when using satadom in SA6400
    1.0.3.5 Remove getstaticmodule() and undefined PROXY variables (cause of lkm download failure in final release)
    1.0.3.6 Use intel_iommu on the command line
    1.0.3.7 Add command line native satadom support option change menu
    1.0.3.8 Sort netif order by bus-id order (Synology netif sorting method)
    1.0.3.9 NVMe-related function supplementation and error correction
            Discontinue use of sortnetif addon, discontinue use of sortnetif if there is only 1 NIC
    1.0.4.0 Added sata_remap processing menu for SataPort reordering.
    1.0.4.1 Added a feature to check whether the pre-counted number of disks matches when booting Friend
    1.0.4.2 Add Support DSM 7.2.2-72803 Official Version
    1.0.4.3 No separation between USB/SATA menus in Jot Mod (boot menu merge)
    1.0.4.4 Loader building is blocked when using Apollolake + proxmox(kvm)/qemu(kvm) (KP occurs in versions after lkm 24.8.29)
    1.0.4.5 Solved the KP occurrence issue when using SATA-type bootloader in proxmox(kvm), 
            SA6400(epyc7002) integration from lkm5 (lkm 24.9.8)
    1.0.4.6 Rearrange menu order, automatically enter Gen value when S/N or mac is not selected
    1.0.4.7 Fix from DSM 7.2.2-72803 to DSM 7.2.2-72806
    1.0.4.8 Enable mmc (SD Card) bus type recognition for the bootloader
    1.0.4.9 When mmc bus type is used, module processing method is applied with priority given to eudev instead of ddsml.
    1.0.5.0 Improved internet check function in menu.sh
    1.0.5.1 Added manual update feature to friend specified version, added disable/enable friend automatic update feature
    1.0.5.2 Upgraded grub version from 2.06 to 2.12 ( improved uefi, legacy boot compatibility [especially in jot mode] )
    1.0.6.0 Added the ability to choose between the integrated modules all-modules (tcrp) and rr-modules
    1.0.6.1 Improved bootloader boot partition detection method
    1.0.6.2 Changed to use only the first one when multiple bootloaders exist
    1.0.6.3 Added ability to force loading mmc and sd modules when loading Tinycore Linux
    1.0.6.4 Expanded MAC address support from 4 to 8.
    1.0.6.5 Includes tinycore linux scsi module for scsi type bootloader support.
    1.0.6.6 Discontinuing support for DS3615xs.
    1.0.6.7 Applying REDPILL background image to grub boot
    1.0.6.8 i915.modeset=0 menu processing improvement (FRIEND guidance console is activated when i915 transcoding is disabled)
    1.1.0.0 Added features for distribution of xTCRP (Tinycore Linux stripped down version)
    1.1.0.1 When using a single m.2 NVMe volume, the DDSML error issue has occurred, so menu usage has been excluded and related support has been strengthened.
    1.2.0.0 Added new platforms purley, broadwellnkv2, broadwellntbap and started supporting all models for each platform
    1.2.1.0 Create tinycore-mshell and xTCRP together in grub boot. Merge Re-install boot entries without USB/SATA distinction and fix KP bug.
    1.2.1.1 Renewal of SynoDisk bootloader injection function
    1.2.1.2 SynoDisk with Bootloader Injection Supports NVMe DISK
    1.2.1.3 SynoDisk with Bootloader Injection Supports Single SHR DISK
    1.2.1.4 SynoDisk with Bootloader Injection Stop Supports BASIC or JBOD DISK
    1.2.1.5 SynoDisk with bootloader injection uses UUID 8765-4321 instead of 6234-C863
    1.2.1.6 DS3615xs(bromolow) support again, LEGACY boot mode must be used!
    1.2.1.7 SynoDisk with Bootloader Injection Supports 2.4GB /dev/md0 size (before dsm 7.1.1)
    1.2.1.8 Modify the method of checking Internet connection in menu.sh
    1.2.1.9 Fixed to keep graphic console screen even in Jot Mode/Legacy Boot environment (use gfxpayload=keep)
    1.2.2.0 Activate Tinycore TTYD web console (port 7681, login use tc/P@ssw0rd)
    1.2.2.1 TTYD web console baremetal headless support fix
    1.2.2.2 Added to change the default value of the Grub boot entry (in the submenu)
    1.2.2.3 Added a feature to immediately reflect changes to user_config.json (no need for loader build)
    1.2.2.4 SynoDisk with bootloader injection Support SHR 2TB or more
    1.2.2.5 SynoDisk with bootloader injection Support UEFI ESP and two more SHR 2TB or more
    1.2.2.6 SynoDisk with bootloader injection Support All Type GPT (BASIC, JBOD, SHR, RAID1,5,6)
    1.2.2.7 SynoDisk with bootloader injection Support xTCRP loader rebuild
    1.2.2.8 Fix DS920+ 3rd partition space shortage issue with SynoDisk with bootloader injection
    1.2.2.9 Fixed the issue where the font of the menu focus would be broken 
            when changing to a 2-byte Unicode language during the first execution of menu.sh.
            Apply i915-related firmware only to sa6400, reduce the size of the patched dsm kernel in other models 
            (solve the issue of insufficient space for injection of large-capacity kernel bootloader such as ds920+/ds1621+)
    1.2.3.0 avoton (DS1515+ kernel 3) support started
    1.2.3.1 cedarview (DS713+ kernel 3) support started
    1.2.3.2 More models supported for avoton and cedarview (including DS1815+)
    1.2.3.3 v1000nk (DS925+ kernel 5) support started
    1.2.3.4 Added Addon selection menu for vmtools, qemu-guest-agent
    1.2.3.5 Added DSM password reset(change) and DSM user add menus
    1.2.3.6 Added Clean System Partition(md0) menu
    1.2.3.7 Added Bootentry Update version correction menu
    1.2.3.8 r1000nk, geminilakenk (DS725+, DS425+ kernel 5) support started
    1.2.5.0 Added SYNO RAID (LVM) volume mount menu (for data recovery)
    1.2.5.1 Added a dedicated menu for mounting SYNO BTRFS volumes (for data recovery)
            Requires Tinycore version 9 with kernel 4, like Synology.
    1.2.5.2 Resize 2nd partition of rd.gz when injecting Geminilake and v1000 bootloader
    1.2.5.3 Format Disk Menu Improvements
    1.2.5.4 Apply separate patched buildroot to older AMD CPUs
    1.2.5.5 Separate build pre-option selection menu
    1.2.5.6 Added udma-crc-check Addon for Telegram alarm when S.M.A.R.T UDMA CRC Count (ID 199) increases
    1.2.5.7 Dramatically improved USB backup speed
    1.2.6.0 Add Support DSM 7.3.0-81180 Official Version (For kernel 4.4-based use only)
    1.2.6.1 Loader image size is distributed in two sizes: 2GB and 4GB
    1.2.6.2 When changing user_config.json, process cmd_line at once without loader build
    1.2.6.3 Add Support DSM 7.3.1-86003 Official Version (For kernel 4.4-based use only)
    1.2.6.4 Add Support DSM 6.2.4-25556 Official Version
    1.2.6.5 Added Format System Partition(md0) menu for new install
    1.2.6.6 Added default processing of Verbose OFF when building a loader & warning message when building 7.3 or 7.3.1 loader
    1.2.6.7 Add Support DSM 7.3.2-86009 Official Version (For kernel 4.4-based use only)
    1.2.6.8 Improved backuploader() function [reflects free space check before backup]
    1.2.6.9 Format System Partition(md0) menu stabilization
    1.2.7.0 Skip backup and reboot after ttyd injection (to prevent infinite reboots)
    1.2.7.1 Added support for DSM 7.1.0, added support for Braswell (DS916+, DS716+)
    1.2.7.2 Apply timeout when selecting locale
            Added EUDEV+DDSML automatic conversion function after Kernel 5 model detects R8168
    1.2.7.3 Changes to warning messages and guides when building the DSM 7.3.X loader
    1.2.7.4 Removed warning message when building DSM 7.3.X loader, adjusted Jot Grub boot entry
    1.2.7.5 Remove the default internalportcfg value (0xffff) in user_config.json
    1.2.7.6 Expose modular selection menu as upper menu
    1.2.7.7 Use static firmware and module loading methods when using custom modules
    1.2.7.8 Support for RS18016xs+ (bromolow DSM 7.3.x) and Traditional Chinese
    1.2.7.9 Switch from zstd to xz(lzma2) when compressing initrd-dsm (ramdisk) of custom module.
    1.2.8.0 Discontinued the use of the term Jot and standardized to Direct-Boot
    1.2.8.1 Official epyc7002(sa6400) 7.3.2 amdgpu module support
    1.2.8.2 Switch all-modules loading method from dynamic loading to static loading (like RR/ARC)
    1.2.8.3 Added user DTS file mapping feature
    1.2.8.4 Supports two distinct menus for module loading methods: In-Memory Module Loading (IML) / Persistent Module Loading (PML)
    1.2.8.5 Discontinued Direct-Boot feature, added menu to revert to previous version build
    1.2.8.6 Added a menu to block automatic updates for Tinycore Loader Builder(TCB) and FRIEND Kernel Console(FKC).
    1.2.8.7 Switching the loading method for the last inactive Grub boot entry, DSM Reinstallation (Junior).
    1.2.8.8 Fixed missing firmware inclusion in PML method (initrd-dsm size increased by approximately 60~100MB)
    1.2.8.9 Separating and stabilizing lkm(redpill.ko) by platform and DSM version
    1.2.9.0 HBA controller support begins on Geminilake (DS920+), R1000 (DS923+), and V1000 (DS1621+)
    1.2.9.1 Fixed HBA syno_block_info write failure error when using custom-modules
            Correct display of HBA disk firmware version in Disk Manager
            Block synolanstatus to inhibit the ixgbe loop (about 50 seconds/30 times) in broadwellnk/broadwell/denverton.
    1.2.9.2 Support Insyde Bios Based Models
            The only model supporting Intel 3rd Gen Official Modules (all-modules) Improvements for RS18016xs+ (bromlow, Kernel 3)        
    1.2.9.3 Fixed the conflict issue between Realtek wrapper rxtx and the vanilla version (with pilot sa6400)
            Updating and stabilizing the latest version of the r8168 module
    1.2.9.4 mshell uses self-compiled modules, extending support for kernel 3-based modules
    1.2.9.5 amd-modules begins supporting AMD GPU DRM (H/W transcoding) - Available only on Kernel 5 platforms
    1.2.9.6 AMD GPU DRM Kernel 4.4.302 Full Platform Support Started in amd-modules
    1.2.9.7 Intel iGPU i915 DRM Kernel 4.4.302 All Platform Supports in all-modules
    1.2.9.8 Keep pats.json at persistent /home/tc so a redpill-load clean no longer empties the DSM version (BUILD)
    1.2.9.9 Complete independence from dependencies on other loader modules, MSHELL module secures its own source tree 
            (Integrated Module Pack, i915 DRM, amdgpu DRM, etc.)
    1.3.0.0 Resolved the issue where custom-modules were not working. (Branching error in handling dedicated bzImage usage)
    1.3.0.1 Detect BMI2 CPU support at startup; on kernel 5.10.55+ with non-BMI2 CPUs, restrict module
            selection to custom-modules only (all 4 platforms). custom-modules now supported on all platforms.
    1.3.0.2 redpill addons git clone stabilization
            The i915 and amdgpu modules can be used simultaneously in custom-modules. (/dev/dri/renderD128, /dev/dri/renderD129)
    1.3.0.3 i915 + amdgpu Dual DRM & Expanded AMD Chipset Support in all-modules. (/dev/dri/renderD128, /dev/dri/renderD129)
    1.3.0.4 Delivered a Linux 5.4 LTS OOT backport of i915 and amdgpu as a unified dual-DRM build, 
            enabling Intel iGPU (up to GEN11/Ice Lake) and AMD dGPU (Polaris~RDNA1) to coexist on DSM 4.4.302 without kernel rebuilding.
            Full coverage across 10 platforms × DSM 7.2/7.3 (20 builds), sharing a single `drm.ko` to eliminate ABI conflicts between drivers.
    1.3.0.5 Add Support DSM 7.4.0-90075 Official Version
    1.3.0.6 Support for the NO DRM Module Pack (simplified version for Inject Loader to Disk) has started in nodrm-modules.
    1.3.0.7 Added Check/Expand System Partition(md0) Capacity menu, grows a legacy 2.4GB md0 to the full partition for DSM 7.4 upgrades.
    1.3.0.8 Added icelaked platform support (FS3420, RS1626xs+, RS3626xs, RS4826xs+, RS6426xs+). Supported from DSM 7.4 onwards.
            NOTE: Module packs are epyc7002-based fake/preview builds. Only vanilla NIC drivers work
            (igb, i40e, ixgbe, r8168, bnxt_en, mlx4/mlx5, atlantic, etc.). Full icelaked modules are not yet available.
    1.3.0.9 Added epyc7003ntb platform support (PAS7700). Supported from DSM 7.4 onwards.
    1.3.1.0 Added FS6420 model support. FS6420 is epyc7003 platform (AMD EPYC 7303, single controller, DSM 7.4.0-90075).
             Started support for DSM 7.4 official toolchain-based modules.
    1.3.1.1 Added DHCP lease-renewal suppression for the TinyCore loader session. Freezes the DHCP-assigned IP right
             before the build, stopping periodic renew/rebind traffic and preventing mid-build IP changes.
    1.4.0.0 Begin TinyCore -> Alpine Linux (musl) diskless migration (alpine-redpill branch).
             Pre-investigation completed via 3 rounds of live measurement on a TinyCore 14.0 box: confirmed glibc 2.36
             runtime, mapped tce-load package calls to apk equivalents, and classified prebuilt binaries by link type
             (static/apk-replaceable/DSM-internal/custom). Decided to standardize on ttyd as the single terminal path,
             dropping the urxvt/X11 + glibc locale stack. No showstopper risk found; kpatch/gcompat functional test is
             the only remaining open item. See docs/alpine-migration-plan.md for the full plan.
    1.4.1.0 Fixed low-RAM (2GB) build-time OOM via rootfs tmpfs/disk-swap tuning, dual-NIC auto-DHCP, ESC/Cancel
             no longer exits the menu, and several build/menu script robustness fixes (FDISK resolution, grub
             background image path, main-branch self-reference hardcoding, my.sh.gz workflow ownership safety).
    1.4.1.1 Fixed xTCRP (Buildroot friend-kernel) boxes silently falling back to the stale main branch for
             functions.sh; raised low-RAM swap to 1.5GB and made cleanup run on successful builds too; added
             redpill-load download failure diagnostics; fixed tcrp-modules/tcrp-addons/rp-ext branch references
             (master->main); brightened default terminal colors.
    1.4.1.2 Build failures now always show a memory/ramdisk diagnostic (RAM/swap/tmpfs usage and OOM-killer
             detection) regardless of verbose mode, plus surfaced cpio/download error detail that was being
             captured but never displayed; monitor() now shows ramdisk (tmpfs) size/usage alongside RAM.
             Low-RAM setup-disk-swap now layers a fast zram tier (priority 200) in front of the disk-backed
             swapfile (priority 100), reducing swap latency and USB/flash wear while keeping the disk swap
             as the real capacity backstop; cleanupmemory() now cycles all active swap devices, not just one.
    1.4.2.0 HEADLINE: DSM .pat files are now radically slimmed down. A downloaded Synology .pat (typically
             300-400MB, almost entirely a DSM OS payload the loader never touches) is reduced to just the
             5 files a build actually needs (zImage/rd.gz/GRUB_VER/grub_cksum.syno/VERSION) both for the
             permanently-cached copy on disk (~97% smaller, ~400MB->~10MB) and during the build itself
             (redpill-load now extracts only those files from the .pat instead of unpacking the whole
             archive into tmpfs) - directly cutting the single largest source of low-RAM build-time OOM.
             Also in this stability milestone: fixed a curl -n(--netrc) typo that made bundled-extension
             downloads fail structurally; fixed /lib64 symlink existence checks that errored on every
             rebuild; fixed dialog silently hanging on TERM=dumb SSH sessions (xTCRP); fixed xTCRP falling
             back to the stale main branch twice more (xtcrp.tgz restore URL, functions.sh's own $build
             variable); fixed bspatch losing its execute bit when copied via sudo. All changes tested
             end-to-end on real hardware (xTCRP + mshell) before merging from the _t test track into
             production.
    1.4.2.1 Add Support DSM 7.4.1-90080 Official Version for all supported models (pats.json/config
             extended; module/addon recipes reuse the existing DSM 7.4 (_74_) keys, same kernel line).
             Fixed the revision-picker menu truncating the oldest supported version now that each
             model has 12 revision buckets instead of 11 (menu_m.sh slice .[:11] -> .[:12]).
    1.4.2.2 Fixed selectversion()'s revision-picker still hiding the 12th (oldest) entry on some
             models: the tags=(a..k) lookup array had only 11 letters even after the .[:12] slice
             fix in 1.4.2.1, leaving the 12th item's tag empty. Unified BMI2-related version gating
             across checkAndResetModuleName()/selectldrmode()/selectversion(): all-modules requires
             BMI2 starting DSM 7.3.0, but the BMI2-free custom-modules alternative is only built
             through DSM 7.3.2, so a BMI2-less CPU can now only use < 7.3.0 (all-modules) or
             7.3.0-7.3.2 (custom-modules) - DSM 7.4.0+ is consistently blocked everywhere instead of
             only at the version-picker step; a stale stored DSM version past 7.3.2 is now corrected
             the moment a BMI2-less model is selected (new enforceBmi2VersionCap(), called from
             modelMenu()). Replaced the TinyCore /etc/motd (fetched from a stale main-branch path)
             with an alpine-redpill-branded colored logo; mshell-only, xTCRP is unaffected.
    1.4.2.3 HEADLINE: End-to-end NVIDIA hardware-transcoding support, selectable from the main menu
             (g) - driver version, optional NVENC ffmpeg for Jellyfin, addon enable, all resolved
             live against kernel/platform capability (kernel 5.10.55: 470/535/550/580; kernel 4.4:
             550 only, NVIDIA's own floor; kernel 3.10: unsupported). Verified on real hardware
             (Quadro P620, epyc7002 + geminilake). Fixed the NVIDIA addon silently missing from
             built loaders: bundled-exts.json (the file the build actually reads) is the source of
             truth again, restoring it from an over-eager general.* refactor that let it drift out
             of sync with the menu toggle; already-drifted installs self-repair on next run.
             Generalized addon preservation across a build's bundled-exts.json reset via an
             upstream-diff merged-addons.json, so any user-enabled addon survives, not just a
             hardcoded list. Reworked the main menu (k/c moved under z, dtsmapping moved to z,
             all-lowercase indices, MAC selection as its own up-to-8-interface submenu, panel size
             shown in the title bar). Also fixed: 8-port MAC flow dropping out after eth6; `menu.sh
             test` crashing on new message IDs (i18n.h wasn't refreshed alongside menu_m.sh);
             --no-tags hiding submenu index letters; missing Mesa DRI packages leaving X's
             framebuffer frozen while openbox/tint2/lxterminal ran (mesa-dri-gallium/gl/egl/gbm
             added). 18 languages updated with 2 new translated strings.
    1.4.2.4 Completed menu localization: every remaining hardcoded English string across the main
             menu and its submenus is now translated into all 18 supported languages. The Verbose
             Mode submenu was rebuilt as a dialog window (previously a plain text prompt), and the
             low-memory notice that blocks 'Rebuild Previous Version' under 6GB is now a dialog
             popup instead of console output that was easy to miss. Also fixed a dialog sizing bug
             that made the Verbose submenu close immediately on 24-row consoles.
    1.4.2.5 Retired the legacy TinyCore-only multi-NIC eth* reorder and DHCP/default-route reset
             from automatic menu startup. Alpine and xTCRP already enumerate NICs in PCI order;
             avoiding the reset preserves active SSH management sessions. Expanded the BMI2-free
             custom-modules path on kernel-5 platforms through DSM 7.4.1, including the relevant
             version cap, model-selection correction, picker filtering, and module-mode validation.
    1.4.2.6 Added a standalone dialog-based loader burner. It can convert a legacy TinyCore
             loader to Alpine while preserving user_config.json when present, explicitly accepts
             TinyCore media without an alpine partition, and rejects the 5GB image when RAM is
             below 8GB. Missing user_config.json now permits recording without restoration.
    1.4.2.7 Added cache panel size selection and improved loader burner display locale and menu
             behavior
    1.4.2.8 Added AMD runtime staging MSHELL Manager updates MAC menu defaults USB cmdline preservation
             and initial image GRUB display fix
    1.4.2.9 Added Alpine 3.8 kernel 4.14 BTRFS recovery environment with storage modules DHCP and BTRFS LVM mount support
    1.4.3.0 Fixed several non-interactive/friend-kernel build issues: prerelease tag lookup no
             longer fails TLS verification without a CA bundle, PAT cache and extension index/
             recipe files written via sudo on a friend kernel are no longer left unreadable to
             the tc user, and the build progress bar no longer errors when no controlling
             terminal is attached.
    1.4.3.1 Promoted from the test track: /home/tc/user_config.json is now a symlink onto
             /mnt/tcrp/user_config.json (a stable alias for the loader partition maintained
             across disk-enumeration changes) instead of a second, separately-synced copy.
             writeConfigKey()/sync_usb_line() now preserve that symlink across writes instead
             of replacing it with a plain file. DeleteConfigKey() and preserve_usb_line_options()
             now drop general.usb_line entries for extra_cmdline keys (sn/mac1-8/vid/pid/
             netif_num) that no longer exist, instead of leaving them orphaned indefinitely.
    1.4.3.2 NetConsole early log: stream the boot log to another PC over UDP in real time, no
            serial port/internet/DHCP required, right up to the last line before a panic. New Environment
            menu item auto-detects everything but the listener IP, translated into all 18 langMenu()
            locales. Plus raw.githubusercontent.com CDN cache busting for every curl call and several
            small fixes (SataPortMap defaults, MODULES_TAG accuracy, usb_line cleanup, git-clone
            validation, checkcpu without lscpu).             
    --------------------------------------------------------------------------------------
EOF
}

            
# Made by Peter Suh
# 2022.04.18                      
# Update add 42661 U1 NanoPacked 
# 2022.04.28
# Update : add noconfig, noclean, manual options
# 2022.04.30
# Update : add noconfig, noclean, manual combinatione options
# 2022.05.06   
# Update : add pat file sha256 check                         
# 2022.05.07      
# Update : Added dtc compilation function for user custom.dts file
# 2022.05.15
# Update : add jumkey's jun mode
# 2022.05.24
# Update : apply jumkey's dyn dtc upx
# 2022.05.25
# Update : apply jumkey's dyn dtc upx for option
# 2022.06.01
# Update : add rd.gz patch for 42661 U2
# 2022.06.03
# Update : Fixed Jun mode build option incorrectly applied
# 2022.06.06
# Update : Add jumkey's Jun mode (use jumkey repo)
# 2022.06.11
# Update : Adjunst Option Operation
# 2022.06.13
# Update : Add manual option for jun mode
# 2022.06.16
# Update : Add dtc mode for known as non-dtc model
# 2022.06.25
# Update : Add dtc model DS2422+ (v1000) support
# 2022.06.27
# Update : remove jumkey, poco oprtions
# 2022.06.30
# Update : Add DS2422+ jot mode
# 2022.07.02
# Update : Add DVA1622 jun mode (Testing)
# 2022.07.07
# Update : Add DS1520+ jun mode
# 2022.07.08
# Update : Add FS2500 jun mode
# 2022.07.10
# Update : function headers for my.sh and myv.shUse common function headers for my.sh and myv.sh
# 2022.07.11
# Update : Add REALMAC Option
# 2022.07.15
# Update : Add DS1621xs+ jun mode
# 2022.07.19
# Update : Add DS1621xs+ jot mode, Add RS4021xs+
# 2022.07.20
# Update : Add DVA3219 jot mode (Release 22.07.25)
# 2022.07.21
# Update : Active rploader satamap for non dtc model
# 2022.07.27
# Update : Add Re-Install DSM menuentry
# 2022.08.03
# Update : Apply fabio's redpill.ko
# 2022.08.04
# Update : Add Userdts Options
# 2022.08.06
# Update : Release FS2500 Jot / Jun Mode
# 2022.08.12
# Update : Add RS3618xs Jot / Jun Mode
# 2022.08.14
# Update : Add RS3413xs+ Jot / Jun Mode
# 2022.08.16
# Update : Added support for DSM 7.1.1-42962
# 2022.09.13
# Update : Add DS1019+ Jot / Jun Mode
# 2022.09.14
# Update : Release DS1520+ jot mode
# 2022.09.14
# Update : Release DVA3219 jun mode
# 2022.09.14
# Update : Sataportmap,DiskIdxMap to blank for VM with noconfig option
# 2022.09.14
# Update : Release TCRP FRIEND mode
# 2022.09.25
# Update : Change to stable redpill kernel ( DS1621xs+, DVA3221, RS3618xs )
# 2022.09.26
# Update : Synchronization according to the TCRP Platform naming convention
# 2022.10.22
# Update : Dropped support for TCRP Jot's Mod /Jun's Mod.
# 2022.11.11
# Update : Deploy menu.sh
# 2022.11.14
# Update : Added autoupdate script, Added Keymap function to menu.sh for multilingual keybaord support
# 2022.11.17
# Update : Added dual mac address make function to menu.sh
# 2022.11.18
# Update : Added ds923+ (r1000)
# 2022.11.25
# Update : Added gitee conversion function when github connection is not possible
# 2022.12.03
# Update : Added quad mac address make function to menu.sh
# 2022.12.04
# Update : Added independent JOT mode build menu to menu.sh
# 2022.12.06
# Correct serial number for DS1520+,DS923+, by Orphee
# 2022.12.13
# Update : Added ds723+ (r1000)
# 2023.01.15
# Update : Add buildable model limit per CPU max threads to menu.sh, add description of features and restrictions for each model
# 2023.01.28
# Update : DT-based model restriction function added to ./menu.sh
# 2023.01.30
# Update : Separation and addition to menu_m.sh for real-time reflection after menu.sh update
# 2023.01.30
# Update : 7.0.1-42218 friend correspondence for DS918+,DS920+,DS1019+, DS1520+ transcoding
# 2023.02.19
# Update : Inspection of FMA3 command support (Haswell or higher) and model restriction function added to menu.sh
# 2023.02.22
# Update :  menu.sh Added new function DDSML / EUDEV selection
#           DDSML ( Detected Device Static Module Loading with modprobe / insmod command )
#           EUDEV (Enhanced Userspace Device with eudev deamon)
# 2023.03.01
# Update : Added erase data disk function to menu.sh
# 2023.03.04
# Update : Increased build processing speed by using RAMDISK & pigz(multithreaded compression) when processing encrypted DSM PAT file decryption
# 2023.03.10
# Update : Improved TCRP loader build process
# 2023.03.14
# Update : Automatic handling of grub.cfg disable_mtrr_trim=1 to unlock AMD Platform 3.5GB RAM limitation
# 2023.03.17
# Update : AMD CPU FRIEND mode menu usage restriction release (except HP N36L/N40L/N54L)
# 2023.03.18
# Update : TCRP FRIEND / JOT menu selection method improvement
# 2023.03.21
# Update : Multilingual menu support started (Korean, Chinese, Japanese, Russian, French, German, Spanish, Brazilian, Italian supported)
# 2023.03.25
# Update : Add language selection menu
# 2023.03.29
# Update : Merging DDSML and EUDEV into one, Improved nic recognition speed by improving realtek firmware omission
# 2023.04.04
# Update : DSM Smallupdateversion Path Management
# 2023.04.15
# Update : Keymap now actually works. (Thanks Orphée)
# 2023.04.29
# Update : Add Postupdate boot entry to Grub Boot for Jot Postupdate to utilize FRIEND's Ramdisk Update
# 2023.05.01
# Update : Add Support DSM 7.2-64551 RC
# 2023.05.02
# Update : Added sa6400 (epyc7002)
# 2023.05.06
# Update : Add 5 models DS720+,RS1221+,RS1619xs+,RS3621xs+,SA3400
# 2023.05.08
# Update : 7.0.1-42218 menu open for all models
# 2023.05.12
# Update : Add Support DSM 7.2-64561 Official Version
# 2023.05.23
# Update : Add Getty Console to DSM 7.2
# 2023.05.26
# Update : Added ds916+ (braswell), 7.2.0 Jot Menu Creation for HP PCs
# 2023.06.03
# Update : Add Support DSM 7.2-64570 Official Version
# 2023.06.17
# Update : Added ds1821+ (v1000)
# 2023.06.18
# Update : Added ds1823xs+ (v1000), ds620slim (apollokale), ds1819+ (denverton)
# 2023.06.20
# Update : Add Support DSM 7.2-64570-1 Official Version
# 2023.07.07
# Update : Fix Bug for userdts option
# 2023.08.24 (M-SHELL for TCRP, v0.9.5.0 release)
# Update : Add storage panel size selection menu
# 2023.08.29
# Update : Added a function to store loader.img for DSM 7.2 for 7.2 automatic loader build of 7.0.1, 7.1.1
# 2023.09.26
# Update : Add Support DSM 7.2.1-69057 Official Version
# 2023.09.30
# Update : Fixed locale selection issue, modified some menu guidance text
# 2023.10.01
# Update : Add "Show SATA(s) # ports and drives" menu
# 2023.10.07
# Update : Add "Burn Anither TCRP Bootloader to USB or SSD" menu
# 2023.10.09
# Update : Add "Clone TCRP Bootloader to USB or SSD" menu
# 2023.10.17
# Update : Add "Show error log of running loader" menu
# 2023.10.18 v0.9.6.0
# Update : Improved extension processing speed (local copy instead of remote curl download)
# 2023.10.22 v0.9.7.0
# Update : Improved build processing speed (removed pat file download process)
# 2023.10.24 v0.9.7.1
# Update : Back to DSM Pat Handle Method
# 2023.10.27 v1.0.0.0
# Update : Kernel patch process improvements    
# 2023.11.04 
# Update : Added DS1522+ (r1000), DS220+ (geminilake), DS2419+ (denverton), DS423+ (geminilake), DS718+ (apollolake), RS2423+ (v1000)
# 2023.11.28
# Update : Turn off thread limits when displaying models (Thanks alirz1)
# 2023.12.01
# Update : Separate tcrp-addons and tcrp-modules repo processing methods
# 2023.12.02
# Update : Add offline loader build function
# 2023.12.18 v1.0.1.0
# Update : Upgrade from Tinycore version 12.0 (kernel 5.10.3) to 14.0 (kernel 6.1.2) to improve compatibility with the latest devices.
# 2023.12.31        
# Added SataPortMap/DiskIdxMap prevent initialization menu for virtual machines  
# 2024.02.03
# Created a menu to select the mac-spoof add-on and a submenu for additional features.
# 2024.02.06
# update corepure64.gz for tc user ttyS0 serial console works
# 2024.02.08
# Add Apollolake DS218+
# 2024.02.22 v1.0.2.0
# Remove restrictions on use of DT-based models when using HBA (apply mpt3sas blacklist instead)
# 2024.03.06 v1.0.2.2
# Recycle initrd-dsm instead of custom.gz (extract /exts)
# 2024.03.13 v1.0.2.3 
# Added RedPill bootloader hard disk porting function
# 2024.03.15
# Added RedPill bootloader hard disk porting function supporting 1 SHR Type DISK
# 2024.03.18
# Added RedPill bootloader hard disk porting function supporting All SHR & RAID Type DISK
# 2024.03.22 v1.0.2.4 
# Added NVMe bootloader support
# 2024.03.23
# Fixed bug where both modules disappear when switching between ddsml and eudev (Causes NIC unresponsiveness)
# 2024.03.24    
# Added missing mmc partition search function
# 2024.04.01 v1.0.2.5
# Provides menu option to disable i915 module loading to prevent console blackout in ApolloLake (DS918+), GeminiLake (DS920+), and Epyc7002 (SA6400)
# 2024.04.09 v1.0.2.6
# Added multilingual support languages (locales) (Arabic, Hindi, Hungarian, Indonesian, Turkish)
# 2024.04.09 v1.0.2.7
# dbgutils Addon Add/Delete selection menu
# 2024.04.14
# sortnetif Addon Add/Delete selection menu
# 2024.05.08 v1.0.2.8
# Added multilingual support languages (locales) (Amharic-Ethiopian, Thai)
# 2024.05.13
# Menu configuration for adding nvmesystem addon
# 2024.05.26 v1.0.3.0
# Integrate my, rploader.sh, myfunc.h into functions.sh, optimize distribution
# 2024.06.01 v1.0.3.1, 1.0.3.2
# Added loader file packing menu for remote update, Added dom_szmax for jot mode
# 2024.06.04 v1.0.3.3 
# Boot entry order for jot mode synchronized with Friend's order
# 2024.06.08 v1.0.3.4
# Maintain boot-wait addon when using satadom in SA6400
# 2024.06.09 v1.0.3.5 
# Remove getstaticmodule() and undefined PROXY variables (cause of lkm download failure in final release)
# 2024.06.10 v1.0.3.6 
# Use intel_iommu on the command line
# 2024.06.11 v1.0.3.7 
# Add command line native satadom support option change menu
# 2024.06.17 v1.0.3.8
# Sort netif order by bus-id order (Synology netif sorting method)
# 2024.07.06 v1.0.3.9 
# NVMe-related function supplementation and error correction
# Discontinue use of sortnetif addon, discontinue use of sortnetif if there is only 1 NIC
# 2024.07.07 v1.0.4.0 
# Added sata_remap processing menu for SataPort reordering.
# 2024.08.23 v1.0.4.1 
# Added a feature to check whether the pre-counted number of disks matches when booting Friend
# 2024.08.26 v1.0.4.2
# Update : Add Support DSM 7.2.2-72803 Official Version
# 2024.08.31 v1.0.4.3 
# No separation between USB/SATA menus in Jot Mod (boot menu merge)
# 2024.09.05 v1.0.4.4 
# Loader building is blocked when using Apollolake + proxmox(kvm)/qemu(kvm) (KP occurs in versions after lkm 24.8.29)
# 2024.09.08 v1.0.4.5 
# Solved the KP occurrence issue when using SATA-type bootloader in proxmox(kvm), 
# SA6400(epyc7002) integration from lkm5 (lkm 24.9.8)
# 2024.09.09 v1.0.4.6 
# Rearrange menu order, automatically enter Gen value when S/N or mac is not selected
# 2024.09.12 v1.0.4.7 
# Fix from DSM 7.2.2-72803 to DSM 7.2.2-72806
# 2024.10.14 v1.0.4.8 
# Enable mmc (SD Card) bus type recognition for the bootloader
# 2024.10.15 v1.0.4.9 
# When mmc bus type is used, module processing method is applied with priority given to eudev instead of ddsml.
# 2024.10.26 v1.0.5.0 
# Improved internet check function in menu.sh
# 2024.11.04 v1.0.5.1 
# Added manual update feature to friend specified version, added disable/enable friend automatic update feature
# 2024.11.05 v1.0.5.2 
# Upgraded grub version from 2.06 to 2.12 ( improved uefi, legacy boot compatibility [especially in jot mode] )
# 2024.11.14 v1.0.6.0 
# Added the ability to choose between the integrated modules all-modules (tcrp) and rr-modules
# 2024.11.16 v1.0.6.1 
# Improved bootloader boot partition detection method
# 2024.11.19 v1.0.6.2 
# Changed to use only the first one when multiple bootloaders exist
# 2024.11.27 v1.0.6.3
# Added ability to force loading mmc and sd modules when loading Tinycore Linux
# 2024.12.17 v1.0.6.4 
# Expanded MAC address support from 4 to 8.
# 2024.12.20 v1.0.6.5 
# Includes tinycore linux scsi module for scsi type bootloader support.
# 2024.12.22 v1.0.6.6 
# Discontinuing support for DS3615xs.
# 2024.12.23 v1.0.6.7
# Applying REDPILL background image to grub boot
# 2025.01.01 v1.0.6.8
# i915.modeset=0 menu processing improvement (FRIEND guidance console is activated when i915 transcoding is disabled)
# 2025.01.06 v1.1.0.0 
# Added features for distribution of xTCRP (Tinycore Linux stripped down version)
# 2025.01.12 v1.1.0.1 
# When using a single m.2 NVMe volume, the DDSML error issue has occurred, 
# so menu usage has been excluded and related support has been strengthened.
# 2025.01.29 v1.2.0.0 
# Added new platforms purley, broadwellnkv2, broadwellntbap and started supporting all models for each platform
# 2025.02.02 v1.2.1.0 
# Create tinycore-mshell and xTCRP together in grub boot. Merge Re-install boot entries without USB/SATA distinction and fix KP bug.
# 2025.02.06 v1.2.1.1 
# Renewal of SynoDisk bootloader injection function
# 2025.02.07 v1.2.1.2 
# SynoDisk with Bootloader Injection Supports NVMe DISK
# 2025.02.09 v1.2.1.3 
# SynoDisk with Bootloader Injection Supports Single SHR DISK
# 2025.02.10 v1.2.1.4 
# SynoDisk with bootloader injection feature discontinues support for BASIC or JBOD DISK
# 2025.02.11 v1.2.1.5 
# SynoDisk with bootloader injection uses UUID 8765-4321 instead of 6234-C863
# 2025.02.17 v1.2.1.6 
# DS3615xs(bromolow) support again, LEGACY boot mode must be used!
# 2025.02.25 v1.2.1.7 
# SynoDisk with Bootloader Injection Supports 2.4GB /dev/md0 size (before dsm 7.1.1)
# 2025.03.01 v1.2.1.8 
# Modify the method of checking Internet connection in menu.sh
# 2025.03.06 v1.2.1.9 
# Fixed to keep graphic console screen even in Jot Mode/Legacy Boot environment (use gfxpayload=keep)
# 2025.03.07 v1.2.2.0 
# Activate Tinycore TTYD web console (port 7681, login use tc/P@ssw0rd)
# 2025.03.11 v1.2.2.1 
# TTYD web console baremetal headless support fix
# 2025.03.13 v1.2.2.2 
# Added to change the default value of the Grub boot entry (in the submenu)
# 2025.03.29 v1.2.2.3
# Added a feature to immediately reflect changes to user_config.json (no need for loader build)
# 2025.04.09 v1.2.2.4 
# SynoDisk with bootloader injection Support SHR 2TB or more
# 2025.04.12 v1.2.2.5 
# SynoDisk with bootloader injection Support UEFI ESP and two more SHR 2TB or more
# 2025.04.12 v1.2.2.6 
# SynoDisk with bootloader injection Support All Type GPT (BASIC, JBOD, SHR, RAID1,5,6)
# 2025.04.13 v1.2.2.7 
# SynoDisk with bootloader injection Support xTCRP loader rebuild
# 2025.04.15 v1.2.2.8 
# Fix DS920+ 3rd partition space shortage issue with SynoDisk with bootloader injection
# 2025.04.18 v1.2.2.9 
# Fixed the issue where the font of the menu focus would be broken 
# when changing to a 2-byte Unicode language during the first execution of menu.sh.
# Apply i915-related firmware only to sa6400, reduce the size of the patched dsm kernel in other models 
# (solve the issue of insufficient space for injection of large-capacity kernel bootloader such as ds920+/ds1621+)
# 2025.04.22 v1.2.3.0 
# avoton (DS1515+ kernel 3) support started
# 2025.04.23 v1.2.3.1 
# cedarview (DS713+ kernel 3) support started
# 2025.04.24 v1.2.3.2 
# More models supported for avoton and cedarview (including DS1815+)
# 2025.04.24 v1.2.3.3 
# v1000nk (DS925+ kernel 5) support started
# 2025.05.14 v1.2.3.4 
# Added Addon selection menu for vmtools, qemu-guest-agent
# 2025.05.21 v1.2.3.5 
# Added DSM password reset (change) and DSM user add menus
# 2025.05.24 v1.2.3.6
# Added Clean System Partition(md0) menu
# 2025.05.26 v1.2.3.7 
# Added Bootentry Update version correction menu
# 2025.05.29 v1.2.3.8 
# r1000nk, geminilakenk (DS725+, DS425+ kernel 5) support started
# 2025.06.03 v1.2.5.0 
# Added SYNO RAID (LVM) volume mount menu (for data recovery)
# 2025.06.05 v1.2.5.1 
# Added a dedicated menu for mounting SYNO BTRFS volumes (for data recovery)
# Requires Tinycore version 9 with kernel 4, like Synology.
# 2025.06.11 v1.2.5.2 
# Resize 2nd partition of rd.gz when injecting Geminilake and v1000 bootloader
# 2025.06.28 v1.2.5.3 
# Format Disk Menu Improvements
# 2025.07.02 v1.2.5.4 
# Apply separate patched buildroot to older AMD CPUs
# 2025.08.14 v1.2.5.5 
# Separate build pre-option selection menu
# 2025.09.01 v1.2.5.6 
# Added udma-crc-check Addon for Telegram alarm when S.M.A.R.T UDMA CRC Count (ID 199) increases
# 2025.10.06 v1.2.5.7 
# Dramatically improved USB backup speed
# 2025.10.08 v1.2.6.0 
# Add Support DSM 7.3.0-81180 Official Version (For kernel 4.4-based use only)
# 2025.10.22 v1.2.6.1 
# Loader image size is distributed in two sizes: 2GB and 4GB
# 2025.10.24 v1.2.6.2 
# When changing user_config.json, process cmd_line at once without loader build
# 2025.10.29 v1.2.6.3
# Add Support DSM 7.3.1-86003 Official Version (For kernel 4.4-based use only)
# 2025.10.31 v1.2.6.4 
# Add Support DSM 6.2.4-25556 Official Version
# 2025.11.07 v1.2.6.5 
# Added Format System Partition(md0) menu for new install
# 2025.11.18 v1.2.6.6 
# Added default processing of Verbose OFF when building a loader & warning message when building 7.3 or 7.3.1 loader
# 2025.12.04 v1.2.6.7 
# Add Support DSM 7.3.2-86009 Official Version (For kernel 4.4-based use only)
# 2025.12.17 v1.2.6.8 
# Improved backuploader() function [reflects free space check before backup]
# 2025.12.31 v1.2.6.9 
# Stabilization of the system partition (md0) format menu
# 2026.01.24 v1.2.7.0 
# Skip backup and reboot after ttyd injection (to prevent infinite reboots)
# 2026.01.30 v1.2.7.1 
# Added support for DSM 7.1.0, added support for Braswell (DS916+, DS716+)
# 2026.02.05 v1.2.7.2 
# Apply timeout when selecting locale
# Added EUDEV+DDSML automatic conversion function after Kernel 5 model detects R8168
# 2026.02.08 v1.2.7.3 
# Changes to warning messages and guides when building the DSM 7.3.X loader
# 2026.02.12 v1.2.7.4 
# Removed warning message when building DSM 7.3.X loader, adjusted Jot Grub boot entry
# 2026.02.22 v1.2.7.5 
# Remove the default internalportcfg value (0xffff) in user_config.json
# 2026.02.26 v1.2.7.6 
# Expose modular selection menu as upper menu
# 2026.03.06 v1.2.7.7 
# Use static firmware and module loading methods when using custom modules
# 2026.03.07 v1.2.7.8 
# Support for RS18016xs+ (bromolow DSM 7.3.x) and Traditional Chinese
# 2026.03.10 v1.2.7.9 
# Switch from zstd to xz(lzma2) when compressing initrd-dsm (ramdisk) of custom module.
# 2026.03.15 v1.2.8.0 
# Discontinued the use of the term Jot and standardized to Direct-Boot
# 2026.03.17 v1.2.8.1 
# Official epyc7002(sa6400) 7.3.2 amdgpu module support
# 2026.03.19 v1.2.8.2 
# Switch all-modules loading method from dynamic loading to static loading (like RR/ARC)
# 2026.03.19 v1.2.8.3 
# Added user DTS file mapping feature
# 2026.03.20 v1.2.8.4 
# Supports two distinct menus for module loading methods: In-Memory Module Loading (IML) / Persistent Module Loading (PML)
# 2026.03.24 v1.2.8.5 
# Discontinued Direct-Boot feature, added menu to revert to previous version build
# 2026.03.25 v1.2.8.6 
# Added a menu to block automatic updates for Tinycore Loader Builder(TCB) and FRIEND Kernel Console(FKC).
# 2026.03.28 v1.2.8.7 
# Switching the loading method for the last inactive Grub boot entry, DSM Reinstallation (Junior).
# 2026.04.03 v1.2.8.8 
# Fixed missing firmware inclusion in PML method (initrd-dsm size increased by approximately 60~100MB)
# 2026.04.12 v1.2.8.9 
# Separating and stabilizing lkm(redpill.ko) by platform and DSM version
# 2026.04.14 v1.2.9.0 
# HBA controller support begins on Geminilake (DS920+), R1000 (DS923+), and V1000 (DS1621+)
# 2026.04.19 v1.2.9.1 
# Fixed HBA syno_block_info write failure error when using custom-modules
# Correct display of HBA disk firmware version in Disk Manager
# Block synolanstatus to inhibit the ixgbe loop (about 50 seconds/30 times) in broadwellnk/broadwell/denverton.
# 2026.05.01 v1.2.9.2 
# Support Insyde Bios Based Models
# The only model supporting Intel 3rd Gen Official Modules (all-modules) Improvements for RS18016xs+ (bromlow, Kernel 3)        
# 2026.05.07 v1.2.9.3 
# Fixed the conflict issue between Realtek wrapper rxtx and the vanilla version (with pilot sa6400)
# Updating and stabilizing the latest version of the r8168 module
# 2026.05.14 v1.2.9.4 
# mshell uses self-compiled modules, extending support for kernel 3-based modules
# 2026.05.22 v1.2.9.5 
# amd-modules begins supporting AMD GPU DRM (H/W transcoding) - Available only on Kernel 5 platforms
# 2026.05.25 v1.2.9.6
# AMD GPU DRM Kernel 4.4.302 Full Platform Support Started in amd-modules
# 2026.05.27 v1.2.9.7 
# Intel iGPU i915 DRM Kernel 4.4.302 All Platform Supports in all-modules
# 2026.05.27 v1.2.9.8
# Keep pats.json at persistent /home/tc so a redpill-load clean no longer empties the DSM version (BUILD)
# 2026.06.02 v1.2.9.9 
# Complete independence from dependencies on other loader modules, MSHELL module secures its own source tree 
# (Integrated Module Pack, i915 DRM, amdgpu DRM, etc.)
# 2026.06.03 v1.3.0.0
# Resolved the issue where custom-modules were not working. (Branching error in handling dedicated bzImage usage)
# 2026.06.07 v1.3.0.1
# Detect BMI2 CPU support at startup; on kernel 5.10.55+ with non-BMI2 CPUs, restrict module selection to custom-modules only (all 4 platforms).
# custom-modules now supported on all 4 platforms (epyc7002, geminilakenk, r1000nk, v1000nk). icelaked added from v1.3.0.8.
# 2026.06.10 v1.3.0.2 
# redpill addons git clone stabilization
# The i915 and amdgpu modules can be used simultaneously in custom-modules. (/dev/dri/renderD128, /dev/dri/renderD129)
# 2026.06.12 v1.3.0.3 
# i915 + amdgpu Dual DRM & Expanded AMD Chipset Support in all-modules. (/dev/dri/renderD128, /dev/dri/renderD129)
# 2026.06.15 v1.3.0.4 
# Delivered a Linux 5.4 LTS OOT backport of i915 and amdgpu as a unified dual-DRM build, 
# enabling Intel iGPU (up to GEN11/Ice Lake) and AMD dGPU (Polaris~RDNA1) to coexist on DSM 4.4.302 without kernel rebuilding.
# Full coverage across 10 platforms × DSM 7.2/7.3 (20 builds), sharing a single `drm.ko` to eliminate ABI conflicts between drivers.
# 2026.06.17 v1.3.0.5 
# Add Support DSM 7.4.0-90075 Official Version
# 2026.06.19 v1.3.0.6
# Support for the NO DRM Module Pack (simplified version for Inject Loader to Disk) has started in nodrm-modules.
# 2026.06.25 v1.3.0.7
# Added "Check / Expand System Partition(md0) Capacity" menu under Syno disk and partition handling.
# Detects a legacy 2.4GB md0 on an 8GB partition (blocks DSM 7.4 upgrade at ~56% file-corrupt) and grows md0 + ext4 to the full partition.

# 2026.07.01 v1.3.0.8
# Added icelaked platform support (FS3420, RS1626xs+, RS3626xs, RS4826xs+, RS6426xs+). Supported from DSM 7.4 onwards.
# Module packs are epyc7002-based fake/preview. Only vanilla NIC drivers work (igb, i40e, ixgbe, r8168, bnxt_en, mlx4/mlx5, atlantic, etc.).

# 2026.07.04 v1.3.0.9
# Added epyc7003ntb platform support (PAS7700). Supported from DSM 7.4 onwards.

# 2026.07.08 v1.3.1.0
# Added FS6420 model support. FS6420 is epyc7003 platform (AMD EPYC 7303, single controller, DSM 7.4.0-90075).
# Started support for DSM 7.4 official toolchain-based modules.

# 2026.07.10 v1.3.1.1
# Added DHCP lease-renewal suppression for the TinyCore loader session (freezes the DHCP-assigned IP during build,
# stopping periodic renew/rebind traffic and preventing mid-build IP changes).

# 2026.07.16 v1.4.0.0
# Begin TinyCore -> Alpine Linux (musl) diskless migration (alpine-redpill branch).

# 2026.07.19 v1.4.1.0
# Fixed low-RAM (2GB) build-time OOM (rootfs tmpfs/disk-swap tuning), dual-NIC auto-DHCP, ESC/Cancel menu exit,
# and several build/menu script robustness fixes.

# 2026.07.19 v1.4.1.1
# Fixed xTCRP falling back to the stale main branch for functions.sh, raised low-RAM swap to 1.5GB, added
# redpill-load download diagnostics, fixed tcrp-modules/tcrp-addons/rp-ext branch references, brightened
# terminal colors.

# 2026.07.22 v1.4.1.2
# Build failures now always show a memory/ramdisk diagnostic (RAM/swap/tmpfs usage, OOM-killer detection)
# regardless of verbose mode, and surface previously-hidden cpio/download error detail. monitor() now shows
# ramdisk (tmpfs) size/usage. Low-RAM swap now layers zram (fast, priority 200) in front of the disk
# swapfile (priority 100); cleanupmemory() cycles all active swap devices.

# 2026.07.22 v1.4.2.0
# HEADLINE: DSM .pat files slimmed to ~3% of their original size (only the 5 files a build actually needs
# are kept, both in the permanent cache and during the build itself) - directly cuts the largest source
# of low-RAM build-time OOM. Also: fixed curl -n(--netrc) breaking extension downloads, /lib64 symlink
# re-creation errors, dialog hanging on TERM=dumb SSH sessions, xTCRP regressing to stale main branch
# (twice more), and bspatch losing its execute bit.

# 2026.07.24 v1.4.2.1
# Added DSM 7.4.1-90080 (official) to the supported revision whitelist for all models, and fixed the
# revision-picker menu truncating the oldest supported version (12 buckets now, slice was still 11).

# 2026.07.25 v1.4.2.2
# Fixed the revision-picker still hiding the 12th (oldest) entry on some models (tags lookup array was
# still only 11 letters). Unified BMI2 version gating across module-name/loader-mode/version-picker: a
# BMI2-less CPU can now only use < 7.3.0 (all-modules) or 7.3.0-7.3.2 (custom-modules), consistently
# blocking DSM 7.4.0+ everywhere, including immediately at model-selection time. Replaced the stale
# TinyCore /etc/motd with an alpine-redpill-branded colored logo (mshell only, xTCRP unaffected).

# 2026.07.26 v1.4.2.3
# HEADLINE: End-to-end NVIDIA hardware-transcoding support (main menu g) - driver version, optional
# NVENC ffmpeg, addon enable, all resolved live against kernel/platform capability; verified on real
# hardware (Quadro P620, epyc7002 + geminilake). Fixed the NVIDIA addon silently missing from built
# loaders (bundled-exts.json restored as source of truth; drifted installs self-repair). Generalized
# addon preservation via an upstream-diff merged-addons.json instead of a hardcoded capture list.
# Reworked the main menu (k/c under z, dtsmapping moved, all-lowercase indices, MAC as its own
# up-to-8-interface submenu, panel size in the title bar). Also fixed: 8-port MAC flow dropping out
# after eth6; `menu.sh test` crashing on new message IDs; --no-tags hiding submenu index letters;
# missing Mesa DRI packages leaving X's framebuffer frozen. 18 languages updated with 2 new strings.

# 2026.07.31 v1.4.2.4
# Completed menu localization - all remaining hardcoded English strings in the main menu and its
# submenus are now translated into all 18 supported languages. Verbose Mode submenu rebuilt as a
# dialog window, and the under-6GB block notice for 'Rebuild Previous Version' is now a dialog
# popup. Fixed a dialog sizing bug that closed the Verbose submenu instantly on 24-row consoles.

# 2026.08.01 v1.4.2.5
# Disabled the legacy TinyCore-only multi-NIC eth* reorder and DHCP/default-route reset at menu
# startup. Alpine and xTCRP already enumerate NICs in PCI order, so this preserves active SSH
# management sessions. Expanded BMI2-free custom-modules support on kernel-5 platforms through
# DSM 7.4.1 and aligned the cap, model-selection correction, picker filtering, and mode validation.

# 2026.08.02 v1.4.2.6
# Added a standalone dialog-based loader burner. Legacy TinyCore media without an alpine partition
# can be converted while user_config.json is backed up and restored when present. The 5GB image
# requires at least 8GB RAM; a missing user_config.json no longer blocks recording.

# 2026.08.07 v1.4.2.7
# Added cache panel size selection and improved loader burner display locale and menu behavior

# 2026.08.12 v1.4.2.8
# Added AMD runtime staging MSHELL Manager updates MAC menu defaults USB cmdline preservation and
# initial image GRUB display fix

# 2026.08.15 v1.4.2.9
# Added Alpine 3.8 kernel 4.14 BTRFS recovery environment with storage modules DHCP and BTRFS LVM mount support

# 2026.08.16 v1.4.3.0
# Fixed several non-interactive/friend-kernel build issues: prerelease tag lookup no longer fails
# TLS verification without a CA bundle, PAT cache and extension index/recipe files written via
# sudo on a friend kernel are no longer left unreadable to the tc user, and the build progress bar
# no longer errors when no controlling terminal is attached.

# 2026.08.17 v1.4.3.1
# Promoted from the test track: /home/tc/user_config.json is now a symlink onto
# /mnt/tcrp/user_config.json instead of a second, separately-synced copy, with writes preserving
# the symlink and general.usb_line no longer accumulating orphaned sn/mac/vid/pid/netif_num
# entries after they are removed from extra_cmdline.

# 2026.08.19 v1.4.3.2
# HEADLINE: NetConsole early log - stream the boot log over UDP to another PC in real time, no
# serial port/internet/DHCP required, right up to the last line before a panic. New menu item at
# the top of Environment: enter only the listener's IP, everything else (own interface/IP,
# listener MAC via ping+ARP lookup) is auto-detected; translated into all 18 langMenu() locales.
# netconsole.ko is sourced from the DSM .pat's hda1.tgz and embedded permanently into the cached
# minipat so it survives re-packing; insmod runs backgrounded with a retry loop from inside
# linuxrc.syno's Main() (earliest point where /proc is mounted but eth0 isn't up yet), parsing
# the cmdline with shell builtins only since tr isn't available that early. Also: raw.githubusercontent.com
# CDN cache busting for every curl call (not just self-update), SataPortMap/DiskIdxMap defaults,
# MODULES_TAG accuracy, usb_line orphan cleanup, git-clone failure validation, and checkcpu()
# no longer depending on lscpu.

function showlastupdate() {
    cat <<'EOF'

# 2025.04.18 v1.2.2.9 
# Fixed the issue where the font of the menu focus would be broken 
# when changing to a 2-byte Unicode language during the first execution of menu.sh.
# Apply i915-related firmware only to sa6400, reduce the size of the patched dsm kernel in other models 
# (solve the issue of insufficient space for injection of large-capacity kernel bootloader such as ds920+/ds1621+)

# 2025.04.22 v1.2.3.0 
# avoton (DS1515+ kernel 3) support started

# 2025.04.23 v1.2.3.1 
# cedarview (DS713+ kernel 3) support started

# 2025.04.24 v1.2.3.2 
# More models supported for avoton and cedarview (including DS1815+)

# 2025.04.24 v1.2.3.3 
# v1000nk (DS925+ kernel 5) support started

# 2025.05.14 v1.2.3.4 
# Added Addon selection menu for vmtools, qemu-guest-agent

# 2025.05.21 v1.2.3.5 
# Added DSM password reset (change) and DSM user add menus

# 2025.05.24 v1.2.3.6
# Added Clean System Partition(md0) menu

# 2025.05.26 v1.2.3.7 
# Added Bootentry Update version correction menu

# 2025.05.29 v1.2.3.8 
# r1000nk, geminilakenk (DS725+, DS425+ kernel 5) support started

# 2025.06.03 v1.2.5.0 
# Added SYNO RAID (LVM) volume mount menu (for data recovery)

# 2025.06.05 v1.2.5.1 
# Added a dedicated menu for mounting SYNO BTRFS volumes (for data recovery)
# Requires Tinycore version 9 with kernel 4, like Synology.

# 2025.06.11 v1.2.5.2 
# Resize 2nd partition of rd.gz when injecting Geminilake and v1000 bootloader

# 2025.06.28 v1.2.5.3 
# Format Disk Menu Improvements

# 2025.07.02 v1.2.5.4 
# Apply separate patched buildroot to older AMD CPUs

# 2025.08.14 v1.2.5.5
# Separate build pre-option selection menu

# 2025.09.01 v1.2.5.6 
# Added udma-crc-check Addon for Telegram alarm when S.M.A.R.T UDMA CRC Count (ID 199) increases

# 2025.10.06 v1.2.5.7 
# Dramatically improved USB backup speed

# 2025.10.08 v1.2.6.0 
# Add Support DSM 7.3.0-81180 Official Version (For kernel 4.4-based use only)

# 2025.10.22 v1.2.6.1 
# Loader image size is distributed in two sizes: 2GB and 4GB

# 2025.10.24 v1.2.6.2 
# When changing user_config.json, process cmd_line at once without loader build

# 2025.10.29 v1.2.6.3
# Add Support DSM 7.3.1-86003 Official Version (For kernel 4.4-based use only)

# 2025.10.31 v1.2.6.4 
# Add Support DSM 6.2.4-25556 Official Version

# 2025.11.07 v1.2.6.5 
# Added Format System Partition(md0) menu for new install

# 2025.11.18 v1.2.6.6 
# Added default processing of Verbose OFF when building a loader & warning message when building 7.3 or 7.3.1 loader

# 2025.12.04 v1.2.6.7 
# Add Support DSM 7.3.2-86009 Official Version (For kernel 4.4-based use only)

# 2025.12.17 v1.2.6.8 
# Improved backuploader() function [reflects free space check before backup]

# 2025.12.31 v1.2.6.9 
# Stabilization of the system partition (md0) format menu

# 2026.01.24 v1.2.7.0 
# Skip backup and reboot after ttyd injection (to prevent infinite reboots)

# 2026.01.30 v1.2.7.1 
# Added support for DSM 7.1.0, added support for Braswell (DS916+, DS716+)

# 2026.02.05 v1.2.7.2 
# Apply timeout when selecting locale
# Added EUDEV+DDSML automatic conversion function after Kernel 5 model detects R8168

# 2026.02.08 v1.2.7.3 
# Changes to warning messages and guides when building the DSM 7.3.X loader

# 2026.02.12 v1.2.7.4 
# Removed warning message when building DSM 7.3.X loader, adjusted Jot Grub boot entry

# 2026.02.22 v1.2.7.5 
# Remove the default internalportcfg value (0xffff) in user_config.json

# 2026.02.26 v1.2.7.6 
# Expose modular selection menu as upper menu

# 2026.03.06 v1.2.7.7 
# Use static firmware and module loading methods when using custom modules

# 2026.03.07 v1.2.7.8 
# Support for RS18016xs+ (bromolow DSM 7.3.x) and Traditional Chinese

# 2026.03.10 v1.2.7.9 
# Switch from zstd to xz(lzma2) when compressing initrd-dsm (ramdisk) of custom module.

# 2026.03.15 v1.2.8.0 
# Discontinued the use of the term Jot and standardized to Direct-Boot

# 2026.03.17 v1.2.8.1 
# Official epyc7002(sa6400) 7.3.2 amdgpu module support

# 2026.03.19 v1.2.8.2 
# Switch all-modules loading method from dynamic loading to static loading (like RR/ARC)

# 2026.03.20 v1.2.8.3 
# Added user DTS file mapping feature

# 2026.03.20 v1.2.8.4
# Supports two distinct menus for module loading methods: In-Memory Module Loading (IML) / Persistent Module Loading (PML)

# 2026.03.24 v1.2.8.5 
# Discontinued Direct-Boot feature, added menu to revert to previous version build

# 2026.03.25 v1.2.8.6 
# Added a menu to block automatic updates for Tinycore Loader Builder(TCB) and FRIEND Kernel Console(FKC).

# 2026.03.28 v1.2.8.7 
# Switching the loading method for the last inactive Grub boot entry, DSM Reinstallation (Junior).

# 2026.04.03 v1.2.8.8 
# Fixed missing firmware inclusion in PML method (initrd-dsm size increased by approximately 60~100MB)

# 2026.04.12 v1.2.8.9 
# Separating and stabilizing lkm(redpill.ko) by platform and DSM version

# 2026.04.14 v1.2.9.0 
# HBA controller support begins on Geminilake (DS920+), R1000 (DS923+), and V1000 (DS1621+)

# 2026.04.19 v1.2.9.1 
# Fixed HBA syno_block_info write failure error when using custom-modules
# Correct display of HBA disk firmware version in Disk Manager
# Block synolanstatus to inhibit the ixgbe loop (about 50 seconds/30 times) in broadwellnk/broadwell/denverton.

# 2026.05.01 v1.2.9.2 
# Support Insyde Bios Based Models
# The only model supporting Intel 3rd Gen Official Modules (all-modules) Improvements for RS18016xs+ (bromlow, Kernel 3)        

# 2026.05.07 v1.2.9.3 
# Fixed the conflict issue between Realtek wrapper rxtx and the vanilla version (with pilot sa6400)
# Updating and stabilizing the latest version of the r8168 module

# 2026.05.14 v1.2.9.4 
# mshell uses self-compiled modules, extending support for kernel 3-based modules

# 2026.05.22 v1.2.9.5 
# amd-modules begins supporting AMD GPU DRM (H/W transcoding) - Available only on Kernel 5 platforms

# 2026.05.25 v1.2.9.6
# AMD GPU DRM Kernel 4.4.302 Full Platform Support Started in amd-modules

# 2026.05.27 v1.2.9.7 
# Intel iGPU i915 DRM Kernel 4.4.302 All Platform Supports in all-modules

# 2026.05.27 v1.2.9.8
# Keep pats.json at persistent /home/tc so a redpill-load clean no longer empties the DSM version (BUILD)

# 2026.06.02 v1.2.9.9 
# Complete independence from dependencies on other loader modules, MSHELL module secures its own source tree 
# (Integrated Module Pack, i915 DRM, amdgpu DRM, etc.)

# 2026.06.03 v1.3.0.0 
# Resolved the issue where custom-modules were not working. (Branching error in handling dedicated bzImage usage)

# 2026.06.07 v1.3.0.1
# Detect BMI2 CPU support at startup; on kernel 5.10.55+ with non-BMI2 CPUs, restrict module selection to custom-modules only (all 4 platforms).
# custom-modules now supported on all 4 platforms (epyc7002, geminilakenk, r1000nk, v1000nk). icelaked added from v1.3.0.8.

# 2026.06.10 v1.3.0.2 
# redpill addons git clone stabilization
# The i915 and amdgpu modules can be used simultaneously in custom-modules. (/dev/dri/renderD128, /dev/dri/renderD129)

# 2026.06.12 v1.3.0.3 
# i915 + amdgpu Dual DRM & Expanded AMD Chipset Support in all-modules. (/dev/dri/renderD128, /dev/dri/renderD129)

# 2026.06.15 v1.3.0.4 
# Delivered a Linux 5.4 LTS OOT backport of i915 and amdgpu as a unified dual-DRM build, 
# enabling Intel iGPU (up to GEN11/Ice Lake) and AMD dGPU (Polaris~RDNA1) to coexist on DSM 4.4.302 without kernel rebuilding.
# Full coverage across 10 platforms × DSM 7.2/7.3 (20 builds), sharing a single `drm.ko` to eliminate ABI conflicts between drivers.

# 2026.06.17 v1.3.0.5 
# Add Support DSM 7.4.0-90075 Official Version

# 2026.06.19 v1.3.0.6
# Support for the NO DRM Module Pack (simplified version for Inject Loader to Disk) has started in nodrm-modules.

# 2026.06.25 v1.3.0.7
# Added "Check / Expand System Partition(md0) Capacity" menu (grows a legacy 2.4GB md0 to the full 8GB partition for DSM 7.4 upgrades).

# 2026.07.01 v1.3.0.8
# Added icelaked platform support (FS3420, RS1626xs+, RS3626xs, RS4826xs+, RS6426xs+). Supported from DSM 7.4 onwards.
# Module packs are epyc7002-based fake/preview. Only vanilla NIC drivers work (igb, i40e, ixgbe, r8168, bnxt_en, mlx4/mlx5, atlantic, etc.).

# 2026.07.04 v1.3.0.9
# Added epyc7003ntb platform support (PAS7700). Supported from DSM 7.4 onwards.

# 2026.07.08 v1.3.1.0
# Added FS6420 model support. FS6420 is epyc7003 platform (AMD EPYC 7303, single controller, DSM 7.4.0-90075).
# Started support for DSM 7.4 official toolchain-based modules.

# 2026.07.10 v1.3.1.1
# Added DHCP lease-renewal suppression for the TinyCore loader session (freezes the DHCP-assigned IP during build,
# stopping periodic renew/rebind traffic and preventing mid-build IP changes).

# 2026.07.16 v1.4.0.0
# Begin TinyCore -> Alpine Linux (musl) diskless migration (alpine-redpill branch).

# 2026.07.19 v1.4.1.0
# Fixed low-RAM (2GB) build-time OOM (rootfs tmpfs/disk-swap tuning), dual-NIC auto-DHCP, ESC/Cancel menu exit,
# and several build/menu script robustness fixes.

# 2026.07.19 v1.4.1.1
# Fixed xTCRP falling back to the stale main branch for functions.sh, raised low-RAM swap to 1.5GB, added
# redpill-load download diagnostics, fixed tcrp-modules/tcrp-addons/rp-ext branch references, brightened
# terminal colors.

# 2026.07.22 v1.4.1.2
# Build failures now always show a memory/ramdisk diagnostic (RAM/swap/tmpfs usage, OOM-killer detection)
# regardless of verbose mode, and surface previously-hidden cpio/download error detail. monitor() now shows
# ramdisk (tmpfs) size/usage. Low-RAM swap now layers zram (fast, priority 200) in front of the disk
# swapfile (priority 100); cleanupmemory() cycles all active swap devices.

# 2026.07.22 v1.4.2.0
# HEADLINE: DSM .pat files slimmed to ~3% of their original size (only the 5 files a build actually needs
# are kept, both in the permanent cache and during the build itself) - directly cuts the largest source
# of low-RAM build-time OOM. Also: fixed curl -n(--netrc) breaking extension downloads, /lib64 symlink
# re-creation errors, dialog hanging on TERM=dumb SSH sessions, xTCRP regressing to stale main branch
# (twice more), and bspatch losing its execute bit.

# 2026.07.24 v1.4.2.1
# Added DSM 7.4.1-90080 (official) to the supported revision whitelist for all models, and fixed the
# revision-picker menu truncating the oldest supported version (12 buckets now, slice was still 11).

# 2026.07.25 v1.4.2.2
# Fixed the revision-picker still hiding the 12th (oldest) entry on some models (tags lookup array was
# still only 11 letters). Unified BMI2 version gating across module-name/loader-mode/version-picker: a
# BMI2-less CPU can now only use < 7.3.0 (all-modules) or 7.3.0-7.3.2 (custom-modules), consistently
# blocking DSM 7.4.0+ everywhere, including immediately at model-selection time. Replaced the stale
# TinyCore /etc/motd with an alpine-redpill-branded colored logo (mshell only, xTCRP unaffected).

# 2026.07.26 v1.4.2.3
# HEADLINE: End-to-end NVIDIA hardware-transcoding support (main menu g) - driver version, optional
# NVENC ffmpeg, addon enable, all resolved live against kernel/platform capability; verified on real
# hardware (Quadro P620, epyc7002 + geminilake). Fixed the NVIDIA addon silently missing from built
# loaders (bundled-exts.json restored as source of truth; drifted installs self-repair). Generalized
# addon preservation via an upstream-diff merged-addons.json instead of a hardcoded capture list.
# Reworked the main menu (k/c under z, dtsmapping moved, all-lowercase indices, MAC as its own
# up-to-8-interface submenu, panel size in the title bar). Also fixed: 8-port MAC flow dropping out
# after eth6; `menu.sh test` crashing on new message IDs; --no-tags hiding submenu index letters;
# missing Mesa DRI packages leaving X's framebuffer frozen. 18 languages updated with 2 new strings.

# 2026.07.31 v1.4.2.4
# Completed menu localization - all remaining hardcoded English strings in the main menu and its
# submenus are now translated into all 18 supported languages. Verbose Mode submenu rebuilt as a
# dialog window, and the under-6GB block notice for 'Rebuild Previous Version' is now a dialog
# popup. Fixed a dialog sizing bug that closed the Verbose submenu instantly on 24-row consoles.

# 2026.08.01 v1.4.2.5
# Disabled the legacy TinyCore-only multi-NIC eth* reorder and DHCP/default-route reset at menu
# startup. Alpine and xTCRP already enumerate NICs in PCI order, so this preserves active SSH
# management sessions. Expanded BMI2-free custom-modules support on kernel-5 platforms through
# DSM 7.4.1 and aligned the cap, model-selection correction, picker filtering, and mode validation.

# 2026.08.02 v1.4.2.6
# Added a standalone dialog-based loader burner. Legacy TinyCore media without an alpine partition
# can be converted while user_config.json is backed up and restored when present. The 5GB image
# requires at least 8GB RAM; a missing user_config.json no longer blocks recording.

# 2026.08.07 v1.4.2.7
# Added cache panel size selection and improved loader burner display locale and menu behavior
# 2026.08.12 v1.4.2.8
# Added AMD runtime staging MSHELL Manager updates MAC menu defaults USB cmdline preservation and
# initial image GRUB display fix
# 2026.08.15 v1.4.2.9
# Added Alpine 3.8 kernel 4.14 BTRFS recovery environment with storage modules DHCP and BTRFS LVM mount support
# 2026.08.16 v1.4.3.0
# Fixed several non-interactive/friend-kernel build issues: prerelease tag lookup no longer fails
# TLS verification without a CA bundle, PAT cache and extension index/recipe files written via
# sudo on a friend kernel are no longer left unreadable to the tc user, and the build progress bar
# no longer errors when no controlling terminal is attached.
# 2026.08.17 v1.4.3.1
# Promoted /home/tc/user_config.json symlink (avoids two separately-synced copies) and its
# dependent usb_line/backup fixes from the test track.
# 2026.08.19 v1.4.3.2
# NetConsole early log: stream the boot log to another PC over UDP in real time, no serial
# port/internet/DHCP required. New Environment menu item auto-detects everything but the
# listener IP, translated into all 18 languages. Plus raw.githubusercontent.com cache busting
# and several small fixes (SataPortMap defaults, MODULES_TAG accuracy, usb_line cleanup,
# git-clone validation, checkcpu without lscpu).
EOF
}

function showhelp() {
    cat <<EOF
$(basename ${0})

----------------------------------------------------------------------------------------
Usage: ${0} <Synology Model Name> <Options>

Options: update, postupdate, noconfig, noclean, manual, realmac, userdts

- update : Option to handle updates to the m shell.

- postupdate : Option to patch the restore loop after applying DSM 7.1.0-42661 after Update 2, no additional build required.

- noconfig: SKIP automatic detection change processing such as SN/Mac/Vid/Pid/SataPortMap of user_config.json file.

- noclean: SKIP the 💊   RedPill LKM/LOAD directory without clearing it with the Clean command. 
           However, delete the Cache directory and loader.img.

- manual: Options for manual extension processing and manual dtc processing in build action (skipping extension auto detection).

- realmac : Option to use the NIC's real mac address instead of creating a virtual one.

- userdts : Option to use the user-defined platform.dts file instead of auto-discovery mapping with dtcpatch.


Please type Synology Model Name after ./$(basename ${0})

- for friend mode

./$(basename ${0}) DS918+-7.2.1-69057
./$(basename ${0}) DS3617xs-7.2.1-69057
./$(basename ${0}) DS3622xs+-7.2.1-69057
./$(basename ${0}) DVA3221-7.2.1-69057
./$(basename ${0}) DS920+-7.2.1-69057
./$(basename ${0}) DS1621+-7.2.1-69057
./$(basename ${0}) DS2422+-7.2.1-69057
./$(basename ${0}) DVA1622-7.2.1-69057
./$(basename ${0}) DS1520+-7.2.1-69057
./$(basename ${0}) FS2500-7.2.1-69057
./$(basename ${0}) DS1621xs+-7.2.1-69057
./$(basename ${0}) RS4021xs+-7.2.1-69057 
./$(basename ${0}) DVA3219-7.2.1-69057
./$(basename ${0}) RS3618xs-7.2.1-69057
./$(basename ${0}) DS1019+-7.2.1-69057
./$(basename ${0}) DS923+-7.2.1-69057
./$(basename ${0}) DS723+-7.2.1-69057
./$(basename ${0}) SA6400-7.2.1-69057
./$(basename ${0}) DS720+-7.2.1-69057
./$(basename ${0}) RS1221+-7.2.1-69057
./$(basename ${0}) RS2423+-7.2.1-69057
./$(basename ${0}) RS1619xs+-7.2.1-69057
./$(basename ${0}) RS3621xs+-7.2.1-69057
./$(basename ${0}) SA6400-7.2.1-69057
./$(basename ${0}) DS916+-7.2.1-69057
./$(basename ${0}) DS1821+-7.2.1-69057
./$(basename ${0}) DS1819+-7.2.1-69057
./$(basename ${0}) DS1823xs+-7.2.1-69057
./$(basename ${0}) DS620slim+-7.2.1-69057

ex) Except for postupdate and userdts that must be used alone, the rest of the options can be used in combination. 

- When you want to build the loader while maintaining the already set SN/Mac/Vid/Pid/SataPortMap
./my DS3622xs+H noconfig

- When you want to build the loader while maintaining the already set SN/Mac/Vid/Pid/SataPortMap and without deleting the downloaded DSM pat file.
./my DS3622xs+H noconfig noclean

- When you want to build the loader while using the real MAC address of the NIC, with extended auto-detection disabled
./my DS3622xs+H realmac manual

EOF

}

#################################################################################
# Verbose Mode Control for RedPill Bootloader Build
# Usage: source verbose_control.sh
#################################################################################

# Global Verbose Flag
VERBOSE_MODE="OFF"
VERBOSE_FLAG=""

#################################################################################
# Progress Bar Display
#################################################################################
show_progress_bar() {
    local current=$1
    local total=$2
    local step_name="$3"

    local width=24
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))

    # /dev/tty only exists when a controlling terminal is attached -
    # unconditionally writing there breaks headless callers (a build
    # driven over su -c with no tty, like MSHELL Manager's automated
    # rebuild) with "No such device or address" on every single write.
    # Falls back to stdout, which every caller already expects to be
    # capturable (e.g. tee'd to a log file).
    local out=/dev/tty
    # [ -w /dev/tty ] only checks the permission bit, not whether an
    # open() would actually succeed - confirmed it still reports true
    # with no controlling terminal attached, while the open itself
    # fails. Doing the real probe instead; 2>/dev/null has to come
    # before the failing redirect or bash reports the open failure via
    # the original stderr before the suppression is even applied.
    : 2>/dev/null > /dev/tty || out=/dev/stdout

    printf "[" > "$out"
    printf "%${filled}s" | tr ' ' '=' > "$out"
    printf "%$((width - filled))s" | tr ' ' '-' > "$out"
    printf "] %d%% (%d/%d) [%s]\n" "$percentage" "$current" "$total" "$step_name" > "$out"
}

#################################################################################
# Logging Functions
#################################################################################
log_build_step() {
    local step_name="$1"
    local step_num="${2:-}"
    local total_steps="${3:-}"
            
    if [ "$VERBOSE_MODE" = "OFF" ]; then
        if [ -n "$step_num" ] && [ -n "$total_steps" ]; then
            show_progress_bar "$step_num" "$total_steps" "$step_name"
        fi
    else
        echo "[$(date '+%H:%M:%S')] ✓ $step_name"    
    fi
}

log_error() {
    # Error is ALWAYS shown
    echo -e "\033[1;31m[ERROR] $(date '+%H:%M:%S'): $1\033[0m"
}

log_warning() {
    # Warning is ALWAYS shown
    echo -e "\033[1;33m[WARNING] $(date '+%H:%M:%S'): $1\033[0m"
}

log_success() {
    # Success is ALWAYS shown
    echo -e "\033[1;32m[SUCCESS] $(date '+%H:%M:%S'): $1\033[0m"
}

log_backup_step() {
    # Backup process is ALWAYS shown
    echo -e "\033[1;36m[BACKUP] $(date '+%H:%M:%S'): $1\033[0m"
}

#################################################################################
# DHCP 임대갱신 억제 (TinyCore 로더 세션 한정)
#################################################################################
# TinyCore 부팅 시 tc-config 가 띄운 udhcpc 데몬은 T1/T2 타이머로 주기적인
# renew/rebind 를 계속 보낸다. 로더 세션에서는 이미 IP 를 확보한 상태이므로
# 갱신 트래픽이 불필요할 뿐 아니라, 서버가 renew 응답으로 다른 IP 를 주면
# 긴 빌드/다운로드 도중 IP 가 바뀌어 세션이 끊길 수 있다.
#
# 이 함수는 상주 udhcpc 데몬만 종료하여 갱신을 멈춘다. busybox udhcpc 는
# -R 없이 SIGTERM 으로 종료되면 RELEASE 를 보내지 않고 인터페이스 설정도
# 해제하지 않으므로, 현재 잡힌 IP/route/resolv.conf 는 그대로 유지된다.
# 만약의 flush 에 대비해 기본 게이트웨이는 종료 후 재확정한다.
# (서버측 임대가 만료돼도 재획득하지 않는 것이 "억제"의 의도 — 짧은 세션 전제)
function dhcp_freeze() {
    local pids dev ip4 gw

    pids=$(pidof udhcpc 2>/dev/null)
    if [ -z "${pids}" ]; then
        echo "${MSGZZ69:-DHCP freeze: no resident udhcpc daemon - suppression not needed}"
        return 0
    fi

    gw=$(route -n 2>/dev/null | awk '$1=="0.0.0.0" && $2!="0.0.0.0"{print $2; exit}')
    for dev in $(ls /sys/class/net 2>/dev/null | grep -E '^(eth|en)'); do
        ip4=$(/sbin/ifconfig "${dev}" 2>/dev/null | awk '/inet /{print $2}' | cut -d: -f2)
        [ -n "${ip4}" ] && printf "${MSGZZ70:-DHCP freeze: %s IP %s pinned (renew stopped)}\n" "${dev}" "${ip4}"
    done

    # SIGTERM (-R 미지정) → RELEASE/deconfig 없이 데몬만 종료
    kill ${pids} 2>/dev/null
    sleep 1
    pids=$(pidof udhcpc 2>/dev/null)
    [ -n "${pids}" ] && kill -9 ${pids} 2>/dev/null

    # 기본 경로 유실 대비 재확정
    if [ -n "${gw}" ] && ! route -n 2>/dev/null | awk '$1=="0.0.0.0"{f=1} END{exit !f}'; then
        ip route add default via "${gw}" 2>/dev/null
    fi
    echo "${MSGZZ71:-DHCP freeze: udhcpc stopped - lease renewal suppressed}"
}

#################################################################################
# Build with Progress Bar
#################################################################################
make_with_progress() {
    local ldr_mode="${1}"
    local prevent_param="${2}"
    local build_cmd=""

    checkUserConfig 
    if [ $? -ne 0 ]; then
        dialog --backtitle "`backtitle`" --title "Error loader building" 0 0 #--textbox "${LOG_FILE}" 0 0      
        return 1  
    fi
    
    usbidentify
    clear

    getip
    dhcp_freeze
    setSuggest $MODEL
    if [ "${R8168_YN}" = "Y" ] && echo "${kver5explatforms}" | grep -qw "${platform}"; then
      DMPM="DDSML+EUDEV"
    fi
    writeConfigKey "general" "devmod" "${DMPM}"

    if [ "${prevent_param}" = "OFF" ]; then
        build_cmd="my ${MODEL}-${BUILD} noconfig ${ldr_mode}"
    else
        build_cmd="my ${MODEL}-${BUILD} noconfig ${ldr_mode} prevent_param"
    fi

    set -o pipefail  
    if [ "$VERBOSE_MODE" = "OFF" ]; then
        echo "Building bootloader..."
        eval "$build_cmd" 2>&1 | tee /home/tc/zlastbuild.log > /dev/null
        exit_code=${PIPESTATUS[0]}
        #echo "$output" | grep -E "(Preparing build environment|Handling DSM pat files|Collecting extensions|Creating bootloader image|Finalizing build)"                
    else
        eval "$build_cmd" 2>&1 | tee /home/tc/zlastbuild.log
        exit_code=${PIPESTATUS[0]}
    fi
    set +o pipefail    
    
    # Always show exit code
    if [ $exit_code -eq 0 ]; then
        log_success "Build completed successfully (Exit Code: $exit_code)"

        if  [ -f /home/tc/custom-module/redpill.ko ]; then
            sudo rm -rf /home/tc/custom-module/redpill.ko
        fi      
st "finishloader" "Finished building" "Finished building the loader"  
log_build_step "Finished building" 12 12
    else
        log_error "Build failed with exit code: $exit_code"
        show_backup_error_info
    fi
    
    echo "press any key to continue..."
    read answer

    rm -f /home/tc/buildstatus  
        
    return $exit_code
}

#################################################################################
# Show Error Information
#################################################################################
show_backup_error_info() {
    echo -e "\n\033[1;31m╔════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;31m║         BUILD ERROR INFORMATION            ║\033[0m"
    echo -e "\033[1;31m╚════════════════════════════════════════════╝\033[0m"

    if [ -f /home/tc/zlastbuild.log ]; then
        echo -e "\n\033[1;33mError-relevant lines from build log:\033[0m"
        grep -inE 'fail|error|\[!\]|no space|cannot allocate|killed' /home/tc/zlastbuild.log | tail -20 | sed 's/^/  /'

        echo -e "\n\033[1;33mLast 10 lines of build log:\033[0m"
        tail -10 /home/tc/zlastbuild.log | sed 's/^/  /'

        if grep -q '\[curl-diag\]' /home/tc/zlastbuild.log 2>/dev/null; then
            echo -e "\n\033[1;33mDownload diagnostics (curl):\033[0m"
            grep '\[curl-diag\]' /home/tc/zlastbuild.log | tail -5 | sed 's/^/  /'
        fi
    fi

    if [ -s /tmp/strerr.log ]; then
        echo -e "\n\033[1;33mcpio/ramdisk repack error detail (/tmp/strerr.log):\033[0m"
        sed 's/^/  /' /tmp/strerr.log
    fi

    # 빌드 실패 원인이 "알파인 메모리/램디스크 부족"인지 매 실패마다 육안으로
    # 바로 판단할 수 있도록, VERBOSE 설정과 무관하게(로그 함수들의 ALWAYS shown
    # 원칙과 동일하게) 실패 시점의 메모리/tmpfs/스왑/OOM-killer 상태를 캡처한다.
    echo -e "\n\033[1;33mMemory/Ramdisk diagnostics (at failure time):\033[0m"
    local mem_line swap_line rootfs_line oom_lines rootfs_pct swap_total_kb swap_used_kb swap_pct

    mem_line=$(free -h 2>/dev/null | awk '/^Mem:/{printf "total=%s used=%s free=%s available=%s", $2,$3,$4,$7}')
    swap_line=$(free -h 2>/dev/null | awk '/^Swap:/{printf "total=%s used=%s free=%s", $2,$3,$4}')
    rootfs_line=$(df -h / 2>/dev/null | awk 'NR==2{printf "size=%s used=%s avail=%s use%%=%s", $2,$3,$4,$5}')
    oom_lines=$(sudo dmesg 2>/dev/null | grep -iE "killed process|out of memory" | tail -5)

    echo "  RAM:        ${mem_line}"
    echo "  Swap:       ${swap_line}"
    echo "  Ramdisk(/): ${rootfs_line}"
    if [ -n "${oom_lines}" ]; then
        echo -e "  OOM-killer: \033[1;31m발생함\033[0m"
        echo "${oom_lines}" | sed 's/^/    /'
    else
        echo -e "  OOM-killer: \033[1;32m발생 안 함\033[0m"
    fi

    rootfs_pct=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    swap_total_kb=$(free 2>/dev/null | awk '/^Swap:/{print $2}')
    swap_used_kb=$(free 2>/dev/null | awk '/^Swap:/{print $3}')
    if [ "${swap_total_kb:-0}" -gt 0 ] 2>/dev/null; then
        swap_pct=$(( swap_used_kb * 100 / swap_total_kb ))
    else
        swap_pct=0
    fi

    echo -e "\n\033[1;33m[진단 요약]\033[0m tmpfs 사용률 ${rootfs_pct:-?}%, 스왑 사용률 ${swap_pct}%, OOM-killer: $([ -n "${oom_lines}" ] && echo '발생' || echo '없음')"

    echo -e "\n\033[1;33mBackup status:\033[0m"
    echo "  Checking for corrupted files..."
    ls -lh /mnt/${tcrppart}/*.pat 2>/dev/null | tail -5
}

#################################################################################
# Toggle Verbose Mode Menu
#################################################################################
toggle_verbose_menu() {
    local TMP_PATH="${TMP_PATH:-.}"

    eval "MSG89=\"\${MSG${tz}89}\""
    eval "MSG90=\"\${MSG${tz}90}\""
    eval "MSG91=\"\${MSG${tz}91}\""
    eval "MSG92=\"\${MSG${tz}92}\""
    eval "MSG93=\"\${MSG${tz}93}\""
    eval "MSG94=\"\${MSG${tz}94}\""
    eval "MSG95=\"\${MSG${tz}95}\""
    eval "MSG96=\"\${MSG${tz}96}\""
    eval "MSG97=\"\${MSG${tz}97}\""
    eval "MSG98=\"\${MSG${tz}98}\""
    eval "MSG99=\"\${MSG${tz}99}\""
    eval "MSG100=\"\${MSG${tz}100}\""
    eval "MSG101=\"\${MSG${tz}101}\""
    eval "MSG102=\"\${MSG${tz}102}\""
    eval "MSG103=\"\${MSG${tz}103}\""
    eval "MSG104=\"\${MSG${tz}104}\""
    eval "MSG106=\"\${MSG${tz}106}\""
    eval "MSG107=\"\${MSG${tz}107}\""

    while true; do
        local modeval
        if [ "$VERBOSE_MODE" = "ON" ]; then
            modeval="\Z2[ON]\Zn"
        else
            modeval="\Z1[OFF]\Zn"
        fi

        local desc
        if [ "$VERBOSE_MODE" = "ON" ]; then
            desc="\Z2${MSG95}\Zn\n  - ${MSG96}\n  - ${MSG97}\n  - ${MSG98}\n  - ${MSG99}"
        else
            desc="\Z2${MSG100}\Zn\n  - ${MSG101}\n  - ${MSG102}\n  - ${MSG103}\n  - ${MSG104}"
        fi

        # 높이/폭은 명시값 사용 - 0(자동)으로 두면 설명문 줄수만큼 상자가
        # 커져 24행 콘솔(시리얼/tty)에서 화면을 넘겨 dialog 가 255 로 실패하고,
        # 그러면 아래 [ $? -ne 0 ] 에 걸려 하위메뉴가 열리자마자 닫힌 것처럼
        # 보인다(152 실기 확인). 설명 5줄 + 항목 3줄 기준으로 18행이면 충분.
        dialog --clear --backtitle "`backtitle`" --colors --title "${MSG89}" \
            --menu "${MSG90} ${modeval}\n\n${MSG94}\n${desc}" 18 72 3 \
            "1" "${MSG91}" \
            "2" "${MSG92}" \
            "3" "${MSG93}" \
            2>"${TMP_PATH}/respv"

        [ $? -ne 0 ] && { clear; return 0; }
        local choice; choice=$(<"${TMP_PATH}/respv")

        case "$choice" in
            1)
                VERBOSE_MODE="ON"
                VERBOSE_FLAG="-v"
                dialog --colors --infobox "\Z2${MSG106}\Zn" 3 40
                sleep 1
                ;;
            2)
                VERBOSE_MODE="OFF"
                VERBOSE_FLAG=""
                dialog --colors --infobox "\Z2${MSG107}\Zn" 3 40
                sleep 1
                ;;
            3)
                clear
                return 0
                ;;
        esac
    done
}

function msgalert() {
    echo -e "\033[1;31m$1\033[0m"
}
function msgwarning() {
    echo -e "\033[1;33m$1\033[0m"
}
function msgnormal() {
    echo -e "\033[1;32m$1\033[0m"
} 
function msgalerttty() {
    printf "\033[1;31m%b\033[0m" "${1//\\n/\\r\\n}" > /dev/tty
}
function msgwarningtty() {
    printf "\033[1;33m%b\033[0m" "${1//\\n/\\r\\n}" > /dev/tty
}
function msgnormaltty() {
    printf "\033[1;32m%b\033[0m" "${1//\\n/\\r\\n}" > /dev/tty
} 

#################################################################################
# Backup with Always-Visible Progress
#################################################################################
function backup_loader() {
    local backup_steps=5
    
    log_backup_step "Starting backup process..."
    
    for i in $(seq 1 $backup_steps); do
        log_backup_step "Backing up config ($i/$backup_steps)"
        # Actual backup command here
        sleep 1
        show_progress_bar "$i" "$backup_steps" "Backup in progress..."
    done
    
    log_backup_step "Backup completed successfully"
}

#################################################################################
# Get Current Verbose Status
#################################################################################
get_verbose_status() {
    echo "$VERBOSE_MODE"
}

function getloaderdisk() {

    loaderdisk=""
    # Get the loader disk using the UUID "6234-C863"
    loaderdisk=$(sudo /sbin/blkid | grep "6234-C863" | cut -d ':' -f1 | sed 's/p\?3//g' | awk -F/ '{print $NF}' | head -n 1)

    # Get the loader disk using the UUID "6234-C863" ( injected bootloader )
    if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then
        [ -z "$loaderdisk" ] && loaderdisk=$(sudo /sbin/blkid | grep "8765-4321" | cut -d ':' -f1 | sed 's/p\?7//g' | awk -F/ '{print $NF}' | head -n 1)
    fi
    
    # If the UUID "6234-C863" is not found, extract the disk name
    if [ -z "$loaderdisk" ]; then
        # Iterate through available disks to find a valid disk name
        while read -r edisk; do
            loaderdisk=$(echo ${edisk} | cut -c 1-12 | awk -F\/ '{print $3}')
            # Break the loop if a valid disk name is found
            [ -n "$loaderdisk" ] && break
        done < <(lsblk -ndo NAME | grep -v '^loop' | grep -v '^zram' | sed 's/^/\/dev\//')
    fi

    # Output the loader disk. Must go to stderr, not stdout: sngen.sh/
    # macgen.sh source functions.sh at the top and are themselves invoked
    # via backticks (e.g. SERIAL=`./sngen.sh ...`), so anything this
    # function writes to stdout ends up prepended to the captured SN/MAC
    # value. mshellSymlinkUserConfig()'s self-invoke at the end of the
    # sourced file calls getloaderdisk() whenever ${loaderdisk} isn't
    # already set in that fresh subshell, which is exactly the case in
    # sngen.sh/macgen.sh - confirmed on real hardware as a corrupted
    # sn value: "LOADER DISK: sda\n<the real generated serial>".
    echo "LOADER DISK: $loaderdisk" >&2
}

function ensure_loader_partition_mounted() {

    local part="$1"
    local dev="/dev/${loaderdisk}${part}"
    local mount_point="/mnt/${loaderdisk}${part}"

    [ -z "${loaderdisk}" ] && getloaderdisk >/dev/null 2>&1
    [ -z "${loaderdisk}" ] && return 1

    sudo mkdir -p "${mount_point}"

    if mountpoint -q "${mount_point}"; then
        _sync_tcrp_alias "${part}" "${mount_point}"
        return 0
    fi

    sudo mount "${dev}"

    if mountpoint -q "${mount_point}"; then
        _sync_tcrp_alias "${part}" "${mount_point}"
        return 0
    fi

    return 1
}

# FRIEND(tcrpfriend) 는 자체 buildroot 커널이 부팅 과정을 전부 제어해서
# 파티션3을 처음부터 고정 경로 /mnt/tcrp 로 마운트한다. Alpine 은
# rebuildfstab(TinyCore 원본을 그대로 이식한 범용 스크립트, 로더 파티션
# 개념을 모름)이 시스템의 모든 블록 디바이스를 실제 장치명 기준으로
# /mnt/<장치명> 에 매핑하므로, 디스크 열거 순서가 바뀌면(sda -> sdb 등)
# 로더 파티션의 실제 마운트 경로도 함께 바뀐다. rebuildfstab 자체는
# 업스트림 이식 코드라 손대지 않고, 대신 이 함수가 파티션3에 한해
# /mnt/tcrp 를 실제 마운트포인트를 가리키는 심볼릭 링크로 유지해서
# 상위 코드(예: mshellSymlinkUserConfig())가 디스크명과 무관한 안정된
# 경로 하나만 참조하면 되게 한다. target 이 최신 마운트포인트와 다르면
# (디스크명이 바뀐 경우) 재연결한다.
function _sync_tcrp_alias() {
    local part="$1"
    local mount_point="$2"

    [ "${part}" = "3" ] || return 0

    if [ -L /mnt/tcrp ]; then
        [ "$(readlink /mnt/tcrp)" = "${mount_point}" ] && return 0
        sudo rm -f /mnt/tcrp
    elif [ -e /mnt/tcrp ]; then
        # 심볼릭 링크가 아닌 다른 무언가가 이미 있으면 건드리지 않는다.
        return 0
    fi

    sudo ln -s "${mount_point}" /mnt/tcrp
}

function get_alpine_os_device() {
    sudo /sbin/blkid -L alpine 2>/dev/null
}

function ensure_alpine_partition_mounted() {

    local dev
    dev=$(get_alpine_os_device)
    [ -z "${dev}" ] && return 1

    local mount_point="/mnt/alpine"
    sudo mkdir -p "${mount_point}"

    if mountpoint -q "${mount_point}"; then
        return 0
    fi

    sudo mount "${dev}" "${mount_point}"

    mountpoint -q "${mount_point}"
}

function ensure_loader_partitions_mounted() {
    ensure_loader_partition_mounted 1
    ensure_loader_partition_mounted 2
    ensure_loader_partition_mounted 3
}

# ==============================================================================          
# Color Function                                                                          
# ==============================================================================          
function cecho () {                                                                                
#    if [ -n "$3" ]                                                                                                            
#    then                                                                                  
#        case "$3" in                                                                                 
#            black  | bk) bgcolor="40";;                                                              
#            red    |  r) bgcolor="41";;                                                              
#            green  |  g) bgcolor="42";;                                                                 
#            yellow |  y) bgcolor="43";;                                             
#            blue   |  b) bgcolor="44";;                                             
#            purple |  p) bgcolor="45";;                                                   
#            cyan   |  c) bgcolor="46";;                                             
#            gray   | gr) bgcolor="47";;                                             
#        esac                                                                        
#    else                                                                            
        bgcolor="0"                                                                 
#    fi                                                                              
    code="\033["                                                                    
    case "$1" in                                                                    
        black  | bk) color="${code}${bgcolor};30m";;                                
        red    |  r) color="${code}${bgcolor};31m";;                                
        green  |  g) color="${code}${bgcolor};32m";;                                
        yellow |  y) color="${code}${bgcolor};33m";;                                
        blue   |  b) color="${code}${bgcolor};34m";;                                
        purple |  p) color="${code}${bgcolor};35m";;                                
        cyan   |  c) color="${code}${bgcolor};36m";;                                
        gray   | gr) color="${code}${bgcolor};37m";;                                
    esac                                                                            
                                                                                                                                                                    
    text="$color$2${code}0m"                                                                                                                                        
    echo -e "$text"                                                                                                                                                 
}   

function zeropadingver() {
  ZPADKVER=$(printf "%01d%03d%03d\n" $(echo "$1" | tr '.' ' '))
}

function getvarsmshell()
{

    # Set the path for the models.json file
    MODELS_JSON="/home/tc/models.json"

    # Define platform groups
    platforms="epyc7002 epyc7003ntb epyc7003 icelaked v1000nk r1000nk geminilakenk broadwellnk broadwell bromolow broadwellnkv2 broadwellntbap purley denverton apollolake r1000 v1000 geminilake avoton braswell cedarview grantley"

    # Initialize MODELS array
    MODELS=()

    # Extract models for each platform and add them to the mdl file
    for platform in $platforms; do
      models=$(jq -r ".$platform.models[]" "$MODELS_JSON" 2>/dev/null)
      if [ -n "$models" ]; then
        MODELS+=($models)
      fi
    done
    
    ORIGIN_PLATFORM=""

    tem="${1}"

    MODEL="$(echo ${tem} |cut -d '-' -f 1)"
    TARGET_REVISION="$(echo ${tem} |cut -d '-' -f 3)"    
    if [ "$TARGET_REVISION" == "64570" ]; then
      TARGET_VERSION="$(echo ${tem} |cut -d '-' -f 2 | cut -c 1-3)"
    else
      TARGET_VERSION="$(echo ${tem} |cut -d '-' -f 2)"
    fi

    #echo "MODEL is $MODEL"
    TARGET_PLATFORM=$(echo "$MODEL" | sed 's/DS/ds/' | sed 's/RS/rs/' | sed 's/+/p/' | sed 's/DVA/dva/' | sed 's/FS/fs/' | sed 's/SA/sa/' )
    SYNOMODEL="${TARGET_PLATFORM}_${TARGET_REVISION}"
    
    
    if ! echo ${MODELS[@]} | grep -qw ${MODEL}; then
        echo "This synology model not supported by TCRP."
        exit 99
    fi

    if [ "$TARGET_REVISION" == "25556" ]; then
        KVER="4.4.59"
    elif [ "$TARGET_REVISION" == "42218" ]; then
        KVER="4.4.180"
    elif [ "$TARGET_REVISION" == "42661" ]; then
        KVER="4.4.180"
    elif [ "$TARGET_REVISION" == "42962" ]; then
        KVER="4.4.180"
    elif [ "$TARGET_REVISION" == "64570" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "69057" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "72806" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "81180" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "86003" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "86009" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "90075" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "90080" ]; then
        KVER="4.4.302"
    elif [ "$TARGET_REVISION" == "101188" ]; then
        KVER="4.4.302"
    else
        echo "Synology model revision not supported by TCRP."
        exit 0
    fi

    # Extract models for each platform and add them to the mdl file
    for platform in $platforms; do
      # Initialize MODELS array
      MODELS=()
      models=$(jq -r ".$platform.models[]" "$MODELS_JSON" 2>/dev/null)
      if [ -n "$models" ]; then
        MODELS=($models)
      fi
      if echo ${MODELS[@]} | grep -qw ${MODEL}; then
        ORIGIN_PLATFORM="${platform}"
        if [ ${ORIGIN_PLATFORM} == "broadwell" ]; then
            if [ "$TARGET_REVISION" == "25556" ]; then
                KVER="3.10.105"
            fi
        fi
        if echo ${kver3platforms} | grep -qw ${ORIGIN_PLATFORM}; then
            if [ "$TARGET_REVISION" == "25556" ]; then
                KVER="3.10.105"
            else
                KVER="3.10.108"
            fi
        fi    
        if echo ${kver5platforms} | grep -qw ${ORIGIN_PLATFORM}; then
            KVER="5.10.55"
        fi
      fi
    done    

    zeropadingver ${KVER}    
    
    case ${MODEL} in
    DS224+)
        permanent="WBR"
        serialstart="2350"
        suffix="alpha"
        ;;
    DS423+)
        permanent="VKR"
        serialstart="22A0"
        suffix="alpha"
        ;;
    DS718+)
        permanent="PEN"
        serialstart="1930"
        suffix="numeric"
        ;;
    DS720+)
        permanent="QWR"
        serialstart="2010 2110"
        suffix="alpha"
        ;;
    DS918+)
        permanent="PDN"
        serialstart="1910"
        suffix="numeric"
        ;;
    DS920+)
        permanent="SBR"
        serialstart="2030 2040 20C0 2150"
        suffix="alpha"
        ;;
    DS923+)
        permanent="TQR"
        serialstart="2270"
        suffix="alpha"
        ;;
    DS925+)
        permanent="YHR"
        serialstart="2520"
        suffix="alpha"
        ;;
    DS1019+)
        permanent="QXR"
        serialstart="1850 1880"
        suffix="numeric"
        ;;
    DS1520+)
        permanent="RYR"
        serialstart="2060"
        suffix="alpha"
        ;;
    DS1522+)
        permanent="TRR"
        serialstart="2270"
        suffix="alpha"
        ;;
    DS1621+)
        permanent="S7R"
        serialstart="2080"
        suffix="alpha"
        ;;
    DS1621xs+)
        permanent="RVR"
        serialstart="2070"
        suffix="alpha"
        ;;
    DS1819+)
        permanent="R5R"
        serialstart="1890"
        suffix="alpha"
        ;;
    DS1821+)
        permanent="SKR"
        serialstart="2110"
        suffix="alpha"
        ;;
    DS1823xs+)
        permanent="V5R"
        serialstart="2280"
        suffix="alpha"
        ;;
    DS2419+)
        permanent="QZA"
        serialstart="1880"
        suffix="alpha"
        ;;
    DS2422+)
        permanent="SLR"
        serialstart="2140 2180"
        suffix="alpha"
        ;;
    DS3615xs)
        permanent="LWN"    
        serialstart="1130 1230 1330 1430"
        suffix="numeric"
      ;;        
    DS3617xs)
        permanent="ODN"
        serialstart="1130 1230 1330 1430"
        suffix="numeric"
        ;;
    DS3622xs+)
        permanent="SQR"
        serialstart="2150"
        suffix="alpha"
        ;;
    DVA1622)
        permanent="UBR"
        serialstart="2030 2040 20C0 2150"
        suffix="alpha"
        ;;
    DVA3219)
        permanent="RFR"
        serialstart="1930 1940"
        suffix="alpha"
        ;;
    DVA3221)
        permanent="SJR"
        serialstart="2030 2040 20C0 2150"
        suffix="alpha"
        ;;
    FS2500)
        permanent="PSN"
        serialstart="1960"
        suffix="numeric"
        ;;
    FS6400)
        permanent="XXX"
        serialstart="0000"
        suffix="alpha"
        ;;
    HD6500)
        permanent="RUR"
        serialstart="20A0 21C0"
        suffix="alpha"
        ;;
    RS1221+)
        permanent="RWR"
        serialstart="20B0"
        suffix="alpha"
        ;;
    RS1619xs+)
        permanent="QPR"
        serialstart="1920"
        suffix="alpha"
        ;;
    RS2423RP+)
        permanent="V3R"
        serialstart="22B0"
        suffix="alpha"
        ;;
    RS3621xs+)
        permanent="SZR"
        serialstart="20A0"
        suffix="alpha"
        ;;
    RS4021xs+)
        permanent="T2R"
        serialstart="2160"
        suffix="alpha"
        ;;
    SA3200D)
        permanent="S4R"
        serialstart="19A0"
        suffix="alpha"
        ;;
    SA3400)
        permanent="RJR"
        serialstart="1970"
        suffix="alpha"
        ;;
    SA6400)
        permanent="W8R"
        serialstart="2350"
        suffix="alpha"
        ;;
    SA3410)
        permanent="UMR"
        serialstart="2270"
        suffix="alpha"
        ;;
    RS18016xs+)    
        permanent="N8N"
        serialstart="1660"
        suffix="alpha"
        ;;
    DS425+)
        permanent="YGR"
        serialstart="2550"
        suffix="alpha"
        ;;
    DS1525+)
        permanent="YJR"
        serialstart="2540"
        suffix="alpha"
        ;;
    DS1825+)
        permanent="WDR"
        serialstart="2540"
        suffix="alpha"
        ;;
    *)
        permanent="XXX"
        serialstart="0000"
        suffix="alpha"
        ;;
    esac


}

# Function READ_YN, cecho                                                                                        
# Made by FOXBI
# 2022.04.14                                                                                                                  
#                                                                                                                             
# ==============================================================================                                              
# Y or N Function                                                                                                             
# ==============================================================================                                              
function READ_YN () { # ${1}:question ${2}:default                                                                                         
    while true; do
        read -n1 -p "${1}" Y_N                                                                                                       
        case "$Y_N" in                                                                                                            
            [Yy]* ) Y_N="y"                                                                                                                
                 echo -e "\n"; break ;;                                                                                                      
            [Nn]* ) Y_N="n"                                                                                                                
                 echo -e "\n"; break ;;                                                                                                      
            *) echo -e "Please answer in Y / y or N / n.\n" ;;                                                                                                        
        esac                                                                                                                      
    done        
}                                                                                         

function st() {
echo -e "[$(date '+%T.%3N')]:-------------------------------------------------------------" >> /home/tc/buildstatus
echo -e "\e[35m$1\e[0m	\e[36m$2\e[0m	$3" >> /home/tc/buildstatus
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
    lvm_volumes+=("$path" "$vol_name ($size)")
  done < <(sudo lvs -o lv_dm_path,lv_size 2>/dev/null | grep volume)
  
  if [ ${#lvm_volumes[@]} -eq 0 ]; then 
    echo "No Available Syno lvm Volume, press any key continue..."
    read -n 1 -s answer                       
    return 0   
  fi
  
  dialog --backtitle "`backtitle`" --colors \
    --menu "Choose a Volume to mount.\Zn" 0 0 $(dlgmenuheight $((${#lvm_volumes[@]}/2))) "${lvm_volumes[@]}" \
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

function open_md0() {
  # assemble and mount md0
  sudo rm -f "${TMP_PATH}/menuz"
  sudo mkdir -p "${TMP_PATH}/mdX"
  num=$(echo $DSMROOTS | wc -w)
  sudo mdadm -C /dev/md0 -e 0.9 -amd -R -l1 --force -n$num $DSMROOTS 2>/dev/null
  T="$(sudo blkid -o value -s TYPE /dev/md0 2>/dev/null)"
  if [ "$FRKRNL" = "NO" ] && [ "$T" = "ext4" ]; then
      sudo tune2fs -O ^quota /dev/md0
  fi    
  sudo mount -t "${T:-ext4}" /dev/md0 "${TMP_PATH}/mdX"
}

function close_md0() {
  sudo umount "${TMP_PATH}/mdX"
  sudo mdadm --stop /dev/md0
  sudo rm -rf "${TMP_PATH}/mdX"
}

###############################################################################
# Find and mount the DSM root filesystem
function findDSMRoot() {
  local DSMROOTS=""
  if [ "$FRKRNL" = "YES" ]; then
      [ -z "${DSMROOTS}" ] && DSMROOTS="$(sudo mdadm --detail --scan 2>/dev/null | grep -E "name=SynologyNAS:0|name=DiskStation:0|name=SynologyNVR:0|name=BeeStation:0" | awk '{print $2}' | uniq)"
      [ -z "${DSMROOTS}" ] && DSMROOTS="$(sudo lsblk -pno KNAME,PARTN,FSTYPE,FSVER,LABEL | grep -E "sd[a-z]{1,2}1" | grep -w "linux_raid_member" | grep "0.9" | awk '{print $1}')"
  else
      if [ "$(which mdadm)_" == "_" ]; then
          tce-load -iw mdadm 2>&1 >/dev/null
      fi    
      [ -z "${DSMROOTS}" ] && DSMROOTS="$(sudo fdisk -l | grep -E "sd[a-z]{1,2}1" | grep -E '16785407|4982527' | awk '{print $1}')"
  fi
  echo "${DSMROOTS}"
  return 0
}

###############################################################################
# Reset DSM system password
function changeDSMPassword() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --colors --aspect 50 \
      --title "Change DSM New Password" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi

  # assemble and mount md0
  open_md0

  [ $? -ne 0 ] && returnto "Assemble and mount md0 failed. Stop processing!!! " && return

  if [ -f "${TMP_PATH}/mdX/etc/shadow" ]; then
    while read -r L; do
      U=$(echo "${L}" | awk -F ':' '{if ($2 != "*" && $2 != "!!") print $1;}')
      [ -z "${U}" ] && continue
      E=$(echo "${L}" | awk -F ':' '{if ($8 == "1") print "disabled"; else print "        ";}')
      grep -q "status=on" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${U}/method.config" 2>/dev/null
      [ $? -eq 0 ] && S="SecureSignIn" || S="            "
      printf "\"%-36s %-10s %-14s\"\n" "${U}" "${E}" "${S}" >>"${TMP_PATH}/menuz"
    done <<<"$(sudo cat "${TMP_PATH}/mdX/etc/shadow" 2>/dev/null)"
  fi

  close_md0
   
  if [ ! -f "${TMP_PATH}/menuz" ]; then
    dialog --backtitle "$(backtitle)" --colors --aspect 50 \
      --title "Change DSM New Password" \
      --msgbox "All existing users have been disabled. Please try adding new user." 0 0
    return
  fi
  dialog --backtitle "$(backtitle)" --colors --aspect 50 \
    --title "Change DSM New Password" \
    --no-items --menu "Choose a user name" 0 0 20 --file "${TMP_PATH}/menuz" \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  USER="$(sudo cat "${TMP_PATH}/resp" 2>/dev/null | awk '{print $1}')"
  [ -z "${USER}" ] && return
  local STRPASSWD
  while true; do
    dialog --backtitle "$(backtitle)" --colors --aspect 50 \
      --title "Change DSM New Password" \
      --inputbox "$(printf "Type a new password for user '%s'" "${USER}")" 0 70 "" \
      2>"${TMP_PATH}/resp"
    [ $? -ne 0 ] && break
    resp="$(sudo cat "${TMP_PATH}/resp" 2>/dev/null)"
    if [ -z "${resp}" ]; then
      dialog --backtitle "$(backtitle)" --colors --aspect 50 \
        --title "Change DSM New Password" \
        --msgbox "Invalid password" 0 0
    else
      STRPASSWD="${resp}"
      break
    fi
  done
  sudo rm -f "${TMP_PATH}/isOk"
  (
    sudo mkdir -p "${TMP_PATH}/mdX"
    local NEWPASSWD
    NEWPASSWD="$(sudo openssl passwd -6 -salt "$(sudo openssl rand -hex 8)" "${STRPASSWD}")"
  
    # assemble and mount md0
    open_md0

    [ $? -ne 0 ] && returnto "Assemble and mount md0 failed. Stop processing!!! " && return

    sudo sed -i "s|^${USER}:[^:]*|${USER}:${NEWPASSWD}|" "${TMP_PATH}/mdX/etc/shadow"
    sudo sed -i "/^${USER}:/ s/^\(${USER}:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:\)[^:]*:/\1:/" "${TMP_PATH}/mdX/etc/shadow"
    sudo sed -i "s|status=on|status=off|g" "${TMP_PATH}/mdX/usr/syno/etc/packages/SecureSignIn/preference/${USER}/method.config" 2>/dev/null
    sudo sync
  
    echo "true" >"${TMP_PATH}/isOk"
    close_md0
    
  ) 2>&1 | dialog --backtitle "$(backtitle)" --colors --aspect 50 \
    --title "Change DSM New Password" \
    --progressbox "Resetting ..." 20 100
  if [ -f "${TMP_PATH}/isOk" ]; then
    MSG="$(printf "Reset password for user '%s' completed." "${USER}")"
  else
    MSG="$(printf "Reset password for user '%s' failed." "${USER}")"
  fi
  dialog --backtitle "$(backtitle)" --colors --aspect 50 \
    --title "Change DSM New Password" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# Add new DSM user
function addNewDSMUser() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --title "Add New DSM User" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi
  MSG="Add to administrators group by default"
  dialog --title "Add New DSM User" \
    --form "${MSG}" 8 60 3 \
    "username:" 1 1 "" 1 10 50 0 \
    "password:" 2 1 "" 2 10 50 0 \
    2>"${TMP_PATH}/resp"
  [ $? -ne 0 ] && return
  username=$(sudo sed -n '1p' "${TMP_PATH}/resp")
  password=$(sudo sed -n '2p' "${TMP_PATH}/resp")

  username_escaped=$(printf "%q" "$username")
  password_escaped=$(printf "%q" "$password")
      
  sudo rm -f "${TMP_PATH}/isOk"
  (
    ONBOOTUP=""
    ONBOOTUP="${ONBOOTUP}if synouser --enum local | grep -q ^${username_escaped}\$; then synouser --setpw ${username_escaped} ${password_escaped}; else synouser --add ${username_escaped} ${password_escaped} mshell 0 user@mshell.com 1; fi\n"
    ONBOOTUP="${ONBOOTUP}synogroup --memberadd administrators ${username_escaped}\n"
    ONBOOTUP="${ONBOOTUP}echo \"DELETE FROM task WHERE task_name LIKE ''ONBOOTUP_ADDUSER'';\" | sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db\n"

    # assemble and mount md0
    open_md0

    [ $? -ne 0 ] && returnto "Assemble and mount md0 failed. Stop processing!!! " && return

    if [ -f "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" ]; then
      sudo sqlite3 "${TMP_PATH}/mdX/usr/syno/etc/esynoscheduler/esynoscheduler.db" <<EOF
DELETE FROM task WHERE task_name LIKE 'ONBOOTUP_ADDUSER';
INSERT INTO task VALUES('ONBOOTUP_ADDUSER', '', 'bootup', '', 1, 0, 0, 0, '', 0, '$(echo -e "${ONBOOTUP}")', 'script', '{}', '', '', '{}', '{}');
EOF
      sudo sync
      echo "true" >"${TMP_PATH}/isOk"
    fi

    close_md0
    
  ) 2>&1 | dialog --title "Add New DSM User" \
    --progressbox "Adding ..." 20 100
  if [ -f "${TMP_PATH}/isOk" ]; then
    MSG=$(printf "Add new user '%s' completed." "${username}")
  else
    MSG=$(printf "Add new user '%s' failed." "${username}")
  fi
  dialog --title "Add New DSM User" \
    --msgbox "${MSG}" 0 0
  return
}

###############################################################################
# CleanSystemPart
function CleanSystemPart() {

param="${1}"

echo -n "(Warning) Do you want to ${param} the System Partition(md0)? [yY/nN] : "
readanswer
if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then

  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --colors --aspect 50 \
      --title "${param} System Partition(md0)" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi

  sudo rm -f "${TMP_PATH}/isOk"
  # assemble and mount md0
  open_md0

  [ $? -ne 0 ] && returnto "Assemble and mount md0 failed. Stop processing!!! " && return

  if [ "${param}" = "clean" ]; then

      if [ -d "${TMP_PATH}/mdX/etc" ]; then
          removed=0
      
          for dir in "@autoupdate" "upd@te" ".log.junior"; do
              path="${TMP_PATH}/mdX/${dir}/*"
              if ls $path 1>/dev/null 2>&1; then
                  sudo rm -vrf ${TMP_PATH}/mdX/${dir}/*
                  removed=1
              fi
          done
      
          sudo sync
      
          if [ $removed -eq 0 ]; then
              echo "Nothing to remove file"
          else
              echo "true" >"${TMP_PATH}/isOk"
          fi
      
          echo "press any key to continue..."
          read answer
      fi
  else
      sudo rm -rf "${TMP_PATH}/mdX/" 2>/dev/null
      sudo sync      
      echo "true" >"${TMP_PATH}/isOk"        
      echo "press any key to continue..."
      read answer
  fi

  close_md0
  
  if [ -f "${TMP_PATH}/isOk" ]; then
    MSG=$(printf "${param} System Partition(md0) completed.")
  else
    MSG=$(printf "${param} System Partition(md0) failed.")
  fi
  dialog --title "${param} System Partition(md0)" \
    --msgbox "${MSG}" 0 0
  return
  
fi

}

###############################################################################
# Check whether md0 (DSM system partition) uses the whole partition, and offer
# to expand it when under-utilized. A legacy ~2.4GB md0 sitting on an 8GB
# partition cannot hold the DSM 7.4 rootfs and makes upgrades fail at ~56%
# ("file corrupt"). This grows the RAID + ext4 to the full partition size.
function checkExpandMd0() {

  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --colors --aspect 50 \
      --title "Check/Expand System Partition(md0)" \
      --msgbox "No DSM system partition(md0) found!\nDSM must be installed and all disks inserted before continuing." 0 0
    return
  fi

  PART="$(echo ${DSMROOTS} | awk '{print $1}')"
  PSIZE=$(sudo blockdev --getsize64 "${PART}" 2>/dev/null)
  PMIB=$(( PSIZE / 1024 / 1024 ))

  # Assemble + mount md0 with the SAME method the other menus use (open_md0,
  # i.e. mdadm -C --force). open_md0 has no --size, so it re-creates the array
  # at the FULL partition size: after this the RAID already spans the whole
  # partition and only the ext4 filesystem may still be smaller (resize2fs).
  open_md0
  if ! mount 2>/dev/null | grep -q "${TMP_PATH}/mdX"; then
    close_md0 2>/dev/null
    dialog --backtitle "$(backtitle)" --colors --title "Check/Expand System Partition(md0)" \
      --msgbox "Failed to assemble/mount md0 from ${DSMROOTS}." 0 0
    return
  fi
  MSIZE=$(sudo blockdev --getsize64 /dev/md0 2>/dev/null)
  MMIB=$(( MSIZE / 1024 / 1024 ))
  read FSTOTAL FSUSED FSPCT <<EOF
$(df -m "${TMP_PATH}/mdX" 2>/dev/null | awk 'NR==2{print $2, $3, $5}')
EOF
  close_md0

  UNUSED=$(( PMIB - ${FSTOTAL:-0} ))
  STAT="System partition : ${PART}\nPartition size    : ${PMIB} MiB\nmd0 (RAID) size   : ${MMIB} MiB\nFilesystem size   : ${FSTOTAL:-?} MiB (used ${FSUSED:-?}, ${FSPCT:-?})\nFS free vs part.   : ${UNUSED} MiB"

  # Filesystem already (nearly) fills the partition -> just report.
  # RAID superblock + alignment overhead means the ext4 never reaches the exact
  # partition size (~200 MiB short on an 8GB partition), so treat it as fully
  # expanded once it is within 768 MiB of the partition OR already > 7.5 GiB.
  # This avoids re-prompting the user to expand an already-maxed md0.
  if [ "${UNUSED:-0}" -le 768 ] || [ "${FSTOTAL:-0}" -ge 7680 ]; then
    dialog --backtitle "$(backtitle)" --colors --title "Check System Partition(md0)" \
      --msgbox "${STAT}\n\nFilesystem already (nearly) fills the partition.\nNo expansion needed." 0 0
    return
  fi

  dialog --backtitle "$(backtitle)" --colors --title "Expand System Partition(md0)" \
    --yesno "${STAT}\n\nThe filesystem uses only ${FSTOTAL} MiB of the ${PMIB} MiB partition.\nA legacy 2.4GB md0 makes DSM 7.4 upgrades fail at ~56% (file corrupt).\n\nExpand the filesystem to the whole partition now?" 0 0
  [ $? -ne 0 ] && return

  # resize2fs is not in the base Tinycore image. Pull e2fsprogs and PERSIST it
  # into the loader's tce store (cde/optional + onboot.lst + backuploader),
  # mirroring the gettext/rxvt permanent-install pattern in menu_m.sh, so it
  # survives reboots. Falls back to a session-only load when no persistent store.
  if [ "$(which resize2fs)_" = "_" ]; then
    echo "Loading e2fsprogs (resize2fs) ..."
    tce-load -wi e2fsprogs
    if [ $? -eq 0 ] && [ "$FRKRNL" = "NO" ] && [ -d "/mnt/${tcrppart}/cde/optional" ] \
       && [ "$(grep -c e2fsprogs "/mnt/${tcrppart}/cde/onboot.lst" 2>/dev/null)" -eq 0 ]; then
      echo "Permanent installation of e2fsprogs ..."
      sudo cp -f /tmp/tce/optional/* "/mnt/${tcrppart}/cde/optional"
      sudo echo "" >> "/mnt/${tcrppart}/cde/onboot.lst"
      sudo echo "e2fsprogs.tcz" >> "/mnt/${tcrppart}/cde/onboot.lst"
      backuploader
    fi
  fi

  clear
  echo "Assembling md0 at full partition size ..."
  open_md0                                  # mdadm -C --force => array spans whole partition
  sudo umount "${TMP_PATH}/mdX" 2>/dev/null # offline resize
  echo "Checking filesystem (e2fsck) ..."
  sudo e2fsck -f -y /dev/md0
  echo "Resizing filesystem (resize2fs) ..."
  sudo resize2fs /dev/md0
  sudo sync
  sudo mount /dev/md0 "${TMP_PATH}/mdX" 2>/dev/null
  NEWFS=$(df -m "${TMP_PATH}/mdX" 2>/dev/null | awk 'NR==2{print $2}')
  close_md0

  dialog --backtitle "$(backtitle)" --colors --title "Expand System Partition(md0)" \
    --msgbox "Expansion complete.\n\nFilesystem : ${FSTOTAL} MiB -> ${NEWFS:-?} MiB\nPartition  : ${PMIB} MiB" 0 0
  return
}

###############################################################################
# Fix SmallFixNumber of Bootentry
function fixBootEntry() {

echo -n "(Warning) Do you want to fix Bootentry Update version? [yY/nN] : "
readanswer
if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then

  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    dialog --backtitle "$(backtitle)" --colors --aspect 50 \
      --title "Bootentry Update version correction" \
      --msgbox "No DSM system partition(md0) found!\nPlease insert all disks before continuing." 0 0
    return
  fi

  # assemble and mount md0
  open_md0

  [ $? -ne 0 ] && returnto "Assemble and mount md0 failed. Stop processing!!! " && return

  if [ -d "${TMP_PATH}/mdX/etc" ]; then
      . ${TMP_PATH}/mdX/etc/VERSION
      cat ${TMP_PATH}/mdX/etc/VERSION
      updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
      sudo sed -i "s/Update [0-9]/Update $smallfixnumber/g" "/mnt/${loaderdisk}1/boot/grub/grub.cfg"
      grep menuentry /mnt/${loaderdisk}1/boot/grub/grub.cfg
      echo "press any key to continue..."
      read answer
  fi

  close_md0
  
  MSG=$(printf "Bootentry Update version correction completed.")
  dialog --title "Bootentry Update version correction" \
    --msgbox "${MSG}" 0 0
  return
  
fi

}

###############################################################################
# Check DSM version of md0
function chkDsmversion() {
  DSMROOTS="$(findDSMRoot)"
  if [ -z "${DSMROOTS}" ]; then
    echo "There is no DSM"
    return 0
  fi

  open_md0 || { returnto "Assemble and mount md0 failed (Maybe there's no synodisk)."; return 1; }

  if [ -d "${TMP_PATH}/mdX/etc" ]; then
    . "${TMP_PATH}/mdX/etc/VERSION"
    close_md0 || true
    if [ "${BUS}" == "block" ]; then
        echo "Preinstalled version on your DSM      : ${productversion:-}"
        echo "Version you are attempting to install : ${TARGET_VERSION}"
    else
        printf "Preinstalled version on your DSM      : ${productversion:-}\n" > /dev/tty
        printf "Version you are attempting to install : ${TARGET_VERSION}\n" > /dev/tty
    fi    
    if [ "${productversion:-}" == "${TARGET_VERSION}" ]; then
        return 0
    else
        if [ "${productversion:-}" == "7.3.1" ] && [ "${TARGET_VERSION}" == "7.3.2" ]; then
            msgwarningtty "If your existing installed DSM version is 7.3.1 (or a false positive of 7.3.2) and the target loader version you want to build is 7.3.2, do you want to take the risk and proceed with the loader build? : "
            if [ "${ucode}" == "ko_KR" ]; then
              msgwarningtty "기존 설치된 DSM 버전이 7.3.1(또는 7.3.2의 오탐지)이고 빌드할 타겟로더 버전이 7.3.2인 경우 위험을 감수하고 로더빌드를 진행하겠습니까? : "
            fi
            readanswer
            if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then
              return 0
            else
              return 1
            fi
        else
            return 1
        fi
    fi  
  else
    close_md0 || true
    return 0
  fi
}

function getlatestmshell() {
  local retval=0

  echo -n "Checking if a newer mshell version exists on the repo -> "

  # 최신 파일 다운로드
  curl -ksL "$mshtarfile" -o latest.mshell.gz || { retval=3; msgalert "Failed to download latest.mshell.gz"; return $retval; }

  if [ ! -f "$mshellgz" ] || [ ! -f latest.mshell.gz ]; then
    retval=3
    msgalert "Required files not found"
    rm -f latest.mshell.gz
    return $retval
  fi

  CURRENTSHA="$(sha256sum "$mshellgz" | awk '{print $1}')"
  REPOSHA="$(sha256sum latest.mshell.gz | awk '{print $1}')"

  if [ "${CURRENTSHA}" != "${REPOSHA}" ]; then
    if [ "${1}" = "noask" ]; then
      local confirmation="y"
    else
      echo -n "There is a newer version of m shell script on the repo should we use that ? [yY/nN]"
      read confirmation
    fi

    if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
      echo "OK, updating, please re-run after updating"
      
      # 업데이트 과정
      cp -f latest.mshell.gz "$mshellgz" || { retval=3; msgalert "Failed to copy mshell.gz"; rm -f latest.mshell.gz; return $retval; }
      rm -f latest.mshell.gz
      
      tar -zxvf "$mshellgz" || { retval=3; msgalert "Failed to extract mshell.gz"; return $retval; }
      
      echo "Updating m shell with latest updates"
      . /home/tc/functions.sh
      showlastupdate
      echo "y" | rploader backup
      
      retval=1  # 업데이트 성공
    else
      rm -f latest.mshell.gz
      retval=2  # 업데이트 거부
    fi
  else
    echo "Version is current"
    rm -f latest.mshell.gz
    retval=0  # 최신 버전
  fi

  return $retval
}

function alpine38entry() {
    cat <<EOF
menuentry 'Mount Syno BTRFS Vol Rescue (with Alpine 3.8)' {
        savedefault
        search --set=root --fs-uuid 6234-C863 --hint hd0,msdos3
        echo Loading Linux 4.14 recovery kernel...
        linux /alpine_3.8/vmlinuz-4.14 loglevel=3 console=ttyS0,115200n8 console=tty1 modules=md_mod,dm_mod,btrfs,raid6_pq,scsi_mod,sd_mod,sg,sr_mod,libata,ahci,nvme_core,nvme,usb_storage,uas,hid,usbhid,hid_generic,evdev,i8042,atkbd,psmouse,virtio,virtio_pci,virtio_ring,virtio_input,xhci_hcd,ehci_hcd,uhci_hcd,igc,e1000e,e1000,igb,ixgbe,r8169,r8152,tg3,bnx2,atlantic,alx,sky2,skge
        echo Loading Alpine recovery initramfs...
        initrd /alpine_3.8/btr-recovery-x86_64.initramfs
        echo Booting Alpine 3.8 BTRFS recovery environment
        set gfxpayload=keep
}
EOF
}

function get_alpine38() {
    echo "Downloading Alpine 3.8 BTRFS recovery image..."
    sudo mkdir -p /mnt/${tcrppart}/alpine_3.8
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/alpine_3.8/vmlinuz-4.14 -o /mnt/${tcrppart}/alpine_3.8/vmlinuz-4.14
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/alpine_3.8/btr-recovery-x86_64.initramfs -o /mnt/${tcrppart}/alpine_3.8/btr-recovery-x86_64.initramfs
    if [ -s /mnt/${tcrppart}/alpine_3.8/vmlinuz-4.14 ] && [ -s /mnt/${tcrppart}/alpine_3.8/btr-recovery-x86_64.initramfs ]; then
      echo "Alpine 3.8 BTRFS recovery image is ready."
      curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/mountvol.sh -o /home/tc/mountvol.sh
      chmod +x /home/tc/mountvol.sh

      #GRUB 부트엔트리 Default 값 조정
      grub_cfg="/mnt/${loaderdisk}1/boot/grub/grub.cfg"
      entry_count=$(grep -c '^menuentry' "$grub_cfg")
      new_default=$((entry_count - 1))
      sudo sed -i "/^set default=/cset default=\"${new_default}\"" "$grub_cfg"
      
      backuploader
      restart
    else
      echo "Alpine 3.8 recovery image download failed" >&2
      return 1
    fi
}

function get_tinycore() {
    cd /mnt/${tcrppart}
    echo "Downloading tinycore 14.0..."
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/main/tinycore_14.0/corepure64.gz -o corepure64.gz_copy
    sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/main/tinycore_14.0/vmlinuz64 -o vmlinuz64_copy
    md5_corepure64=$(sudo md5sum corepure64.gz_copy | awk '{print $1}')
    md5_vmlinuz64=$(sudo md5sum vmlinuz64_copy | awk '{print $1}')
    if [ ${md5_corepure64} = "f33c4560e3909a7784c0e83ce424ff5c" ] && [ ${md5_vmlinuz64} = "04cb17bbf7fbca9aaaa2e1356a936d7c" ]; then
      echo "tinycore 14.0 md5 check is OK! ( corepure64.gz / vmlinuz64 ) "
      sudo mv corepure64.gz_copy corepure64.gz
      sudo mv vmlinuz64_copy vmlinuz64
      cd ~      
      return 0
    else
      cd ~
      return 1
    fi
}

function update_tinycore() {
  echo "check update for tinycore 14.0..."
  md5_corepure64=$(sudo md5sum /mnt/${tcrppart}/corepure64.gz | awk '{print $1}')
  md5_vmlinuz64=$(sudo md5sum /mnt/${tcrppart}/vmlinuz64 | awk '{print $1}')
  if [ ${md5_corepure64} != "f33c4560e3909a7784c0e83ce424ff5c" ] || [ ${md5_vmlinuz64} != "04cb17bbf7fbca9aaaa2e1356a936d7c" ]; then
      echo "current tinycore version is not 14.0, update tinycore linux to 14.0..."
      get_tinycore
      if [ $? -eq 0 ]; then
        sudo curl -kL#  https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/main/tinycore_14.0/etc/shadow -o /etc/shadow
        echo "etc/shadow" >> /opt/.filetool.lst
        backuploader
        restart
      fi
  fi
}

function update_motd() {
  echo "check update for /etc/motd"
  md5_motd=$(sudo md5sum /etc/motd | awk '{print $1}')
  if [ ${md5_motd} != "c3e6e18603242c1ac22cf886c4981d76"  ]; then
    sudo curl -kL#  https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/refs/heads/alpine-redpill/alpine/etc/motd -o /etc/motd
  fi
}

function macgen() {
echo

    if [ "$realmac" == 'Y' ] ; then
        mac2=$(/sbin/ifconfig eth1 | head -1 | awk '{print $NF}')
        echo "Real Mac2 Address : $mac2"
        echo "Notice : realmac option is requested, real mac2 will be used"
    else
        mac2="$(generateMacAddress ${1})"
    fi

    cecho y "Mac2 Address for Model ${1} : $mac2 "

    macaddress2=$(echo $mac2 | sed -s 's/://g')

    if [ $(cat user_config.json | grep "mac2" | wc -l) -gt 0 ]; then
        bf_mac2="$(cat user_config.json | grep "mac2" | cut -d ':' -f 2 | cut -d '"' -f 2)"
        cecho y "The Mac2 address : $bf_mac2 already exists. Change an existing value."
        json="$(jq --arg var "$macaddress2" '.extra_cmdline.mac2 = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
#        sed -i "/mac2/s/'$bf_mac2'/'$macaddress2'/g" user_config.json
    else
        sed -i "/\"extra_cmdline\": {/c\  \"extra_cmdline\": {\"mac2\": \"$macaddress2\",\"netif_num\": \"2\", "  user_config.json
    fi

    echo "After changing user_config.json"      
    cat user_config.json

}

function generateMacAddress() {
    printf '00:11:32:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))

}
function random() {
        printf "%06d" $(($RANDOM % 30000 + 1))
}
function randomhex() {
        val=$(($RANDOM % 255 + 1))
        echo "obase=16; $val" | bc
}
function generateRandomLetter() {
        for i in a b c d e f g h j k l m n p q r s t v w x y z; do
            echo $i
        done | sort -R | tail -1
}
function generateRandomValue() {
        for i in 0 1 2 3 4 5 6 7 8 9 a b c d e f g h j k l m n p q r s t v w x y z; do
            echo $i
        done | sort -R | tail -1
}
function toupper() {
       echo $1 | tr '[:lower:]' '[:upper:]'
}
function generateSerial() {
    case ${suffix} in
    numeric)
        serialnum="$(echo "$serialstart" | tr ' ' '\n' | sort -R | tail -1)$permanent"$(random)
        ;;
    alpha)
        serialnum=$(toupper "$(echo "$serialstart" | tr ' ' '\n' | sort -R | tail -1)$permanent"$(generateRandomLetter)$(generateRandomValue)$(generateRandomValue)$(generateRandomValue)$(generateRandomValue)$(generateRandomLetter))
        ;;
    *)    
        serialnum="$(echo "$serialstart" | tr ' ' '\n' | sort -R | tail -1)$permanent"$(random)
        ;;  
    esac
    echo $serialnum
}

function readanswer() {
    while true; do
        read answ
        case $answ in
            [Yy]* ) answer="$answ"; break;;
            [Nn]* ) answer="$answ"; break;;
            * ) msgwarning "Please answer yY/nN.";;
        esac
    done
}        

function readanswerwithskip() {
    while true; do
        read answ
        case $answ in
            [Yy]* ) answer="$answ"; break;;
            [Nn]* ) answer="$answ"; break;;
            [Ss]* ) answer="$answ"; break;;            
            * ) msgwarning "Please answer yY/nN/Ss.";;
        esac
    done
}        


function sync_usb_line() {
    # 현재 usb_line 추출
    updated_usb_line=$(jq -r '.general.usb_line' "$userconfigfile")

    # 2026-08-17: 기존의 "있으면 sed 제자리치환, 없으면 끝에 append" 방식은
    # 매칭 실패 시 조용히 append 로 빠지면서 (a) 이미 존재하는 값과 중복되고,
    # (b) 문자열 끝에 공백 없이 그대로 이어붙는(예: 실기 45.34에서 확인된
    # "split_lock_detect=offSataPortMap=@") 문제가 있었다. 정규식 매칭 여부에
    # 의존하지 않고, 매 항목마다 "해당 key= 토큰을 전부 제거 후 끝에 하나만
    # 다시 붙이기"로 바꿔 중복/공백누락이 구조적으로 생길 수 없게 한다.
    while IFS='=' read -r key value; do
        if [ -z "$value" ] || [ "$value" = "null" ]; then
            continue
        fi

        # 과거 오염(값 뒤 공백 없이 다음 key= 가 그대로 붙어버린 경우)을 방어적으로
        # 분리한다. 이미 공백으로 구분된 정상 케이스는 [^ ] 매칭 대상이 없어 그대로 둔다.
        updated_usb_line=$(printf '%s' "${updated_usb_line}" | sed -E "s/([^ ])${key}=/\\1 ${key}=/g")

        # 공백 기준 토큰으로 쪼개 이 key= 로 시작하는 토큰을 전부(중복 포함) 제거.
        local -a tokens=()
        local tok
        for tok in ${updated_usb_line}; do
            [[ "${tok}" == "${key}="* ]] && continue
            tokens+=("${tok}")
        done
        tokens+=("${key}=${value}")
        updated_usb_line="${tokens[*]}"
    done < <(jq -r '.extra_cmdline | to_entries[] | "\(.key)=\(.value)"' "$userconfigfile")

    updated_usb_line="${updated_usb_line} "

    # JSON 파일 업데이트
    # mv 대신 cp+rm: $userconfigfile 가 mshellSymlinkUserConfig() 이후로는
    # /mnt/tcrp/user_config.json 을 가리키는 심볼릭 링크다.
    # mv 는 목적지가 심볼릭 링크여도 링크 자체를 새 일반 파일로 교체해
    # 버리므로(대상 파일에 덮어쓰지 않음), writeConfigKey() 가 호출될
    # 때마다(=거의 모든 설정 저장마다) 심볼릭 링크가 끊기고 실기에서
    # 실제로 재현됨. cp 는 기본적으로 심볼릭 링크를 따라가 타깃 파일
    # 내용만 덮어쓰므로 링크 자체가 유지된다.
    jq --arg new_line "$updated_usb_line" '.general.usb_line = $new_line' "$userconfigfile" > "${userconfigfile}.tmp" \
        && cp "${userconfigfile}.tmp" "$userconfigfile" && rm -f "${userconfigfile}.tmp"
}

# Keep user-supplied kernel parameters when a loader build regenerates the
# platform's default USB command line. Generated values win for a matching
# key, while options known only to the existing user_config.json are retained.
#
# extra_cmdline-managed keys (sn/mac1-8/vid/pid/netif_num) are the one
# exception: sync_usb_line() only ever adds/updates these into general.
# usb_line, never removes them, so a key deleted from .extra_cmdline (e.g.
# NIC count auto-detect dropping mac2) can leave an orphaned "mac2=..."
# sitting in the stored usb_line indefinitely. DeleteConfigKey() now cleans
# this up going forward, but that only handles keys deleted *after* the fix
# existed - devices with pre-existing orphaned entries (or any other path
# that edits .extra_cmdline without going through DeleteConfigKey) would
# still have them silently reinstated here on every rebuild, since this is
# the only place that merges the stored usb_line back in. So this function
# also self-heals: for these specific keys, only keep the token if the key
# still exists in current .extra_cmdline - regardless of how it got stale.
function preserve_usb_line_options() {
    local generated_line="$1"
    local existing_line token key generated_token found
    local managed_keys=" sn mac1 mac2 mac3 mac4 mac5 mac6 mac7 mac8 vid pid netif_num "
    local current_extra_keys
    local skip_next="false"

    existing_line=$(jq -r '.general.usb_line // empty' "$userconfigfile" 2>/dev/null)
    [ -z "${existing_line}" ] && {
        printf '%s\n' "${generated_line}"
        return
    }

    current_extra_keys=" $(jq -r '.extra_cmdline | keys[]?' "$userconfigfile" 2>/dev/null | tr '\n' ' ') "

    for token in ${existing_line}; do
        [ -z "${token}" ] && continue

        # 관리 키(=)가 아니면서 콜론으로 끝나는 날것 단어(예: "DISK:")와
        # 그 바로 뒤에 오는 값(예: "sda")은 정상적인 커널 cmdline
        # 파라미터 형태가 아니다 - getloaderdisk() 등 디버그 echo 가
        # stdout 오염으로 "LABEL: value" 형태로 usb_line 에 새어 들어간
        # 잔재(실기에서 "... split_lock_detect=off DISK: sda" 로 확인)일
        # 가능성이 높다. key=value 형태는 여기 걸리지 않으므로 사용자가
        # 수동으로 넣은 정상 커스텀 값은 영향받지 않는다.
        if [ "${skip_next}" = "true" ]; then
            skip_next="false"
            continue
        fi
        if [[ "${token}" != *=* ]] && [[ "${token}" == *: ]]; then
            skip_next="true"
            continue
        fi

        key="${token%%=*}"

        if [[ "${managed_keys}" == *" ${key} "* ]] && [[ "${current_extra_keys}" != *" ${key} "* ]]; then
            continue
        fi

        found="false"

        for generated_token in ${generated_line}; do
            if [ "${token}" = "${generated_token}" ] || \
               { [[ "${token}" == *=* ]] && [ "${key}" = "${generated_token%%=*}" ]; }; then
                found="true"
                break
            fi
        done

        [ "${found}" = "true" ] || generated_line="${generated_line} ${token}"
    done

    printf '%s\n' "${generated_line}"
}

###############################################################################
# Read json config file
function readConfigKey() {
  local section="$1"
  local key="$2"
  jq -r -e ".${section}.${key} // empty" "${userconfigfile}" 2>/dev/null
}

###############################################################################
# Write to json config file
function writeConfigKey() {

    block="$1"
    field="$2"
    value="$3"

    if [ -n "$1 " ] && [ -n "$2" ]; then
        jsonfile=$(jq ".$block+={\"$field\":\"$value\"}" $userconfigfile)
        echo $jsonfile | jq . >$userconfigfile
        sync_usb_line
    else
        echo "No values to update"
    fi

}

###############################################################################
# Delete field from json config file
function DeleteConfigKey() {

    block="$1"
    field="$2"

    if [ -n "$1 " ] && [ -n "$2" ]; then
        jsonfile=$(jq "del(.$block.$field)" $userconfigfile)
        echo $jsonfile | jq . >$userconfigfile

        # sync_usb_line() 은 extra_cmdline 의 각 키를 general.usb_line 에
        # 추가/갱신만 하고 절대 제거하지 않는다 - 그래서 여기서
        # extra_cmdline 항목을 지워도(예: NIC 개수 감소 시 mac2 이상 삭제,
        # menu_m.sh 자동 감지 루틴) usb_line 에는 옛 key=value 조각이 고아
        # 상태로 영구히 남아있는 문제가 실기에서 확인됨. extra_cmdline
        # 항목 삭제 시에는 usb_line 에서도 같은 키를 함께 제거한다.
        [ "${block}" = "extra_cmdline" ] && strip_usb_line_key "${field}"
    else
        echo "No values to remove"
    fi

}

# DeleteConfigKey() 가 extra_cmdline 에서 키를 지울 때, sync_usb_line() 이
# 과거에 general.usb_line 에 심어둔 같은 key=value 조각을 함께 제거한다.
function strip_usb_line_key() {
    local key="$1" line

    line="$(jq -r '.general.usb_line // ""' "$userconfigfile")"
    line="$(echo "${line}" | sed -E "s/(^| )${key}=[^ ]*/\1/g" | sed -E 's/ +/ /g; s/^ +//; s/ +$//')"

    jq --arg new_line "${line}" '.general.usb_line = $new_line' "$userconfigfile" > "${userconfigfile}.tmp" \
        && cp "${userconfigfile}.tmp" "$userconfigfile" && rm -f "${userconfigfile}.tmp"
}
    
function checkmachine() {

    if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
        MACHINE="VIRTUAL"
        HYPERVISOR=$(sudo dmesg | grep -i "Hypervisor detected" | awk '{print $5}')
        echo "Machine is $MACHINE Hypervisor=$HYPERVISOR"
    else
        MACHINE="NON-VIRTUAL"
    fi

    if [ $(lspci -nn | grep -ie "\[0107\]" | wc -l) -gt 0 ]; then
        echo "Found SAS HBAs, Restrict use of DT Models."
        HBADETECT="ON"
    else
        HBADETECT="OFF"    
    fi   
    
}

function check_github() {

    echo -n "Checking GitHub Access -> "
#    nslookup $gitdomain 2>&1 >/dev/null
    curl --insecure -L -s https://raw.githubusercontent.com/about.html -O 2>&1 >/dev/null

    if [ $? -eq 0 ]; then
        echo "OK"
    else
        cecho g "Error: GitHub is unavailable. Please try again later."
        exit 99
    fi

}

###############################################################################
# check for Sas module
function checkforsas() {

    local modalias="/lib/modules/$(uname -r)/modules.alias"
    sasmods="mpt3sas hpsa mvsas"
    for sasmodule in $sasmods
    do
        echo "Checking existense of $sasmodule"
        for sas in `grep -i $sasmodule "${modalias}" 2>/dev/null |grep pci|cut -d":" -f 2 | cut -c 6-9,15-18`
    do
        if [ `grep -i $sas /proc/bus/pci/devices |wc -l` -gt 0 ] ; then
            echo "  => $sasmodule, device found, block eudev mode" 
            BLOCK_EUDEV="Y"
        fi
    done
    done 
}

###############################################################################
# check Intel or AMD
function checkcpu() {

    # lscpu 대신 /proc/cpuinfo 를 직접 읽는다 - lscpu 는 util-linux 패키지가
    # 있어야 하는데, DSM 실기(SA6400/DSM 7.4.1 확인됨)에는 존재하지 않아
    # "lscpu: command not found" 로 두 grep 파이프가 항상 빈 결과가 되고,
    # 그 결과 CPU 세대와 무관하게 매번 CPU=AMD / AFTERHASWELL=OFF 로
    # 오판되는 문제가 있었다(MSHELL Manager 의 모델 선택 기능을 DSM 쪽에
    # 이식하며 실기 검증 중 발견). /proc/cpuinfo 는 lscpu 가 참조하는
    # 것과 같은 원천 데이터라 벤더/movbe 플래그를 동일하게 판별할 수
    # 있고, DSM 을 포함해 모든 리눅스 환경에 항상 존재한다.
    if grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        CPU="INTEL"
    else
        #if [ $(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//' | grep -e N36L -e N40L -e N54L | wc -l) -gt 0 ]; then
        #    CPU="HP"
        #    LDRMODE="JOT"
        #    writeConfigKey "general" "loadermode" "${LDRMODE}"
        #else
            CPU="AMD"
        #fi
    fi

    if grep -qw "movbe" /proc/cpuinfo 2>/dev/null; then
        AFTERHASWELL="ON"
    else
        AFTERHASWELL="OFF"
    fi

    if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
        AFTERHASWELL="ON"
    fi

}

###############################################################################
# Get fastest url in list
# @ - url list
function _get_fastest() {
  local speedlist=""
  for I in $@; do
    speed=$(ping -c 1 -W 5 ${I} 2>/dev/null | awk '/time=/ {print $7}' | cut -d '=' -f 2)
    speedlist+="${I} ${speed:-999}\n"
  done
  fastest="$(echo -e "${speedlist}" | tr -s '\n' | sort -k2n | head -1 | awk '{print $1}')"
  echo "${fastest}"
}

function chkavail() {

    if [ $(df -h /mnt/${tcrppart} | grep mnt | awk '{print $4}' | grep G | wc -l) -gt 0 ]; then
        avail_str=$(df -h /mnt/${tcrppart} | grep mnt | awk '{print $4}' | sed -e 's/G//g' | cut -c 1-3)
        avail=$(echo "$avail_str 1000" | awk '{print $1 * $2}')
    else
        avail=$(df -h /mnt/${tcrppart} | grep mnt | awk '{print $4}' | sed -e 's/M//g' | cut -c 1-3)
    fi

    avail_num=$(($avail))
    
    echo "Avail space ${avail_num}M on /mnt/${tcrppart}"
}    

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  BUS=""
  # usb/ata(sata/ide)/scsi
  [ -z "${BUS}" ] && BUS=$(udevadm info --query property --name "${1}" 2>/dev/null | grep ID_BUS | cut -d= -f2 | sed 's/ata/sata/')
  # usb/sata(sata/ide)/nvme
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}') #Spaces are intentional
  # usb/scsi(sata/ide)/virtio(scsi/virtio)/mmc/nvme/loop block
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk '{print $2}' | awk -F':' '{print (NF>1) ? $2 : $0}') #Spaces are intentional
  # empty is block
  [ -z "${BUS}" ] && BUS="block"
  echo "${BUS}"

  [ "${BUS}" = "nvme" ] && [[ "${loaderdisk}" != *p ]] && loaderdisk="${loaderdisk}p"
  [ "${BUS}" = "mmc"  ] && [[ "${loaderdisk}" != *p ]] && loaderdisk="${loaderdisk}p"
  [ "${BUS}" = "block" ] && [[ "${loaderdisk}" != *p ]] && loaderdisk="${loaderdisk}p"

}

###############################################################################
# git clone redpill-load
function gitclone() {
    git clone -b master --single-branch --depth 1 --filter=blob:none https://github.com/PeterSuh-Q3/redpill-load.git
    # clone 실패(또는 부분 실패로 .git 없는 손상된 디렉터리)를 여기서
    # 바로 잡지 않으면, 뒤이은 모든 단계(bundled-exts.json 읽기, 확장
    # 다운로드, redpill.ko 복사 등)가 존재하지 않거나 손상된
    # redpill-load 를 전제로 계속 진행되다가 한참 뒤 전혀 무관해 보이는
    # 단계에서야 실패로 드러난다(실기에서 재현: clone 직후 디렉터리가
    # 지워진 상태로 "cp: cannot create regular file .../rp-lkm/..." 까지
    # 진행됨). clone 이 실패하면 즉시 중단한다.
    if [ $? -ne 0 ] || [ ! -d "/home/tc/redpill-load/.git" ]; then
        cecho r "Failed to clone redpill-load from GitHub. Check network connectivity and try again."
        exit 99
    fi
    patchredpillload
}

# redpill-load의 brp_pack_cpiord()는 기본적으로 find/cpio stderr를 /dev/null로 버려서
# "Failed to repack flat ramdisk" 실패시 원인(디스크 공간부족/OOM 등)을 알 수 없다.
# 또한 rpt_download_remote()도 curl의 stderr를 캡처하지 않아, raw.githubusercontent.com
# 다운로드가 실패해도 DNS/연결/TLS/타임아웃 중 무엇이 원인인지 로그에 전혀 남지 않는다
# (152 실기에서 rpext-index.json 다운로드 반복 실패, 원인 불명 확인, 2026-07-19).
# /home/tc/redpill-load는 tmpfs 위에 매 빌드마다 새로 clone되므로, clone 직후 이
# 함수를 통해 로그가 남도록 패치한다 (원본 저장소를 직접 수정할 수 없어 로컬 패치).
function patchredpillload() {
    local f="/home/tc/redpill-load/include/file.sh"
    [ -f "$f" ] || return 0

    # (1) cpio 리패킹 실패 원인 로그 캡처
    if ! grep -q 'cpio -o -H newc -R root:root 2>>/tmp/strerr.log' "$f"; then
        local cpio_line find_line
        cpio_line=$(grep -n 'cpio -o -H newc -R root:root 2>/dev/null 1> "\${1}")' "$f" | head -1 | cut -d: -f1)
        if [ -n "$cpio_line" ]; then
            find_line=$((cpio_line - 1))
            sed -i "${find_line}s|2>/dev/null|2>/tmp/strerr.log|" "$f"
            sed -i "${cpio_line}s|2>/dev/null|2>>/tmp/strerr.log|" "$f"
        fi
    fi

    # (2) 원격 다운로드 실패 원인(DNS/연결/TLS 소요시간, HTTP 코드, curl 에러메시지) 로그 캡처
    # 2026-07-22: 이 로그 캡처로 실제 원인이 curl의 -n(--netrc) 플래그였음을 발견
    # (152 실기, "eudev bundled extension" 다운로드가 ".netrc error: no such file"로
    # 매번 즉시 실패, http_code=000). ~/.netrc가 없는 diskless 환경에서 이 플래그는
    # 네트워크 시도 자체를 막는 명백한 버그라 -kns를 -ks로 수정(원본 redpill-load
    # include/file.sh도 동일하게 수정, 이 함수는 매 clone마다 통째로 줄을 치환하므로
    # 여기 하드코딩된 값도 함께 고쳐야 함).
    if ! grep -q 'curl-diag' "$f"; then
        local dl_line indent newline
        dl_line=$(grep -n -- '--progress-bar --retry 5 --output' "$f" | head -1 | cut -d: -f1)
        if [ -n "$dl_line" ]; then
            indent=$(sed -n "${dl_line}p" "$f" | sed 's/[^ ].*//')
            newline=$(cat <<EOF
${indent}out=\$("\${CURL_PATH}" -ks --location --fail --retry 5 --output "\${2}" --write-out ' [curl-diag] http_code=%{http_code} dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s errormsg=%{errormsg} url=%{url_effective}' "\${1}" 2>&1)
EOF
)
            awk -v n="$dl_line" -v repl="$newline" 'NR==n{print repl; next} {print}' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
        fi
    fi
}

function gitdownload() {

    cd /home/tc
    git config --global http.sslVerify false    
    if [ -d "/home/tc/redpill-load" ]; then
        cecho y "Loader sources already downloaded, pulling latest"
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

function _pat_process() {

  PATURL="${URL}"
  PAT_FILE="${SYNOMODEL}.pat"
  PAT_PATH="${patfile}"
  #mirrors=("global.synologydownload.com" "global.download.synology.com" "cndl.synology.cn")
  mirrors=("global.synologydownload.com" "global.download.synology.com")

  fastest=$(_get_fastest "${mirrors[@]}")
  echo "fastest = " "${fastest}"
  mirror="$(echo ${PATURL} | sed 's|^http[s]*://\([^/]*\).*|\1|')"
  echo "mirror = " "${mirror}"
  if echo "${mirrors[@]}" | grep -wq "${mirror}" && [ "${mirror}" != "${fastest}" ]; then
      echo "Based on the current network situation, switch to ${fastest} mirror to downloading."
      PATURL="$(echo ${PATURL} | sed "s/${mirror}/${fastest}/")"
  fi

  # Discover remote file size
  echo "BUS type = ${BUS} (Discover remote file size)"

  if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then
      msgnormal "Skip Checking Pat files on xTCRP with Synoboot Injected."
  else
      if [ "${BUS}" != "block"  ]; then
          SPACELEFT=$(df --block-size=1 | awk '/'${loaderdisk}'3/{print $4}') # Check disk space left
          FILESIZE=$(curl -k -sLI "${PATURL}" | grep -i Content-Length | awk '{print$2}')
    
          FILESIZE=$(echo "${FILESIZE}" | tr -d '\r')
          SPACELEFT=$(echo "${SPACELEFT}" | tr -d '\r')
    
          FILESIZE_FORMATTED=$(printf "%'d" "${FILESIZE}")
          SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
          FILESIZE_MB=$((FILESIZE / 1024 / 1024))
          SPACELEFT_MB=$((SPACELEFT / 1024 / 1024))    
        
          echo "FILESIZE  = ${FILESIZE_FORMATTED} bytes (${FILESIZE_MB} MB)"
          echo "SPACELEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"
        
          if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
              # No disk space to download, change it to RAMDISK
              echo "No adequate space on ${local_cache} to download file into cache folder, clean up PAT file now ....."
              sudo sh -c "$([ "$FRKRNL" = "NO" ] && echo "sudo ")rm -vf $(ls -t "${local_cache}"/*.pat | head -n 1)"
          fi
      fi
  fi    
  
  echo "PATURL = " "${PATURL}"
  STATUS=$(sudo curl -k -w "%{http_code}" -L "${PATURL}" -o "${PAT_PATH}" --progress-bar)
  if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      sudo rm -f "${PAT_PATH}"
      echo "Check internet or cache disk space.\nError: ${STATUS}"
      exit 99
  fi

}

function setnetwork() {

    if [ -f /opt/eth*.sh ] && [ "$(grep dhcp /opt/eth*.sh | wc -l)" -eq 0 ]; then

        ipset="static"
        ipgw="$(route | grep default | head -1 | awk '{print $2}')"
        ipprefix="$(grep /sbin/ifconfig /opt/eth*.sh | head -1 | awk '{print "ipcalc -p " $3 " " $5 }' | sh - | awk -F= '{print $2}')"
        myip="$(grep /sbin/ifconfig /opt/eth*.sh | head -1 | awk '{print $3 }')"
        ipaddr="${myip}/${ipprefix}"
        ipgw="$(grep route /opt/eth*.sh | head -1 | awk '{print  $5 }')"
        ipdns="$(grep nameserver /opt/eth*.sh | head -1 | awk '{print  $3 }')"
        ipproxy="$(env | grep -i http | awk -F= '{print $2}' | uniq)"

        for field in ipset ipaddr ipgw ipdns ipproxy; do
            jsonfile=$(jq ".ipsettings+={\"$field\":\"${!field}\"}" $userconfigfile)
            echo $jsonfile | jq . >$userconfigfile
        done

    fi

}

function check_r8168_once() {
    if [ "$R8168_DETECTED" != "Y" ] && [[ "$DRIVER" == r816* ]]; then
        R8168_YN="Y"
        R8168_DETECTED="Y"
    elif [ "$R8168_DETECTED" != "Y" ]; then
        R8168_YN="N"
    fi
}

function getip() {
    ethdevs=$(ls /sys/class/net/ | grep eth || true)
    for eth in $ethdevs; do 
        DRIVER=$(ls -ld /sys/class/net/${eth}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
        if [ $(ls -l /sys/class/net/${eth}/device | grep "0000:" | wc -l) -gt 0 ]; then
            BUSID=$(ls -ld /sys/class/net/${eth}/device 2>/dev/null | awk -F '0000:' '{print $NF}')
        else
            BUSID=""
        fi
        IP="$(/sbin/ifconfig ${eth} | grep inet | awk '{print $2}' | awk -F \: '{print $2}')"
        HWADDR="$(/sbin/ifconfig ${eth} | grep HWaddr | awk '{print $5}')"
        if [ -f /sys/class/net/${eth}/device/vendor ] && [ -f /sys/class/net/${eth}/device/device ]; then
            VENDOR=$(cat /sys/class/net/${eth}/device/vendor | sed 's/0x//')
            DEVICE=$(cat /sys/class/net/${eth}/device/device | sed 's/0x//')
            if [ ! -z "${VENDOR}" ] && [ ! -z "${DEVICE}" ]; then
                MATCHDRIVER=$(echo "$(matchpciidmodule ${VENDOR} ${DEVICE})")
                if [ ! -z "${MATCHDRIVER}" ]; then
                    if [ "${MATCHDRIVER}" != "${DRIVER}" ]; then
                        DRIVER=${MATCHDRIVER}
                    fi
                fi
            fi    
        fi    
        check_r8168_once
        echo "IP Addr : $(msgnormal "${IP}"), ${HWADDR}, ${BUSID}, ${eth} (${DRIVER})"
    done
}

function listpci() {

    lspci -n | while read line; do

        bus="$(echo $line | cut -c 1-7)"
        class="$(echo $line | cut -c 9-12)"
        vendor="$(echo $line | cut -c 15-18)"
        device="$(echo $line | cut -c 20-23)"

        #echo "PCI : $bus Class : $class Vendor: $vendor Device: $device"
        case $class in
#        0100)
#            echo "Found SCSI Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0106)
#            echo "Found SATA Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0101)
#            echo "Found IDE Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
        0104)
            msgnormal "RAID bus Controller : Required Extension : $(matchpciidmodule ${vendor} ${device})"
            echo `lspci -nn |grep ${vendor}:${device}|awk 'match($0,/0104/) {print substr($0,RSTART+7,100)}'`| sed 's/\['"$vendor:$device"'\]//' | sed 's/(rev 05)//'
            ;;
        0107)
            msgnormal "SAS Controller : Required Extension : $(matchpciidmodule ${vendor} ${device})"
            echo `lspci -nn |grep ${vendor}:${device}|awk 'match($0,/0107/) {print substr($0,RSTART+7,100)}'`| sed 's/\['"$vendor:$device"'\]//' | sed 's/(rev 03)//'
            ;;
#        0200)
#            msgnormal "Ethernet Interface : Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0680)
#            msgnormal "Ethernet Interface : Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0300)
#            echo "Found VGA Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0c04)
#            echo "Found Fibre Channel Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
        esac
    done

}

function monitor() {

    getloaderdisk
    if [ -z "${loaderdisk}" ]; then
        echo "Not Supported Loader BUS Type, program Exit!!!"
        exit 99
    fi

    getBus "${loaderdisk}" 

    ensure_loader_partitions_mounted

    HYPERVISOR=$(sudo dmesg | grep -i "Hypervisor detected" | awk '{print $5}')

    while true; do
        clear
        echo -e "-------------------------------System Information----------------------------"
        echo -e "Hostname:\t\t"$(hostname) 
        echo -e "uptime:\t\t\t"$(uptime | awk '{print $3}' | sed 's/,//')" min"
        echo -e "Board Manufacturer:\t"$(cat /sys/class/dmi/id/board_vendor)
        echo -e "Board Name:\t\t"$(cat /sys/class/dmi/id/board_name)
        echo -e "Board Version:\t"$(cat /sys/class/dmi/id/board_version)
        echo -e "Board Serial Number:\t"$(sudo cat /sys/class/dmi/id/board_serial)
        echo -e "Operating System:\t"$(grep PRETTY_NAME /etc/os-release | awk -F \= '{print $2}')
        echo -e "Kernel:\t\t\t"$(uname -r)
        echo -e "Processor Name:\t\t"$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')
        echo -e "Machine Type:\t\t"$(
            vserver=$(lscpu | grep Hypervisor | wc -l)
            [ $vserver -gt 0 ] && echo -e "VM (${HYPERVISOR})\n" || echo -e "Physical\n"
            [ -d /sys/firmware/efi ] && echo ": EFI" || echo ": LEGACY(CSM,BIOS)"
        ) 
        msgnormal "CPU Threads:\t\t"$(nproc)
        echo -e "Current Date Time:\t"$(date)
        #msgnormal "System Main IP:\t\t"$(/sbin/ifconfig | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | awk -F \: '{print $2}' | tr '\n' ',' | sed 's#,$##')
        getip
        listpci
        echo -e "-------------------------------Loader boot entries---------------------------"
        grep -i menuentry /mnt/${loaderdisk}1/boot/grub/grub.cfg | awk -F \' '{print $2}'
        echo -e "-------------------------------CPU / Memory----------------------------------"
        msgnormal "Total Memory (MB):\t"$(cat /proc/meminfo |grep MemTotal | awk '{printf("%.2f"), $2/1000}')
        echo -e "Swap Usage:\t\t"$(free | awk '/Swap/{printf("%.2f%"), ($2>0 ? $3/$2*100 : 0)}')
        echo -e "Ramdisk Size (/):\t"$(df -h / | awk 'NR==2{print $2}')
        echo -e "Ramdisk Usage (/):\t"$(df -h / | awk 'NR==2{printf "%s (%s)", $3, $5}')
        echo -e "CPU Usage:\t\t"$(cat /proc/stat | awk '/cpu/{printf("%.2f%\n"), ($2+$4)*100/($2+$4+$5)}' | awk '{print $0}' | head -1)
        echo -e "-------------------------------Disk Usage >80%-------------------------------"
        df -Ph /mnt/${loaderdisk}1 /mnt/${loaderdisk}2 /mnt/${loaderdisk}3

        echo "Press ctrl-c to exit"
        sleep 10
    done

}

function savesession() {

    lastsessiondir="/mnt/${tcrppart}/lastsession"

    echo -n "Saving user session for future use. "

    [ ! -d ${lastsessiondir} ] && sudo mkdir ${lastsessiondir}

    echo -n "Saving current extensions "

    if [ "$FRKRNL" = "NO" ]; then
        cat /home/tc/redpill-load/custom/extensions/*/*json | jq '.url' >${lastsessiondir}/extensions.list
    else
        echo
    fi

    [ -f ${lastsessiondir}/extensions.list ] && echo " -> OK !"

    echo -n "Saving current user_config.json "

    $( [ "$FRKRNL" != "NO" ] && echo sudo ) cp /home/tc/user_config.json "${lastsessiondir}/user_config.json"
    [ -f ${lastsessiondir}/user_config.json ] && echo " -> OK !"

}

function copyextractor() {
#m shell mofified
    local_cache="/mnt/${tcrppart}/auxfiles"

    echo "making directory ${local_cache}"
    [ ! -d ${local_cache} ] && mkdir ${local_cache}

    echo "making directory ${local_cache}/extractor"
    [ ! -d ${local_cache}/extractor ] && sudo mkdir ${local_cache}/extractor
    [ ! -f /home/tc/extractor.gz ] && sudo curl -kL -# "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/extractor.gz" -o /home/tc/extractor.gz
    sudo tar -zxvf /home/tc/extractor.gz -C ${local_cache}/extractor

    if [ "${BUS}" = "block"  ]; then
      # clone 실패를 확인하지 않으면 cd 가 그대로 실패한 채 넘어가
      # docker build 가 엉뚱한(현재) 디렉터리를 대상으로 실행되거나
      # 조용히 실패해, 뒤늦게 이미지가 없다는 식으로 원인과 동떨어진
      # 곳에서 문제가 드러난다.
      if ! git clone https://github.com/technorabilia/syno-extract-system-patch.git || \
         [ ! -d syno-extract-system-patch/.git ]; then
        echo "[ERROR] Failed to clone syno-extract-system-patch from GitHub. Check network connectivity and try again."
        exit 99
      fi
      cd syno-extract-system-patch
      sudo docker build --tag syno-extract-system-patch .
      sudo mkdir -p ~/data/in
      sudo mkdir -p ~/data/out
    fi

    echo "Copying required libraries to local lib directory"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/lib* /lib/
    echo "Linking lib to lib64"
    # gcompat 등이 /lib64를 이미 실제 디렉토리로 만들어두는 경우, "-h /lib64"는
    # 항상 참(=/lib64 자체는 심볼릭 링크가 아님)이 되어 매번 ln이 재시도되고
    # "/lib64/lib: File exists"로 실패한다(ln이 기존 디렉토리 안에 이름을 만듦).
    # 실제 결과 경로(/lib64/lib)의 존재 여부로 확인해야 재실행에도 안전함.
    [ ! -e /lib64/lib ] && [ ! -L /lib64/lib ] && sudo ln -s /lib /lib64
    echo "Copying executable"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/scemd /bin/syno_extract_system_patch
    echo "pigz copy for multithreaded compression"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/pigz /usr/bin/pigz

}

function downloadextractor() {

st "extractor" "Extraction tools" "Extraction Tools downloaded"
[ "${BUS}" != "block" ] && log_build_step "Extraction tools" 3 12
#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    local_cache="/mnt/${tcrppart}/auxfiles"
    temp_folder="/tmp/synoesp"

#m shell mofified
    copyextractor

    if [ -d ${local_cache/extractor /} ] && [ -f ${local_cache}/extractor/scemd ]; then

        msgnormal "Found extractor locally cached"

    else

        echo "Getting required extraction tool"
        echo "------------------------------------------------------------------"
        echo "Checking tinycore cache folder"

        [ -d $local_cache ] && echo "Found tinycore cache folder, linking to home/tc/custom-module" && [ ! -h /home/tc/custom-module ] && sudo ln -s $local_cache /home/tc/custom-module

        echo "Creating temp folder /tmp/synoesp"

        mkdir ${temp_folder}

        if [ -d /home/tc/custom-module ] && [ -f /home/tc/custom-module/*42218*.pat ]; then

            patfile=$(ls /home/tc/custom-module/*42218*.pat | head -1)
            echo "Found custom pat file ${patfile}"
            echo "Processing old pat file to extract required files for extraction"
            tar -C${temp_folder} -xf /${patfile} rd.gz
        else
            curl -kL https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat -o /home/tc/oldpat.tar.gz
            [ -f /home/tc/oldpat.tar.gz ] && tar -C${temp_folder} -xf /home/tc/oldpat.tar.gz rd.gz
        fi

        echo "Entering synoesp"
        cd ${temp_folder}

        xz -dc <rd.gz >rd 2>/dev/null || echo "extract rd.gz"
        echo "finish"
        cpio -idm <rd 2>&1 || echo "extract rd"
        mkdir extract

        mkdir /mnt/${tcrppart}/auxfiles && cd /mnt/${tcrppart}/auxfiles

        echo "Copying required files to local cache folder for future use"

        mkdir /mnt/${tcrppart}/auxfiles/extractor

        for file in usr/lib/libcurl.so.4 usr/lib/libmbedcrypto.so.5 usr/lib/libmbedtls.so.13 usr/lib/libmbedx509.so.1 usr/lib/libmsgpackc.so.2 usr/lib/libsodium.so usr/lib/libsynocodesign-ng-virtual-junior-wins.so.7 usr/syno/bin/scemd; do
            echo "Copying $file to /mnt/${tcrppart}/auxfiles"
            cp $file /mnt/${tcrppart}/auxfiles/extractor
        done

    fi

    echo "Removing temp folder /tmp/synoesp"
    rm -rf $temp_folder

    if [ "${BUS}" != "block" ]; then
        msgnormal "Checking if tool is accessible"
        if [ -d ${local_cache/extractor /} ] && [ -f ${local_cache}/extractor/scemd ]; then    
            /bin/syno_extract_system_patch 2>&1 >/dev/null
        else
            /bin/syno_extract_system_patch
        fi
        if [ $? -eq 255 ]; then echo "Executed succesfully"; else echo "Cound not execute"; fi    
    fi
}

function testarchive() {

    archive="$1"
    if [ "${BUS}" != "block" ]; then
        archiveheader="$(od -bcN2 ${archive} | awk 'NR==1 {print $3; exit}')"
    
        case ${archiveheader} in
        105)
            echo "${archive}, is a Tar file"
            isencrypted="no"
            return 0
            ;;
        255)
            echo "File ${archive}, is  encrypted"
            isencrypted="yes"
            return 1
            ;;
        213)
            echo "File ${archive}, is a compressed tar"
            isencrypted="no"
            ;;
        057)
            echo "File ${archive}, is a compressed tar (from GNU friend kernel)"
            isencrypted="no"
            ;;
        *)
            echo "Could not determine if file ${archive} is encrypted or not, maybe corrupted"
            ls -ltr ${archive}
            echo ${archiveheader}
            exit 99
            ;;
        esac
    else
        if [ ${TARGET_REVISION} -gt 42218 ]; then
            echo "Found build request for revision greater than 42218"
            echo "File ${archive}, is  encrypted"
            isencrypted="yes"
            return 1
        else
            echo "Found build request for revision less equal than 42218"
            echo "${archive}, is a Tar file"
            isencrypted="no"
            return 0
        fi
    fi

}

function processpat() {

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then
        local_cache="/dev/shm"
    else
        local_cache="/mnt/${tcrppart}/auxfiles"
    fi    
    temp_pat_folder="/tmp/pat"
    temp_dsmpat_folder="/tmp/dsmpat"

    setplatform

    if [ ! -d "${temp_pat_folder}" ]; then
        msgnormal "Creating temp folder ${temp_pat_folder} "
        mkdir ${temp_pat_folder} && sudo mount -t tmpfs -o size=512M tmpfs ${temp_pat_folder} && cd ${temp_pat_folder}
        mkdir ${temp_dsmpat_folder} && sudo mount -t tmpfs -o size=512M tmpfs ${temp_dsmpat_folder}
    fi

    echo "Checking for cached pat file"
    [ -d $local_cache ] && msgnormal "Found tinycore cache folder, linking to home/tc/custom-module" && [ ! -h /home/tc/custom-module ] && sudo ln -s $local_cache /home/tc/custom-module

    # [netconsole] 이 기능이 생기기 전에 만들어진 캐시(미니팻)는 netconsole.ko 를
    # 내장하고 있지 않다. 그런 캐시를 그대로 쓰면 buildloader() 가 이번 빌드에서도
    # netconsole.ko 를 못 찾으므로, 캐시된 pat 에 없으면 지워서 아래 로직이
    # "캐시 없음"으로 보고 원본을 새로 받아 다시 만들도록 강제한다.
    # 주의: 이 함수는 재귀 호출된다(암호화 pat 다운로드 직후 재호출) - 그 시점의
    # 캐시는 아직 암호화된 상태라 tar -tf 가 실패(빈 리스팅)하는데, 그걸 "netconsole.ko
    # 없음"으로 오판해 방금 받은 파일을 지우면 무한 재다운로드 루프에 빠진다.
    # tar 리스팅이 실제로 비어있지 않을 때(=유효한 tar, 이미 복호화됨)만 검사한다.
    for _nc_cached in ${local_cache}/*${SYNOMODEL}*.pat ${local_cache}/*${MODEL}*${TARGET_REVISION}*.pat; do
        [ -f "${_nc_cached}" ] || continue
        _nc_listing="$(tar -tf "${_nc_cached}" 2>/dev/null)"
        if [ -n "${_nc_listing}" ] && ! echo "${_nc_listing}" | grep -q "usr/lib/modules/netconsole\.ko\$"; then
            echo "[netconsole] cached pat ${_nc_cached} predates netconsole.ko bundling - removing to force full re-download"
            rm -f "${_nc_cached}"
        fi
    done

    if [ -d ${local_cache} ] && [ -f ${local_cache}/*${SYNOMODEL}*.pat ] || [ -f ${local_cache}/*${MODEL}*${TARGET_REVISION}*.pat ]; then

        [ -f /home/tc/custom-module/*${SYNOMODEL}*.pat ] && patfile=$(ls /home/tc/custom-module/*${SYNOMODEL}*.pat | head -1)
        [ -f ${local_cache}/*${MODEL}*${TARGET_REVISION}*.pat ] && patfile=$(ls /home/tc/custom-module/*${MODEL}*${TARGET_REVISION}*.pat | head -1)

        msgnormal "Found locally cached pat file ${patfile}"
st "iscached" "Caching pat file" "Patfile ${SYNOMODEL}.pat is cached"
[ "${BUS}" != "block" ] && log_build_step "Caching pat file" 4 12
        testarchive "${patfile}"
        if [ ${isencrypted} = "no" ]; then
            echo "File ${patfile} is already decrypted"
            msgnormal "Copying file to /home/tc/redpill-load/cache folder"
            sudo mv -f ${patfile} /home/tc/redpill-load/cache/
        elif [ ${isencrypted} = "yes" ]; then
            [ -f /home/tc/redpill-load/cache/${SYNOMODEL}.pat ] && testarchive /home/tc/redpill-load/cache/${SYNOMODEL}.pat
            if [ -f /home/tc/redpill-load/cache/${SYNOMODEL}.pat ] && [ ${isencrypted} = "no" ]; then
                echo "Decrypted file is already cached in :  /home/tc/redpill-load/cache/${SYNOMODEL}.pat"
            else
                if [ "${BUS}" = "block"  ]; then            
                  echo "Copying encrypted pat file : ${patfile} to ~/data/in"
                  sudo mv -f ${patfile} ~/data/in/${SYNOMODEL}.pat
                  echo "Extracting encrypted pat file : ~/data/in/${SYNOMODEL}.pat to ~/data/out"
                  sudo docker run --rm -v ~/data:/data syno-extract-system-patch /data/in/${SYNOMODEL}.pat /data/out/. || echo "extract latest pat"
                  rsync -a --remove-source-files ~/data/out/ ${temp_pat_folder}/
                else
                  echo "Copying encrypted pat file : ${patfile} to ${temp_dsmpat_folder}"
                  sudo mv -f ${patfile} ${temp_dsmpat_folder}/${SYNOMODEL}.pat
                  echo "Extracting encrypted pat file : ${temp_dsmpat_folder}/${SYNOMODEL}.pat to ${temp_pat_folder}"
                  sudo /bin/syno_extract_system_patch ${temp_dsmpat_folder}/${SYNOMODEL}.pat ${temp_pat_folder} || echo "extract latest pat"
                fi
                echo "Decrypted pat file tar compression in progress ${SYNOMODEL}.pat to /home/tc/redpill-load/cache folder (multithreaded comporession)"
                mkdir -p /home/tc/redpill-load/cache/
                echo "threads = ${threads}"
                if [ "${BUS}" = "block"  ]; then
                  cd ${temp_pat_folder} && tar -cf ${temp_dsmpat_folder}/${SYNOMODEL}.pat ./ && cp -f ${temp_dsmpat_folder}/${SYNOMODEL}.pat /home/tc/redpill-load/cache/${SYNOMODEL}.pat
                else
                  if [ "$FRKRNL" = "NO" ]; then
                      cd ${temp_pat_folder} && sudo sh -c "tar -cf - ./ | pigz -p ${threads} > ${temp_dsmpat_folder}/${SYNOMODEL}.pat" && sudo cp -f ${temp_dsmpat_folder}/${SYNOMODEL}.pat /home/tc/redpill-load/cache/${SYNOMODEL}.pat
                  else    
                      cd ${temp_pat_folder} && sudo sh -c "tar -cf ${temp_dsmpat_folder}/${SYNOMODEL}.pat ./" && sudo cp -f ${temp_dsmpat_folder}/${SYNOMODEL}.pat /home/tc/redpill-load/cache/${SYNOMODEL}.pat
                  fi    
                fi
            fi
            patfile="/home/tc/redpill-load/cache/${SYNOMODEL}.pat"
            # every branch above that reaches here wrote this via sudo
            # (mv/cp), leaving it root-owned and unreadable to tc -
            # ext-manager.sh/build-loader.sh unpack it without sudo later.
            sudo chmod a+r "${patfile}" 2>/dev/null

        else
            echo "Something went wrong, please check cache files"
            exit 99
        fi

        cd /home/tc/redpill-load/cache
st "patextraction" "Pat file extracted" "VERSION:${BUILD}"
[ "${BUS}" != "block" ] && log_build_step "Pat file extracted" 5 12
        sudo tar xvf /home/tc/redpill-load/cache/${SYNOMODEL}.pat ./VERSION && sudo chmod a+r ./VERSION && . ./VERSION && cat ./VERSION && rm ./VERSION
        os_md5=$(md5sum /home/tc/redpill-load/cache/${SYNOMODEL}.pat | awk '{print $1}')
        msgnormal "Pat file md5sum is : $os_md5"

        echo -n "Checking config file existence -> "
        if [ -f "${configfile}" ]; then
            echo "OK"
        else
            echo "No config file(pats.json) found, The download may be corrupted or may not be run the original repo. Please re-download from original repo."
            exit 99
        fi

        msgnormal "Editing config file !!!!!"
       
        echo -n "Verifying config file -> "
        verifyid=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.sum) | .[0]" "${configfile}")
        sed -i "s/${verifyid}/$os_md5/" ${configfile}
        verifyid="$os_md5"

        if [ "$os_md5" == "$verifyid" ]; then
            echo "OK ! "
        else
            echo "config file, os md5 verify FAILED, check ${configfile} "
            exit 99
        fi

        msgnormal "Clearing temp folders"
        sudo umount ${temp_pat_folder} && sudo rm -rf ${temp_pat_folder}
        sudo umount ${temp_dsmpat_folder} && sudo rm -rf ${temp_dsmpat_folder}        

        return

    else

        echo "Could not find pat file locally cached"
        
        pat_url=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.url) | .[0]" "${configfile}")
        echo -e "Configfile: $configfile \nPat URL : $pat_url"
        echo "Downloading pat file from URL : ${pat_url} "

        chkavail
        if [ $avail_num -le 370 ]; then
            echo "No adequate space on ${local_cache} to download file into cache folder, clean up the space and restart"
            exit 99
        fi

        [ -n $pat_url ] && curl -kL# ${pat_url} -o "/${local_cache}/${SYNOMODEL}.pat"
        patfile="/${local_cache}/${SYNOMODEL}.pat"
        if [ -f ${patfile} ]; then
            testarchive ${patfile}
        else
            echo "Failed to download PAT file $patfile from ${pat_url} "
            exit 99
        fi

        if [ "${isencrypted}" = "yes" ]; then
            echo "File ${patfile}, has been cached but its encrypted, re-running decrypting process"
            processpat
        else
            return
        fi

    fi

}

function addrequiredexts() {

    echo "Processing add_extensions entries found on models.json file : ${EXTENSIONS}"
    for extension in ${EXTENSIONS_SOURCE_URL}; do
        echo "Adding extension ${extension} "
        cd /home/tc/redpill-load/ && ./ext-manager.sh add "$(echo $extension | sed -s 's/"//g' | sed -s 's/,//g')"
        if [ $? -ne 0 ]; then
            echo "FAILED : Processing add_extensions failed check the output for any errors"
            rploader clean
            exit 99
        fi
    done
    for extension in ${EXTENSIONS}; do
        echo "Updating extension : ${extension} contents for platform, kernel : ${ORIGIN_PLATFORM}, ${DSMVER}, ${KVER}  "
        # Add Use RR's custom kernel module
        DSMVER_NOTDOT="$(echo ${DSMVER} | sed 's/\.//g')"
        nkver="$(echo ${KVER} | sed 's/\.//g')"
        echo "nkver = ${nkver}"
        cd /home/tc/redpill-load/ && ./ext-manager.sh _update_platform_exts ${ORIGIN_PLATFORM} ${DSMVER_NOTDOT} ${nkver} ${extension}
        if [ $? -ne 0 ]; then
            echo "FAILED : Processing add_extensions failed check the output for any errors"
            rploader clean
            exit 99
        fi
    done

    # MSHELL Manager is not model-specific.  It must be collected here, before
    # build-loader packages custom.gz; relying only on bundled-exts.json can
    # register it after this collection stage.
    local mshell_addon_url="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/aeudev/rpext-index.json"
    jsonfile=$(jq --arg url "${mshell_addon_url}" '. + {"aeudev": $url}' /home/tc/redpill-load/bundled-exts.json) \
      && echo "${jsonfile}" | jq . > /home/tc/redpill-load/bundled-exts.json
    echo "Adding required MSHELL Manager addon"
    cd /home/tc/redpill-load/ && ./ext-manager.sh add "${mshell_addon_url}" \
      && ./ext-manager.sh _update_platform_exts "${ORIGIN_PLATFORM}" "${DSMVER_NOTDOT}" "${nkver}" aeudev
    if [ $? -ne 0 ]; then
        echo "FAILED : MSHELL Manager addon preparation failed"
        rploader clean
        exit 99
    fi

#m shell only
 #Use user define dts file instaed of dtbpatch ext now
    #if [ ${ORIGIN_PLATFORM} = "geminilake" ] || [ ${ORIGIN_PLATFORM} = "v1000" ] || [ ${ORIGIN_PLATFORM} = "r1000" ]; then
    #    echo "For user define dts file instaed of dtbpatch ext"
    #    patchdtc
    #    echo "Patch dtc is superseded by fbelavenuto dtbpatch"
    #fi
    
}

function updateuserconfig() {

    echo "Checking user config for general block"
    generalblock="$(jq -r -e '.general' $userconfigfile)"
    if [ "$generalblock" = "null" ] || [ -n "$generalblock" ]; then
        echo "Result=${generalblock}, File does not contain general block, adding block"

        for field in model version smallfixnumber redpillmake zimghash rdhash usb_line sata_line; do
            jsonfile=$(jq ".general+={\"$field\":\"\"}" $userconfigfile)
            echo $jsonfile | jq . >$userconfigfile
        done
    fi

}
function updateuserconfigfield() {

    block="$1"
    field="$2"
    value="$3"

    if [ -n "$1 " ] && [ -n "$2" ]; then
        jsonfile=$(jq ".$block+={\"$field\":\"$value\"}" $userconfigfile)
        echo $jsonfile | jq . >$userconfigfile
    else
        echo "No values to update specified"
    fi
}

function postupdate() {

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"

    cd /home/tc

    updateuserconfig
    setnetwork

    updateuserconfigfield "general" "model" "$MODEL"
    updateuserconfigfield "general" "version" "${BUILD}"
    updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
    updateuserconfigfield "general" "redpillmake" "${redpillmake}-${TAG}"
    echo "Creating temp ramdisk space" && mkdir /home/tc/ramdisk

    echo "Mounting partition ${loaderdisk}1" && ensure_loader_partition_mounted 1
    echo "Mounting partition ${loaderdisk}2" && ensure_loader_partition_mounted 2
    echo "Mounting partition ${loaderdisk}3" && ensure_loader_partition_mounted 3

    zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
    updateuserconfigfield "general" "zimghash" "$zimghash"
    rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
    updateuserconfigfield "general" "rdhash" "$rdhash"

    zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
    updateuserconfigfield "general" "zimghash" "$zimghash"
    rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
    updateuserconfigfield "general" "rdhash" "$rdhash"
    echo "Backing up $userconfigfile "
    cp $userconfigfile /mnt/${loaderdisk}3

    cd /home/tc/ramdisk

    echo "Extracting update ramdisk"

    if [ $(od /mnt/${loaderdisk}2/rd.gz | head -1 | awk '{print $2}') == "000135" ]; then
        sudo unlzma -c /mnt/${loaderdisk}2/rd.gz | cpio -idm 2>&1 >/dev/null
    else
        sudo cat /mnt/${loaderdisk}2/rd.gz | cpio -idm 2>&1 >/dev/null
    fi

    . ./etc.defaults/VERSION && echo "Found Version : ${productversion}-${buildnumber}-${smallfixnumber}"

#    echo -n "Do you want to use this for the loader ? [yY/nN] : "
#    readanswer

#    if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then

        echo "Extracting redpill ramdisk"

        if [ $(od /mnt/${loaderdisk}3/rd.gz | head -1 | awk '{print $2}') == "000135" ]; then
            sudo unlzma -c /mnt/${loaderdisk}3/rd.gz | cpio -idm
            RD_COMPRESSED="yes"
        else
            sudo cat /mnt/${loaderdisk}3/rd.gz | cpio -idm
        fi

        . ./etc.defaults/VERSION && echo "The new smallupdate version will be  : ${productversion}-${buildnumber}-${smallfixnumber}"

#        echo -n "Do you want to use this for the loader ? [yY/nN] : "
#        readanswer

#        if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then

            echo "Recreating ramdisk "

            if [ "$RD_COMPRESSED" = "yes" ]; then
                sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | xz -9 --format=lzma >../rd.gz
            else
                sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root >../rd.gz
            fi

            cd ..

            echo "Adding fake sign" && sudo dd if=/dev/zero of=rd.gz bs=68 count=1 conv=notrunc oflag=append

            echo "Putting ramdisk back to the loader partition ${loaderdisk}1" && sudo cp -f rd.gz /mnt/${loaderdisk}3/rd.gz

            echo "Removing temp ramdisk space " && rm -rf ramdisk

            echo "Done"
#        else
#            echo "Removing temp ramdisk space " && rm -rf ramdisk
#            exit 0
#        fi
#    fi

}

function getgrubbkg() {

    curl -kLO# "https://github.com/PeterSuh-Q3/tinycore-redpill/raw/${build}/grub/grubbkg.cfg"
    if [ ! -f /home/tc/grubbkg.png ]; then
        curl -kLO# "https://github.com/PeterSuh-Q3/tinycore-redpill/raw/${build}/grub/grubbkg.png"
        sudo cp -vf /home/tc/grubbkg.png /mnt/alpine/grubbkg.png
    fi
}

function getbspatch() {

    chmod 777 /home/tc/tools/bspatch
    # 2026-07-22: "sudo cp"는 원본(777) 권한을 보존하지 않고 root의 umask를 따라
    # 복사한다. 이 환경(xTCRP/Buildroot)의 root umask가 엄격해 결과물이 -rwx------
    # (700)로 복사되어, tc 계정에서 which/실행이 안 되고 "Some tools weren't
    # available"로 빌드가 실패하는 사고를 실측 확인(152 실기). cp 직후 명시적으로
    # chmod를 추가해 모든 사용자가 실행 가능하도록 보장.
    if [ "$FRKRNL" = "YES" ]; then
        if [ ! -x /usr/bin/bspatch ]; then
            echo "bspatch does not exist, copy from tools"
            sudo cp -vf /home/tc/tools/bspatch /usr/bin/
            sudo chmod 755 /usr/bin/bspatch
        fi
    else
        if [ ! -x /usr/local/bin/bspatch ]; then
            echo "bspatch does not exist, copy from tools"
            sudo cp -vf /home/tc/tools/bspatch /usr/local/bin/
            sudo chmod 755 /usr/local/bin/bspatch
        fi
    fi

}

function getpigz() {

    if [ ! -n "$(which pigz)" ]; then
        echo "pigz does not exist, bringing over from repo"
        curl -skLO "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/tools/pigz"
        chmod 777 /home/tc/pigz
        sudo cp -vf /home/tc/pigz /usr/bin/
    fi

}

function removemodelexts() {                                                                             
                                                                                        
    echo "Entering redpill-load directory to remove exts"                                                            
    cd /home/tc/redpill-load/
    echo "Removing all exts directories..."
    sudo rm -rf /home/tc/redpill-load/custom/extensions/*
                                                                                                                              
    #echo "Removing model exts directories..."
    #for modelextdir in ${EXTENSIONS}; do
    #    if [ -d /home/tc/redpill-load/custom/extensions/${modelextdir} ]; then                                                         
    #        echo "Removing : ${modelextdir}"
    #        sudo rm -rf /home/tc/redpill-load/custom/extensions/${modelextdir}            
    #    fi                                                                                            
    #done                                                           

} 

function getPlatforms() {

    platform_versions=$(jq -s '.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]'  custom_config.json | jq -r '.build_configs[].id')
    echo "platform_versions=$platform_versions"

}

function selectPlatform() {

    platform_selected=$(jq -r ".${1}" models.json)
    echo "platform_selected=${platform_selected}"

}
function getValueByJsonPath() {

    local JSONPATH=${1}
    local CONFIG=${2}
    jq -c -r "${JSONPATH}" <<<${CONFIG}

}
function readConfig() {

    if [ ! -e custom_config.json ]; then
        cat global_config.json
    else
        jq -s '.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]'  custom_config.json
    fi

}

function setplatform() {

    SYNOMODEL=${TARGET_PLATFORM}_${TARGET_REVISION}
    #MODEL=$(echo "${TARGET_PLATFORM}" | sed 's/ds/DS/' | sed 's/rs/RS/' | sed 's/p/+/' | sed 's/dva/DVA/' | sed 's/fs/FS/' | sed 's/sa/SA/' )
    #ORIGIN_PLATFORM="$(echo $platform_selected | jq -r -e '.platform_name')"

}

function getvars() {

    KVER="$(jq -r -e '.general.kver' $userconfigfile)"

    CONFIG=$(readConfig)
    selectPlatform $1

    GETTIME=$(curl -k -v -s https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
    INTERNETDATE=$(date +"%d%m%Y" -d "$GETTIME")
    LOCALDATE=$(date +"%d%m%Y")

    #EXTENSIONS="$(echo $platform_selected | jq -r -e '.add_extensions[]')"
    EXTENSIONS="$(echo $platform_selected | jq -r -e '.add_extensions[]' | grep json | awk -F: '{print $1}' | sed -s 's/"//g')"
    #EXTENSIONS_SOURCE_URL="$(echo $platform_selected | jq '.add_extensions[] .url')"
    EXTENSIONS_SOURCE_URL="$(echo $platform_selected | jq '.add_extensions[]' | grep json | awk '{print $2}')"
    #TARGET_PLATFORM="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[0])"
    #TARGET_VERSION="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[1])"
    #TARGET_REVISION="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[2])"

    tcrppart="${tcrpdisk}3"
    local_cache="/mnt/${tcrppart}/auxfiles"
    usbpart1uuid=$(/sbin/blkid /dev/${tcrpdisk}1 | awk '{print $3}' | sed -e "s/\"//g" -e "s/UUID=//g")
    usbpart3uuid="6234-C863"

    # gcompat 등이 /lib64를 이미 실제 디렉토리로 만들어두는 경우, "-h /lib64"는
    # 항상 참(=/lib64 자체는 심볼릭 링크가 아님)이 되어 매번 ln이 재시도되고
    # "/lib64/lib: File exists"로 실패한다(ln이 기존 디렉토리 안에 이름을 만듦).
    # 실제 결과 경로(/lib64/lib)의 존재 여부로 확인해야 재실행에도 안전함.
    [ ! -e /lib64/lib ] && [ ! -L /lib64/lib ] && sudo ln -s /lib /lib64

    sudo chown -R tc:staff /home/tc

    getgrubbkg
    getbspatch
    getpigz

    if [ "${offline}" = "NO" ]; then
        echo "Redownload the latest module.alias.4.json file ..."    
        echo
        curl -ksL "$modalias4" -o modules.alias.4.json.gz
        [ -f modules.alias.4.json.gz ] && gunzip -f modules.alias.4.json.gz    
    fi    

    [ ! -d ${local_cache} ] && sudo mkdir -p ${local_cache}
    [ -h /home/tc/custom-module ] && unlink /home/tc/custom-module
    [ ! -h /home/tc/custom-module ] && sudo ln -s $local_cache /home/tc/custom-module

    if [ -z "$TARGET_PLATFORM" ] || [ -z "$TARGET_VERSION" ] || [ -z "$TARGET_REVISION" ]; then
        echo "Error : Platform not found "
        showhelp
        exit 99
    fi

    if echo ${kver3platforms} | grep -qw ${ORIGIN_PLATFORM}; then
        KERNEL_MAJOR="3"
        MODULE_ALIAS_FILE="modules.alias.3.json"
    else
        KERNEL_MAJOR="4"
        MODULE_ALIAS_FILE="modules.alias.4.json"
    fi

    setplatform

    threads="$(nproc)"
    [ -z "$threads" ] && threads="1"

    #echo "Platform : $platform_selected"
    echo "Verbose Mode      : $VERBOSE_MODE"
    echo "Rploader Version  : ${rploaderver}"
    echo "Extensions        : $EXTENSIONS "
    echo "Extensions URL    : $EXTENSIONS_SOURCE_URL"
    echo "TARGET_PLATFORM   : $TARGET_PLATFORM"
    echo "TARGET_VERSION    : $TARGET_VERSION"
    echo "TARGET_REVISION   : $TARGET_REVISION"
    echo "KERNEL_MAJOR      : $KERNEL_MAJOR"
    echo "MODULE_ALIAS_FILE : $MODULE_ALIAS_FILE"
    echo "SYNOMODEL         : $SYNOMODEL"
    echo "MODEL             : $MODEL"
    echo "KERNEL VERSION    : $KVER"
    echo "Local Cache Folder : $local_cache"
    echo "CPU THREADS       : $threads"
    echo "DATE Internet     : $INTERNETDATE Local : $LOCALDATE"

  if [ "${offline}" = "NO" ]; then
    if [ "$INTERNETDATE" != "$LOCALDATE" ]; then
        echo "ERROR ! System DATE is not correct"
        synctime
        echo "Current time after communicating with NTP server ${ntpserver} :  $(date) "
    fi

    LOCALDATE=$(date +"%d%m%Y")
    if [ "$INTERNETDATE" != "$LOCALDATE" ]; then
        echo "Sync with NTP server ${ntpserver} :  $(date) Fail !!!"
        echo "ERROR !!! The system date is incorrect."
        exit 99        
    fi
  fi
    #getvarsmshell "$MODEL"

}

function cleanloader() {

    echo "Clearing local redpill files"
    sudo rm -rf /home/tc/redpill*
    sudo rm -rf /home/tc/*tgz

    cleanupmemory

}

# 빌드(성공/실패 무관) 직후 메모리 정리: 페이지캐시/dentry/inode 캐시를 반환하고,
# 스왑을 껐다 켜서 더 이상 필요없어진 스왑아웃 페이지를 회수한다.
# 연속으로 여러 모델을 빌드할 때 스왑 사용량이 줄지 않고 누적되는 현상을 완화하기 위함.
function cleanupmemory() {

    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1

    # zram(1차, 우선순위 200) + 디스크 스왑파일(2차, 우선순위 100)이 동시에
    # 있을 수 있으므로 첫 번째 장치만이 아니라 전체를 순회하며 각자의 기존
    # 우선순위를 유지한 채 off/on 한다.
    swapon --show=NAME,PRIO --noheadings 2>/dev/null | while read -r swap_dev swap_prio; do
        [ -z "${swap_dev}" ] && continue
        sudo swapoff "${swap_dev}" 2>/dev/null
        sudo swapon -p "${swap_prio:-100}" "${swap_dev}" 2>/dev/null
    done

}

function backupxtcrp() {

    TGZ_FILE="${1}/xtcrp.tgz"
    BACKUP_FILE="/dev/shm/xtcrp.tgz.bak"
    TAR_UNZIPPED="/dev/shm/xtcrp.tar"
    SOURCE_FILE="/home/tc/user_config.json"
    
    if [ -f "$TGZ_FILE" ]; then
        if [ ! -f "$SOURCE_FILE" ]; then
            echo "Error: Source file ${SOURCE_FILE} does not exist!"
            exit 1
        fi
    
        echo "Adding ${SOURCE_FILE} to ${TGZ_FILE} !!!"
    
        # 백업 생성
        sudo cp "$TGZ_FILE" "$BACKUP_FILE"

        sudo cp "$TGZ_FILE" /dev/shm/xtcrp.tgz
    
        # Decompress the existing archive
        if ! sudo gunzip /dev/shm/xtcrp.tgz; then
            echo "Error: Failed to decompress ${TGZ_FILE}. Restoring backup."
            sudo mv "$BACKUP_FILE" "$TGZ_FILE"
            exit 1
        fi
    
        # Add the file to the archive with relative path
        if ! sudo tar --append -C "$(dirname "$SOURCE_FILE")" --file="$TAR_UNZIPPED" "$(basename "$SOURCE_FILE")"; then
            echo "Error: Failed to add ${SOURCE_FILE} to archive."
            sudo mv "$BACKUP_FILE" "$TGZ_FILE"
            exit 1
        fi
    
        # Compress the archive again and save with the original name
        if ! sudo sh -c "gzip -c $TAR_UNZIPPED > $TGZ_FILE"; then
            echo "Error: Failed to compress ${TAR_UNZIPPED}. Restoring original file."
            sudo mv "$BACKUP_FILE" "$TGZ_FILE"
            exit 1
        fi
    
        # Replace original file with compressed archive and clean up temporary files
        sudo rm -f "$TAR_UNZIPPED" "$BACKUP_FILE"
    
        echo "Successfully added ${SOURCE_FILE} to ${TGZ_FILE}."
    else
        echo "Error: Target archive ${TGZ_FILE} does not exist!"
    fi

}

# ============================================================================
# 개선된 backuploader() 함수
# 
# 기능 개선사항:
# 1. /mnt/${tcrppart} 여유공간 사전 계산
# 2. xtcrp.tgz 및 mydata.tgz를 /dev/shm/ 에서 압축
# 3. 용량 초과 시 /mnt/${tcrppart}/auxfiles/*.pat 파일 임의 1개 삭제
# 4. 기존 sudo 권한 삭제 로직 참조
# ============================================================================
function backuploader() {

    # Define the path to the file
    local FILE_PATH="/opt/.filetool.lst"

    sudo ln -sf /home/tc/menu.sh /usr/bin/menu.sh
    sudo ln -sf /home/tc/monitor.sh /usr/bin/monitor.sh
    sudo ln -sf /home/tc/ntp.sh /usr/bin/ntp.sh

    # Define the patterns to be added
    PATTERNS=("etc/motd" "usr/bin/menu.sh" "usr/bin/monitor.sh" "usr/bin/ntp.sh" "usr/sbin/sz" "usr/sbin/rz" "usr/local/bin/bspatch" "usr/bin/pigz")
    
    # 파일이 존재하고 FILE_PATH에 없는 경우만 추가
    for pattern in "${PATTERNS[@]}"; do
        if [ -f "/$pattern" ]; then
            # 중복 확인 후 추가
            if [ -f "$FILE_PATH" ] && grep -qF "$pattern" "$FILE_PATH"; then
                echo "Already exists in list: $pattern" >&2
            else
                echo "$pattern" >> "$FILE_PATH"
                echo "Added to backup list: $pattern" >&2
            fi
        else
            echo "File not found, skipping: /$pattern" >&2
        fi
    done 2>/dev/null  # 전체 오류 출력 억제


    local thread=$(nproc)
    local backup_path="/mnt/${tcrppart}"
    local auxfiles_path="${backup_path}/auxfiles"
    local shm_path="/dev/shm"
    
    # 로깅 함수 (기존 코드와 호환)
    local log_prefix="[BACKUP]"
    
    echo "${log_prefix} Backup loader process starting..."
    
    # ========================================================================
    # STEP 1: /mnt/${tcrppart}의 여유공간 계산
    # ========================================================================
    echo "${log_prefix} Calculating available space on ${backup_path}..."
    
    local avail_space_kb=$(df "${backup_path}" | tail -1 | awk '{print $4}')
    local avail_space_mb=$((avail_space_kb / 1024))
    
    echo "${log_prefix} Available space: ${avail_space_mb} MB"
    
    # 필요한 최소 여유공간 (버퍼: 100MB)
    local min_required_space=$((150 + 100))  # xtcrp.tgz + mydata.tgz + 버퍼
    
    if [ ${avail_space_mb} -lt ${min_required_space} ]; then
        echo "${log_prefix} WARNING: Low disk space (${avail_space_mb}MB < ${min_required_space}MB)"
        echo "${log_prefix} Will attempt to free up space by removing old .pat files..."
    fi
    
    # ========================================================================
    # STEP 2: /dev/shm에서 xtcrp.tgz 압축
    # ========================================================================
    echo "${log_prefix} Compressing xtcrp to ${shm_path}/xtcrp.tgz..."
    
    local xtcrp_shm="${shm_path}/xtcrp.tgz"
    local xtcrp_dest="${backup_path}/xtcrp.tgz"
    local alpine_no_mydata=0
    
    # 기존 /dev/shm 파일 정리
    if [ -f "${xtcrp_shm}" ]; then
        sudo rm -f "${xtcrp_shm}"
    fi
    
    # xtcrp 압축 (ramdisk에서 수행하여 속도 향상)
    if [ "${BUS}" != "block" ]; then
        # BIOS_CNT가 1이고 FRKRNL이 YES인 경우 특별 처리
        if [ ${BIOS_CNT} -eq 1 ] && [ "${FRKRNL}" = "YES" ]; then
            backupxtcrp "${backup_path}"
            return $?
        else
            # 표준 백업: tar + pigz 사용
            if ! sudo sh -c "cd . && tar -cf - . | pigz -p ${thread}" > "${xtcrp_shm}" 2>/dev/null; then
                echo "${log_prefix} ERROR: Failed to create xtcrp.tgz in ${shm_path}!"
                return 1
            fi
        fi
    else
        # BUS == block 인 경우
        if ! sudo sh -c "cd . && tar -cf - . | pigz -p ${thread}" > "${xtcrp_shm}" 2>/dev/null; then
            echo "${log_prefix} ERROR: Failed to create xtcrp.tgz in ${shm_path}!"
            return 1
        fi
    fi
    
    echo "${log_prefix} xtcrp.tgz created successfully in ${shm_path}"
    
    # ========================================================================
    # STEP 3: /dev/shm에서 mydata.tgz 압축
    # ========================================================================
    echo "${log_prefix} Compressing mydata to ${shm_path}/mydata.tgz..."
    
    local mydata_shm="${shm_path}/mydata.tgz"
    local mydata_dest="${backup_path}/mydata.tgz"
    
    # 기존 /dev/shm 파일 정리
    if [ -f "${mydata_shm}" ]; then
        sudo rm -f "${mydata_shm}"
    fi
    
    if [ "${FRKRNL}" = "YES" ]; then
        # 기존 mydata.tgz가 있으면 먼저 처리
        if [ -f "${mydata_dest}" ]; then
            local home_size=$(du -sh /home/tc | awk '{print $1}')
            echo "${log_prefix} Current /home/tc size: ${home_size}"
            echo "${log_prefix} Please ensure using latest 1GB img before backup"
            echo "${log_prefix} Note: Keep /home/tc size less than 1GB for image compatibility"
            
            # 기존 파일에 새로운 userconfig.json 추가
            echo "${log_prefix} Adding updated userconfig.json to mydata.tgz..."
        else
            echo "${log_prefix} Creating new mydata.tgz..."
        fi

        local existing_file="/mnt/tcrp/mydatab.tgz"
        local extract_dir="${shm_path}/mydatab"
        
        # /mnt/tcrp/mydatab.tgz 존재 확인 및 처리
        if [ -f "${existing_file}" ]; then
            sudo rm -rf "${extract_dir}"
            sudo mkdir -p "${extract_dir}"
            if ! sudo tar -xzf "${existing_file}" -C "${extract_dir}"; then
                echo "${log_prefix} ERROR: Failed to extract ${existing_file} to ${extract_dir}!"
                read answer
                return 1
            fi
            
            # /home/tc 내용을 /dev/shm/mydatab에 overwrite copy
            if ! sudo cp -a /home/tc/ "${extract_dir}/home/"; then
                echo "${log_prefix} ERROR: Failed to rsync /home/tc to ${extract_dir}!"
                read answer
                return 1
            fi
            
            # /dev/shm/mydatab를 루트처럼 사용해 압축 (절대경로처럼 동작)
            if ! sudo sh -c \
                "cd ${extract_dir} && \\
                 tar -cf - . | \\
                 pigz -p ${thread}" > "${mydata_shm}" 2>/dev/null; then
                echo "${log_prefix} ERROR: Failed to create mydata.tgz from ${extract_dir}!"
                read answer
                return 1
            fi
            sudo rm -rf "${extract_dir}"
        fi
        
    else
        if is_alpine; then
            # Alpine의 영속화는 lbu(apkovl)가 담당하므로 TinyCore 전용
            # mydata.tgz를 만들지 않는다.
            echo "${log_prefix} Alpine: persisting settings with lbu commit..."
            sudo lbu commit -d
            alpine_no_mydata=1
        else
            sudo /bin/tar -C / -T /opt/.filetool.lst -X /opt/.xfiletool.lst -cf - | pigz -p ${thread} > ${shm_path}/mydata.tgz
        fi
    fi
    
    if [ ${alpine_no_mydata} -eq 0 ]; then
        echo "${log_prefix} mydata.tgz created successfully in ${shm_path}"
    else
        echo "${log_prefix} Alpine: skipping mydata.tgz (using apkovl)"
    fi
    
    # ========================================================================
    # STEP 4: /dev/shm 파일 크기 확인 및 공간 부족 시 처리
    # ========================================================================
    echo "${log_prefix} Checking total backup size..."
    
    local xtcrp_size=0
    local mydata_size=0
    local total_backup_size=0
    
    if [ -f "${xtcrp_shm}" ]; then
        xtcrp_size=$(stat -f%z "${xtcrp_shm}" 2>/dev/null || stat -c%s "${xtcrp_shm}" 2>/dev/null)
        xtcrp_size=$((xtcrp_size / 1024 / 1024))  # Convert to MB
    fi
    
    if [ ${alpine_no_mydata} -eq 0 ] && [ -f "${mydata_shm}" ]; then
        mydata_size=$(stat -f%z "${mydata_shm}" 2>/dev/null || stat -c%s "${mydata_shm}" 2>/dev/null)
        mydata_size=$((mydata_size / 1024 / 1024))  # Convert to MB
    fi
    
    total_backup_size=$((xtcrp_size + mydata_size))
    
    echo "${log_prefix} Backup sizes - xtcrp: ${xtcrp_size}MB, mydata: ${mydata_size}MB, total: ${total_backup_size}MB"
    echo "${log_prefix} Available space: ${avail_space_mb}MB"
    
    # 여유공간이 부족한 경우 처리
    if [ ${avail_space_mb} -lt $((total_backup_size + 50)) ]; then
        echo "${log_prefix} WARNING: Insufficient space detected!"
        echo "${log_prefix} Attempting to free space by removing old .pat files..."
        
        # 여유공간 충분할 때까지 .pat 파일 삭제
        while [ ${avail_space_mb} -lt $((total_backup_size + 50)) ]; do
            if [ ! -d "${auxfiles_path}" ]; then
                echo "${log_prefix} ERROR: ${auxfiles_path} directory not found!"
                return 1
            fi
            
            # .pat 파일 목록 확인
            local pat_files=($(find "${auxfiles_path}" -maxdepth 1 -name "*.pat" -type f 2>/dev/null))
            
            if [ ${#pat_files[@]} -eq 0 ]; then
                echo "${log_prefix} ERROR: No .pat files found to delete!"
                echo "${log_prefix} Backup aborted due to insufficient space!"
                return 1
            fi
            
            # 임의의 .pat 파일 선택 (RANDOM 사용)
            local random_idx=$((RANDOM % ${#pat_files[@]}))
            local pat_file_to_delete="${pat_files[${random_idx}]}"
            local pat_filename=$(basename "${pat_file_to_delete}")
            
            echo "${log_prefix} Deleting ${pat_filename}..."
            
            # sudo 권한으로 파일 삭제 (기존 로직 참조)
            if sudo rm -vf "${pat_file_to_delete}" 2>/dev/null; then
                local pat_size=$(stat -f%z "${pat_file_to_delete}" 2>/dev/null || stat -c%s "${pat_file_to_delete}" 2>/dev/null)
                pat_size=$((pat_size / 1024 / 1024))
                echo "${log_prefix} Successfully deleted ${pat_filename} (${pat_size}MB recovered)"
                
                # 여유공간 재계산
                avail_space_kb=$(df "${backup_path}" | tail -1 | awk '{print $4}')
                avail_space_mb=$((avail_space_kb / 1024))
                echo "${log_prefix} Available space after cleanup: ${avail_space_mb}MB"
            else
                echo "${log_prefix} ERROR: Failed to delete ${pat_filename}!"
                return 1
            fi
        done
    fi
    
    # ========================================================================
    # STEP 5: /dev/shm에서 최종 목적지로 파일 이동
    # ========================================================================
    echo "${log_prefix} Moving backup files to ${backup_path}..."
    backup_loader
    # xtcrp.tgz 이동
    if [ -f "${xtcrp_shm}" ]; then
        if sudo dd if="${xtcrp_shm}" of="${xtcrp_dest}" conv=fsync status=progress 2>/dev/null; then
            echo "${log_prefix} xtcrp.tgz moved successfully"
        else
            echo "${log_prefix} ERROR: Failed to move xtcrp.tgz!"
            return 1
        fi
    fi
    
    # mydata.tgz 이동 (Alpine은 lbu/apkovl을 사용하므로 생략)
    if [ ${alpine_no_mydata} -eq 0 ] && [ -f "${mydata_shm}" ]; then
        if sudo dd if="${mydata_shm}" of="${mydata_dest}" conv=fsync status=progress 2>/dev/null; then
            echo "${log_prefix} mydata.tgz moved successfully"
        else
            echo "${log_prefix} ERROR: Failed to move mydata.tgz!"
            return 1
        fi
    fi
    
    # ========================================================================
    # STEP 6: /dev/shm 정리 및 마무리
    # ========================================================================
    echo "${log_prefix} Cleaning up temporary files..."
    
    sudo rm -f "${xtcrp_shm}" "${mydata_shm}"
    
    # fsync로 디스크 동기화
    sync
    sudo sync
    
    if [ $? -eq 0 ]; then
        echo "${log_prefix} Backup completed successfully!"
        return 0
    else
        echo "${log_prefix} ERROR: Backup completed with errors!"
        return 1
    fi
}

function backuploader_old() {

  thread=$(nproc)
  if [ "${BUS}" != "block"  ]; then
#Apply pigz for fast backup  
    getpigz

    # backup xtcrp together
    if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then
        backupxtcrp "/mnt/${tcrppart}"
        return
    else
        sudo sh -c "tar -cf - ./ | pigz -p ${thread} > /mnt/${tcrppart}/xtcrp.tgz"
        if [ $? -ne 0 ]; then
            cecho r "An error occurred while backing up the loader!!!"
        else
            cecho y "Successfully backed up the loader!!!"
        fi
    fi    

    if [ "$FRKRNL" = "YES" ]; then
        TGZ_FILE="/mnt/${tcrppart}/mydata.tgz"
        TAR_UNZIPPED="/mnt/${tcrppart}/mydata.tar"
        SOURCE_FILE="/home/tc/user_config.json"
        # Check if the compressed file exists
        if [ -f "$TGZ_FILE" ]; then
            echo "Adding ${SOURCE_FILE} to ${TGZ_FILE} !!!"
            # Decompress the existing archive
            sudo gunzip "$TGZ_FILE"
            # Add the file to the archive
            sudo tar --append -C / --file="$TAR_UNZIPPED" "$SOURCE_FILE"
            # Compress the archive again and save with the original name
            sudo sh -c "gzip -c $TAR_UNZIPPED > $TGZ_FILE"
            # Remove the decompressed temporary file
            sudo rm "$TAR_UNZIPPED"
        fi
        return
    fi
    
    #if [ $(cat /usr/bin/filetool.sh | grep pigz | wc -l ) -eq 0 ]; then
    #    sudo sed -i "s/\-czvf/\-cvf \- \| pigz -p "${thread}" \> \/dev\/shm\/\${MYDATA}.tgz \&\& cp \/dev\/shm\/\${MYDATA}.tgz /g" /usr/bin/filetool.sh
    #    sudo sed -i "s/\-czf/\-cf \- \| pigz -p "${thread}" \> \/dev\/shm\/\${MYDATA}.tgz \&\& cp \/dev\/shm\/\${MYDATA}.tgz /g" /usr/bin/filetool.sh
    #fi
  fi  
#    loaderdisk=$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)
    homesize=$(du -sh /home/tc | awk '{print $1}')

    echo "Please make sure you are using the latest 1GB img before using backup option"
    echo "Current /home/tc size is $homesize , try to keep it less than 1GB as it might not fit into your image"

    echo "Should i update the $loaderdisk with your current files [Yy/Nn]"
    readanswer
    if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
        # Define the path to the file
        FILE_PATH="/opt/.filetool.lst"

        sudo ln -sf /home/tc/menu.sh /usr/bin/menu.sh
        sudo ln -sf /home/tc/monitor.sh /usr/bin/monitor.sh
        sudo ln -sf /home/tc/ntp.sh /usr/bin/ntp.sh

        # Define the patterns to be added
        PATTERNS=("etc/motd" "usr/bin/menu.sh" "usr/bin/monitor.sh" "usr/bin/ntp.sh" "usr/sbin/sz" "usr/sbin/rz" "usr/local/bin/bspatch" "usr/bin/pigz")
        
        # 파일이 존재하고 FILE_PATH에 없는 경우만 추가
        for pattern in "${PATTERNS[@]}"; do
            if [ -f "/$pattern" ]; then
                # 중복 확인 후 추가
                if [ -f "$FILE_PATH" ] && grep -qF "$pattern" "$FILE_PATH"; then
                    echo "Already exists in list: $pattern" >&2
                else
                    echo "$pattern" >> "$FILE_PATH"
                    echo "Added to backup list: $pattern" >&2
                fi
            else
                echo "File not found, skipping: /$pattern" >&2
            fi
        done 2>/dev/null  # 전체 오류 출력 억제

        if is_alpine; then
            # Alpine 이식: /opt/.filetool.lst(TC filetool.sh 전용)가 없어 mydata.tgz
            # 생성이 불필요. 실제 영속화는 lbu(apkovl)이므로 lbu commit으로 대체.
            cecho y "Alpine: persisting settings with lbu commit (instead of mydata.tgz)..."
            sudo lbu commit -d
            backup_loader
        else
            cecho y "Backing up home files to /mnt/${tcrppart}/mydata.tgz"
            sudo /bin/tar -C / -T /opt/.filetool.lst -X /opt/.xfiletool.lst -cf - | pigz -p ${thread} > /dev/shm/mydata.tgz
            backup_loader
            sudo dd if=/dev/shm/mydata.tgz of=/mnt/${tcrppart}/mydata.tgz conv=fsync status=progress
            if [ $? -ne 0 ]; then
                echo "Error: Couldn't backup files"
            fi
        fi
    else
        echo "OK, keeping last status"
    fi

}

function checkfilechecksum() {

    local FILE="${1}"
    local EXPECTED_SHA256="${2}"
    local SHA256_RESULT=$(sha256sum ${FILE})
    if [ "${SHA256_RESULT%% *}" != "${EXPECTED_SHA256}" ]; then
        echo "The ${FILE} is corrupted, expected sha256 checksum ${EXPECTED_SHA256}, got ${SHA256_RESULT%% *}"
        #rm -f "${FILE}"
        #echo "Deleted corrupted file ${FILE}. Please re-run your action!"
        echo "Please delete the file ${FILE} manualy and re-run your command!"
        exit 99
    fi

}

function tcrpfriendentry() {
    cat <<EOF
menuentry 'Tiny Core Friend $MODEL ${BUILD} Update ${smallfixnumber} ${DMPM} ${MDLNAME}:${MLMETHOD} v${rploaderver}' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8
        echo Loading initramfs...
        initrd /initrd-friend
        echo Booting TinyCore Friend
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function tcrpentry_junior() {
    cat <<EOF
menuentry 'Re-Install DSM of $MODEL ${BUILD} Update ${smallfixnumber} ${DMPM} ${MDLNAME}:${MLMETHOD}' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8 force_junior
        echo Loading initramfs...
        initrd /initrd-friend
        echo Booting TinyCore Friend
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function xtcrpconfigureentry() {
    cat <<EOF
menuentry 'xTCRP Configure Boot Loader (Loader Build)' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8 IWANTTOCONFIGURE
        echo Loading initramfs to configure loader...
        initrd /initrd-friend
        echo Loding RAMDISK to configure loader...
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function postupdateentry() {
    cat <<EOF
menuentry 'Tiny Core PostUpdate (RamDisk Update) $MODEL ${BUILD} Update ${smallfixnumber} ${DMPM} ${MDLNAME}:${MLMETHOD}' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 
        echo Loading initramfs...
        initrd /initrd-friend
        echo Booting TinyCore Friend
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function tinyjotfunc() {
    cat <<EOF
function savedefault {
    saved_entry="\${chosen}"
    save_env --file \$prefix/grubenv saved_entry
    set gfxpayload=keep
    set color_normal=green/black    
    echo "TCRP-MSHELL Direct-Boot Version : ${rploaderver}"
    echo "BUS Type:   ${BUS}"
    echo -n "Boot Time: "; date
    echo ""
    echo "Model   : ${MODEL}(${ORIGIN_PLATFORM})"
    echo "Version : ${BUILD}"
    echo "Kernel  : ${KVER}"
    echo "Module  : ${MDLNAME}-${MLMETHOD}"
    echo "DMI     : $(dmesg 2>/dev/null | grep -i "DMI:" | head -1 | sed 's/\[.*\] DMI: //i')"
    echo "CPU     : $(awk -F': ' '/model name/ {print $2}' /proc/cpuinfo | uniq)"
    echo "MEM     : $(awk '/MemTotal:/ {printf "%.2f", $2 / 1024}' /proc/meminfo) MB"
    echo ""
    set color_normal=light-cyan/black
    echo "Cmdline:"
    echo "${CMD_LINE}"
    echo ""
    echo "Access http://find.synology.com/ or http://${IP}:5000 to connect the DSM via web."
    echo ""
}    
EOF
}

function tcrpjotentry() {
    cat <<EOF
menuentry 'RedPill $MODEL ${BUILD} Direct-Boot (USB/SATA, Verbose, ${DMPM} ${MDLNAME}-${MLMETHOD})' {
        savedefault
        search --set=root --fs-uuid 6234-C863 --hint hd0,msdos3
        echo Loading DSM Linux... ${DMPM}
        linux /zImage-dsm ${CMD_LINE}
        echo Loading DSM initramfs...
        initrd /initrd-dsm
        echo Starting kernel with USB/SATA boot
        echo
        echo "HTTP, Synology Web Assistant (BusyBox httpd) service may take 20 - 40 seconds."
        echo "(Network access is not immediately available)"
        echo "Kernel loading has started, nothing will be displayed here anymore ..."
        echo -en "Enter the following address in your web browser :"
        echo " http://${IP}:5000"
}
EOF
}

function tcrpjot_junior() {
    cat <<EOF
menuentry 'Re-Install DSM of $MODEL ${BUILD} Direct-Boot Update 0 ${DMPM} ${MDLNAME}-${MLMETHOD}' {    
        savedefault
        search --set=root --fs-uuid 6234-C863 --hint hd0,msdos3
        echo Loading DSM Linux... ${DMPM}
        linux /zImage-dsm ${CMD_LINE} force_junior
        echo Loading DSM initramfs...
        initrd /initrd-dsm
        echo Starting kernel with USB/SATA boot
        echo
        echo "HTTP, Synology Web Assistant (BusyBox httpd) service may take 20 - 40 seconds."
        echo "(Network access is not immediately available)"
        echo "Kernel loading has started, nothing will be displayed here anymore ..."
        echo -en "Enter the following address in your web browser :"
        echo " http://${IP}:5000"
}
EOF
}

function showsyntax() {
    cat <<EOF
$(basename ${0})

Version : $rploaderver
----------------------------------------------------------------------------------------

Usage: ${0} <action> <platform version> <static or compile module> [extension manager arguments]

Actions: build, ext, download, clean, listmod, serialgen, identifyusb, patchdtc, 
satamap, backup, backuploader, restoreloader, restoresession, mountdsmroot, postupdate,
mountshare, version, monitor, getgrubconf, help

----------------------------------------------------------------------------------------
Available platform versions:
----------------------------------------------------------------------------------------
$(getPlatforms)
----------------------------------------------------------------------------------------
Check custom_config.json for platform settings.
EOF
}

function showhelp() {
    cat <<EOF
$(basename ${0})

Version : $rploaderver
----------------------------------------------------------------------------------------
Usage: ${0} <action> <platform version> <static or compile module> [extension manager arguments]

Actions: build, ext, download, clean, listmod, serialgen, identifyusb, patchdtc, 
satamap, backup, backuploader, restoreloader, restoresession, mountdsmroot, postupdate, 
mountshare, version, monitor, bringfriend, downloadupgradepat, help 

- build <platform> <option> : 
  Build the 💊 RedPill LKM and update the loader image for the specified platform version and update
  current loader.

  Valid Options:     static/compile/manual/junmod/withfriend

  ** withfriend add the TCRP friend and a boot option for auto patching 
  
- ext <platform> <option> <URL> 
  Manage extensions using redpill extension manager. 

  Valid Options:  add/force_add/info/remove/update/cleanup/auto . Options after platform 
  
  Example: 
  rploader ext apollolake-7.0.1-42218 add https://raw.githubusercontent.com/PeterSuh-Q3/rp-ext/master/e1000/rpext-index.json
  or for auto detect use 
  rploader ext apollolake-7.0.1-42218 auto 
  
- download <platform> :
  Download redpill sources only
  
- clean :
  Removes all cached and downloaded files and starts over clean
 
- listmods <platform>:
  Tries to figure out any required extensions. This usually are device modules
  
- serialgen <synomodel> <option> :
  Generates a serial number and mac address for the following platforms 
  DS3615xs DS3617xs DS916+ DS918+ DS920+ DS3622xs+ FS6400 DVA3219 DVA3221 DS1621+ DVA1622 DS2422+ RS4021xs+ DS923+
  
  Valid Options :  realmac , keeps the real mac of interface eth0
  
- identifyusb :    
  Tries to identify your loader usb stick VID:PID and updates the user_config.json file 
  
- patchdtc :       
  Tries to identify and patch your dtc model for your disk and nvme devices. If you want to have 
  your manually edited dts file used convert it to dtb and place it under /home/tc/custom-modules
  
- satamap :
  Tries to identify your SataPortMap and DiskIdxMap values and updates the user_config.json file 
  
- backup :
  Backup and make changes /home/tc changed permanent to your loader disk. Next time you boot,
  your /home will be restored to the current state.
  
- backuploader :
  Backup current loader partitions to your TCRP partition
  
- restoreloader :
  Restore current loader partitions from your TCRP partition
  
- restoresession :
  Restore last user session files. (extensions and user_config.json)
  
- mountdsmroot :
  Mount DSM root for manual intervention on DSM root partition
  
- postupdate :
  Runs a postupdate process to recreate your rd.gz, zImage and custom.gz for junior to match root
  
- mountshare :
  Mounts a remote CIFS working directory

- version <option>:
  Prints rploader version and if the history option is passed then the version history is listed.

  Valid Options : history, shows rploader release history.

- monitor :
  Prints system statistics related to TCRP loader 

- getgrubconf :
  Checks your user_config.json file variables against current grub.cfg variables and updates your
  user_config.json accordingly

- bringfriend
  Downloads TCRP friend and makes it the default boot option. TCRP Friend is here to assist with
  automated patching after an upgrade. No postupgrade actions will be required anymore, if TCRP
  friend is left as the default boot option.

- downloadupgradepat
  Downloads a specific upgade pat that can be used for various troubleshooting purposes

- removefriend
  Reverse bringfriend actions and remove TCRP from your loader 

- help:           Show this page

----------------------------------------------------------------------------------------
Version : $rploaderver
EOF

}

function checkUserConfig() {

  SN=$(jq -r -e '.extra_cmdline.sn' "$userconfigfile")
  MACADDR1=$(jq -r -e '.extra_cmdline.mac1' "$userconfigfile")
  netif_num=$(jq -r -e '.extra_cmdline.netif_num' $userconfigfile)
  netif_num_cnt=$(cat $userconfigfile | grep \"mac | wc -l)
  
  tz="US"

  if [ "${BUS}" = "block"  ]; then
    [ ! -n "${SN}" ] && SN=$(echo $(generateSerial ${MODEL})) && writeConfigKey "extra_cmdline" "sn" "${SN}"
    [ ! -n "${MACADDR1}" ] && MACADDR1=`./macgen.sh "randommac" "eth0" ${MODEL}` && writeConfigKey "extra_cmdline" "mac1" "${MACADDR1}"
  fi

  if [ ! -n "${SN}" ]; then
    eval "echo \${MSG${tz}36}"
    msgalert "Synology serial number not set. Check user_config.json again. Abort the loader build !!!!!!"
    exit 99
  fi
  
  if [ ! -n "${MACADDR1}" ]; then
    eval "echo \${MSG${tz}37}"
    msgalert "The first MAC address is not set. Check user_config.json again. Abort the loader build !!!!!!"
    exit 99
  fi

  if [ "${BUS}" != "block"  ]; then
      if [ $netif_num != $netif_num_cnt ]; then
        echo "netif_num = ${netif_num}"
        echo "number of mac addresses = ${netif_num_cnt}"       
        eval "echo \${MSG${tz}38}"
        msgalert "The netif_num and the number of mac addresses do not match. Check user_config.json again. Abort the loader build !!!!!!"
        exit 99
      fi  
  fi
}

###############################################################################
# Replace/remove/add values in .conf K=V file
# 1 - file
# 2 - key
# 3 - value
function _set_conf_kv() {
  # Delete
  if [ -z "${3}" ]; then
    sed -i "/^${2}=/d" "${1}" 2>/dev/null
    return $?
  fi

  # Replace
  if grep -q "^${2}=" "${1}" 2>/dev/null; then
    sed -i "s#^${2}=.*#${2}=\"${3}\"#" "${1}" 2>/dev/null
    return $?
  fi

  # Add if doesn't exist
  mkdir -p "$(dirname "${1}" 2>/dev/null)" 2>/dev/null
  echo "${2}=\"${3}\"" >>"${1}" 2>/dev/null
  return $?
}

function buildloader() {

#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    local_cache="/mnt/${tcrppart}/auxfiles"

checkmachine

    [ "$1" == "junmod" ] && JUNLOADER="YES" || JUNLOADER="NO"

    [ -d $local_cache ] && echo "Found tinycore cache folder, linking to home/tc/custom-module" && [ ! -d /home/tc/custom-module ] && ln -s $local_cache /home/tc/custom-module

    DMPM="$(jq -r -e '.general.devmod' $userconfigfile)"
    msgnormal "Device Module Processing Method is ${DMPM}"

    cd /home/tc

    echo -n "Checking user_config.json : "
    if jq -s . user_config.json >/dev/null; then
        echo "Done"
    else
        echo "Error : Problem found in user_config.json"
        exit 99
    fi

    echo "Clean up extension files before building!!!"
    removemodelexts    

    [ ! -e /lib64 ] && [ ! -L /lib64 ] && sudo ln -s /lib /lib64
    [ ! -e /lib64/libbz2.so.1 ] && [ ! -L /lib64/libbz2.so.1 ] && sudo ln -s /usr/local/lib/libbz2.so.1.0.8 /lib64/libbz2.so.1
    [ ! -f /home/tc/redpill-load/user_config.json ] && ln -s /home/tc/user_config.json /home/tc/redpill-load/user_config.json
    [ ! -d cache ] && mkdir -p /home/tc/redpill-load/cache
    cd /home/tc/redpill-load

# download commands...
    if [ ${TARGET_REVISION} -gt 42218 ]; then
        echo "Found build request for revision greater than 42218"
        downloadextractor
        processpat
    else
        [ -d /home/tc/custom-module ] && sudo cp -adp /home/tc/custom-module/*${TARGET_REVISION}*.pat /home/tc/redpill-load/cache/
    fi

    [ -d /home/tc/redpill-load ] && cd /home/tc/redpill-load

    [ ! -d /home/tc/redpill-load/custom/extensions ] && mkdir -p /home/tc/redpill-load/custom/extensions

# compilation commands...       
st "extensions" "Extensions collection" "Extensions collection..."
[ "${BUS}" != "block" ] && log_build_step "Collecting extensions" 6 12
    addrequiredexts

# image creation commands...
st "make loader" "Creation boot loader" "Compile n make boot file."
[ "${BUS}" != "block" ] && log_build_step "Creation boot loader" 7 12
st "copyfiles" "Copying files to P1,P2" "Copied boot files to the loader"
[ "${BUS}" != "block" ] && log_build_step "Copying files to P1,P2" 8 12
    UPPER_ORIGIN_PLATFORM=$(echo ${ORIGIN_PLATFORM} | tr '[:lower:]' '[:upper:]')

    #if echo ${kver5platforms} | grep -qw ${ORIGIN_PLATFORM}; then
    #    vkersion=${major}${minor}_${KVER}
    #else
    #    vkersion=${KVER}
    #fi

    #if [ "$WITHFRIEND" != "YES" ]; then
    #    jsonfile=$(jq "del(.[\"localrss\"])" /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
    #fi 
    
    if [ "$JUNLOADER" == "YES" ]; then
        echo "jun build option has been specified, so JUN MOD loader will be created"
        # jun's mod must patch using custom.gz from the first partition, so you need to fix the partition.
        sed -i "s/BRP_OUT_P2}\/\${BRP_CUSTOM_RD_NAME/BRP_OUT_P1}\/\${BRP_CUSTOM_RD_NAME/g" /home/tc/redpill-load/build-loader.sh
        $( [ "$FRKRNL" = "NO" ] && echo sudo ) BRP_JUN_MOD=1 BRP_DEBUG=0 BRP_USER_CFG=user_config.json ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${KVER} ${SYNOMODEL}
    else
        $( [ "$FRKRNL" = "NO" ] && echo sudo ) ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${KVER} ${SYNOMODEL}
    fi

    [ $? -ne 0 ] && echo "FAILED : Loader creation failed check the output for any errors" && exit 99
    msgnormal "Chkeck Result of build-loader"
    ls -l /mnt/${loaderdisk}1/
    ls -l /mnt/${loaderdisk}2/
    ls -l /mnt/${loaderdisk}3/

    msgnormal "Modify Jot Menu entry"
    # backup Jot menuentry to tempentry
    # Get Only USB Part from line 61 to 80
    tempentry=$(cat /tmp/grub.cfg | head -n 80 | tail -n 20)
    #if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
    #    sudo sed -i '61,80d' /tmp/grub.cfg
    #else
        sudo sed -i '43,80d' /tmp/grub.cfg
    #fi
    echo "$tempentry" > /tmp/tempentry.txt
    # Append background to grub.cfg
    #if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
    #    echo
    #else
        sudo tee -a /tmp/grub.cfg < /home/tc/grubbkg.cfg
    #fi
    
    if [ "$WITHFRIEND" = "YES" ]; then
        echo
    else
        sudo sed -i "s/light-magenta/white/" /tmp/grub.cfg
        sudo sed -i '31,34d' /tmp/grub.cfg
        # Check dom size and set max size accordingly for jot
        if [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 5 ]; then
            if [ "${BUS}" != "usb" ]; then
                DOM_PARA="dom_szmax=$(sudo /sbin/fdisk -l /dev/${loaderdisk} | head -1 | awk -F: '{print $2}' | awk '{ print $1*1024}')"
                sed -i "s/earlyprintk/${DOM_PARA} earlyprintk/" /tmp/tempentry.txt
            fi
        fi    
        sed -i "s/${ORIGIN_PLATFORM}/${MODEL}/" /tmp/tempentry.txt
        sed -i "s/earlyprintk/syno_hw_version=${MODEL} earlyprintk/" /tmp/tempentry.txt
    fi

    msgnormal "Replacing set root with filesystem UUID instead"
    sudo sed -i "s/set root=(hd0,msdos1)/search --set=root --fs-uuid $usbpart1uuid --hint hd0,msdos1/" /tmp/tempentry.txt
    sudo sed -i "s/Verbose/Verbose, ${DMPM}/" /tmp/tempentry.txt
    sudo sed -i "s/Linux.../Linux... ${DMPM}/" /tmp/tempentry.txt

    # Share RD of friend kernel with JOT 2023.05.01
    if [ ! -f /home/tc/friend/initrd-friend ] && [ ! -f /home/tc/friend/bzImage-friend ]; then
st "frienddownload" "Friend downloading" "TCRP friend copied to /mnt/${loaderdisk}3"
[ "${BUS}" != "block" ] && log_build_step "Friend downloading" 9 12
        bringoverfriend
        #upgrademan v0.1.3m
    fi

    if [ -f /home/tc/friend/initrd-friend ] && [ -f /home/tc/friend/bzImage-friend ]; then
      if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then 
        sudo dd if=/home/tc/friend/initrd-friend of=/mnt/${loaderdisk}1/initrd-friend conv=fsync status=progress
        sudo dd if=/home/tc/friend/bzImage-friend of=/mnt/${loaderdisk}1/bzImage-friend conv=fsync status=progress
      else
        sudo dd if=/home/tc/friend/initrd-friend of=/mnt/${loaderdisk}3/initrd-friend conv=fsync status=progress
        sudo dd if=/home/tc/friend/bzImage-friend of=/mnt/${loaderdisk}3/bzImage-friend conv=fsync status=progress
      fi  
    fi

    USB_LINE="$(grep -A 5 "USB," /tmp/tempentry.txt | grep linux | cut -c 16-999)"
    if [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 5 ]; then
        SATA_LINE="$(grep -A 5 "SATA," /tmp/tempentry.txt | grep linux | cut -c 16-999)"
        SATA_DOM=$(echo "$SATA_LINE" | grep -oE 'synoboot_satadom=[^ ]+' | cut -d= -f2)
        if [ -n "$SATA_DOM" ]; then
            SATA_LINE="synoboot_satadom=${SATA_DOM} "
        fi        
    fi

    if echo "apollolake geminilake purley" | grep -wq "${ORIGIN_PLATFORM}"; then
        USB_LINE="${USB_LINE} nox2apic"
    fi

    if echo "apollolake geminilake geminilakenk" | grep -wq "${ORIGIN_PLATFORM}"; then
        USB_LINE="${USB_LINE} intel_iommu=igfx_off"
    fi

    if [ "$KVER" == "4.4.180" ]; then
        USB_LINE="${USB_LINE} i915.enable_guc=0"
    fi

    #if echo "geminilake v1000 r1000" | grep -wq "${ORIGIN_PLATFORM}"; then
    #    echo "add modprobe.blacklist=mpt3sas for Device-tree based platforms"
    #    USB_LINE="${USB_LINE} modprobe.blacklist=mpt3sas"
    #fi
    
    USB_LINE="${USB_LINE} pcie_aspm=off"

    if [ -v CPU ]; then
        if [ "${CPU}" == "AMD" ]; then
            echo "Add configuration disable_mtrr_trim for AMD"
            USB_LINE="${USB_LINE} disable_mtrr_trim=1"
        else
            #if echo "epyc7002 apollolake geminilake" | grep -wq "${ORIGIN_PLATFORM}"; then
            #    if [ "$MACHINE" = "VIRTUAL" ]; then
            #        USB_LINE="${USB_LINE} intel_iommu=igfx_off "
            #    fi   
            #fi    
    
            if [ -d "/home/tc/redpill-load/custom/extensions/nvmesystem" ]; then
                echo "Add configuration pci=nommconf for nvmesystem addon"
                USB_LINE="${USB_LINE} pci=nommconf"
            fi
        fi
    fi

    if lspci -nn | grep -qi 'VGA.*\[1002:'; then
        if [ "${MDLNAME}" == "custom-modules" ]; then
            USB_LINE="${USB_LINE} amdgpu.exp_hw_support=1 pci=nocrs"
        fi
    fi

    [ "$WITHFRIEND" == "YES" ] && USB_LINE="${USB_LINE} syno_hw_version=${MODEL}"

    # /tmp/tempentry.txt only has generated defaults. Merge back options that
    # exist solely in general.usb_line before using and persisting CMD_LINE.
    USB_LINE="$(preserve_usb_line_options "${USB_LINE}")"
    USB_LINE="${USB_LINE} "

    if [ "${BUS}" = "usb" ]; then
        CMD_LINE=${USB_LINE}
    else
        [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 5 ] && CMD_LINE=${USB_LINE}+" "+${SATA_LINE} || CMD_LINE=${USB_LINE}
    fi

    #if echo ${nosas5platforms} | grep -qw ${ORIGIN_PLATFORM}; then
    #    writeConfigKey "synoinfo" "supportsas" "no"
    #else
    #    writeConfigKey "synoinfo" "supportsas" "yes"
    #fi

    if [ "$WITHFRIEND" = "YES" ]; then
        echo "Creating tinycore friend entry"
        tcrpfriendentry | sudo tee --append /tmp/grub.cfg
    else
        #Create Jot Information
        tinyjotfunc | sudo tee --append /tmp/grub.cfg    
        echo "Creating tinycore Jot entry"
        tcrpjotentry | sudo tee --append /tmp/grub.cfg        
    fi

    echo "Creating alpinecore configure loader entry"
    alpineentry | sudo tee --append /tmp/grub.cfg
    
    echo "Creating xTCRP configure loader entry"
    xtcrpconfigureentry | sudo tee --append /tmp/grub.cfg

    if [ "$WITHFRIEND" = "YES" ]; then
        echo "Creating tinycore friend Junior Boot entry"    
        tcrpentry_junior | sudo tee --append /tmp/grub.cfg 
    else
        echo "Creating tinycore Jot Junior Boot entry"
        tcrpjot_junior | sudo tee --append /tmp/grub.cfg
    fi

    cd /home/tc/redpill-load

    msgnormal "Entries in Localdisk bootloader : "
    echo "======================================================================="
    grep menuentry /tmp/grub.cfg

    ### Updating user_config.json
    updateuserconfigfield "general" "model" "$MODEL"
    updateuserconfigfield "general" "version" "${BUILD}"
    updateuserconfigfield "general" "redpillmake" "${redpillmake}-${TAG}"
    updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
    zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
    updateuserconfigfield "general" "zimghash" "$zimghash"
    rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
    updateuserconfigfield "general" "rdhash" "$rdhash"
    
    msgwarning "Updated user_config with USB Command Line : $USB_LINE"
    json=$(jq --arg var "${USB_LINE}" '.general.usb_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile
    if [ "$(echo "${KVER:-4}" | cut -d'.' -f1)" -lt 5 ]; then
        msgwarning "Updated user_config with SATA Command Line : $SATA_LINE"
        json=$(jq --arg var "${SATA_LINE}" '.general.sata_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile
    else
        msgwarning "Starting with kernel 5, the unused sata_line element is removed."
        json=$(jq 'del(.general.sata_line)' "$userconfigfile") && echo -E "${json}" | jq . > "$userconfigfile"
    fi    

    sudo cp $userconfigfile /mnt/${loaderdisk}3/

    # Share RD of friend kernel with JOT 2023.05.01
    sudo cp /mnt/${loaderdisk}1/zImage /mnt/${loaderdisk}3/zImage-dsm

    # Repack custom.gz including /usr/lib/modules and /usr/lib/firmware in all_modules 2024.02.18
    # Compining rd.gz and custom.gz

    declare -A SYNOINFO    
    # Read synoinfo from user config
    # SYNOINFO["SN"]="${SN}"
    while read -r KEY VALUE; do
      SYNOINFO["$KEY"]="$VALUE"
    done < <(jq -r '.synoinfo | to_entries[] | "\(.key) \(.value)"' "${userconfigfile}")

    rdtemp="/home/tc/rd.temp"
    
    [ ! -d $rdtemp ] && mkdir $rdtemp
    [ -d $rdtemp ] && cd $rdtemp
    RD_COMPRESSED=$(cat /home/tc/redpill-load/config/${ORIGIN_PLATFORM}/${BUILD}/config.json | jq -r -e ' .extra .compress_rd')

    if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then
        gzs_path="/dev/shm"  
    else
        gzs_path="/mnt/${loaderdisk}3"
    fi

    if [ "$RD_COMPRESSED" = "false" ]; then
        echo "Ramdisk in not compressed "
        cat ${gzs_path}/rd.gz | sudo cpio -idm
    else    
        echo "Ramdisk in compressed " 
        unlzma -dc ${gzs_path}/rd.gz | sudo cpio -idm
    fi

    # 1.0.2.2 Recycle initrd-dsm instead of custom.gz (extract /exts), The priority starts from custom.gz
    if [ -f ${gzs_path}/custom.gz ]; then
        echo "Found custom.gz, so extract from custom.gz " 
        cat ${gzs_path}/custom.gz | sudo cpio -idm  >/dev/null 2>&1
    else
        echo "Not found custom.gz, extract /exts from initrd-dsm" 
        cat ${gzs_path}/initrd-dsm | sudo cpio -idm "*exts*"  >/dev/null 2>&1
        cat ${gzs_path}/initrd-dsm | sudo cpio -idm "*modprobe*"  >/dev/null 2>&1
        cat ${gzs_path}/initrd-dsm | sudo cpio -idm "*rp.ko*"  >/dev/null 2>&1
    fi

    # Network card configuration file
    for N in $(seq 0 7); do
      echo -e "DEVICE=eth${N}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=dhcp\nIPV6_ACCEPT_RA=1" >"/home/tc/ifcfg-eth${N}"
    done
    sudo cp -vf /home/tc/ifcfg-eth* $rdtemp/etc/sysconfig/network-scripts/

    # SA6400 patches for JOT Mode
    if echo ${kver5platforms} | grep -qw ${ORIGIN_PLATFORM}; then
        echo -e "Apply Epyc7002, v1000nk, r1000nk, geminilakenk  Fixes"
        sudo sed -i 's#/dev/console#/var/log/lrc#g' $rdtemp/usr/bin/busybox
        sudo sed -i '/^echo "START/a \\nmknod -m 0666 /dev/console c 1 3' $rdtemp/linuxrc.syno
    fi

    # [netconsole-early] usb_line 의 netconsole= 를 linuxrc.syno 최초 실행 시점에 바로
    # insmod 한다 - on_early 확장 훅보다도 이른 지점(DSM 파티션 마운트/확장 매니저
    # 실행 전)이라 커널 패닉을 더 넓게 잡을 수 있다. netconsole.ko 는 부트타임
    # ramdisk 계열(rd.gz/all-modules/custom-modules)에는 없고 DSM 자체 .pat 안에만
    # 있다. processpat() 의 "이미 캐시됨" 분기는 auxfiles 의 pat 을
    # /home/tc/redpill-load/cache/ 로 mv 하면서도 patfile 변수 자체는 갱신하지
    # 않는 기존 버그가 있어(실기 확인: 캐시 재사용 빌드에서 netconsole.ko 추출
    # 실패), 그 변수에 의존하지 않고 processpat() 과 동일한 우선순위로 직접
    # 경로를 고른다: auxfiles(영구 캐시, 미니팻이면 netconsole.ko 내장되어 있음)
    # 가 있으면 그걸 쓰고, 없으면(첫 빌드라 아직 미니팻화 전) 이번 빌드용으로
    # 막 받은/복호화된 /home/tc/redpill-load/cache/${SYNOMODEL}.pat 을 쓴다.
    NETCONSOLE_KO_SRC="/mnt/${tcrppart}/auxfiles/${SYNOMODEL}.pat"
    [ -f "${NETCONSOLE_KO_SRC}" ] || NETCONSOLE_KO_SRC="/home/tc/redpill-load/cache/${SYNOMODEL}.pat"
    NETCONSOLE_KO_FOUND=0
    if [ -f "${NETCONSOLE_KO_SRC}" ]; then
        _NC_TMPDIR="$(mktemp -d)"
        # BusyBox tar 는 아카이브 멤버명을 정확히 일치시켜야 하는데, 이 .pat 은
        # tar -cf x.pat ./ 로 만들어져 내부 경로가 "./usr/lib/modules/netconsole.ko"
        # (선행 "./" 포함)이다. "./" 없이 요청하면 "not found in archive" 로 매번
        # 조용히 실패해 항상 hda1.tgz 폴백만 타는 것을 실기로 확인했다.
        if tar -xf "${NETCONSOLE_KO_SRC}" -C "${_NC_TMPDIR}" ./usr/lib/modules/netconsole.ko 2>/dev/null \
           && [ -f "${_NC_TMPDIR}/usr/lib/modules/netconsole.ko" ]; then
            NETCONSOLE_KO_FOUND=1
        else
            _nc_hda1_entry="$(tar -tf "${NETCONSOLE_KO_SRC}" 2>/dev/null | grep -E '(^|/)hda1\.tgz$' | head -1)"
            if [ -n "${_nc_hda1_entry}" ] \
               && tar -xf "${NETCONSOLE_KO_SRC}" -C "${_NC_TMPDIR}" "${_nc_hda1_entry}" 2>/dev/null \
               && tar -xf "${_NC_TMPDIR}/${_nc_hda1_entry}" -C "${_NC_TMPDIR}" usr/lib/modules/netconsole.ko 2>/dev/null \
               && [ -f "${_NC_TMPDIR}/usr/lib/modules/netconsole.ko" ]; then
                NETCONSOLE_KO_FOUND=1
            fi
        fi
        if [ "${NETCONSOLE_KO_FOUND}" -eq 1 ]; then
            sudo mkdir -p $rdtemp/usr/lib/modules
            sudo cp -f "${_NC_TMPDIR}/usr/lib/modules/netconsole.ko" $rdtemp/usr/lib/modules/netconsole.ko
            echo "[netconsole] bundled netconsole.ko into ramdisk"
        else
            echo "[netconsole] netconsole.ko not found in ${NETCONSOLE_KO_SRC} - insmod will be skipped at boot"
        fi
        rm -rf "${_NC_TMPDIR}"
    else
        echo "[netconsole] patfile ${NETCONSOLE_KO_SRC} not found - insmod will be skipped at boot"
    fi
    cat >/tmp/netconsole-early.sh <<'NCEOF'
#!/bin/sh
# 이 스크립트는 Main() 진입 직후, acovermissingbin 의 on_early(usr.tgz 로
# tr/grep/cut 등을 갖춘 실제 busybox 유틸을 usr/sbin, usr/lib 에 풀어주는
# 단계)보다도, 그리고 eth0 실제 NIC 드라이버가 로드되는 시점보다도 이른
# 시점에 실행된다. 실기 확인: (1) tr 이 아직 없어 "tr: not found" 로
# NETCONSOLE_PARAM 파싱 자체가 실패했었고(수정함, 아래 참고), (2) 그 다음엔
# "insmod: can't insert '.../netconsole.ko': No such device" - eth0 가
# 아직 커널에 등록되기 전이라 netpoll 이 타겟 인터페이스를 못 찾음.
# Main() 은 이 스크립트 호출 뒤에 이어서 RunWithLog .../linuxrc.syno.impl
# 을 실행하는데, 그 안에서 실제 NIC 드라이버가 로드된다 - 즉 여기서 동기적으로
# 기다려봐야 그동안 아무 것도 진행되지 않아 소용없다(단일 프로세스 순차 실행).
# 그래서 호출하는 쪽(sed 로 삽입되는 라인)에서 백그라운드(&)로 띄우고, 이
# 스크립트 자신은 짧게 폴링하며 eth0/모듈이 준비될 때까지 재시도한다.
# tr/grep/cut 같은 외부 유틸 없이 셸 내장 word-splitting + case 패턴
# 매칭만으로 /proc/cmdline 에서 netconsole= 를 뽑는다.
NETCONSOLE_PARAM=""
for _nc_tok in $(cat /proc/cmdline); do
  case "${_nc_tok}" in
    netconsole=*)
      NETCONSOLE_PARAM="${_nc_tok#netconsole=}"
      ;;
  esac
done
if [ -n "${NETCONSOLE_PARAM}" ]; then
  KO=""
  for _cand in /usr/lib/modules/netconsole.ko /lib/modules/netconsole.ko; do
    if [ -f "${_cand}" ]; then
      KO="${_cand}"
      break
    fi
  done
  if [ -n "${KO}" ]; then
    _nc_i=0
    while [ "${_nc_i}" -lt 60 ]; do
      if insmod "${KO}" netconsole="${NETCONSOLE_PARAM}" 2>/var/log/netconsole.err; then
        break
      fi
      _nc_i=$((_nc_i + 1))
      sleep 1
    done
  fi
fi
NCEOF
    sudo cp /tmp/netconsole-early.sh $rdtemp/netconsole-early.sh
    sudo chmod +x $rdtemp/netconsole-early.sh
    # "echo START" 직후(파일 맨 위)는 WithTypedMounted 가 아직 /proc 를 마운트하기
    # 전이라 netconsole-early.sh 의 `cat /proc/cmdline` 이 조용히 실패해 아무 것도
    # 안 하고 끝나는 것을 실기로 확인(실제 부팅에서 insmod 자체가 시도되지 않음 -
    # 수동 실행 시엔 이미 /proc 가 있는 완전 부팅 상태라 성공했던 것과 대조됨).
    # linuxrc.syno 는 "WithTypedMounted proc ... WithTypedMounted sysfs ...
    # WithTypedMounted devtmpfs ... Main" 체인으로 /proc/sys/dev 를 먼저 마운트한
    # 뒤에야 Main() 을 호출하므로, Main() 함수 본문 첫 줄에 넣으면 /proc 는 이미
    # 마운트돼 있으면서도 여전히 Main() 안의 RunWithLog .../linuxrc.syno.impl
    # (DSM 파티션 마운트 등 본 로직) 보다는 이르다 - 이게 이 파일 구조에서 실제로
    # 도달 가능한 가장 이른 지점이다.
    # eth0 실제 NIC 드라이버는 이 뒤에 이어지는 RunWithLog .../linuxrc.syno.impl
    # 안에서 로드된다 - 여기서 동기 호출하면(&없이) 드라이버가 없는 채로
    # insmod 가 "No such device" 로 실패하고 끝나버린다(실기 확인). 백그라운드(&)
    # 로 띄워 Main() 이 곧장 .impl 로 진행되게 하고, 스크립트 자신이 안에서
    # 짧게 폴링 재시도한다.
    sudo sed -i '/^Main() {/a \\n/netconsole-early.sh \&' $rdtemp/linuxrc.syno
    rm -f /tmp/netconsole-early.sh
    # linuxrc.syno 최종 확인용 - SA6400 mknod 패치와 이 netconsole-early 패치가
    # 모두 적용된 뒤의 완성본을 빌드 로그에서 그대로 확인할 수 있도록 여기로 옮김.
    sudo cat $rdtemp/linuxrc.syno
    if [ "${ORIGIN_PLATFORM}" = "broadwellntbap" ]; then
        sudo sed -i 's/IsUCOrXA="yes"/XIsUCOrXA="yes"/g; s/IsUCOrXA=yes/XIsUCOrXA=yes/g' "$rdtemp/usr/syno/share/environments.sh"
    fi
    if [ "${BUS}" != "block" ]; then
        if [ "${MLMETHOD}" = "PML" ]; then
            echo "Use Persistent Module Loading (PML) methods on firmware and module ..."
            [ ! -d $rdtemp/usr/lib/firmware ] && sudo mkdir $rdtemp/usr/lib/firmware
            if [ "${MDLNAME}" == "custom-modules" ]; then
                sudo tar xvfz $rdtemp/exts/custom-modules/${ORIGIN_PLATFORM}*${KVER}.tgz -C $rdtemp/usr/lib/modules/  >/dev/null 2>&1
                sudo tar xvfz $rdtemp/exts/custom-modules/firmware.tgz -C $rdtemp/usr/lib/firmware/ >/dev/null 2>&1
            else
                sudo tar xvfz $rdtemp/exts/all-modules/${ORIGIN_PLATFORM}*${KVER}.tgz -C $rdtemp/usr/lib/modules/  >/dev/null 2>&1
                sudo tar xvfz $rdtemp/exts/all-modules/firmware.tgz -C $rdtemp/usr/lib/firmware/ >/dev/null 2>&1
                [ -f $rdtemp/exts/all-modules/firmwarei915.tgz ] && sudo tar xvfz $rdtemp/exts/all-modules/firmwarei915.tgz -C $rdtemp/usr/lib/firmware/ >/dev/null 2>&1
            fi

        fi

        #epyc7003ntb 듀얼-native(하이브리드): microP SED 하드웨어 잠금만 무력화한다.
        #com1 시리얼 캡처로 확인 — ramdisk 'Handle SED for FSDN' 단계에서
        #  microPLock=$(synomulticontroller --up_lock_ctrl GET_LOCK SYNO_UP_LOCK_SED)
        #  while [ "$microPLock" = "0" ]; do sleep 1; ... done
        #이 무한 루프에 걸려 hang. 이 잠금은 섀시 백플레인 microP(물리 i2c 마이크로컨트롤러)가
        #두 컨트롤러 SED 를 중재하는 하드웨어 호출이라, 일반 박스엔 칩이 없어 영원히 0 이다.
        #ntb_eth0 피어(synoaa/HA 네트워크 조율)로는 대체 불가 → GET_LOCK 대입을 1(획득됨)로
        #치환해 SED 루프만 통과시킨다. IsFSDN=yes(=ramdisk-004 제거)는 유지되어 synoaa
        #이중 컨트롤러 네트워크 조율은 그대로 native 로 동작한다. (구 5a1c2227 방식 복구)
        #SED 는 이 박스들에 없으므로 '획득됨' 처리는 무해하다.
        if echo "epyc7003ntb" | grep -wq "${ORIGIN_PLATFORM}"; then
            sudo sed -i 's#microPLock=$(/usr/syno/bin/synomulticontroller --up_lock_ctrl GET_LOCK SYNO_UP_LOCK_SED)#microPLock=1#g' "$rdtemp/linuxrc.syno.impl"
            echo "[NTB-fix] forced microP SED UP-lock acquired (hardware chip absent) in linuxrc.syno.impl"
            #btrfs 이후 xtrace 를 ttyS0 로 유지 — SED 통과 후 다음 정지 지점을 계속 추적.
            sudo sed -i '/SYNOLoadModules xor raid6_pq zstd_compress syno_cache_protection btrfs/a exec 2>/dev/ttyS0; set -x; echo "=== NTB-TRACE-START ===" >/dev/ttyS0' "$rdtemp/linuxrc.syno.impl"
            echo "[NTB-trace] instrumented linuxrc.syno.impl (xtrace -> ttyS0 after btrfs load)"
        fi

        # [BMI2-fix] kernel 5.x + DSM 7.3: USB 8개 모듈을 all-modules tgz에서
        # 추출해 ramdisk /usr/lib/modules/ 의 바닐라 DSM 모듈을 강제 교체한다.
        # (PML/IML 공통 — BUS != block 조건 하에서 항상 실행)
        if echo "${kver5platforms}" | grep -qw "${ORIGIN_PLATFORM}" && [ "${DSMVER}" = "7.3" ] && \
           strings /mnt/${loaderdisk}1/zImage 2>/dev/null | grep -q "PeterSuh-Q3"; then
            _USB_TGZ=$(ls $rdtemp/exts/all-modules/${ORIGIN_PLATFORM}*${KVER}.tgz 2>/dev/null | head -1)
            if [ -n "${_USB_TGZ}" ]; then
                echo "[BMI2-fix] Replacing vanilla USB modules with BMI2-free versions from ${_USB_TGZ}"
                _USB_MODS="usbcore.ko usb-common.ko usb-storage.ko ehci-hcd.ko ehci-pci.ko uhci-hcd.ko xhci-hcd.ko xhci-pci.ko hid.ko hid-generic.ko usbhid.ko uas.ko fat.ko vfat.ko adt7475.ko cdc-acm.ko e1000e.ko i40e.ko igb.ko ip_tables.ko ixgbe.ko mpt3sas.ko nf_conntrack.ko nf_defrag_ipv4.ko r8168.ko sg.ko sunrpc.ko vxlan.ko loop.ko sha256_generic.ko leds-atmega1608.ko leds-atmega1608-seg7.ko leds-lp3943.ko nfs.ko nfsv2.ko nfsv3.ko nfsv4.ko"
                _TMPUSB=$(mktemp -d)
                sudo tar xfz "${_USB_TGZ}" -C "${_TMPUSB}" ${_USB_MODS} >/dev/null 2>&1
                for _MOD in ${_USB_MODS}; do
                    if [ -f "${_TMPUSB}/${_MOD}" ]; then
                        sudo cp -f "${_TMPUSB}/${_MOD}" "$rdtemp/usr/lib/modules/${_MOD}"
                        echo "[BMI2-fix] Replaced: ${_MOD}"
                    fi
                done
                rm -rf "${_TMPUSB}"
            fi
        fi
    fi
    sudo chmod +x $rdtemp/usr/sbin/modprobe    

    # add dummy loop0 test
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tcrpfriend/main/buildroot/board/tcrpfriend/rootfs-overlay/root/boot-image-dummy-sda.img.gz -o $rdtemp/root/boot-image-dummy-sda.img.gz
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tcrpfriend/main/buildroot/board/tcrpfriend/rootfs-overlay/root/load-sda-first.sh -o $rdtemp/root/load-sda-first.sh
    #sudo chmod +x $rdtemp/root/load-sda-first.sh 
    #sudo mkdir -p $rdtemp/etc/udev/rules.d
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tcrpfriend/main/buildroot/board/tcrpfriend/rootfs-overlay/etc/udev/rules.d/99-custom.rules -o $rdtemp/etc/udev/rules.d/99-custom.rules
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/losetup/master/sbin/libsmartcols.so.1 -o $rdtemp/usr/lib/libsmartcols.so.1
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/losetup/master/sbin/losetup -o $rdtemp/usr/sbin/losetup
    #sudo chmod +x $rdtemp/usr/sbin/losetup

    RAMDISK_PATH="$rdtemp"
    # Patch synoinfo.conf
    mkdir -p "${RAMDISK_PATH}/addons"
    echo "v${rploaderver}" >"${RAMDISK_PATH}/addons/VERSION"
    # MSHELL Manager 의 System Info 탭에서 표시할 빌드 시점 스냅샷.
    # user_config.json(라이브 설정)과는 별개로, 이 커스텀 램디스크가
    # 실제로 어떤 LKM/모듈팩/모듈 로딩 방식으로 빌드됐는지를 기록한다 -
    # 재빌드 전까지는 라이브 설정이 바뀌어도 이 값은 그대로여야 정확하다.
    echo "${redpillmake}-${TAG}" >"${RAMDISK_PATH}/addons/LKM_VERSION"
    echo "${MODULES_TAG}" >"${RAMDISK_PATH}/addons/MODULES_VERSION"
    echo "${MDLNAME} (${MLMETHOD})" >"${RAMDISK_PATH}/addons/MODULE_TYPE"
    echo -n "."
    echo -n "" >"${RAMDISK_PATH}/addons/synoinfo.conf"
    for KEY in "${!SYNOINFO[@]}"; do
      echo "Set synoinfo ${KEY}"
      echo "${KEY}=\"${SYNOINFO[${KEY}]}\"" >>"${RAMDISK_PATH}/addons/synoinfo.conf"
      _set_conf_kv "${RAMDISK_PATH}/etc/synoinfo.conf" "${KEY}" "${SYNOINFO[${KEY}]}"
      _set_conf_kv "${RAMDISK_PATH}/etc.defaults/synoinfo.conf" "${KEY}" "${SYNOINFO[${KEY}]}"
    done
    cat "${RAMDISK_PATH}/addons/synoinfo.conf"

    #copy redoill lkm rp.ko.
    sudo cp -vf /home/tc/custom-module/redpill.ko "${RAMDISK_PATH}/addons/rp.ko"

    #copy bmi2_emul.ko for BMI2 instruction emulation on Ivy Bridge / J4125 (5.10.55+)
    #if [ -f /home/tc/redpill-load/src/bmi2_emul/bmi2_emul.ko ]; then
    #    sudo mkdir -p "${RAMDISK_PATH}/usr/lib/modules"
    #    sudo cp -vf /home/tc/redpill-load/src/bmi2_emul/bmi2_emul.ko "${RAMDISK_PATH}/usr/lib/modules/bmi2_emul.ko"
    #fi

    #copy user dts file.
    [ -f /home/tc/model.dts ] && sudo cp /home/tc/model.dts "${RAMDISK_PATH}/addons/model.dts"

    # The shared aeudev recipe owns MSHELL Manager release metadata.  Keep it
    # outside this build script so a new SPK only changes that recipe.
    MSHELL_MANAGER_MANIFEST_URL="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/aeudev/recipes/universal.json"
    MSHELL_MANAGER_MANIFEST="$(curl -kfL --retry 2 --connect-timeout 15 "${MSHELL_MANAGER_MANIFEST_URL}" 2>/dev/null)"
    MSHELL_MANAGER_SPK="$(printf '%s' "${MSHELL_MANAGER_MANIFEST}" | jq -r '.mshell_manager.name // empty' 2>/dev/null)"
    MSHELL_MANAGER_URL="$(printf '%s' "${MSHELL_MANAGER_MANIFEST}" | jq -r '.mshell_manager.url // empty' 2>/dev/null)"
    MSHELL_MANAGER_SHA256="$(printf '%s' "${MSHELL_MANAGER_MANIFEST}" | jq -r '.mshell_manager.sha256 // empty' 2>/dev/null)"
    if ! echo "${MSHELL_MANAGER_SPK}" | grep -Eq '^MshellManager-x86_64-[0-9]+\.[0-9]+\.[0-9]+\.spk$' || \
        [ "${MSHELL_MANAGER_URL##*/}" != "${MSHELL_MANAGER_SPK}" ] || \
        ! echo "${MSHELL_MANAGER_SHA256}" | grep -Eq '^[a-f0-9]{64}$'; then
      echo "[!] MSHELL Manager metadata in aeudev recipe is missing or invalid; skipped."
    elif ! curl -kfL --retry 2 --connect-timeout 15 "${MSHELL_MANAGER_URL}" \
        -o "${RAMDISK_PATH}/addons/${MSHELL_MANAGER_SPK}"; then
      echo "[!] MSHELL Manager SPK download failed; addon will retry after DSM boots."
      sudo rm -f "${RAMDISK_PATH}/addons/${MSHELL_MANAGER_SPK}"
    elif [ "$(sha256sum "${RAMDISK_PATH}/addons/${MSHELL_MANAGER_SPK}" 2>/dev/null | awk '{print $1}')" != \
        "${MSHELL_MANAGER_SHA256}" ]; then
      echo "[!] MSHELL Manager SPK checksum mismatch; discarded."
      sudo rm -f "${RAMDISK_PATH}/addons/${MSHELL_MANAGER_SPK}"
    else
      # aeudev's DSM-side installer reads this verified metadata after boot.
      # Keeping it beside the SPK lets that installer compare versions and
      # perform upgrades without duplicating release data in its shell code.
      printf '%s' "${MSHELL_MANAGER_MANIFEST}" | jq -c '.mshell_manager' \
        > "${RAMDISK_PATH}/addons/mshell-manager.json"
      echo "MSHELL Manager SPK saved to /addons/${MSHELL_MANAGER_SPK}"
    fi

    # If a supported AMD display controller is present, stage the matching
    # runtime SPK from the latest release for every MSHELL module mode.
    if [ -x "/home/tc/tools/install-amdgpu-addon.sh" ]; then
      /home/tc/tools/install-amdgpu-addon.sh "${ORIGIN_PLATFORM}" "${DSMVER}" "${KVER}" \
        "${RAMDISK_PATH}/addons" || echo "[amdgpu] optional staging failed; continuing loader build"
    fi

    # nvidiadriver addon: junior can't read user_config.json, so bake the menu
    # choice (driver version / ffmpeg layer / container runtime) into
    # /addons/nvidia.conf for its install.sh (on_patches). Empty driver => Auto
    # (install.sh detects the GPU).
    if grep -q '"nvidiadriver"' /home/tc/redpill-load/bundled-exts.json 2>/dev/null; then
      NVDRV=$(jq -r '.general.nvidia_driver // empty' "${userconfigfile}" 2>/dev/null)
      NVFF=$(jq -r '.general.nvidia_ffmpeg // empty' "${userconfigfile}" 2>/dev/null)
      NVCR=$(jq -r '.general.nvidia_container_runtime // empty' "${userconfigfile}" 2>/dev/null)
      { [ -n "$NVDRV" ] && echo "nvidia_driver=$NVDRV"
        [ -n "$NVFF"  ] && echo "nvidia_ffmpeg=$NVFF"
        [ -n "$NVCR"  ] && echo "nvidia_container_runtime=$NVCR"; } | sudo tee "${RAMDISK_PATH}/addons/nvidia.conf" >/dev/null
      echo "nvidiadriver: baked /addons/nvidia.conf (driver=${NVDRV:-auto} ffmpeg=${NVFF:-off} container-runtime=${NVCR:-off})"
    fi

    # epyc7003ntb (PAS7700): 단일(single) standalone 방식으로 통일 — 피어/이중 컨트롤러
    # 조율을 쓰지 않으므로 ntb_eth0.json(컨트롤러 역할 파일) 베이킹은 제거했다.
    # (misc addon 이 단일 노드용 synomulticontroller 래퍼로 apply-lock 을 통과시키고,
    #  IsFSDN 은 junior=ramdisk-004, 설치본=misc late 에서 각각 off 처리)

    [ ! -f "${RAMDISK_PATH}/etc.defaults/rc.sas" ] && sudo touch "${RAMDISK_PATH}/etc.defaults/rc.sas"

    #mark PML or not
    if [ "${BUS}" != "block" ]; then
        [ "${MLMETHOD}" = "PML" ] && sudo touch "${RAMDISK_PATH}/addons/pml_on" || sudo rm -f "${RAMDISK_PATH}/addons/pml_on"
    fi

    # 2026-08-21: exts/all-modules/firmwareamdgpu.tgz는 (kernel5 플랫폼 기준)
    # initrd-dsm 전체의 약 28%(28MB)를 차지하는데, tcrp-modules의
    # all-modules/src/install.sh는 하드웨어 감지 없이 "파일이 있으면 무조건
    # 설치"한다 - AMD GPU가 없는 대부분의 서버(예: epyc7002/SA6400은 AMD EPYC
    # CPU 서버 플랫폼일 뿐 AMD GPU 유무와는 무관)에서도 항상 그대로 실린다.
    # 위쪽(line ~5414)에서 이미 쓰는 것과 동일한 AMD VGA 감지 패턴을 재사용해,
    # 실제 AMD GPU가 없으면 cpio로 묶기 전에 이 파일만 제거한다. PML이든
    # IML이든 exts/ 트리 전체가 그대로 initrd-dsm에 포함되므로 MLMETHOD와
    # 무관하게 항상 확인한다.
    if [ -f "${rdtemp}/exts/all-modules/firmwareamdgpu.tgz" ] && ! lspci -nn 2>/dev/null | grep -qi 'VGA.*\[1002:'; then
        _AMDGPU_FW_SIZE=$(du -h "${rdtemp}/exts/all-modules/firmwareamdgpu.tgz" 2>/dev/null | awk '{print $1}')
        echo "No AMD GPU detected - dropping exts/all-modules/firmwareamdgpu.tgz (${_AMDGPU_FW_SIZE}) from initrd-dsm"
        sudo rm -f "${rdtemp}/exts/all-modules/firmwareamdgpu.tgz"
    fi

    # Reassembly ramdisk ( no compress, use cpio raw type )
    if [ "$RD_COMPRESSED" = "false" ]; then
        if [ "$FRKRNL" = "NO" ]; then
            #if [ "${MDLNAME}" == "custom-modules" ]; then
            #    if [ "$(which zstd)_" == "_" ]; then  
            #        echo "zstd does not exist, install from tinycore"
            #        tce-load -iw zstd 
            #    fi            
            #    echo "Ramdisk in not compressed, use bsdcpio + zstd -T0 -19"
            #    (cd $rdtemp && sudo find . | sudo bsdcpio -o -H newc -R root:root | zstd -c -T0 -19 > /mnt/${loaderdisk}3/initrd-dsm) >/dev/null            
            #else
                echo "Ramdisk in not compressed, use cpio raw"            
                (cd $rdtemp && sudo find . | sudo cpio -o -H newc -R root:root > /mnt/${loaderdisk}3/initrd-dsm) >/dev/null
            #fi
        else
            #if [ "$(which zstd)_" == "_" ]; then  
                echo "Ramdisk in not compressed, use cpio raw"                    
                (cd $rdtemp && sudo find . | sudo cpio -o -H newc -R root:root > /tmp/initrd-dsm)
            #else
            #    echo "Ramdisk in not compressed, use bsdcpio + zstd -T0 -19"
            #    (cd $rdtemp && sudo find . | sudo bsdcpio -o -H newc -R root:root | zstd -c -T0 -19 > /tmp/initrd-dsm)
            #fi
            sudo dd if=/tmp/initrd-dsm of=/mnt/${loaderdisk}3/initrd-dsm conv=fsync status=progress            
        fi
    else
        echo "Ramdisk in compressed, use xz(lzma) "
        (cd "$rdtemp" && $( [ "$FRKRNL" = "NO" ] && echo sudo ) find . | sudo cpio -o -H newc -R root:root | xz -9 --format=lzma >"/mnt/${loaderdisk}3/initrd-dsm") >/dev/null
    fi
    
    if [ "$WITHFRIEND" = "YES" ]; then
        msgnormal "Setting default boot entry to TCRP Friend"
    else
        msgnormal "Setting default boot entry to JOT ${BUS}"
    fi
    if [ -f /tmp/test_mode ]; then
        cecho g "###############################  This is Test Mode  ############################"
        sudo sed -i "/set default=\"*\"/cset default=\"0\"" /tmp/grub.cfg    
    else
        sudo sed -i "/set default=\"*\"/cset default=\"0\"" /tmp/grub.cfg    
    fi

    if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then
        sudo sed -i "s/6234-C863/1234-5678/g" /tmp/grub.cfg
    fi
    sudo cp -vf /tmp/grub.cfg /mnt/${loaderdisk}1/boot/grub/grub.cfg
st "gen grub     " "Gen GRUB entries" "Finished Gen GRUB entries : ${MODEL}"
[ "${BUS}" != "block" ] && log_build_step "Gen GRUB entries" 10 12

# finalization commands...
    [ -f /mnt/${loaderdisk}3/loader72.img ] && rm /mnt/${loaderdisk}3/loader72.img
    [ -f /mnt/${loaderdisk}3/grub72.cfg ] && rm /mnt/${loaderdisk}3/grub72.cfg
    [ -f /mnt/${loaderdisk}3/initrd-dsm72 ] && rm /mnt/${loaderdisk}3/initrd-dsm72

    sudo cp -vf $rdtemp/linuxrc.syno.impl /home/tc/linuxrc.syno.impl.${SYNOMODEL}
    sudo cp -vf $rdtemp/usr/sbin/init.post /home/tc/init.post.${SYNOMODEL}
    sudo rm -rf $rdtemp /home/tc/friend /home/tc/cache/*.pat

    if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then 
        msgnormal "Skip Caching files on xTCRP with Synoboot Injected."
    else
        if [ "${BUS}" != "block" ]; then
            msgnormal "Caching files for future use"
            [ ! -d ${local_cache} ] && mkdir ${local_cache}
        
            # Discover remote file size
            patfile=$(ls /home/tc/redpill-load/cache/*${TARGET_REVISION}*.pat | head -1)    
            FILESIZE=$(stat -c%s "${patfile}")
            SPACELEFT=$(df --block-size=1 | awk '/'${loaderdisk}'3/{print $4}') # Check disk space left    
        
            FILESIZE_FORMATTED=$(printf "%'d" "${FILESIZE}")
            SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
            FILESIZE_MB=$((FILESIZE / 1024 / 1024))
            SPACELEFT_MB=$((SPACELEFT / 1024 / 1024))    
        
            echo "FILESIZE  = ${FILESIZE_FORMATTED} bytes (${FILESIZE_MB} MB)"
            echo "SPACELEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"
        
            if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
                # No disk space to download, change it to RAMDISK
                echo "No adequate space on ${local_cache} to backup cache pat file, clean up PAT file now ....."
                sudo sh -c "rm -vf $(ls -t ${local_cache}/*.pat | head -n 1)"
            fi
        
            if [ -f ${patfile} ]; then
                echo "Found ${patfile}, moving to cache directory : ${local_cache} "
                # 2026-07-22: .pat 전체(보통 300~400MB, 대부분 DSM 자체 설치용 페이로드로
                # 로더 빌드엔 불필요)를 그대로 영구 캐시하던 것을, 실제 참조되는 5개 파일
                # (zImage/rd.gz: redpill-load 커널·램디스크, GRUB_VER/grub_cksum.syno:
                # bootp1_copy/bootp2_copy, VERSION: 이 스크립트 자신이 3417번째 줄 근방에서
                # 직접 추출) 만 뽑아 재압축한 "미니 pat"으로 대체해 캐시 용량을 절감한다
                # (실측 398MB -> 약 9MB, 97%+ 절감). 파일명은 원본과 동일하게 유지해
                # redpill-load의 "파일이 이미 있으면 다운로드 스킵" 로직과 완전히 호환된다.
                # 5개 중 하나라도 못 찾으면 안전하게 원본 그대로 보존한다(폴백).
                #
                # 2026-07-22 실기 검증: testarchive()(암호화 여부 판별)가 파일의 2번째
                # 바이트만으로 tar/암호화 형식을 판별하는데(od -bcN2), 원본 .pat은
                # "tar -cf x.pat ./"처럼 디렉토리 자체를 아카이빙해 첫 엔트리가 "./"
                # (바이트 './' )로 시작하는 반면, 개별 파일명을 나열해 만든 첫 버전은
                # 첫 엔트리가 "zImage"(바이트 'zI')로 시작해 판별식 어디에도 안 걸려
                # "maybe corrupted"로 오판, 빌드가 깨지는 사고가 실측 확인됨
                # (sa6400_90075.pat, 12.9MB 미니 pat). 추출을 별도 하위 디렉토리에
                # 하고 그 디렉토리(".")를 통째로 아카이빙해 원본과 동일하게 "./" 로
                # 시작하는 tar를 만들도록 수정.
                MINIPAT_FILES="zImage rd.gz GRUB_VER grub_cksum.syno VERSION"
                MINIPAT_TMPDIR="$(mktemp -d)"
                MINIPAT_INNER="${MINIPAT_TMPDIR}/extracted"
                mkdir -p "${MINIPAT_INNER}"
                MINIPAT_OK=1
                MINIPAT_RESOLVED=""
                MINIPAT_LISTING="$(tar -tf "${patfile}" 2>/dev/null)"

                for _mp_f in ${MINIPAT_FILES}; do
                    _mp_resolved="$(echo "${MINIPAT_LISTING}" | grep -E "(^|/)${_mp_f}\$" | head -1)"
                    if [ -z "${_mp_resolved}" ]; then
                        echo "[minipat] ${_mp_f} not found in ${patfile} - keeping original pat as-is"
                        MINIPAT_OK=0
                        break
                    fi
                    MINIPAT_RESOLVED="${MINIPAT_RESOLVED}${MINIPAT_RESOLVED:+ }${_mp_resolved}"
                done

                # [netconsole] hda1.tgz 는 미니팻 대상 목록(MINIPAT_FILES)에 없어서
                # 그대로 두면 버려진다. 그 안의 netconsole.ko(부트타임 ramdisk 계열엔
                # 없고 DSM 자체 설치본에만 있는 모듈)를, 원본 .pat 이 아직 손 안에 있는
                # 지금 미리 뽑아 미니팻 본문(MINIPAT_INNER)에 usr/lib/modules/netconsole.ko
                # 로 같이 담아둔다 - 이렇게 미니팻 자체에 내장해야 다음 빌드가 이 미니팻
                # 캐시만 재사용해도(hda1.tgz 는 이미 사라진 뒤라도) 계속 꺼내 쓸 수 있다.
                # 주의: 이 함수가 "이미 netconsole.ko 를 내장한 미니팻"을 다시 patfile
                # 로 받아 재압축하는 경우(재실행/재캐싱)도 있는데, 그런 입력엔 애초에
                # hda1.tgz 가 없어 매번 hda1.tgz 로만 시도하면 재압축할 때마다
                # netconsole.ko 가 조용히 빠지는 회귀가 생긴다(실기 확인). patfile 에서
                # usr/lib/modules/netconsole.ko 를 직접 추출 시도부터 하고, 없을 때만
                # hda1.tgz 를 거친다. BusyBox tar 는 이 .pat 이 tar -cf x.pat ./ 로
                # 만들어져 내부 경로가 "./usr/lib/modules/netconsole.ko" 인 것을 "./"
                # 없이 요청하면 못 찾는 것을 실기로 확인 - 재압축 시마다 netconsole.ko
                # 가 빠지던 회귀의 진짜 원인이었다.
                if [ "${MINIPAT_OK}" -eq 1 ]; then
                    if tar -xf "${patfile}" -C "${MINIPAT_INNER}" ./usr/lib/modules/netconsole.ko 2>/dev/null \
                       && [ -f "${MINIPAT_INNER}/usr/lib/modules/netconsole.ko" ]; then
                        echo "[netconsole] embedded netconsole.ko into minipat cache (already present in patfile)"
                    else
                        _nc_hda1="$(echo "${MINIPAT_LISTING}" | grep -E "(^|/)hda1\.tgz\$" | head -1)"
                        if [ -n "${_nc_hda1}" ] \
                           && tar -xf "${patfile}" -C "${MINIPAT_TMPDIR}" "${_nc_hda1}" 2>/dev/null \
                           && tar -xf "${MINIPAT_TMPDIR}/${_nc_hda1}" -C "${MINIPAT_INNER}" usr/lib/modules/netconsole.ko 2>/dev/null \
                           && [ -f "${MINIPAT_INNER}/usr/lib/modules/netconsole.ko" ]; then
                            echo "[netconsole] embedded netconsole.ko into minipat cache (extracted from hda1.tgz)"
                        else
                            echo "[netconsole] netconsole.ko not embedded into minipat cache (not found in patfile or hda1.tgz)"
                        fi
                    fi
                fi

                if [ "${MINIPAT_OK}" -eq 1 ]; then
                    if tar -xf "${patfile}" -C "${MINIPAT_INNER}" ${MINIPAT_RESOLVED} 2>/dev/null \
                       && tar -cf "${MINIPAT_TMPDIR}/$(basename ${patfile})" -C "${MINIPAT_INNER}" . 2>/dev/null; then
                        echo "[minipat] Reduced $(basename ${patfile}) to 5 essential files (zImage/rd.gz/GRUB_VER/grub_cksum.syno/VERSION)"
                        $( [ "$FRKRNL" != "NO" ] && echo sudo ) cp -vf "${MINIPAT_TMPDIR}/$(basename ${patfile})" ${local_cache}
                    else
                        echo "[minipat] selective repack failed - keeping original pat as-is"
                        MINIPAT_OK=0
                    fi
                fi
                [ "${MINIPAT_OK}" -eq 0 ] && $( [ "$FRKRNL" != "NO" ] && echo sudo ) cp -vf ${patfile} ${local_cache}
                rm -rf "${MINIPAT_TMPDIR}"
                $( [ "$FRKRNL" != "NO" ] && echo sudo ) rm -vf /home/tc/redpill-load/cache/*.pat
            fi
st "cachingpat" "Caching pat file" "Cached file to: ${local_cache}"
[ "${BUS}" != "block" ] && log_build_step "Caching pat file" 11 12
        fi
    fi

    cleanupmemory

}

function curlfriend() {
    REPO="PeterSuh-Q3/tcrpfriend"
    FRTAG=""

    if [ -f /tmp/test_mode ]; then
        cecho g "###############################  This is Test Mode  ############################"
        PRERELEASE_TAG=$(curl -sk "https://api.github.com/repos/$REPO/releases" | \
          jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)
        if [ -n "$PRERELEASE_TAG" ]; then
            echo "Pre-release tag found: $PRERELEASE_TAG"
            FRTAG="$PRERELEASE_TAG"
        fi
        writeConfigKey "general" "friendautoupd" "false"
    fi

    if [ -z "$FRTAG" ]; then
        LATESTURL=$(curl --connect-timeout 5 -skL -w %{url_effective} -o /dev/null "https://github.com/$REPO/releases/latest")
        FRTAG="${LATESTURL##*/}"
        [ -f /tmp/test_mode ] || echo "Latest tag: $FRTAG"
    fi

    # [ "${CPU}" = "HP" ] && FRTAG="${FRTAG}a"
    echo "FRIEND TAG is ${FRTAG}"

    curl -kLO# "https://github.com/$REPO/releases/download/${FRTAG}/chksum" \
         -O "https://github.com/$REPO/releases/download/${FRTAG}/bzImage-friend" \
         -O "https://github.com/$REPO/releases/download/${FRTAG}/initrd-friend"

    if [ $? -ne 0 ]; then
        msgalert "Download failed from github.com friend... !!!!!!!!"
    else
        msgnormal "Bringing over my friend from github.com Done!!!!!!!!!!!!!!"
    fi
}

function bringoverfriend() {
  local retval=0

  [ ! -d /home/tc/friend ] && mkdir -p /home/tc/friend && cd /home/tc/friend

  if [ ! -f /mnt/${tcrppart}/bzImage-friend ] || [ -f /tmp/test_mode ]; then
    # 파일 없음 → curlfriend 호출 후 리턴값 전달
    curlfriend || { retval=2; msgalert "curlfriend failed"; }
    return $retval
  fi

  echo -n "Checking for latest friend -> "
  URL="https://github.com/PeterSuh-Q3/tcrpfriend/releases/latest/download/chksum"
  curl --connect-timeout 5 -s -k -L "$URL" -O || { retval=3; msgalert "Failed to download chksum"; return $retval; }

  if [ -f chksum ]; then
    FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
    BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
    INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"

    if [ "$(sha256sum /mnt/${tcrppart}/bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && \
       [ "$(sha256sum /mnt/${tcrppart}/initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ]; then
      msgnormal "OK, latest \n"
      return 0  # 최신 버전
    else
      msgwarning "Found new version, bringing over new friend version : $FRIENDVERSION \n"
      curlfriend || { retval=2; msgalert "curlfriend update failed"; return $retval; }
      
      # 체크섬 검증
      if [ -f bzImage-friend ] && [ -f initrd-friend ] && [ -f chksum ]; then
        [ "$(sha256sum bzImage-friend | awk '{print $1}')" != "$BZIMAGESHA256" ] && { retval=2; msgalert "bzImage-friend checksum ERROR!"; return $retval; }
        [ "$(sha256sum initrd-friend | awk '{print $1}')" != "$INITRDSHA256" ] && { retval=2; msgalert "initrd-friend checksum ERROR!"; return $retval; }
        msgnormal "Update successful: $FRIENDVERSION"
        return 1  # 업데이트 성공
      else
        retval=2
        msgalert "Could not find friend files!"
        return $retval
      fi
    fi
  else
    retval=3
    msgalert "No chksum file downloaded"
    return $retval
  fi
}

function synctime() {

    if [ "$FRKRNL" = "NO" ]; then
        #Get Timezone
        tz=$(curl -s ipinfo.io | grep timezone | awk '{print $2}' | sed 's/,//')
        if [ $(echo $tz | grep Seoul | wc -l ) -gt 0 ]; then
            ntpserver="asia.pool.ntp.org"
        else
            ntpserver="pool.ntp.org"
        fi
    
        if [ "$(which ntpclient)_" == "_" ]; then
            tce-load -iw ntpclient 2>&1 >/dev/null
        fi    
        export TZ="${timezone}"
        echo "Synchronizing dateTime with ntp server $ntpserver ......"
        sudo ntpclient -s -h ${ntpserver} 2>&1 >/dev/null
    else
        GOOGLETIME=$(curl -k -v -s https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
        sudo date -u -s "$(date -d "$GOOGLETIME" "+%Y-%m-%d %H:%M:%S")"
    fi
    echo
    echo "DateTime synchronization complete!!!"

}

function matchpciidmodule() {

    MODULE_ALIAS_FILE="modules.alias.4.json"

    vendor="$(echo $1 | sed 's/[a-z]/\U&/g')"
    device="$(echo $2 | sed 's/[a-z]/\U&/g')"

    pciid="${vendor}d0000${device}"

    #jq -e -r ".modules[] | select(.alias | test(\"(?i)${1}\")?) |   .name " modules.alias.json
    # Correction to work with tinycore jq
    matchedmodule=$(jq -e -r ".modules[] | select(.alias | contains(\"${pciid}\")?) | .name " $MODULE_ALIAS_FILE)

    # Call listextensions for extention matching

    echo "$matchedmodule"

    #listextension $matchedmodule

}

function getmodaliasfile() {

    echo "{"
    echo "\"modules\" : ["

    grep -ie pci -ie usb /lib/modules/$(uname -r)/modules.alias | while read line; do

        read alias pciid module <<<"$line"
        echo "{"
        echo "\"name\" :  \"${module}\"",
        echo "\"alias\" :  \"${pciid}\""
        echo "}",
        #       echo "},"

    done | sed '$ s/,//'

    echo "]"
    echo "}"

}

function listmodules() {

    if [ ! -f $MODULE_ALIAS_FILE ]; then
        echo "Creating module alias json file"
        getmodaliasfile >modules.alias.4.json
    fi

    echo -n "Testing $MODULE_ALIAS_FILE -> "
    if $(jq '.' $MODULE_ALIAS_FILE >/dev/null); then
        echo "File OK"
        echo "------------------------------------------------------------------------------------------------"
        echo -e "It looks that you will need the following modules : \n\n"

        if [ "$WITHFRIEND" = "YES" ]; then
            echo "Block listpci for using all-modules. 2022.11.09"
        else    
            listpci
        fi

        echo "------------------------------------------------------------------------------------------------"
    else
        echo "Error : File $MODULE_ALIAS_FILE could not be parsed"
    fi

}

function ext_manager() {

    local _SCRIPTNAME="${0}"
    local _ACTION="${1}"
    local _PLATFORM_VERSION="${2}"
    shift 2
    local _REDPILL_LOAD_SRC="/home/tc/redpill-load"
    export MRP_SRC_NAME="${_SCRIPTNAME} ${_ACTION} ${_PLATFORM_VERSION}"
    ${_REDPILL_LOAD_SRC}/ext-manager.sh $@
    exit $?

}

function getredpillko() {

    DSMVER=$(echo ${TARGET_VERSION} | cut -c 1-3 )
    echo "KERNEL VERSION of getredpillko() is ${KVER}, DSMVER is ${DSMVER}"
    v=""

    REPO="PeterSuh-Q3/redpill-lkm"
    TAG=""
    MODULES_TAG="unknown"
    if [ "${offline}" = "NO" ]; then
        echo "Downloading ${ORIGIN_PLATFORM} ${KVER}+ redpill.ko ..."

        # TAG 해석: test_mode 시 pre-release 우선 조회
        if [ -f /tmp/test_mode ]; then
            cecho g "###############################  This is Test Mode  ############################"
            [ "${DSMVER}" = "7.3" ] && redpillmake="dev"
            LKM_PRERELEASE_TAG=$(curl --connect-timeout 10 -sk "https://api.github.com/repos/$REPO/releases" | \
              jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)
            if [ -n "$LKM_PRERELEASE_TAG" ]; then
                echo "Pre-release tag found: $LKM_PRERELEASE_TAG"
                TAG="$LKM_PRERELEASE_TAG"
            fi
        fi

        # TAG 미확정 시 GitHub API로 latest 조회 (안정적)
        if [ -z "${TAG}" ]; then
            TAG=$(curl --connect-timeout 10 -skL \
              "https://api.github.com/repos/${REPO}/releases/latest" \
              | jq -r '.tag_name')
        fi

        # API 실패 시 redirect URL 방식으로 fallback
        if [ -z "${TAG}" ] || [ "${TAG}" = "null" ]; then
            echo "API tag resolution failed, trying redirect fallback..."
            LATESTURL=$(curl --connect-timeout 10 -skL -w '%{url_effective}' -o /dev/null \
              "https://github.com/${REPO}/releases/latest")
            TAG="${LATESTURL##*/}"
        fi

        # TAG 최종 검증
        if [ -z "${TAG}" ] || [ "${TAG}" = "null" ] || [ "${TAG}" = "latest" ]; then
            echo "[ERROR] Failed to resolve latest release tag for ${REPO}" >&2
            return 1
        fi

        echo "TAG is ${TAG}"
        updateuserconfigfield "general" "redpillmake" "${redpillmake}-${TAG}"

        # tcrp-modules 의 실제 다운로드(all-modules/custom-modules/aeudev
        # rpext-index.json 등)는 release asset 이 아니라 main 브랜치 raw
        # 콘텐츠에서 이뤄지므로, 엄밀히는 "최신 릴리즈 태그"가 이 빌드가
        # 실제로 받은 내용과 다를 수 있다(main 이 태그 이후 앞서갈 때).
        # 그래도 화면/System Info 표기는 "26.8.15" 같은 짧은 태그명으로
        # 보여주는 게 목적이므로, 커밋 SHA 비교 없이 최신 릴리즈 태그명을
        # 그대로 기록한다.
        #
        # tcrp-modules 의 releases/latest 응답은 (에셋 목록이 많아)
        # ~380KB 로, redpill-lkm 쪽과 달리 셸 변수에 담아 파이프로
        # 넘기면 "jq/sudo: Argument list too long" 로 죽는 게 실기에서
        # 재현됨(같은 세션의 뒤이은 무관한 sudo 호출까지 함께 실패하는
        # 것으로 보아 인자 목록이 아니라 환경/스택 한도 문제로 추정).
        # 변수+파이프 대신 임시 파일에 받아 jq 가 파일을 직접 읽게 해서
        # 이 한도 자체를 우회한다.
        _modules_json_file="/tmp/.mshell_tcrp_modules_latest.json"
        curl --connect-timeout 10 -skL \
          "https://api.github.com/repos/PeterSuh-Q3/tcrp-modules/releases/latest" \
          -o "${_modules_json_file}" 2>/dev/null
        MODULES_TAG=$(jq -r '.tag_name // empty' "${_modules_json_file}" 2>/dev/null)
        rm -f "${_modules_json_file}"
        [ -z "${MODULES_TAG}" ] && MODULES_TAG="unknown"
        echo "tcrp-modules TAG is ${MODULES_TAG}"

        # 다운로드: --retry 3, connect-timeout 15s, max-time 120s, HTTP 오류 검증
        local ZIP_PATH="/mnt/${tcrppart}/rp-lkms${v}.zip"
        local DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/rp-lkms.zip"
        echo "Downloading: ${DOWNLOAD_URL}"

        #RR_VER="26.3.1"
        #STATUS=`sudo curl --connect-timeout 5 -skL -w "%{http_code}" "https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/download/${TAG}/rp-lkms-${RR_VER}.zip" -o "/mnt/${tcrppart}/rp-lkms${v}.zip"`
        STATUS=$(sudo curl \
            --connect-timeout 15 \
            --max-time 120 \
            --retry 3 \
            --retry-delay 5 \
            --retry-connrefused \
            -skL -w "%{http_code}" \
            "${DOWNLOAD_URL}" \
            -o "${ZIP_PATH}")

        # HTTP 상태코드 검증
        if [ "${STATUS}" != "200" ]; then
            echo "[ERROR] rp-lkms.zip 다운로드 실패 (HTTP ${STATUS})" >&2
            echo "[ERROR] URL: ${DOWNLOAD_URL}" >&2
            sudo rm -f "${ZIP_PATH}"
            return 1
        fi

        # 파일 크기 검증 (손상된 파일 방어)
        local ZIPSIZE
        ZIPSIZE=$(stat -c%s "${ZIP_PATH}" 2>/dev/null || echo 0)
        if [ "${ZIPSIZE}" -lt 10240 ]; then
            echo "[ERROR] rp-lkms.zip 크기 이상 (${ZIPSIZE} bytes) - 손상된 파일" >&2
            sudo rm -f "${ZIP_PATH}"
            return 1
        fi

        echo "Download OK: ${ZIPSIZE} bytes (HTTP ${STATUS})"
    else
        echo "Unzipping ${ORIGIN_PLATFORM} ${KVER}+ redpill.ko ..."
    fi

    sudo rm -f /home/tc/custom-module/*.gz
    sudo rm -f /home/tc/custom-module/*.ko

    # 오류 발생 즉시 중단 + 파이프 오류도 감지
    set -euo pipefail
    
    # 오류 발생 위치 출력 함수
    die() {
        echo "[ERROR] $1" >&2
        echo "[ERROR] Line ${BASH_LINENO[0]} 에서 중단됨" >&2
        exit 1
    }

    rp_file="rp-${ORIGIN_PLATFORM}-${DSMVER}-${KVER}-${redpillmake}.ko"
    rp_gz_file="${rp_file}.gz"
    echo "${rp_gz_file}"
    # 1. ko.gz 파일 추출
    sudo unzip /mnt/${tcrppart}/rp-lkms${v}.zip \
        "${rp_gz_file}" \
        -d /tmp >/dev/null 2>&1 \
        || die "unzip 실패: rp-lkms${v}.zip 에서 ko.gz 추출 오류"
    
    # 2. gunzip 압축 해제
    sudo gunzip -f "/tmp/${rp_gz_file}" >/dev/null 2>&1 \
        || die "gunzip 실패: ko.gz 압축 해제 오류"
    
    # 3. redpill.ko 복사
    sudo cp -vf "/tmp/${rp_file}" \
        /home/tc/custom-module/redpill.ko \
        || die "cp 실패: redpill.ko 복사 오류"
    
    # 4. TAG가 없으면 VERSION 파일에서 추출
    if [ -z "${TAG:-}" ]; then
        rm -f /tmp/VERSION
        unzip /mnt/${tcrppart}/rp-lkms${v}.zip VERSION -d /tmp >/dev/null 2>&1 \
            || die "unzip 실패: VERSION 파일 추출 오류"
    
        [ -f /tmp/VERSION ] || die "VERSION 파일이 존재하지 않음"
    
        TAG=$(cat /tmp/VERSION)
        [ -n "${TAG}" ] || die "VERSION 파일이 비어 있음"
    
        echo "TAG of VERSION is ${TAG}"
    fi
    
    # 5. 커널 버전에 따라 모듈 이름 결정
    KVER_MAJOR="$(echo "${KVER:-3}" | cut -d'.' -f1)"
    if [ "${KVER_MAJOR}" -eq 3 ]; then
        REDPILL_MOD_NAME="redpill-linux-v${KVER}.ko"
    else
        REDPILL_MOD_NAME="redpill-linux-v${KVER}+.ko"
    fi
    
    # 6. 최종 위치로 복사
    sudo cp -vf /home/tc/custom-module/redpill.ko \
        /home/tc/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME} \
        || die "cp 실패: ${REDPILL_MOD_NAME} 복사 오류"
    
    # 7. 디버그 심볼 제거
    sudo strip --strip-debug \
        /home/tc/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME} \
        || die "strip 실패: ${REDPILL_MOD_NAME}"

    set +euo pipefail    

}

function changeautoupdate {
    if [ -z "$1" ]; then
      echo -en "\r$(msgalert "There is no on or off parameter.!!!")\n"
      exit 99
    elif [ "$1" != "on" ] && [ "$1" != "off" ]; then
      echo -en "\r$(msgalert "There is no on or off parameter.!!!")\n"
      exit 99
    fi

    getloaderdisk
    tcrppart="${loaderdisk}3"

    jsonfile=$(jq . "$userconfigfile")
    
    echo -n "friendautoupd on User config file needs update, updating -> "
    if [ "$1" = "on" ]; then
        writeConfigKey "general" "friendautoupd" "true"
    else
        writeConfigKey "general" "friendautoupd" "false"
    fi
    cp $userconfigfile /mnt/${tcrppart}/
    echo $jsonfile | jq . >$userconfigfile && echo "Done" || echo "Failed"
    
    cat $userconfigfile | grep friendautoupd
}

function upgrademan() {
    if [ -z "$1" ]; then
      echo -en "\r$(msgalert "There is no TCRP Friend version.!!!")\n"
      exit 99
    fi

    getloaderdisk
    tcrppart="${loaderdisk}3"

    [ ! -d /home/tc/friend ] && mkdir /home/tc/friend/ && cd /home/tc/friend
    
    friendautoupd="$(jq -r -e '.general.friendautoupd' $userconfigfile)"
    if [ "${friendautoupd}" = "false" ]; then
        echo -en "\r$(msgwarning "TCRP Friend auto update disabled")\n"
    else
        echo -en "\r$(msgwarning "TCRP Friend auto update enabled")\n"	
    fi
    FRIENDVERSION="$1"
    msgwarning "Found target version, bringing over new friend version : $FRIENDVERSION \n"
    echo -n "Checking for version $FRIENDVERSION friend -> "
    URL=$(curl --connect-timeout 15 -s --insecure -L https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/tags/"${FRIENDVERSION}" | jq -r -e .assets[].browser_download_url | grep chksum)
    if [ $? -ne 0 ]; then
        msgalert "Error downloading version of $FRIENDVERSION friend...\n"
        exit 99
    fi

    # download file chksum
    [ -n "$URL" ] && curl -s --insecure -L $URL -O
    if [ $? -ne 0 ]; then
        msgalert "Error downloading version of $FRIENDVERSION friend...\n"
        exit 99
    fi
    URLS=$(curl --insecure -s https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/tags/"${FRIENDVERSION}" | jq -r ".assets[].browser_download_url")
    for file in $URLS; do curl --insecure --location --progress-bar "$file" -O; done
    FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
    BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
    INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
    [ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f bzImage-friend /mnt/${tcrppart}/ && msgnormal "bzImage OK! \n"
    [ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f initrd-friend /mnt/${tcrppart}/ && msgnormal "initrd-friend OK! \n"
    echo -e "$(msgnormal "TCRP FRIEND HAS BEEN UPDATED!!!")"
    changeautoupdate "off"

    if [ -f /home/tc/friend/initrd-friend ] && [ -f /home/tc/friend/bzImage-friend ]; then
        sudo dd if=/home/tc/friend/initrd-friend of=/mnt/${tcrppart}/initrd-friend conv=fsync status=progress
        sudo dd if=/home/tc/friend/bzImage-friend of=/mnt/${tcrppart}/bzImage-friend conv=fsync status=progress
        sudo rm -rf /home/tc/friend
    fi

}

function returnto() {
    echo "${1}"
    read answer
    cd ~
}

function spacechk() {
  # Discover file size
  SPACEUSED=$(df --block-size=1 | awk '/'${1}'/{print $3}') # Check disk space used
  SPACELEFT=$(df --block-size=1 | awk '/'${2}'/{print $4}') # Check disk space left

  SPACEUSED_FORMATTED=$(printf "%'d" "${SPACEUSED}")
  SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
  SPACEUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${SPACEUSED} / 1024 / 1024}")
  SPACELEFT_MB=$(awk "BEGIN {printf \"%.1f\", ${SPACELEFT} / 1024 / 1024}")      

  msgwarning "SOURCE SPACE USED = ${SPACEUSED_FORMATTED} bytes (${SPACEUSED_MB} MB)"
  msgwarning "TARGET SPACE LEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"
}

function get_partition() {
    local disk=$1
    local num=$2
    if [[ "$disk" =~ ^/dev/nv ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

function tcrpfriendentry_hdd() {
    
    cat <<EOF
menuentry 'Tiny Core Friend ${MODEL} ${BUILD} Update 0 ${DMPM}' {
        savedefault
        search --set=root --fs-uuid "1234-5678" --hint hd0,msdos${1}
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8
        echo Loading initramfs...
        initrd /initrd-friend
        echo Booting TinyCore Friend
}
EOF

}

function xtcrpconfigureentry_hdd() {
    cat <<EOF
menuentry 'xTCRP Configure Boot Loader (Loader Build)' {
        savedefault
        search --set=root --fs-uuid "1234-5678" --hint hd0,msdos${1}
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8 IWANTTOCONFIGURE
        echo Loading initramfs to configure loader...
        initrd /initrd-friend
        echo Loding xTCRP RAMDISK to configure loader...
}
EOF
}

function wr_part1() {

    fediskpart="$(get_partition "${edisk}" ${1})"
    mdiskpart=$(echo "${fediskpart}" | sed 's/dev/mnt/')
    
    [ ! -d "${mdiskpart}" ] && sudo mkdir "${mdiskpart}"
    while true; do
        sleep 1
        echo "Mounting ${fediskpart} ..."
        sudo mount "${fediskpart}" "${mdiskpart}"
        if [ $? -ne 0 ]; then
            echo -e "Failed to mount the 4th partition ${fediskpart}. Stop processing!!!\n"
            remove_loader
            return 1
        fi
        [ $( mount | grep "${fediskpart}" | wc -l ) -gt 0 ] && break
    done
    sudo rm -rf "${mdiskpart}"/*

    diskid=$(echo "${fediskpart}" | sed 's#/dev/##')
    spacechk "${loaderdisk}1" "${diskid}"
    FILESIZE1=$(ls -l /mnt/${loaderdisk}3/bzImage-friend | awk '{print$5}')
    FILESIZE2=$(ls -l /mnt/${loaderdisk}3/initrd-friend | awk '{print$5}')
    
    a_num=$(echo $FILESIZE1 | bc)
    b_num=$(echo $FILESIZE2 | bc)
    c_num=$(echo $SPACEUSED | bc)
    t_num=$(($a_num + $b_num + $c_num))

    # 2026-08-21: wr_part3()의 "Files to copy onto..." 항목별 표기와 동일한
    # 스타일로, FRIEND 커널 두 파일의 크기도 여기서 보여준다.
    msgwarning "Files to copy onto ${fediskpart}:"
    msgwarning "  bzImage-friend = $(printf "%'d" "${a_num}") bytes ($(awk "BEGIN {printf \"%.1f\", ${a_num} / 1024 / 1024}") MB)"
    msgwarning "  initrd-friend  = $(printf "%'d" "${b_num}") bytes ($(awk "BEGIN {printf \"%.1f\", ${b_num} / 1024 / 1024}") MB)"

    TOTALUSED=$(echo $t_num)
    TOTALUSED_FORMATTED=$(printf "%'d" "${TOTALUSED}")
    TOTALUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${TOTALUSED} / 1024 / 1024}")
    msgwarning "TARGET TOTAL USED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"

    ZIMAGESIZE=""
    if [ 0${TOTALUSED} -ge 0${SPACELEFT} ]; then
        ZIMAGESIZE=$(ls -l /mnt/${loaderdisk}1/zImage | awk '{print$5}')
        z_num=$(echo $ZIMAGESIZE | bc)
        t_num=$(($t_num - $z_num))

        TOTALUSED=$(echo $t_num)
        TOTALUSED_FORMATTED=$(printf "%'d" "${TOTALUSED}")
        TOTALUSED_MB=$((TOTALUSED / 1024 / 1024))
        echo "FIXED TOTALUSED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"

        if [ 0${TOTALUSED} -ge 0${SPACELEFT} ]; then
            mountpoint -q "${mdiskpart}" && sudo umount "${mdiskpart}"
            returnto "Source Partition is too big ${TOTALUSED}, Space left ${SPACELEFT} !!!. Stop processing!!! " 
            false
        fi   
    fi

    if [ -z ${ZIMAGESIZE} ]; then
        cd /mnt/${loaderdisk}1 && sudo find . | sudo cpio -pdm "${mdiskpart}" 2>/dev/null
    else
        cd /mnt/${loaderdisk}1 && sudo find . -not -name "zImage" | sudo cpio -pdm "${mdiskpart}" 2>/dev/null
    fi

    echo "Modifying grub.cfg for new loader boot..."
    sudo sed -i '61,$d' "${mdiskpart}"/boot/grub/grub.cfg
    tcrpfriendentry_hdd ${1} | sudo tee --append "${mdiskpart}"/boot/grub/grub.cfg
    # 2026-08-21: 데이터 디스크 주입 부팅에는 FRIEND 커널 진입점 하나면 충분하고,
    # "xTCRP Configure Boot Loader" 항목은 xtcrp.tgz(방금 제거한 다운로드/백업
    # 단계)를 전제로 한 로더 재설정 경로라 여기서는 의미가 없어 같이 뺀다.

    sudo cp -vf /mnt/${loaderdisk}3/bzImage-friend  "${mdiskpart}"
    sudo cp -vf /mnt/${loaderdisk}3/initrd-friend  "${mdiskpart}"

    sudo mkdir -p /usr/local/share/locale

    true
}

function wr_part2() {

    fediskpart="$(get_partition "${edisk}" ${1})"
    mdiskpart=$(echo "${fediskpart}" | sed 's/dev/mnt/')
    
    [ ! -d "${mdiskpart}" ] && sudo mkdir "${mdiskpart}"
    while true; do
        sleep 1
        echo "Mounting ${fediskpart} ..."
        sudo mount "${fediskpart}" "${mdiskpart}"
        if [ $? -ne 0 ]; then
            echo -e "Failed to mount the 6th partition ${fediskpart}. Stop processing!!!\n"
            remove_loader
            return 1
        fi
        [ $( mount | grep "${fediskpart}" | wc -l ) -gt 0 ] && break
    done
    sudo rm -rf "${mdiskpart}"/*

    diskid=$(echo "${fediskpart}" | sed 's#/dev/##')        
    spacechk "${loaderdisk}2" "${diskid}"

    TOTALUSED_FORMATTED=$(printf "%'d" "${SPACEUSED}")
    TOTALUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${SPACEUSED} / 1024 / 1024}")
    msgwarning "TARGET TOTAL USED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"

    if [ 0${SPACEUSED} -ge 0${SPACELEFT} ]; then
        mountpoint -q "${mdiskpart}" && sudo umount "${mdiskpart}"
        returnto "Source Partition is too big ${SPACEUSED}, Space left ${SPACELEFT} !!!. Stop processing!!! " 
        false
    fi   
  
    cd /mnt/${loaderdisk}2 && sudo find . | sudo cpio -pdm "${mdiskpart}" 2>/dev/null
    true
}

function wr_part3() {

    fediskpart="$(get_partition "${edisk}" ${1})"
    mdiskpart=$(echo "${fediskpart}" | sed 's/dev/mnt/')
    
    [ ! -d "${mdiskpart}" ] && sudo mkdir "${mdiskpart}"
    while true; do
        sleep 1
        echo "Mounting ${fediskpart} ..."
        sudo mount "${fediskpart}" "${mdiskpart}"
        if [ $? -ne 0 ]; then
            echo -e "Failed to mount the 7th partition ${fediskpart}. Stop processing!!!\n"
            remove_loader
            return 1
        fi
        [ $( mount | grep "${fediskpart}" | wc -l ) -gt 0 ] && break
    done
    sudo rm -rf "${mdiskpart}"/*

    diskid=$(echo "${fediskpart}" | sed 's#/dev/##')

    # 2026-08-20: spacechk()가 찍던 "SOURCE SPACE USED"는 로더 파티션3
    # 전체 디스크 사용량(캐시/pat 파일 등 포함)이라, 실제로 이 파티션에
    # 복사되는 zImage-dsm+initrd-dsm 크기와는 무관한데도 마치 전송량인 것처럼
    # 보여서 혼란을 줬다(실기에서 "1.17GB 필요"로 오인한 사례). 목적지 여유
    # 공간만 직접 계산하고, 실제 복사 대상 파일은 항목별로 보여준다.
    SPACELEFT=$(df --block-size=1 | awk '/'${diskid}'/{print $4}')
    SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
    SPACELEFT_MB=$(awk "BEGIN {printf \"%.1f\", ${SPACELEFT} / 1024 / 1024}")
    msgwarning "TARGET SPACE LEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"

    FILESIZE1=$(ls -l /mnt/${loaderdisk}3/zImage-dsm | awk '{print$5}')
    FILESIZE2=$(ls -l /mnt/${loaderdisk}3/initrd-dsm | awk '{print$5}')

    a_num=$(echo $FILESIZE1 | bc)
    b_num=$(echo $FILESIZE2 | bc)
    t_num=$(($a_num + $b_num + 2000 ))
    TOTALUSED=$(echo $t_num)

    msgwarning "Files to copy onto ${fediskpart}:"
    msgwarning "  zImage-dsm = $(printf "%'d" "${a_num}") bytes ($(awk "BEGIN {printf \"%.1f\", ${a_num} / 1024 / 1024}") MB)"
    msgwarning "  initrd-dsm = $(printf "%'d" "${b_num}") bytes ($(awk "BEGIN {printf \"%.1f\", ${b_num} / 1024 / 1024}") MB)"

    TOTALUSED_FORMATTED=$(printf "%'d" "${TOTALUSED}")
    TOTALUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${TOTALUSED} / 1024 / 1024}")
    msgwarning "TARGET TOTAL USED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"

    if [ 0${TOTALUSED} -ge 0${SPACELEFT} ]; then
        mountpoint -q "${mdiskpart}" && sudo umount "${mdiskpart}"
        returnto "Source Partition is too big ${TOTALUSED}, Space left ${SPACELEFT} !!!. Stop processing!!! " 
        remove_loader
        return 1
    fi   

    cd /mnt/${loaderdisk}3 && find . -name "*dsm*" -o -name "user_config.json" | sudo cpio -pdm "${mdiskpart}" 2>/dev/null

    # 2026-08-21: xtcrp.tgz(약 264MB) 다운로드+백업(backupxtcrp) 단계를 제거했다.
    # 이 파티션(7번)은 애초에 79~83MB 안팎의 여유공간만 있어 xtcrp.tgz가 들어갈
    # 수조차 없고(공간 부족 시 조용히 skip되긴 하지만), 설령 이전에 남은
    # /dev/shm/xtcrp.tar 잔재가 있으면 backupxtcrp() 내부의 `gunzip`(-f 없이
    # 호출)이 "File exists"로 실패해 "Failed to decompress ... Restoring
    # backup."로 죽는 문제도 실기에서 확인됨. 이 주입 기능 자체가 xtcrp.tgz를
    # 필요로 하지 않으므로 아예 시도하지 않는다.
    true
}

function prepare_grub() {

    tce-load -i grub2-multi 
    if [ $? -eq 0 ]; then
        echo "Install grub2-multi OK !!!"
    else
        tce-load -iw grub2-multi
        [ $? -ne 0 ] && returnto "Install grub2-multi failed. Stop processing!!! " && false
    fi
    #sudo echo "grub2-multi.tcz" >> /mnt/${tcrppart}/cde/onboot.lst

    true
}

function prepare_img() {

    echo "Downloading tempelete disk image to ${imgpath}..."
    imgpath="/dev/shm/boot-image-to-hdd.img"  
    if [ -f ${imgpath} ]; then
        echo "Image file ${imgpath} Already Exist..."
     else
        sudo curl -kL# https://github.com/PeterSuh-Q3/rp-ext/releases/download/temp/boot-image-to-hdd.img.gz -o "${imgpath}.gz"
        [ $? -ne 0 ] && returnto "Download failed. Stop processing!!! ${imgpath}" && false
        echo "Unpacking image ${imgpath}..."
        sudo gunzip -f "${imgpath}.gz"
    fi

     if [ -z "$(losetup | grep -i ${imgpath})" ]; then
        if [ ! -n "$(losetup -j ${imgpath} | awk '{print $1}' | sed -e 's/://')" ]; then
            echo -n "Setting up ${imgpath} loop -> "
            sudo losetup -fP ${imgpath}
            [ $? -ne 0 ] && returnto "Mount loop device for ${imgpath} failed. Stop processing!!! " && false
        else
            echo -n "Loop device exists..."
        fi
    fi
    loopdev=$(losetup -j ${imgpath} | awk '{print $1}' | sed -e 's/://')
    echo "$loopdev"
 
    true
}

function get_disk_type_cnt() {

    RAID_CNT="$(sudo $FDISK -l | grep -e "Linux RAID" -e "fd Linux raid" | grep ${1} | wc -l )"
    DOS_CNT="$(sudo $FDISK -l | grep -e "83 Linux" -e "Linux filesystem" | grep ${1} | wc -l )"
    W95_CNT="$(sudo $FDISK -l | grep "95 Ext" | grep ${1} | wc -l )" 
    EXT_CNT="$(sudo $FDISK -l | grep "Extended" | grep ${1} | wc -l )"
    BIOS_CNT="$(sudo $FDISK -l | grep "BIOS" | grep ${1} | wc -l )"
    
    if [ "${2}" = "Y" ]; then
        echo "RAID_CNT=$RAID_CNT"
        echo "DOS_CNT=$DOS_CNT"
        echo "W95_CNT=$W95_CNT"
        echo "EXT_CNT=$EXT_CNT"
        echo "BIOS_CNT=$BIOS_CNT"
        echo "TB2T_CNT=$TB2T_CNT"
    fi
}

# SHR/RAID 데이터 디스크는 보통 mdadm 이 자동조립한 md 배열과 그 위의 LVM VG가
# 이미 활성 상태다. 이 상태에서 fdisk/gdisk 로 파티션을 새로 만들고
# blockdev --rereadpt 를 하면 커널이 "Resource busy"로 거부한다(실기에서
# 재현). 한 번만 정지시켜도 안심할 수 없다 - 파티션 테이블 변경 자체가
# udev change 이벤트를 유발해 mdadm 이 rereadpt 시도 직전에 다시 자동조립을
# 걸어버리는 레이스도 실기에서 확인됐다. 그래서 rereadpt 직전마다 매번
# 다시 정지시키고, 실패하면 짧게 대기 후 재시도한다. 데이터 자체는 건드리지
# 않고 단순히 비활성화만 하므로(vgchange -an / mdadm --stop) 안전하게
# 재시도 가능하다.
function rereadPartitionTable() {
    local edisk="${1}"
    local _mdd _vg _try

    for _try in 1 2 3; do
        for _mdd in $(lsblk -ln -o NAME,TYPE "${edisk}" 2>/dev/null | awk '$2 ~ /^raid/{print $1}'); do
            for _vg in $(sudo pvs --noheadings -o vg_name "/dev/${_mdd}" 2>/dev/null); do
                echo "Deactivating LVM VG ${_vg} on /dev/${_mdd}..."
                sudo vgchange -an "${_vg}" >/dev/null 2>&1
            done
            echo "Stopping md array /dev/${_mdd} (built on ${edisk}) before rereading partition table..."
            sudo mdadm --stop "/dev/${_mdd}" >/dev/null 2>&1
        done
        sudo blockdev --rereadpt "${edisk}" && return 0
        sleep 2
    done
    return 1
}

function inject_loader() {

  if [ ! -f /mnt/${loaderdisk}3/bzImage-friend ] || [ ! -f /mnt/${loaderdisk}3/initrd-friend ] || [ ! -f /mnt/${loaderdisk}3/zImage-dsm ] || [ ! -f /mnt/${loaderdisk}3/initrd-dsm ] || [ ! -f /mnt/${loaderdisk}3/user_config.json ] || [ ! $(grep -i "Tiny Core Friend" /mnt/${loaderdisk}1/boot/grub/grub.cfg | wc -l) -eq 1 ]; then
    returnto "The loader has not been built yet. Start with the build.... Stop processing!!! " && return
  fi

  plat=$(cat /mnt/${loaderdisk}1/GRUB_VER | grep PLATFORM | cut -d "=" -f2 | tr '[:upper:]' '[:lower:]' | sed 's/"//g')
  # ORIGIN_PLATFORM은 getvarsmshell()(my() 빌드 흐름)에서만 설정되는 변수라,
  # my()를 거치지 않고 바로 호출되는 이 "부트로더 주입" 기능에서는 정의된 적이
  # 없어 set -u 하에서 "unbound variable"로 즉시 죽었다(실기에서 재현). 바로
  # 위에서 이미 빌드된 로더의 GRUB_VER에서 읽어온 plat을 검사해야 한다.
  if echo ${kver5platforms} | grep -qw ${plat}; then
      returnto "${plat} is not supported... Stop processing!!! "
      return
  fi

  #[ "$MACHINE" = "VIRTUAL" ] &&    returnto "Virtual system environment is not supported. Two or more BASIC type hard disks are required on bare metal. (SSD not possible)... Stop processing!!! " && return

  SHR=0
  SHR_EX=0
  GPT=0 
  GPT_EX=0 
  TB2T_CNT=0
  DETECTED_DISKS=()  # SHR 또는 SHR_EX 디스크를 저장할 배열
  FIRST_SHR=""      # 사용자가 선택한 첫 번째 SHR 디스크
  
  while read -r edisk; do
      get_disk_type_cnt "${edisk}" "N"
      
      if [ $RAID_CNT -eq 3 ]; then
          case "$DOS_CNT $W95_CNT" in
              "0 1")
                  echo "This is SHR Type Hard Disk. $edisk"
                  ((SHR++))
                  DETECTED_DISKS+=("$edisk")  # 배열에 추가
                  ;;
              "3 1")
                  echo "This is SHR Type Hard Disk and Has synoboot1, synoboot2 and synoboot3 Boot Partition $edisk"
                  ((SHR_EX++))
                  DETECTED_DISKS+=("$edisk")  # 배열에 추가
                  FIRST_SHR="$edisk"
                  ;;
              "0 0" | "3 0")
                  EXPECTED_START_1=8192
                  EXPECTED_START_2=16785408
  
                  EXPECTED_START_11=2048
                  EXPECTED_START_22=4982528
  
                  partition_table=$(sudo fdisk -l "$edisk" | grep -E 'dos|gpt' | awk '{print $NF}')
                  
                  IS_GPT="OFF"
                  if [[ "$partition_table" == "gpt" ]]; then
                      IS_GPT="ON"
                  fi
  
                  partitions=$(sudo fdisk -l "$edisk" | grep "^$edisk[0-9]")
          
                  start_1=$(echo "$partitions" | grep "${edisk}1" | awk '{print $2}')
                  start_2=$(echo "$partitions" | grep "${edisk}2" | awk '{print $2}')
          
                  if { [ "$start_1" == "$EXPECTED_START_1" ] && [ "$start_2" == "$EXPECTED_START_2" ] && [ "$IS_GPT" == "ON" ]; } || \
                     { [ "$start_1" == "$EXPECTED_START_11" ] && [ "$start_2" == "$EXPECTED_START_22" ] && [ "$IS_GPT" == "ON" ]; }; then
                      echo -e "Detected GPT Type Hard Disk (larger than 2TB). $edisk \n"
                      if [ $BIOS_CNT -eq 1 ]; then 
                          ((GPT_EX++))
                          DETECTED_DISKS+=("$edisk")  # 배열에 추가
                          FIRST_SHR="$edisk"
                      else
                          ((GPT++))
                          DETECTED_DISKS+=("$edisk")  # 배열에 추가
                      fi
                      ((W95_CNT++))
                      TB2T_CNT=$((GPT + GPT_EX))
                  fi
                  ;;
              *)
                  echo "Unknown disk type for $edisk"
                  ;;                  
          esac
      fi
  done < <(sudo $FDISK -l | grep -e "Disk /dev/sd" -e "Disk /dev/nv" | awk '{print $2}' | sed 's/://' | sort -k1.6 -r)
  echo -e "GPT = $GPT, GPT_EX=$GPT_EX, MBR SHR = $SHR, MBR SHR_EX = $SHR_EX \n"

  SHR=$((SHR + GPT))
  SHR_EX=$((SHR_EX + GPT_EX))
  # 사용자 메뉴 제공 및 선택 처리
  # 2026-08-19: 텍스트 read -p 프롬프트를 dialog --menu 로 전환. 이 위의
  # 진단 echo(감지된 디스크 타입/파티션 시작섹터 등)는 진행 로그라 그대로
  # 두고, "선택"이라는 의사결정 지점만 다이얼로그로 바꾼다 - 전체를
  # 다이얼로그로 감싸면 이 함수에서 자주 나오는 에러 출력(fdisk/mount 등)이
  # 팝업 뒤로 숨어 원인 추적이 어려워질 위험이 커서 의도적으로 최소화함.
  if [ -z "$FIRST_SHR" ]; then
      if [ ${#DETECTED_DISKS[@]} -gt 0 ]; then
          echo "Detected SHR(MBR) or GPT disks:"
          : > "${TMP_PATH}/menu_injectdisk"
          for i in "${!DETECTED_DISKS[@]}"; do
              echo "$((i + 1)). ${DETECTED_DISKS[$i]}"
              echo "$((i + 1)) \"${DETECTED_DISKS[$i]}\"" >> "${TMP_PATH}/menu_injectdisk"
          done

          dialog --backtitle "$(backtitle)" --title "Select a disk" \
              --menu "Detected SHR(MBR) or GPT disks:" 0 0 $(dlgmenuheight ${#DETECTED_DISKS[@]}) \
              --file "${TMP_PATH}/menu_injectdisk" 2>"${TMP_PATH}/resp_injectdisk"

          if [ $? -eq 0 ]; then
              selection="$(cat "${TMP_PATH}/resp_injectdisk")"
              FIRST_SHR="${DETECTED_DISKS[$((selection - 1))]}"
              echo "You selected: $FIRST_SHR"
          else
              echo "No disk selected."
          fi
          rm -f "${TMP_PATH}/menu_injectdisk" "${TMP_PATH}/resp_injectdisk"
      else
          echo "No MBR SHR or GPT disks detected."
      fi
  fi

  # 예전 read -p 루프는 취소가 불가능해 FIRST_SHR이 항상 채워졌지만,
  # dialog --menu는 Cancel/Esc로 빈 값이 나올 수 있다 - 아래 SHR_EX/SHR
  # 카운트 체크는 FIRST_SHR 유무와 무관하게 통과해버리므로 여기서 명시적으로
  # 막아준다.
  if [ -z "$FIRST_SHR" ]; then
      returnto "No disk selected. Function Exit now!!! Press any key to continue..." && return
  fi

  [ -n "$FIRST_SHR" ] && echo -e "Selected Synodisk Bootloader Inject Disk: $FIRST_SHR \n"

  [ -n "$FIRST_SHR" ] && sudo $FDISK -l "${FIRST_SHR}"

  do_ex_first=""
  if [ $SHR_EX -eq 1 ]; then
    echo -e "There is at least one SHR type disk each with an injected bootloader...OK \n"
    do_ex_first="Y"
  elif [ $SHR -ge 1 ]; then
    echo -e "There is at least one disk of type SHR...OK \n"
    if [ -z "${do_ex_first}" ]; then
      do_ex_first="N"
    fi
  else
      echo
      returnto "There is not enough Type Disk. Function Exit now!!! Press any key to continue..." && return  
  fi

  echo -e "do_ex_first = ${do_ex_first} \n"

dialog --backtitle "$(backtitle)" --title "Inject Bootloader" \
    --yesno "(Warning) Do you want to port the bootloader to Syno disk?\n\nTarget disk: ${FIRST_SHR}" 0 0
if [ $? -eq 0 ]; then
    synomodel="$(jq -r -e '.general.model' $userconfigfile)"
    synoversion="$(jq -r -e '.general.version' $userconfigfile)"
    getvarsmshell "${synomodel}-${synoversion}"
    tce-load -i gdisk
    if [ $? -eq 0 ]; then
        echo "Install gdisk OK !!!"
    else
        tce-load -iw gdisk
        [ $? -ne 0 ] && returnto "Install gdisk failed. Stop processing!!! " && false
    fi
    tce-load -i bc
    if [ $? -eq 0 ]; then
        echo "Install bc OK !!!"
    else
        tce-load -iw bc
        [ $? -ne 0 ] && returnto "Install grub2-multi failed. Stop processing!!! " && return
    fi
    tce-load -i dosfstools
    if [ $? -eq 0 ]; then
        echo "Install dosfstools OK !!!"
    else
        tce-load -iw dosfstools
        [ $? -ne 0 ] && returnto "Install dosfstools failed. Stop processing!!! " && false
    fi

    if [ "${do_ex_first}" = "N" ]; then
        if [ $SHR -ge 1 ]; then
            echo -e "New bootloader injection (including /sbin/fdisk partition creation)...\n"

            BOOTMAKE=""
            SYNOP3MAKE=""

            # If there is a SHR disk, only process that disk.
            if [ -n "$FIRST_SHR" ]; then
                disk_list="$FIRST_SHR"
            else
                # descending sort from /dev/sd            
                disk_list=$(sudo $FDISK -l | grep -e "Disk /dev/sd" -e "Disk /dev/nv" | awk '{print $2}' | sed 's/://' | sort -k1.6 -r)
            fi
            
            for edisk in $disk_list; do
         
                model=$(lsblk -o PATH,MODEL | grep $edisk | head -1)
                get_disk_type_cnt "${edisk}" "Y"
                if [ $TB2T_CNT -ge 1 ]; then
                    W95_CNT=$TB2T_CNT
                fi
                
                if [ $RAID_CNT -eq 0 ] && [ $DOS_CNT -eq 3 ] && [ $W95_CNT -eq 0 ] && [ $EXT_CNT -eq 0 ]; then
                    echo "Skip this disk as it is a loader disk. $model"
                    continue
                elif [ -z "${BOOTMAKE}" ] && [ $RAID_CNT -eq 3 ] && [ $DOS_CNT -eq 0 ]; then

                    prepare_grub
                    [ $? -ne 0 ] && return

                    if [ $W95_CNT -ge 1 ]; then
                        # SHR OR RAID can make primary partition
                        echo -e "Create primary partitions on disk. ${model} \n"
                        # get 1st partition's end sector
                        end_sector="$(sudo fdisk -l "${edisk}" | grep "$(get_partition "${edisk}" 1)" | awk '{print $3}')"

                        if [ "${end_sector}" = "4982527" ]; then
                        # Before DSM 7.0.1    
                            last_sector="9176832"
                        else
                        # After DSM 7.1.1
                            last_sector="20979712"
                        fi
                    
                        # +127M
                        echo -e "Create 4th partition on disks... $edisk\n"
                        if [ $TB2T_CNT -ge 1 ]; then
                            if [ -d /sys/firmware/efi ]; then
                                parttype="EF00"
                            else
                                parttype="8300"
                            fi
                            echo -e "n\n4\n$last_sector\n+127M\n$parttype\nw\ny\n" | sudo ${GDISK} "${edisk}" > /dev/null 2>&1
                        else
                            echo -e "n\np\n$last_sector\n+127M\nw\n" | sudo /sbin/fdisk -w always -W always "${edisk}" > /dev/null 2>&1
                        fi

                        # gdisk 명령의 성공 여부 확인
                        if [ $? -ne 0 ]; then
                            echo  -e "Failed to create the 4th partition on ${edisk}. Stop processing!!!\n"
                            remove_loader
                            return
                        fi
                        sleep 2
                        rereadPartitionTable "${edisk}"

                        if [ $? -ne 0 ]; then
                            echo -e "Failed to reread partition table on ${edisk}. Stop processing!!!\n"
                            remove_loader
                            return
                        fi
                        sleep 4         

                        # make 6th partition
                        last_sector="$(sudo fdisk -l "${edisk}" | grep "$(get_partition "${edisk}" 5)" | awk '{print $3}')"
                        # for RAID 1, RAID 5, RAID 6, BASIC ETC...
                        [ -z "${last_sector}" ] && last_sector="$(sudo fdisk -l "${edisk}" | grep "$(get_partition "${edisk}" 3)" | awk '{print $3}')"

                        if [ $TB2T_CNT -ge 1 ]; then
                            # +1 sectors
                            [ -n $last_sector ] && last_sector=$((${last_sector} + 1))
                        else
                            # 2026-08-20: 이전에는 플랫폼별로 +513/+65 섹터의 고정
                            # 오프셋을 뒀는데, 이 값들은 예전 fdisk 버전에서만 우연히
                            # 맞던 매직넘버였다. 최신 util-linux fdisk(2.42.1, 새 로지컬
                            # 파티션에 1MiB 정렬을 강제)에서는 +513으로 부족해 "Sector
                            # X is already allocated"로 거부되고, 스크립트가 예상 못 한
                            # 재입력 프롬프트가 뜨면서 이후 모든 파이프 입력(+13M, w)이
                            # 한 칸씩 밀려 fdisk 자신의 기본값(짜투리 공간 시작부의 작은
                            # 갭)으로 파티션이 엉뚱하게 생기는 문제가 실기에서 재현됨.
                            # 고정 오프셋 대신 1MiB(2048섹터) 경계로 올림한다. 실기에서
                            # 최소 허용 시작 섹터가 딱 다음 경계(+1칸)보다도 더 뒤였던
                            # 것을 확인했으므로(정확한 예약 크기는 알 수 없어 안전하게)
                            # 한 칸 더(+2칸) 여유를 둔다 - 짜투리 공간이 수십~수백MB라
                            # 1MiB 정도 더 쓰는 건 무시할 수준이다.
                            [ -n "${last_sector}" ] && last_sector=$(( (last_sector / 2048 + 2) * 2048 ))
                        fi

                        # +13M
                        echo -e "Create 6th partition on disks... $edisk\n"
                        if [ $TB2T_CNT -ge 1 ]; then
                            echo -e "n\n6\n$last_sector\n+13M\n8300\nw\ny\n" | sudo ${GDISK} "${edisk}" > /dev/null 2>&1
                        else
                            if [ ${ORIGIN_PLATFORM} = "geminilake" ] || [ ${ORIGIN_PLATFORM} = "v1000" ] || [ ${ORIGIN_PLATFORM} = "geminilakenk" ] || [ ${ORIGIN_PLATFORM} = "v1000nk" ] || [ ${ORIGIN_PLATFORM} = "r1000nk" ]; then
                                partsize="12800K"
                            else
                                partsize="13M"
                            fi
                            echo -e "n\n$last_sector\n+$partsize\nw\n" | sudo /sbin/fdisk -w always -W always "${edisk}" > /dev/null 2>&1
                        fi

                        # gdisk 명령의 성공 여부 확인 (6th partition)
                        if [ $? -ne 0 ]; then
                            echo -e "Failed to create the 6th partition on ${edisk}. Stop processing!!!\n"
                            remove_loader
                            return
                        fi
                        sleep 2
                        rereadPartitionTable "${edisk}"

                        if [ $? -ne 0 ]; then
                            echo -e "Failed to reread partition table on ${edisk}. Stop processing!!!\n"
                            remove_loader
                            return
                        fi
                        sleep 4

                        echo -e "Create 7th partition on disks... $edisk\n"
                        if [ $(/sbin/blkid | grep "8765-4321" | wc -l) -eq 0 ]; then
                            # make 7th partition
                            last_sector="$(sudo fdisk -l "${edisk}" | grep "$(get_partition "${edisk}" 6)" | awk '{print $3}')"

                            if [ $TB2T_CNT -ge 1 ]; then
                                # +1 sectors
                                [ -n "${last_sector}" ] && last_sector=$((${last_sector} + 1))
                            else
                                # 6th 파티션과 동일한 이유(고정 섹터 오프셋이 최신 fdisk의
                                # 1MiB 정렬 강제를 못 넘음) - 다음 1MiB 경계로 올림한다.
                                [ -n "${last_sector}" ] && last_sector=$(( (last_sector / 2048 + 2) * 2048 ))
                            fi

                            # about +79M ~ +83M (last all space)
                            if [ $TB2T_CNT -ge 1 ]; then
                                echo -e "n\n7\n\n\n8300\nw\ny\n" | sudo ${GDISK} "${edisk}" > /dev/null 2>&1
                            else
                                echo -e "n\n$last_sector\n\n\nw\n" | sudo /sbin/fdisk -w always -W always "${edisk}" > /dev/null 2>&1
                            fi

                            # gdisk 명령의 성공 여부 확인 (7th partition)
                            if [ $? -ne 0 ]; then
                                echo -e "Failed to create the 7th partition on ${edisk}. Stop processing!!!\n"
                                remove_loader
                                return
                            fi
                            sleep 2
                            rereadPartitionTable "${edisk}"

                            if [ $? -ne 0 ]; then
                                echo -e "Failed to reread partition table on ${edisk}. Stop processing!!!\n"
                                remove_loader
                                return
                            fi
                            sleep 4
                        else
                            echo -e "The synoboot3 was already made!!!\n"
                        fi

                        # Make BIOS Boot Parttion (EF02,GPT) or Activate (MBR)
                        if [ $TB2T_CNT -ge 1 ]; then
                            if [ -d /sys/firmware/efi ]; then
                                echo -e "UEFI does not require a Bios Boot Partition...\n"
                            else
                                if sudo gdisk -l "${edisk}" | grep -q 'EF02'; then
                                    echo -e "EF02 Partition is already exists!!!\n"
                                else
                                    echo -e "n\n\n\n+1M\nEF02\nw\ny" | sudo ${GDISK} "${edisk}" > /dev/null 2>&1
                                fi
                            fi    
                        else
                            echo -e "a\n4\nw" | sudo /sbin/fdisk -w always -W always "${edisk}" > /dev/null 2>&1
                        fi
                        sleep 2
                        rereadPartitionTable "${edisk}"
                        [ $? -ne 0 ] && returnto "Make BIOS Boot Parttion (GPT) or Activate (MBR) on ${edisk} failed. Stop processing!!! " && remove_loader && return
                        sleep 2

                        if [[ $TB2T_CNT -ge 1 ]] && [ -d /sys/firmware/efi ]; then
                            echo "Creating FAT32 filesystem on partition $(get_partition "${edisk}" 4)"
                            sudo mkfs.vfat -i 12345678 -F32 "$(get_partition "${edisk}" 4)" > /dev/null 2>&1
                        else
                            echo "Creating FAT16 filesystem on partition $(get_partition "${edisk}" 4)"
                            sudo mkfs.vfat -i 12345678 -F16 "$(get_partition "${edisk}" 4)" > /dev/null 2>&1
                        fi
                        if [ $? -ne 0 ]; then
                            echo -e "Failed to create filesystem on $(get_partition "${edisk}" 4). Stop processing!!!\n"
                            remove_loader
                            return
                        fi
                        synop1=$(get_partition "${edisk}" 4)
                        wr_part1 "4"
                        [ $? -ne 0 ] && remove_loader && return

                        # 6/7번 파티션은 남는 공간을 그러모아 만드는 몇 MB짜리 스테이징
                        # 공간이라 -F16 을 강제하면 dosfstools가 "too small ... filesystem"
                        # 으로 거부한다(실기에서 재현, 5.9MB 파티션). 크기를 강제하지 않고
                        # mkfs.vfat 이 크기에 맞는 FAT 종류를 알아서 고르게 하고, 실패하면
                        # (구 코드는 여기서 exit code 를 버려서 실패해도 그대로 마운트를
                        # 시도하다 "wrong fs type"으로 뒤늦게 죽었다) 여기서 바로 멈춘다.
                        sudo mkfs.vfat "$(get_partition "${edisk}" 6)" > /dev/null 2>&1
                        if [ $? -ne 0 ]; then
                            echo -e "Failed to create filesystem on $(get_partition "${edisk}" 6). Stop processing!!!\n"
                            remove_loader
                            return
                        fi
                        synop2=$(get_partition "${edisk}" 6)
                        wr_part2 "6"
                        [ $? -ne 0 ] && remove_loader && return

                        #prepare_img
                        sudo mkfs.vfat -i 87654321 "$(get_partition "${edisk}" 7)" > /dev/null 2>&1
                        if [ $? -ne 0 ]; then
                            echo -e "Failed to create filesystem on $(get_partition "${edisk}" 7). Stop processing!!!\n"
                            remove_loader
                            return
                        fi
                        synop3=$(get_partition "${edisk}" 7)
                        wr_part3 "7"
                        [ $? -ne 0 ] && remove_loader && return
                        
                        SYNOP3MAKE="YES"
                        break
                    fi    
           
                else
                    echo "The conditions for adding a fat partition are not met (3 rd, 0 83). $model"
                    continue
                fi
            done
        fi
    elif [ "${do_ex_first}" = "Y" ]; then
        if [ $SHR_EX -eq 1 ]; then
            echo -e "Reinject bootloader (into existing partition)... \n"

            # If there is a SHR disk, only process that disk.
            if [ -n "$FIRST_SHR" ]; then
                disk_list="$FIRST_SHR"
            else
                # descending sort from /dev/sd            
                disk_list=$(sudo $FDISK -l | grep -e "Disk /dev/sd" -e "Disk /dev/nv" | awk '{print $2}' | sed 's/://' | sort -k1.6 -r)
            fi
            
            for edisk in $disk_list; do
         
                model=$(lsblk -o PATH,MODEL | grep $edisk | head -1)
                get_disk_type_cnt "${edisk}" "Y"
                if [ $TB2T_CNT -ge 1 ]; then
                    W95_CNT=$TB2T_CNT
                fi
                
                echo
                if [ $RAID_CNT -eq 0 ] && [ $DOS_CNT -eq 3 ] && [ $W95_CNT -eq 0 ] && [ $EXT_CNT -eq 0 ]; then
                    echo "Skip this disk as it is a loader disk. $model"
                    continue
                elif [ $RAID_CNT -eq 3 ] && [ $DOS_CNT -eq 3 ] && [ $W95_CNT -ge 1 ] && [ $EXT_CNT -eq 0 ]; then
                    # single SHR 
                    prepare_grub
                    [ $? -ne 0 ] && remove_loader && return

                    synop1=$(get_partition "${edisk}" 4)                    
                    wr_part1 "4"
                    [ $? -ne 0 ] && remove_loader && return                    

                    synop2=$(get_partition "${edisk}" 6)                 
                    wr_part2 "6"
                    [ $? -ne 0 ] && remove_loader && return

                    synop3=$(get_partition "${edisk}" 7)
                    wr_part3 "7"
                    [ $? -ne 0 ] && remove_loader && return
                    
                    break
              
                fi
            done
        fi
    fi 
    #sudo losetup -d ${loopdev}
    #[ -z "$(losetup | grep -i ${imgpath})" ] && echo "boot-image-to-hdd.img losetup OK !!!"
    sync
    echo -e "unmount synoboot partitions...${synop1}, ${synop2}, ${synop3} \n"
    synop1=$(echo "${synop1}" | sed 's/dev/mnt/')
    synop2=$(echo "${synop2}" | sed 's/dev/mnt/')
    synop3=$(echo "${synop3}" | sed 's/dev/mnt/')

    sudo rm -rf ${synop1}/boot/grub/locale
    if [ -d /sys/firmware/efi ]; then
        cecho y "Installing BIOS & EFI GRUB-INSTALL..."
        sudo grub-install --target=x86_64-efi --boot-directory=${synop1}/boot --efi-directory=${synop1} --removable
        [ $? -ne 0 ] && returnto "excute grub-install ${synop1} for EFI failed. Stop processing!!! " && false
    else
        cecho y "Installing BIOS GRUB-INSTALL..."
        sudo grub-install --target=i386-pc --boot-directory=${synop1}/boot ${edisk}
        [ $? -ne 0 ] && returnto "excute grub-install ${synop1} for BIOS(CSM,LEGACY) failed. Stop processing!!! " && false
    fi    

    echo
    
    mountpoint -q "${synop1}" && sudo umount ${synop1} 
    mountpoint -q "${synop2}" && sudo umount ${synop2} 
    mountpoint -q "${synop3}" && sudo umount ${synop3}

    sudo $FDISK -l "${edisk}"
    
    returnto "The entire process of injecting the boot loader into the disk has been completed! Press any key to continue..." && return
fi

}

function debug_msg() {
    echo "[DEBUG] $1" >&2
}

function remove_loader() {

  dialog --backtitle "$(backtitle)" --title "Remove Injected Bootloader" \
      --yesno "(Warning) Do you want to remove partitions from Syno disk?" 0 0
  if [ $? -eq 0 ]; then

    tce-load -i gdisk
    if [ $? -eq 0 ]; then
        echo "Install gdisk OK !!!"
    else
        tce-load -iw gdisk
        [ $? -ne 0 ] && returnto "Install gdisk failed. Stop processing!!! " && false
    fi
    
    # Delete partitions with GUID codes 8300 (Linux filesystem) or EF02 (BIOS boot)
    # 모든 디스크 스캔
    LC_ALL=C sudo fdisk -l | grep -E '^Disk /dev/s' | awk '{print $2}' | tr -d ':' | while read -r disk; do
        echo "Processing $disk..."
        
        # 파티션 테이블 유형 확인 (GPT 또는 MBR)
        partition_table=$(sudo fdisk -l "$disk" | grep -E 'dos|gpt' | awk '{print $NF}')
        
        if [[ "$partition_table" == "gpt" ]]; then
            echo "Detected GPT partition table on $disk"
            
            # GPT 디스크의 대상 파티션 찾기 및 삭제
            target_partitions=$(
              sudo sgdisk -p "$disk" | awk '
                ($6 == "EF02" && $1 == 3) || 
                ($6 == "EF00" && $1 == 4) || 
                ($6 == "EF02" && $1 == 5) || 
                ($6 == "8300" && $1 >=4) {print $1}
              ' | sort -nr | tr '\n' ' '
            )
            
            if [[ -n "$target_partitions" ]]; then
                IFS=' ' read -ra partitions <<< "$target_partitions"
                for part in "${partitions[@]}"; do
                    echo "Processing Delete: Partition $part on GPT disk"
                    # 이전 실패한 주입 시도가 이 파티션을 마운트해 둔 채 남아있을 수
                    # 있다(실기에서 재현: /mnt/sdb4가 언마운트 안 된 채로 남아있어서
                    # 다음 재시도의 재파티션이 "Resource busy"로 죽었다). 삭제 전에
                    # 먼저 언마운트한다.
                    sudo umount -f "${disk}${part}" > /dev/null 2>&1
                    sudo sgdisk -d "$part" "$disk" > /dev/null 2>&1
                done
                rereadPartitionTable "$disk" > /dev/null 2>&1
            fi

        elif [[ "$partition_table" == "dos" ]]; then
            echo "Detected MBR (DOS) partition table on $disk"
            
            # MBR 디스크의 대상 파티션 찾기 (4번 파티션 이후로 Linux 타입만)
            target_partitions=$(
              sudo sgdisk -p "$disk" | awk '
                ($6 == "8300" && $1 >=4) {print $1}
              ' | sort -nr | tr '\n' ' '
            )
            
            if [[ -n "$target_partitions" ]]; then
                IFS=' ' read -ra partitions <<< "$target_partitions"
                for part in "${partitions[@]}"; do
                    echo "Processing Delete: Partition $part on MBR disk"
                    # GPT 쪽과 동일한 이유로 삭제 전에 먼저 언마운트한다.
                    sudo umount -f "${disk}${part}" > /dev/null 2>&1
                    echo -e "d\n${part}\nw\n" | sudo fdisk -w always -W always "$disk" > /dev/null 2>&1
                done
                rereadPartitionTable "$disk" > /dev/null 2>&1
            fi

        else
            echo "Unknown partition table type for $disk. Skipping..."
        fi
        
    done
  
  fi
  returnto "The entire process of removing the partition is completed! Press any key to continue..." && return

}

function rploader() {

    getip
    echo "LOADER DISK = ${loaderdisk}"
    [ -z "${loaderdisk}" ] && getloaderdisk
    if [ -z "${loaderdisk}" ]; then
        echo "Not Supported Loader BUS Type, program Exit!!!"
        exit 99
    fi
    
    #getBus "${loaderdisk}" 
    echo -ne "Loader BUS: $(msgnormal "${BUS}")\n"

    tcrppart="${loaderdisk}3"
    tcrpdisk=$loaderdisk

    case $1 in

    build)

        getvars $ORIGIN_PLATFORM
        if [ -d /dev/shm/tcrp-modules/ ]; then
            offline="YES"
        else
            offline="NO"
            check_github
        fi    
#        getlatestrploader
#        gitdownload     # When called from the parent my.sh, -d flag authority check is not possible, pre-downloaded in advance 
        checkUserConfig
        getredpillko
#for test getredpillko
#exit 0
echo "$3"

        [ "$3" = "withfriend" ] && WITHFRIEND="YES" || WITHFRIEND="NO"

        case $3 in

        manual)

            echo "Using static compiled redpill extension"
            echo "Got $REDPILL_MOD_NAME "
            echo "Manual extension handling,skipping extension auto detection "
            echo "Starting loader creation "
            buildloader "manual"
            [ $? -eq 0 ] && savesession
            ;;

        jun)
            echo "Using static compiled redpill extension"
            echo "Got $REDPILL_MOD_NAME "
            listmodules
            echo "Starting loader creation "
            buildloader "junmod"
            [ $? -eq 0 ] && savesession
            ;;

        static | *)
            echo "No extra build option or static specified, using default <static> "
            echo "Using static compiled redpill extension"
            echo "Got $REDPILL_MOD_NAME "
            listmodules 
            echo "Starting loader creation "
            buildloader "static"
            [ $? -eq 0 ] && savesession
            ;;

        esac
        ;;

    clean)
        cleanloader
        ;;

    backup)
        backuploader
        ;;

    postupdate)
        getvars $ORIGIN_PLATFORM
        check_github
        gitdownload
        postupdate
        [ $? -eq 0 ] && savesession
        ;;
    help)
        showhelp
        exit 99
        ;;
    monitor)
        monitor
        exit 0
        ;;    
    *)
        showsyntax
        exit 99
        ;;

    esac
}

function add-addons() {
    jsonfile=$(jq ". |= .+ {\"${1}\": \"https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/${1}/rpext-index.json\"}" /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
}

# NON-DT 모델에서 rploader satamap(실기 SATA 컨트롤러 스캔) 실행 전, user_config.json에
# SataPortMap/DiskIdxMap이 아직 비어 있으면 synoinfo.maxdisks 기준의 넉넉한 기본값을
# 선제로 채워 둔다. 단일 컨트롤러가 maxdisks만큼의 포트를 모두 커버한다고 가정하는
# "안전망" 값이라 실제 컨트롤러 구성과는 다를 수 있지만, 값이 부족해 디스크를 아예
# 인식 못 하는 것보다 과다 매핑(빈 베이 표시 정도)이 안전하다는 판단. satamap이
# 정상 동작하면 이 값은 실측 결과로 덮어써진다. 이미 값이 있으면 건드리지 않는다.
function prefillDefaultSataPortMap() {
    local maxdisks curmap curidx portchar

    maxdisks=$(jq -r '.synoinfo.maxdisks // empty' user_config.json)
    case "$maxdisks" in ''|*[!0-9]*) return 0 ;; esac
    [ "$maxdisks" -lt 1 ] && return 0

    curmap=$(jq -r '.extra_cmdline.SataPortMap // empty' user_config.json)
    curidx=$(jq -r '.extra_cmdline.DiskIdxMap // empty' user_config.json)
    if [ -n "$curmap" ] && [ -n "$curidx" ]; then
        cecho p "SataPortMap/DiskIdxMap already set (${curmap}/${curidx}), skip default prefill."
        return 0
    fi

    # 9포트 초과는 rploader satamap과 동일한 방식(포트수+48을 ASCII 문자로)으로 인코딩.
    if [ "$maxdisks" -gt 9 ]; then
        portchar=$(printf \\$(printf "%o" $((maxdisks + 48))))
    else
        portchar="$maxdisks"
    fi

    cecho p "Pre-filling generous default SataPortMap/DiskIdxMap for maxdisks=${maxdisks} (single-controller blanket: ${portchar}/00)"
    json="$(jq --arg m "$portchar" '.extra_cmdline.SataPortMap = $m | .extra_cmdline.DiskIdxMap = "00"' user_config.json)" && echo -E "${json}" | jq . >user_config.json

    # writeConfigKey()를 거치지 않고 jq로 직접 썼기 때문에, 그 함수가 항상 같이
    # 호출해 주는 sync_usb_line()이 자동으로 따라오지 않는다. 이걸 빼먹으면
    # extra_cmdline에는 값이 들어가도 general.usb_line에는 반영이 안 되는 상태로
    # 남는다 - 직접 호출로 맞춰준다.
    sync_usb_line
}

function my() {

  echo "$1"
  echo "$2"
  echo "$3"

  echo "LOADER DISK = ${loaderdisk}"
  [ -z "${loaderdisk}" ] && getloaderdisk
  if [ -z "${loaderdisk}" ]; then
      echo "Not Supported Loader BUS Type, program Exit!!!"
      exit 99
  fi

  echo "${loaderdisk}" > /tmp/loaderdisk
  
  #getBus "${loaderdisk}" 
    
  tcrppart="${loaderdisk}3"

  if [ "${BUS}" = "block" ]; then
    # clone 실패를 확인하지 않으면 이어지는 mv -f ./tcrp-addons/* 가
    # "no such file or directory" 로 조용히 실패하거나 아무것도 옮기지
    # 못한 채 넘어가, /dev/shm/tcrp-addons 가 빈 상태로 빌드가 계속
    # 진행되다가 한참 뒤 확장 설치 단계에서야 실패가 드러난다.
    if ! git clone --depth=1 "https://github.com/PeterSuh-Q3/tcrp-addons.git" || \
       [ ! -d ./tcrp-addons/.git ]; then
      echo "[ERROR] Failed to clone tcrp-addons from GitHub. Check network connectivity and try again."
      exit 99
    fi
    mkdir -p /dev/shm/tcrp-addons
    rm -rf ./tcrp-addons/.git/
    mv -f ./tcrp-addons/* /dev/shm/tcrp-addons/
  fi
  
  if [ -d /dev/shm/tcrp-modules/ ]; then
      offline="YES"
  else
      offline="NO"
      check_github
      if [ "$gitdomain" = "raw.githubusercontent.com" ]; then
          if [ $# -lt 1 ]; then
              getlatestmshell "ask"
          else
              if [ "$1" = "update" ]; then 
                  getlatestmshell "noask"
                  exit 0
              else
                  if [ "${BUS}" != "block" ]; then
                      [ "$TCB" = "true" ] && getlatestmshell "noask"
                  fi    
              fi
          fi
      fi
      gitdownload
  fi
  
  if [ $# -lt 1 ]; then
      showhelp 
      exit 99
  fi
  
  getvarsmshell "$1"

  #echo "$TARGET_REVISION"                                                      
  #echo "$TARGET_PLATFORM"                                            
  #echo "$SYNOMODEL"                                      
  
  postupdate="N"
  userdts="N"
  noconfig="N"
  jot="N"
  prevent_param="N"
  
  shift
      while [[ "$#" > 0 ]] ; do
  
          case $1 in
          postupdate)
              postupdate="Y"
              ;;
              
          userdts)
              userdts="Y"
              ;;
  
          noconfig)
              noconfig="Y"
              ;;
           
          jot)
              jot="Y"
              ;;
  
          fri)
              jot="N"
              ;;
  
          prevent_param)
              prevent_param="Y"
              ;;
  
          *)
              echo "Syntax error, not valid arguments or not enough options"
              exit 99
              ;;
  
          esac
          shift
      done
  
  #echo $postupdate
  #echo $userdts
  #echo $noconfig
  
  echo
  
  if [ "$tcrppart" = "mmc3" ]; then
      tcrppart="mmcblk0p3"
  fi
  
  echo
  echo "loaderdisk is" "${loaderdisk}"
  echo
  
  if [ ! -d "/mnt/${tcrppart}/auxfiles" ]; then
      cecho g "making directory  /mnt/${tcrppart}/auxfiles"  
      mkdir -p /mnt/${tcrppart}/auxfiles 
  fi
  if [ ! -h /home/tc/custom-module ]; then
      cecho y "making link /home/tc/custom-module"  
      sudo ln -s /mnt/${tcrppart}/auxfiles /home/tc/custom-module 
  fi
  
  local_cache="/mnt/${tcrppart}/auxfiles"
  
  #if [ -d ${local_cache/extractor /} ] && [ -f ${local_cache}/extractor/scemd ]; then
  #    echo "Found extractor locally cached"
  #else
  #    cecho g "making directory  /mnt/${tcrppart}/auxfiles/extractor"  
  #    mkdir /mnt/${tcrppart}/auxfiles/extractor
  #    sudo curl --insecure -L --progress-bar "https://$gitdomain/PeterSuh-Q3/tinycore-redpill/${build}/extractor.gz" --output /mnt/${tcrppart}/auxfiles/extractor/extractor.gz
  #    sudo tar -zxvf /mnt/${tcrppart}/auxfiles/extractor/extractor.gz -C /mnt/${tcrppart}/auxfiles/extractor
  #fi
  
  echo
  cecho y "TARGET_PLATFORM is $TARGET_PLATFORM"
  cecho r "ORIGIN_PLATFORM is $ORIGIN_PLATFORM"
  cecho c "TARGET_VERSION is $TARGET_VERSION"
  cecho p "TARGET_REVISION is $TARGET_REVISION"
  cecho g "SYNOMODEL is $SYNOMODEL"  
  cecho c "KERNEL VERSION is $KVER"  
  cecho c "ZPAD KERNEL VERSION is $ZPADKVER"

  if [ "$ZPADKVER" -le 4004059 ]; then
    if [ "${BUS}" != "block" ]; then
        if [ -d /sys/firmware/efi ]; then
          msgalert "It does not work in UEFI boot mode on kernel versions 4.4.59 and earlier.\n"
          msgalert "Change to CSM Enabled Legacy Mode (Not Legacy Boot Mode). Aborting the loader build!!!\n"
          echo "press any key to continue..."      
          read answer 
          exit 99
        fi  
    fi    
    if [ "${BUS}" = "nvme" ] || [ "${BUS}" = "mmc" ]; then
      msgalert "Kernel versions 4.4.59 and earlier have restrictions on the use of NVME or MMC type bootloaders!!!\n"
      echo "Aborting the loader build, press any key to continue..."
      read answer
      exit 99
    fi
    if [ "${BUS}" != "block" ]; then
        if [ "${DMPM}" != "DDSML" ]; then    
          msgalert "Kernel versions 4.4.59 and earlier have restricted 'EUDEV' usage.!!!\n"
          echo "Aborting the loader build, press any key to continue..."
          read answer
          exit 99
        fi
    fi    
    if echo ${dsm6notsupported} | grep -qw ${ORIGIN_PLATFORM}; then
      msgalert "DSM 6.2.4 ${ORIGIN_PLATFORM} will be temporarily unavailable until system instability is confirmed!!!\n"
      echo "Aborting the loader build, press any key to continue..."
      read answer
      exit 99
    fi
  fi
    
  st "buildstatus" "Building started" "Model :$MODEL-$TARGET_VERSION-$TARGET_REVISION"
  [ "${BUS}" != "block" ] && log_build_step "Building started" 1 12
  
  #fullupgrade="Y"
  
  cecho y "If fullupgrade is required, please handle it separately."
  
  cecho g "Downloading Peter Suh's custom configuration files.................."
  
  writeConfigKey "general" "kver" "${KVER}"
  
  DMPM="$(jq -r -e '.general.devmod' $userconfigfile)"
  if [ "${DMPM}" = "null" ]; then
      DMPM="DDSML"
      writeConfigKey "general" "devmod" "${DMPM}"
  fi
  cecho y "Device Module Processing Method is ${DMPM}"

  MDLNAME="$(jq -r -e '.general.modulename' $userconfigfile)"
  if [ "${MDLNAME}" = "null" ]; then
      MDLNAME="all-modules"
      writeConfigKey "general" "modulename" "${MDLNAME}"
  fi
  cecho y "The selected integrated module pack is ${MDLNAME}"
  
  # Preserve ALL user-toggled addons across the GitHub reset via a generated
  # /home/tc/merged-addons.json (= current bundled-exts MINUS the fresh GitHub
  # default MINUS module packs). This replaces the old hardcoded capture list,
  # so ANY addon (mac-spoof, dbgutils, nvidiadriver, future ones) survives
  # generically with no per-addon code.
  echo  "download original bundled-exts.json file..."
  if [ -f /tmp/test_mode ]; then
    cecho g "###############################  This is Test Mode  ############################"
    curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/bundled-exts_t.json -o /tmp/default-bundled-exts.json
  else
    curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/bundled-exts.json -o /tmp/default-bundled-exts.json
  fi
  # user addons = keys present now but NOT in the fresh default, minus module packs
  if [ -s /tmp/default-bundled-exts.json ] && jq -e . /tmp/default-bundled-exts.json >/dev/null 2>&1; then
    jq -s '
      .[0] as $cur | .[1] as $def |
      ["all-modules","custom-modules","anodrm-modules"] as $excl |
      $cur | with_entries( .key as $k | select( (($def|has($k))|not) and (($excl|index($k))==null) ) )
    ' /home/tc/redpill-load/bundled-exts.json /tmp/default-bundled-exts.json > /home/tc/merged-addons.json
    cecho y "merged-addons.json (preserved): $(jq -r 'keys | join(", ") // "(none)"' /home/tc/merged-addons.json)"
    cp -f /tmp/default-bundled-exts.json /home/tc/redpill-load/bundled-exts.json
  else
    cecho p "[!] default bundled-exts.json download failed - keeping existing file (addons intact)"
  fi

  if [ "${DMPM}" = "DDSML" ]; then
      jq 'del(.eudev, .aeudev)' \
        /home/tc/redpill-load/bundled-exts.json > /tmp/bundled-exts.tmp && \
        mv /tmp/bundled-exts.tmp /home/tc/redpill-load/bundled-exts.json
  elif [ "${DMPM}" = "EUDEV" ]; then
      jsonfile=$(jq 'del(.ddsml)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  elif [ "${DMPM}" = "DDSML+EUDEV" ]; then
      cecho p "It uses both ddsml and eudev from /home/tc/redpill-load/bundled-exts.json file"
  else
      cecho p "Device Module Processing Method is Undefined, Program Exit!!!!!!!!"
      exit 99
  fi

  # bundled-exts.json 의 *-modules 키를 selectldrmode() 가 저장한 MDLNAME 으로 재적용.
  # 위 curl 이 GitHub 원본으로 덮어썼으므로 여기서 다시 정정해야
  # custom-modules 선택이 보존된다. 모듈별로 저장소가 다름:
  #   all-modules    → tcrp-modules/main/all-modules/rpext-index.json
  #   custom-modules → tcrp-modules/main/custom-modules/rpext-index.json
  case "${MDLNAME}" in
    all-modules)    _MDLURL="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/all-modules/rpext-index.json" ;;
    custom-modules) _MDLURL="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-modules/main/custom-modules/rpext-index.json" ;;
    *) _MDLURL="" ;;
  esac
  if [ -n "${_MDLURL}" ] && [ -f /home/tc/redpill-load/bundled-exts.json ]; then
    jsonfile=$(jq --arg name "${MDLNAME}" --arg url "${_MDLURL}" '
        del(.["all-modules"])
      | del(.["custom-modules"])
      | . + {($name): $url}
    ' /home/tc/redpill-load/bundled-exts.json) && echo "${jsonfile}" | jq . > /home/tc/redpill-load/bundled-exts.json
    cecho y "bundled-exts.json: *-modules entry set to ${MDLNAME}"
  fi
  unset _MDLURL

  #if [ "$MACHINE" = "VIRTUAL" ]; then
  #    jsonfile=$(jq 'del(.acpid)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  #fi
  
  # re-apply ALL preserved user addons generically from merged-addons.json
  if [ -s /home/tc/merged-addons.json ]; then
    jsonfile=$(jq -s '.[0] * .[1]' /home/tc/redpill-load/bundled-exts.json /home/tc/merged-addons.json) && echo "${jsonfile}" | jq . > /home/tc/redpill-load/bundled-exts.json
    cecho y "bundled-exts.json: re-applied user addons -> $(jq -r 'keys | join(", ") // "(none)"' /home/tc/merged-addons.json)"
  fi

  [ "${offline}" = "NO" ] && curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/${build}/models.json

  if [ "${MDLNAME}" = "all-modules" ]; then
      sed -i "s/rr-modules/all-modules/g" models.json
  elif [ "${MDLNAME}" = "rr-modules" ]; then
      sed -i "s/all-modules/rr-modules/g" models.json
  fi  
  
  echo
  if [ "$jot" = "N" ]; then    
  cecho y "This is TCRP friend mode"
  else    
  cecho y "This is TCRP original jot mode"
  fi
  
  if [ -f /home/tc/custom-module/${TARGET_PLATFORM}.dts ]; then
      sed -i "s/dtbpatch/redpill-dtb-static/g" models.json
  fi
  
  if [ "$postupdate" = "Y" ]; then
      cecho y "Postupdate in progress..."  
      sudo rploader postupdate ${TARGET_PLATFORM}-7.1.1-${TARGET_REVISION}
  
      echo                                                                                                                                        
      cecho y "Backup in progress..."
      echo                                                                                                                                        
      echo "y"|rploader backup    
      exit 0
  fi
  
  if [ "$userdts" = "Y" ]; then
      
      cecho y "user-define dts file make in progress..."  
      echo
      
      cecho g "copy and paste user dts contents here, press any key to continue..."      
      read answer
      sudo vi /home/tc/custom-module/${TARGET_PLATFORM}.dts
  
      cecho p "press any key to continue..."
      read answer
  
      echo                                                                                                                                        
      cecho y "Backup in progress..."
      echo                                                                                                                                        
      echo "y"|rploader backup    
      exit 0
  fi
  
  echo

  checkmachine

  # DT(Device-Tree) 모델 여부. noconfig/non-noconfig 두 분기 모두에서 SataPortMap
  # 관련 처리 대상인지 판단하는 데 같은 기준을 쓴다.
  # 2026-08-19: 하드코딩된 v1000/r1000/geminilake(nk) 목록이 실제 공식
  # DT/kernel5 플랫폼 목록(kver5platforms, functions.sh:165)과 어긋나 있어
  # epyc7002(SA6400)/epyc7003/epyc7003ntb/icelaked 이 빠져 있었다 - 이
  # 플랫폼들은 DT(model.dts의 internal_slot)로 디스크를 매핑해서
  # SataPortMap/DiskIdxMap 을 아예 안 쓰는데도 prefillDefaultSataPortMap()이
  # 불필요하게 채워 넣고 있었다(svrforum.com/all_nas/3173289, N54L+SA6400
  # HBA 조합에서 온보드 SATA SSD 하나가 누락되는 문의 중 발견). 실제
  # 플랫폼 목록을 그대로 재사용해 어긋날 일이 없게 한다.
  DT_MODEL="N"
  if [ "$ORIGIN_PLATFORM" = "v1000" ] || [ "$ORIGIN_PLATFORM" = "r1000" ] || [ "$ORIGIN_PLATFORM" = "geminilake" ] || \
     echo "${kver5platforms}" | grep -qw "${ORIGIN_PLATFORM}"; then
      DT_MODEL="Y"
  fi

  if [ "$noconfig" = "Y" ]; then
      cecho r "SN Gen/Mac Gen/Vid/Pid/SataPortMap detection skipped!!"
      if [ "${prevent_param}" = "N" ]; then
          cecho p "Remove Sataportmap,DiskIdxMap"
          json="$(jq 'del(.extra_cmdline.SataPortMap, .extra_cmdline.DiskIdxMap)' user_config.json)" && echo -E "${json}" | jq . >user_config.json
      fi
      # menu_m.sh의 실제 빌드 메뉴는 항상 noconfig 인자를 붙여서 my()를 호출하므로
      # (menu_m.sh:1561/1563), 이 분기가 실사용자의 정상 빌드 경로다. satamap 실측
      # 탐지 자체가 이 분기에서는 절대 돌지 않으므로, 여기서도 넉넉한 기본값을
      # 채워야 한다 - 예전에는 else 분기(non-noconfig, CLI에서만 접근 가능)에만
      # 있어 메뉴 빌드에서는 죽은 코드였다(실기 45.34에서 재현/확인됨).
      [ "${DT_MODEL}" = "N" ] && prefillDefaultSataPortMap
  else
      cecho c "Before changing user_config.json"
      cat user_config.json
      echo "y"|rploader identifyusb

      if [ "${DT_MODEL}" = "Y" ]; then
          cecho p "Device Tree based model does not need SataPortMap setting...."
      else
          prefillDefaultSataPortMap
          rploader satamap
      fi
      cecho y "After changing user_config.json"
  fi
  cat user_config.json  
  
  echo
  echo
  DN_MODEL="$(echo $MODEL | sed 's/+/%2B/g')"
  echo "DN_MODEL is $DN_MODEL"

  BUILD=$(jq -r -e '.general.version' "$userconfigfile")

  echo "BUILD is $BUILD"
  
  cecho p "DSM PAT file pre-downloading in progress..."
  
  echo  "download original pats.json file..."
  pats_url="https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/config/pats.json"
  pats_t_url="https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/config/pats_t.json"
  if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
    curl -skL# $pats_t_url -o $configfile
  else
    if [ -f /tmp/test_mode ]; then
        cecho g "###############################  This is Test Mode  ############################"
        curl -skL# $pats_t_url -o $configfile
    else
        [ "${BUS}" == "block" ] && curl -skL# $pats_t_url -o $configfile || curl -skL# $pats_url -o $configfile
    fi
  fi
  # mirror the persistent copy into redpill-load/config for the loader build
  [ -s "$configfile" ] && [ -d /home/tc/redpill-load/config ] && cp -f "$configfile" "$configfile_loader"

  URL=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.url) | .[0]" "${configfile}")
  cecho y "$URL"
  if [[ $BIOS_CNT -eq 1 ]] && [ "$FRKRNL" = "YES" ]; then 
      patfile="/dev/shm/${SYNOMODEL}.pat"
  else
      patfile="/mnt/${tcrppart}/auxfiles/${SYNOMODEL}.pat"
  fi    
  
  if [ "$TARGET_VERSION" = "7.2" ]; then
      TARGET_VERSION="7.2.0"
  fi
  if [ "$TARGET_VERSION" = "7.3" ]; then
      TARGET_VERSION="7.3.0"
  fi
  
#  if [[ "${BUS}" != "block" ]] && [[ "$TARGET_VERSION" == "7.3"* ]]; then
#      msgnormaltty "We recommend using the Synology Control Panel update for DSM 7.2.2 and earlier, rather than the loader build for DSM 7.3.X.\n"
#      msgnormaltty "After this Control Panel update, FRIEND kernels v0.1.3w and later will automatically upgrade to DSM 7.3.2.\n"
#      msgnormaltty "If you still want this build, it will only be allowed if the corresponding version of DSM 7.3.X has been pre-installed on your Synology Disk.\n"
#      msgnormaltty "Please note that building the loader without prior updates may result in network unresponsiveness and system partition initialization.\n"
#      msgwarningtty "(Warning) If you build without checking the version, the system partition may be initialized.\n"
#      msgwarningtty "(Warning) Do you want to continue building this version? or Skip version checking? [yY/nN/sS] : "
#
#      if [ "${ucode}" == "ko_KR" ]; then
#          msgnormaltty "DSM 7.3.X 의 로더빌드 보다는 DSM 7.2.2 이하에서 시놀로지 제어판의 업데이트 사용을 권장합니다.\n"
#          msgnormaltty "이 제어판 업데이트 이후 FRIEND 커널 v0.1.3w 이상에서 DSM 7.3.2 로의 업그레이드가 자동진행됩니다.\n"
#          msgnormaltty "그래도 이 빌드를 원하신다면, 해당 버전의 DSM 7.3.X 를 시노디스크에 미리 설치한 경우만 빌드를 허용합니댜.\n"
#          msgnormaltty "사전 업데이트 없이 로더부터 빌드하면, 네트워크 무반응, 시스템 파티션 초기화 현상을 동반할 수 있으므로 주의하시기 바랍니다.\n"
#          msgwarningtty "(경고) 버전 확인 없이 빌드하면 시스템 파티션이 초기화될 수 있습니다.\n"
#          msgwarningtty "(경고) 이 버전을 계속 빌드하시겠습니까? 아니면 버전 확인을 건너뛰시겠습니까? [yY/nN/sS] : "
#      fi      
#      readanswerwithskip
#      if [ "${answer}" = "S" ] || [ "${answer}" = "s" ]; then
#          printf "[OK] Now skip checking DSM version. Continue...\n" > /dev/tty
#      elif [ "${answer}" = "N" ] || [ "${answer}" = "n" ]; then
#          exit 99
#      elif [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then
#          if chkDsmversion; then
#              printf "[OK] The DSM versions match. Or, there is no DSM. Continue...\n" > /dev/tty
#          else
#              msgalerttty "[FAIL] Pre Installed DSM version mismatch or verification failed. Exiting.\n"
#              [ "${ucode}" == "ko_KR" ] && msgwarningtty "[FAIL] 사전설치된 DSM version 이 불일치 하거나 검증에 실패했습니다. 종료합니다.\n"
#              exit 99
#          fi    
#      fi    
#  fi

  #if [ "$ORIGIN_PLATFORM" = "apollolake" ] || [ "$ORIGIN_PLATFORM" = "geminilake" ]; then
  #   jsonfile=$(jq 'del(.drivedatabase)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  #   sudo rm -rf /home/tc/redpill-load/custom/extensions/drivedatabase
  #   jsonfile=$(jq 'del(.reboottotcrp)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  #   sudo rm -rf /home/tc/redpill-load/custom/extensions/reboottotcrp
  #fi   

  [ -f /mnt/${tcrppart}/auxfiles/sa6400_86009.pat ] && sudo rm -f /mnt/${tcrppart}/auxfiles/sa6400_86009.pat

  if [ "${BUS}" != "block" ]; then
    if [[ "${MLMETHOD}" = "PML" && "${MDLNAME}" != "all-modules" ]]; then
        echo "Discover left space for ${MDLNAME} initrd-dsm ... "        
        SPACELEFT=$(df --block-size=1 | awk '/'${loaderdisk}'3/{print $4}') # Check disk space left    
        SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
        SPACELEFT_MB=$((SPACELEFT / 1024 / 1024))    
        echo "SPACELEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"
    
        SPACELEFT_MB=$(df -BM --output=avail /dev/"${loaderdisk}"3 | tail -1 | sed 's/M//')
        if [ "${SPACELEFT_MB%.*}" -le 800 ]; then  # 800MB 기준
            echo "Insufficient space (${SPACELEFT_MB}MB), cleaning up... Space has been freed up. Now, please rebuild."
            sudo rm -rf /mnt/${tcrppart}/auxfiles/*.pat
            exit 99
        fi    
    fi    
  fi  
  if [ -f ${patfile} ]; then
      cecho r "Found locally cached pat file ${SYNOMODEL}.pat in /mnt/${tcrppart}/auxfiles"
      cecho b "Downloadng Skipped!!!"
  st "download pat" "Found pat    " "Found ${SYNOMODEL}.pat"
  [ "${BUS}" != "block" ] && log_build_step "Found pat file" 2 12
  else
  
  st "download pat" "Downloading pat  " "${SYNOMODEL}.pat"        
  [ "${BUS}" != "block" ] && log_build_step "Download pat file" 2 12
      #if [ 1 = 0 ]; then
      #  STATUS=`curl --insecure -w "%{http_code}" -L "${URL}" -o ${patfile} --progress-bar`
      #  if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      #    echo  "Check internet or cache disk space"
      #    exit 99
      #  fi
      #else
      echo "offline = ${offline}"
        [ "${offline}" = "NO" ] && _pat_process    
      #fi
  
      os_md5=$(md5sum ${patfile} | awk '{print $1}')                                
      cecho y "Pat file md5sum is : $os_md5"                                       
       
      verifyid=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.sum) | .[0]" "${configfile}")
      cecho p "verifyid md5sum is : $verifyid"                                        
  
      if [ "$os_md5" = "$verifyid" ]; then                                            
          cecho y "pat file md5sum is OK ! "                                           
      else                                                                                
          cecho y "os md5sum verify FAILED, check ${patfile} "
          exit 99                                                                         
      fi
  fi
  
  echo
  cecho g "Loader Building in progress..."
  echo
  
  if [ "$MODEL" = "SA6400" ] && [ "${BUS}" = "usb" ] && [ "${MDLNAME}" != "custom-modules" ]; then
      cecho g "Remove Exts for SA6400 (thethorgroup.boot-wait) ..."
      jsonfile=$(jq 'del(.["thethorgroup.boot-wait"])' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
      sudo rm -rf /home/tc/redpill-load/custom/extensions/thethorgroup.boot-wait

      cecho g "Remove Exts for SA6400 (automount) ..."
      jsonfile=$(jq 'del(.["automount"])' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
      sudo rm -rf /home/tc/redpill-load/custom/extensions/automount
  fi
  
  if [ "$jot" = "N" ]; then
      echo "n"|rploader build ${TARGET_PLATFORM}-${BUILD} withfriend
  else
      echo "n"|rploader build ${TARGET_PLATFORM}-${BUILD} static
  fi

  errorcode=$?
  echo "errorcode = $errorcode"

  if [ "$errorcode" != "0" ]; then
      cecho r "An error occurred while building the loader!!! Clean the redpill-load directory!!! "
      echo "y"|rploader clean
  else
      cleanupmemory
      [ "${BUS}" = "block" ] && exit 0
      [ "$MACHINE" != "VIRTUAL" ] && sleep 2
      echo "y"|rploader backup
  fi
  return $errorcode
#[ "$FRKRNL" = "YES" ] && readanswer  
}

if [ $# -gt 1 ]; then
    case $1 in
    
    my) 
        getloaderdisk
        getBus "${loaderdisk}"
        my "$2" "$3" "$4"
        ;;
    update)
        upgrademan "$2"
        ;;
    autoupdate)
        changeautoupdate "$2"
        ;;
    *)
        ;;
    esac    
fi

# 2026-08-01: gfxpayload=1280x960 고정은 QEMU/virtio-gpu(가상 디스플레이는 어떤
# 모드든 받아줌) 기준으로 정해진 값이라, 이 4:3 해상도를 EDID에 갖고 있지 않은
# 실물 FHD/HD 모니터에서 "지원되지 않는 해상도"로 거부당하는 사례가 실사용자
# (N54L, 모니터 2대 다 재현)에게서 보고됨. keep 으로 바꿔 펌웨어가 이미 잡아둔
# 모드를 그대로 이어받게 한다 - sx 안의 터미널 4개는 픽셀좌표가 아니라 글자단위
# 크기 + openbox Smart 배치라 해상도가 달라져도 안전(참고: xorg.conf.d/
# 20-monitor.conf 의 Virtual-1 프리퍼드모드도 동일한 가상환경 전제라 실기에서는
# 원래도 매칭 안 되고 무시됨 - 별도 처리 불필요).
# 아래 heredoc 은 grub.cfg 에 그대로 append 되는 실제 텍스트이므로 절대 그
# 안쪽에 셸/설명용 주석을 넣지 말 것 - GRUB 파서가 menuentry 블록 내부의
# 줄을 어떻게 다룰지 보장이 없어 예기치 않은 파싱 오류를 일으킬 수 있다.
function alpineentry() {
    cat <<EOF
menuentry 'Alpine Redpill Image Build' {
        savedefault
        search --set=root --label alpine --hint hd0,msdos4
        set gfxpayload=keep
        echo Loading Linux...
        linux /vmlinuz-lts loglevel=3 console=ttyS0 console=tty1 video=Virtual-1:1280x960 modules=nvme,nvme-core,hwmon
        echo Loading initramfs...
        initrd /initramfs-lts
        echo Booting Alpine for loader creation
}
EOF
}

# mshellSymlinkUserConfig()(위쪽, is_alpine() 바로 다음에 정의)는
# 반드시 파일 맨 끝에서 호출해야 한다 - getloaderdisk/getBus/
# ensure_loader_partition_mounted 를 내부에서 쓰는데 이 함수들은 전부
# 이 지점보다 한참 뒤가 아니라 이미 위에서 정의가 끝난 상태라야 호출
# 가능하다. bash는 파일을 위에서 아래로 순차 실행하므로, 정의보다 먼저
# 호출하면(테스트 트랙에서 과거 자기 정의 바로 다음 줄에 호출을 뒀다가
# 이 증상으로 깨진 적이 있다) "command not found"로 즉시 죽는다 -
# 실기에서 정확히 이 증상으로 재현/확인됨.
mshellSymlinkUserConfig
