#!/bin/bash
# Synology 단일 디스크 시스템 파티션(md0) 2.4G -> 8.0G in-place 확장 (외부 백업 불필요)
#
# 대상 구조 : LVM 기반 풀  (md2 -> vg1 -> volume_1 btrfs)
#             * 순수 BASIC(md2 위 btrfs 직접)인 경우 Phase1/5 의 lvm 단계만 빼면 됨
# 동작 개요 : 계층 축소(btrfs < LV < PV < md2) -> 데이터 소량 역방향 이동 -> 8G 정확 재파티션
#             -> md0 0.90 재생성 + resize2fs(데이터오프셋0 이라 ext4 보존) -> md2/LVM/btrfs 14G 재확장 -> swap
# 실행 환경 : TinyCore(tc) 로더 박스에서 sudo 로 실행
#
# 사용법: sudo bash expand-md0-8g.sh <disk> [--from-phase N]
#   <disk>          : 대상 디스크 (예: /dev/sda)
#   --from-phase N  : N 단계(1-6)부터 실행. 이전 단계가 완료된 상태에서 재실행 시 사용.
#                     주의: Phase 1(축소)이 완료된 상태에서 --from-phase 2 이상 사용 가능.
#
# *** 경고: Phase 2(이동)~Phase 3(재파티션) 구간은 무중단 보장이 안 됨(정전/리셋=복구불가).
#           단일 디스크 무중복이므로 테스트/파괴가능 환경, 또는 사전 백업이 있는 경우에만 사용. ***
set -e
MDADM=/usr/local/sbin/mdadm; BTRFS=/usr/local/bin/btrfs; LVM=/usr/local/sbin/lvm
SFDISK=/usr/local/sbin/sfdisk; E2FSCK=/sbin/e2fsck; BLOCKDEV=/usr/local/sbin/blockdev

### ===== 인자 파싱 =====
DISK=${1:-/dev/sdb}
FROM_PHASE=1
if [ "$2" = "--from-phase" ] && [ -n "$3" ]; then
    FROM_PHASE=$3
fi

P1_SIZE=16777216   # 시스템 파티션 목표 크기 8.00 GiB (sectors)
P2_SIZE=4194304    # swap 2.00 GiB (sectors)
VG=vg1; LV=volume_1
CHUNK_SECTORS=524288   # 256 MiB 이동 청크
SB_BIN=/tmp/md0_sb.bin

ts(){ date +%H:%M:%S; }
log(){ echo "[$(ts)] $*"; }
skip(){ log "--- Phase $1 건너뜀 (--from-phase ${FROM_PHASE}) ---"; }

log "===== md0 2.4G -> 8G in-place 확장 on ${DISK} (from-phase=${FROM_PHASE}) ====="

# resize2fs(e2fsprogs) 선확보 - TinyCore 기본 이미지엔 없을 수 있음
if [ -z "$(which resize2fs 2>/dev/null)" ]; then
  log "e2fsprogs 설치 시도 (로컬 캐시)"
  su tc -c "tce-load -i e2fsprogs" 2>/dev/null || true
  if [ -z "$(which resize2fs 2>/dev/null)" ]; then
    log "e2fsprogs 설치 시도 (네트워크)"
    su tc -c "tce-load -wi e2fsprogs" || true
  fi
fi
RESIZE2FS=$(which resize2fs 2>/dev/null || find /usr/local/sbin /usr/sbin /sbin -name resize2fs 2>/dev/null | head -1)
[ -n "${RESIZE2FS}" ] || { log "ERROR: resize2fs 없음 — 'tce-load -wi e2fsprogs' 를 수동으로 실행 후 재시도"; exit 1; }

# ===== 공통 레이아웃 감지 =====
# Phase 2 이후부터 시작할 때는 p1이 이미 2.4G인지 확인하지 않으므로
# 재파티션 전 기준값을 디스크에서 다시 읽는다.
P1_START=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}1 .*start=[[:space:]]*\([0-9]*\).*#\1#p")
[ -n "${P1_START}" ] || { log "ERROR: ${DISK}1 파티션을 찾을 수 없음"; exit 1; }
case "${P1_START}" in
  2048|8192) ;;
  *) log "ERROR: 예상치 못한 P1_START=${P1_START} — Synology 표준(2048/8192) 아님"; exit 1 ;;
