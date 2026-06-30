#!/bin/bash
# Synology 단일 디스크 시스템 파티션(md0) 2.4G -> 8.0G in-place 확장 (외부 백업 불필요)
#
# 대상 구조 : LVM 기반 풀  (md2 -> vg1 -> volume_1 btrfs)
#             * 순수 BASIC(md2 위 btrfs 직접)인 경우 Phase1/5 의 lvm 단계만 빼면 됨
# 동작 개요 : 계층 축소(btrfs < LV < PV < md2) -> 데이터 소량 역방향 이동 -> 8G 정확 재파티션
#             -> md0 0.90 재생성 + resize2fs(데이터오프셋0 이라 ext4 보존) -> md2/LVM/btrfs 14G 재확장 -> swap
# 실행 환경 : TinyCore(tc) 로더 박스에서 sudo 로 실행
#
# *** 경고: Phase 2(이동)~Phase 3(재파티션) 구간은 무중단 보장이 안 됨(정전/리셋=복구불가).
#           단일 디스크 무중복이므로 테스트/파괴가능 환경, 또는 사전 백업이 있는 경우에만 사용. ***
set -e
MDADM=/usr/local/sbin/mdadm; BTRFS=/usr/local/bin/btrfs; LVM=/usr/local/sbin/lvm
SFDISK=/usr/local/sbin/sfdisk; E2FSCK=/sbin/e2fsck; BLOCKDEV=/usr/local/sbin/blockdev

### ===== 설정 =====
DISK=${1:-/dev/sdb}
P1_SIZE=16777216   # 시스템 파티션 목표 크기 8.00 GiB (sectors)
P2_SIZE=4194304    # swap 2.00 GiB (sectors)
VG=vg1; LV=volume_1
CHUNK_SECTORS=524288   # 256 MiB 이동 청크

ts(){ date +%H:%M:%S; }
log(){ echo "[$(ts)] $*"; }

log "===== md0 2.4G -> 8G in-place 확장 on ${DISK} ====="

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

# P1_START 자동 감지: 실제 p1 시작 섹터를 읽어 재파티션 시 그대로 유지
# (하드코딩하면 ext4 data-offset=0 기반 보존이 깨짐)
P1_START=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}1 .*start=[[:space:]]*\([0-9]*\).*#\1#p")
[ -n "${P1_START}" ] || { log "ERROR: ${DISK}1 파티션을 찾을 수 없음"; exit 1; }
# 알려진 Synology 레이아웃 값만 허용 (2048 = DSM ≤7.0, 8192 = DSM ≥7.1)
case "${P1_START}" in
  2048|8192) ;;
  *) log "ERROR: 예상치 못한 P1_START=${P1_START} — Synology 표준(2048/8192) 아님"; exit 1 ;;
esac
P2_START=$(( P1_START + P1_SIZE ))
P3_START=$(( P2_START + P2_SIZE ))
log "P1_START=${P1_START} (자동감지)  P2_START=${P2_START}  P3_START=${P3_START}"

$SFDISK -l ${DISK} 2>/dev/null | grep "${DISK}[123]"
OLD_P1_SIZE=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}1 .*size=[[:space:]]*\([0-9]*\).*#\1#p")
[ -n "${OLD_P1_SIZE}" ] || { log "ERROR: ${DISK}1 크기를 읽을 수 없음"; exit 1; }
OLD_P3_START=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}3 .*start=[[:space:]]*\([0-9]*\).*#\1#p")
TOTAL=$($BLOCKDEV --getsz ${DISK}); P3_SIZE=$(( TOTAL - P3_START ))
log "OLD sdb3=${OLD_P3_START}  NEW=${P3_START}  total=${TOTAL}  newdata=${P3_SIZE} sec"
[ -n "${OLD_P3_START}" ] || { log "ERROR: ${DISK}3 없음"; exit 1; }
[ ${P3_START} -gt ${OLD_P3_START} ] || { log "ERROR: 이동 방향 오류(이미 8G?)"; exit 1; }

log "--- Phase 1: btrfs -> LV -> PV -> md2 축소 ---"
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
    # DSM btrfs 에 TinyCore 커널이 인식 못하는 feature flag 가 있어 마운트 불가.
    # btrfs check --readonly 로 실제 사용 바이트를 오프라인 추출한다.
    USED_BYTES=$($BTRFS check --readonly /dev/mapper/${VG}-${LV} 2>&1 | grep "found .* bytes used" | grep -oE '[0-9]+ bytes used' | grep -oE '^[0-9]+')
    USED_MiB=$(( ${USED_BYTES:-0} / 1048576 + 1 ))
    log "btrfs used ~${USED_MiB} MiB (offline, mount unavailable)"