esac
P2_START=$(( P1_START + P1_SIZE ))
P3_START=$(( P2_START + P2_SIZE ))
log "P1_START=${P1_START}  P2_START=${P2_START}  P3_START=${P3_START}"

$SFDISK -l ${DISK} 2>/dev/null | grep "${DISK}[123]"
TOTAL=$($BLOCKDEV --getsz ${DISK}); P3_SIZE=$(( TOTAL - P3_START ))

# Phase 1에만 필요한 OLD 값 (Phase 2 이후 --from-phase 사용 시 irrelevant)
OLD_P1_SIZE=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}1 .*size=[[:space:]]*\([0-9]*\).*#\1#p")
OLD_P3_START=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}3 .*start=[[:space:]]*\([0-9]*\).*#\1#p")

# ===== 사전 감지: md0 슈퍼블록 유무 (모든 Phase 공통) =====
# Phase 4 분기 기준을 스크립트 시작 시점에 결정한다.
# --from-phase 로 Phase 1을 건너뛰어도 동일하게 판단된다.
SB_OFF_OLD=$(( (OLD_P1_SIZE & ~31) - 32 ))
dd if=${DISK}1 of=${SB_BIN} bs=512 skip=${SB_OFF_OLD} count=8 2>/dev/null
SB_MAGIC=$(od -A n -t x1 -N 4 ${SB_BIN} 2>/dev/null | tr -d ' \n')
if [ "${SB_MAGIC}" = "fc4e2ba9" ]; then
    MD0_METHOD=restore
    log "md0 슈퍼블록 감지(0.90) → Phase 4: backup/restore 방식"
else
    MD0_METHOD=create
    log "md0 슈퍼블록 없음(got=${SB_MAGIC}) → Phase 4: --create 방식"
fi

# ===== Phase 1: btrfs -> LV -> PV -> md2 축소 + md0 슈퍼블록 백업 =====
if [ "${FROM_PHASE}" -le 1 ]; then
    log "--- Phase 1: btrfs -> LV -> PV -> md2 축소 ---"
    [ -n "${OLD_P3_START}" ] || { log "ERROR: ${DISK}3 없음"; exit 1; }
    [ ${P3_START} -gt ${OLD_P3_START} ] || { log "ERROR: 이동 방향 오류 (이미 8G?)"; exit 1; }
    log "OLD P1_SIZE=${OLD_P1_SIZE}  OLD_P3_START=${OLD_P3_START}  NEW_P3_START=${P3_START}"

    $MDADM --stop /dev/md2 2>/dev/null || true
    $MDADM --assemble --run /dev/md2 ${DISK}3
    $LVM vgchange -ay ${VG}
    mkdir -p /mnt/d2
    BTRFS_MOUNTED=0
    if mount -t btrfs /dev/mapper/${VG}-${LV} /mnt/d2 2>/dev/null; then
        BTRFS_MOUNTED=1
        USED_MiB=$(df -m /mnt/d2 | awk 'NF==5{print $2} NF==6{print $3}')
        log "btrfs used ~${USED_MiB} MiB (mounted)"
    else
        USED_BYTES=$($BTRFS check --readonly /dev/mapper/${VG}-${LV} 2>&1 | grep "found .* bytes used" | grep -oE '[0-9]+ bytes used' | grep -oE '^[0-9]+')
        USED_MiB=$(( ${USED_BYTES:-0} / 1048576 + 1 ))
        log "btrfs used ~${USED_MiB} MiB (offline, mount unavailable)"
    fi
    BTRFS_SHRINK_MiB=$(( USED_MiB + 2560 ))
    LV_SHRINK_MiB=$(( BTRFS_SHRINK_MiB + 256 ))
    PV_SHRINK_MiB=$(( LV_SHRINK_MiB + 128 ))
    MD2_SHRINK_MiB=$(( PV_SHRINK_MiB + 128 ))
    log "축소 타겟 btrfs=${BTRFS_SHRINK_MiB} LV=${LV_SHRINK_MiB} PV=${PV_SHRINK_MiB} md2=${MD2_SHRINK_MiB} MiB"
    [ ${MD2_SHRINK_MiB} -lt $(( P3_SIZE / 2048 )) ] || { log "ERROR: 축소 타겟이 새 데이터 파티션보다 큼"; [ ${BTRFS_MOUNTED} -eq 1 ] && umount /mnt/d2; exit 1; }
    if [ ${BTRFS_MOUNTED} -eq 1 ]; then
        $BTRFS filesystem resize ${BTRFS_SHRINK_MiB}m /mnt/d2
        umount /mnt/d2
    else
        log "btrfs filesystem resize 건너뜀 (mount 불가) — LV 직접 축소"
    fi
    $LVM lvreduce -f -y -L ${LV_SHRINK_MiB}M ${VG}/${LV} || true
    echo y | $LVM pvresize --setphysicalvolumesize ${PV_SHRINK_MiB}M /dev/md2 || true
    $LVM vgchange -an ${VG}
    $MDADM --grow /dev/md2 --size=$(( MD2_SHRINK_MiB*1024 )) || true
    $MDADM --stop /dev/md2
    swapoff ${DISK}2 2>/dev/null || true
    $MDADM --stop /dev/md1 2>/dev/null || true
    $MDADM --stop /dev/md0 2>/dev/null || true
    log "Phase 1 완료"