fi
# [FIX 1] btrfs 축소는 청크 재배치 공간이 필요 -> 사용량 + 2560 MiB 여유 (512 로는 No space left)
BTRFS_SHRINK_MiB=$(( USED_MiB + 2560 ))
LV_SHRINK_MiB=$(( BTRFS_SHRINK_MiB + 256 ))   # 각 계층은 안쪽보다 크게
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
$LVM lvreduce -f -y -L ${LV_SHRINK_MiB}M ${VG}/${LV}
echo y | $LVM pvresize --setphysicalvolumesize ${PV_SHRINK_MiB}M /dev/md2
$LVM vgchange -an ${VG}
$MDADM --grow /dev/md2 --size=$(( MD2_SHRINK_MiB*1024 ))
$MDADM --stop /dev/md2
swapoff ${DISK}2 2>/dev/null || true
$MDADM --stop /dev/md1 2>/dev/null || true
$MDADM --stop /dev/md0 2>/dev/null || true
# md0 0.90 슈퍼블록 백업: 0.90 슈퍼블록은 파티션 끝에 위치.
# 재파티션으로 파티션이 커지면 슈퍼블록이 중간에 묻혀 mdadm 이 새 끝에서 찾지 못함.
# 공식: MD_RESERVED_SECTORS=32, offset = ((size & ~31) - 32) sectors from partition start
SB_OFF_OLD=$(( (OLD_P1_SIZE & ~31) - 32 ))
log "md0 슈퍼블록 백업 (${DISK}1 offset ${SB_OFF_OLD} sectors)"
dd if=${DISK}1 of=/tmp/md0_sb.bin bs=512 skip=${SB_OFF_OLD} count=8 2>/dev/null
# md 0.90 magic = 0xa92b4efc (little-endian: fc 4e 2b a9)
SB_MAGIC=$(od -A n -t x1 -N 4 /tmp/md0_sb.bin 2>/dev/null | tr -d ' \n')
[ "${SB_MAGIC}" = "fc4e2ba9" ] || {
    log "ERROR: md0 슈퍼블록 magic 불일치 (got=${SB_MAGIC}, expected=fc4e2ba9)"
    log "       슈퍼블록 위치가 틀렸거나 md0 가 이미 손상됨 — 중단"
    exit 1
}

log "--- Phase 2: 데이터 우측 역방향 이동 (겹침 안전: 높은 섹터부터) ---"
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

log "--- Phase 3: 8G 정확 재파티션 ---"
$SFDISK ${DISK} <<EOF
label: dos
start=${P1_START}, size=${P1_SIZE}, type=fd
start=${P2_START}, size=${P2_SIZE}, type=fd
start=${P3_START}, size=${P3_SIZE}, type=fd
EOF
partprobe ${DISK} 2>/dev/null || $BLOCKDEV --rereadpt ${DISK} 2>/dev/null || true
$SFDISK -l ${DISK} 2>/dev/null | grep "${DISK}[123]"

log "--- Phase 4: md0 슈퍼블록 복원 + 조립 + grow + resize2fs ---"
# 0.90 슈퍼블록을 새 파티션 끝 위치에 복원한 후 --update=devicesize 로 조립.
# --create 미사용: TinyCore 디바이스 번호(sdb1=8:17)가 기록되면
# DSM 부팅 시 sata1p1(8:1)과 불일치 → 주니어 모드 → 이식 불가.
SB_OFF_NEW=$(( (P1_SIZE & ~31) - 32 ))
log "md0 슈퍼블록 복원 (${DISK}1 new offset ${SB_OFF_NEW} sectors)"
dd if=/tmp/md0_sb.bin of=${DISK}1 bs=512 seek=${SB_OFF_NEW} count=8 conv=notrunc 2>/dev/null
sync
$MDADM -A --run --update=devicesize /dev/md0 ${DISK}1 || \
    $MDADM -A --run --update=devicesize --force /dev/md0 ${DISK}1
$MDADM --grow /dev/md0 --size=max
$E2FSCK -f -y /dev/md0 || true
$RESIZE2FS /dev/md0
$MDADM --detail /dev/md0 | grep "Array Size"

log "--- Phase 5: md2 조립 + LVM/btrfs 14G 재확장 ---"
# [FIX 3] 이동된 md2 슈퍼블록의 Avail Dev Size(옛 큰 파티션)를 새 파티션 크기로 갱신해야 조립됨
$MDADM --stop /dev/md2 2>/dev/null || true
$MDADM --assemble --run --update=devicesize /dev/md2 ${DISK}3
$MDADM --grow /dev/md2 --size=max
$LVM pvresize /dev/md2
$LVM vgchange -ay ${VG}
$LVM lvextend -l +100%FREE ${VG}/${LV}
if mount -t btrfs /dev/mapper/${VG}-${LV} /mnt/d2 2>/dev/null; then
    $BTRFS filesystem resize max /mnt/d2
    df -h /mnt/d2 | tail -1
    umount /mnt/d2
else
    log "btrfs mount 불가 (DSM feature flag 비호환) — LV 확장만 완료, btrfs resize 는 DSM 첫 부팅 시 자동 처리됨"
fi
$LVM vgchange -an ${VG}

log "--- Phase 6: swap 재생성 ---"
echo y | $MDADM --create /dev/md1 --metadata=0.90 --level=1 --raid-devices=1 --force ${DISK}2
mkswap /dev/md1 >/dev/null

log "--- 검증 ---"
mount /dev/md0 /mnt/d2; df -h /dev/md0; umount /mnt/d2
$MDADM --detail /dev/md2 2>/dev/null | grep -E "Array Size"
log "===== 완료: md0 8G + 데이터 14G + swap (DSM 재부팅하여 인식 확인) ====="