else
    skip 1
fi

# ===== Phase 2: 데이터 우측 역방향 이동 =====
if [ "${FROM_PHASE}" -le 2 ]; then
    log "--- Phase 2: 데이터 우측 역방향 이동 (겹침 안전: 높은 섹터부터) ---"
    # Phase 1 건너뜀 시 MD2_SHRINK_MiB 가 없으므로 현재 md2 크기에서 역산
    if [ -z "${MD2_SHRINK_MiB}" ]; then
        $MDADM --stop /dev/md2 2>/dev/null || true
        $MDADM --assemble --run /dev/md2 ${DISK}3
        MD2_SHRINK_MiB=$($MDADM --detail /dev/md2 2>/dev/null | awk '/Array Size/{gsub(/[^0-9]/,"",$3); print int($3/1024)}')
        $MDADM --stop /dev/md2
        log "md2 현재 크기에서 역산: MD2_SHRINK_MiB=${MD2_SHRINK_MiB}"
    fi
    [ -n "${OLD_P3_START}" ] || OLD_P3_START=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}3 .*start=[[:space:]]*\([0-9]*\).*#\1#p")
    MOVE_LEN=$(( MD2_SHRINK_MiB*1024*2 + 65536 ))
    N=$(( (MOVE_LEN + CHUNK_SECTORS - 1) / CHUNK_SECTORS ))
    log "이동 ${MOVE_LEN} sec, ${N} chunks(256MiB) 역순 (${OLD_P3_START} -> ${P3_START})"
    i=$(( N - 1 ))
    while [ $i -ge 0 ]; do
        dd if=${DISK} of=${DISK} bs=512 skip=$(( OLD_P3_START + i*CHUNK_SECTORS )) seek=$(( P3_START + i*CHUNK_SECTORS )) count=${CHUNK_SECTORS} conv=notrunc 2>/dev/null
        log "  chunk $(( N - i ))/${N}"
        i=$(( i - 1 ))
    done
    sync
    log "Phase 2 완료"
else
    skip 2
fi

# ===== Phase 3: 8G 정확 재파티션 =====
if [ "${FROM_PHASE}" -le 3 ]; then
    log "--- Phase 3: 8G 정확 재파티션 ---"
    $SFDISK ${DISK} <<EOF
label: dos
start=${P1_START}, size=${P1_SIZE}, type=fd
start=${P2_START}, size=${P2_SIZE}, type=fd
start=${P3_START}, size=${P3_SIZE}, type=fd
EOF
    partprobe ${DISK} 2>/dev/null || $BLOCKDEV --rereadpt ${DISK} 2>/dev/null || true
    udevadm settle --timeout=10 2>/dev/null || sleep 3
    $SFDISK -l ${DISK} 2>/dev/null | grep "${DISK}[123]"
    log "Phase 3 완료"
else
    skip 3
fi

# ===== Phase 4: md0 조립 + grow + resize2fs =====
if [ "${FROM_PHASE}" -le 4 ]; then
    log "--- Phase 4: md0 조립 + grow + resize2fs ---"
    SB_OFF_NEW=$(( (P1_SIZE & ~31) - 32 ))

    if [ "${MD0_METHOD}" = "restore" ]; then
        log "슈퍼블록 복원 방식 (${DISK}1 new offset=${SB_OFF_NEW})"
        dd if=${SB_BIN} of=${DISK}1 bs=512 seek=${SB_OFF_NEW} count=8 conv=notrunc 2>/dev/null
        sync
        $MDADM -A --run --update=devicesize /dev/md0 ${DISK}1 || \
            $MDADM -A --run --update=devicesize --force /dev/md0 ${DISK}1
        $MDADM --grow /dev/md0 --size=max
    else
        log "신규 --create 방식 (슈퍼블록 없음 또는 DISK minor=1 보장)"
        $MDADM --zero-superblock ${DISK}1 2>/dev/null || true
        echo y | $MDADM --create /dev/md0 --metadata=0.90 --level=1 \
            --raid-devices=1 --force --assume-clean ${DISK}1
    fi

    $E2FSCK -f -y /dev/md0 || true
    $RESIZE2FS /dev/md0
    $MDADM --detail /dev/md0 | grep "Array Size"
    log "Phase 4 완료"
else
    skip 4
fi

# ===== Phase 5: md2 조립 + LVM/btrfs 재확장 =====
if [ "${FROM_PHASE}" -le 5 ]; then
    log "--- Phase 5: md2 조립 + LVM/btrfs 14G 재확장 ---"
    $MDADM --stop /dev/md2 2>/dev/null || true
    $MDADM --assemble --run --update=devicesize /dev/md2 ${DISK}3
    $MDADM --grow /dev/md2 --size=max
    $LVM pvresize /dev/md2
    $LVM vgchange -ay ${VG}
    $LVM lvextend -l +100%FREE ${VG}/${LV}
    mkdir -p /mnt/d2
    if mount -t btrfs /dev/mapper/${VG}-${LV} /mnt/d2 2>/dev/null; then
        $BTRFS filesystem resize max /mnt/d2
        df -h /mnt/d2 | tail -1
        umount /mnt/d2
    else
        log "btrfs mount 불가 (DSM feature flag 비호환) — LV 확장만 완료, btrfs resize 는 DSM 첫 부팅 시 자동 처리됨"
    fi
    $LVM vgchange -an ${VG}
    log "Phase 5 완료"
else
    skip 5
fi

# ===== Phase 6: swap 재생성 =====
if [ "${FROM_PHASE}" -le 6 ]; then
    log "--- Phase 6: swap 재생성 ---"
    $MDADM --stop /dev/md1 2>/dev/null || true
    echo y | $MDADM --create /dev/md1 --metadata=0.90 --level=1 --raid-devices=1 --force ${DISK}2
    mkswap /dev/md1 >/dev/null
    log "Phase 6 완료"
else
    skip 6
fi

log "--- 검증 ---"
mkdir -p /mnt/d2
mount /dev/md0 /mnt/d2; df -h /dev/md0; umount /mnt/d2
$MDADM --detail /dev/md2 2>/dev/null | grep -E "Array Size"
log "===== 완료: md0 8G + 데이터 14G + swap (DSM 재부팅하여 인식 확인) ====="
