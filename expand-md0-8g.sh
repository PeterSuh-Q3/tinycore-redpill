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
DISK=/dev/sdb
P1_SIZE=16777216   # 시스템 파티션 목표 크기 8.00 GiB (sectors)
P2_SIZE=4194304    # swap 2.00 GiB (sectors)
VG=vg1; LV=volume_1
CHUNK_SECTORS=524288   # 256 MiB 이동 청크

ts(){ date +%H:%M:%S; }
log(){ echo "[$(ts)] $*"; }

log "===== md0 2.4G -> 8G in-place 확장 on ${DISK} ====="

# resize2fs(e2fsprogs) 선확보 - TinyCore 기본 이미지엔 없을 수 있음
if [ -z "$(which resize2fs 2>/dev/null)" ]; then
  log "e2fsprogs 설치 (resize2fs)"
  tce-load -wi e2fsprogs >/dev/null 2>&1 || true
fi
RESIZE2FS=$(which resize2fs 2>/dev/null)
[ -n "${RESIZE2FS}" ] || { log "ERROR: resize2fs 없음 (e2fsprogs 설치 실패)"; exit 1; }

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
OLD_P3_START=$($SFDISK -d ${DISK} | sed -n "s#^${DISK}3 .*start=[[:space:]]*\([0-9]*\).*#\1#p")
TOTAL=$($BLOCKDEV --getsz ${DISK}); P3_SIZE=$(( TOTAL - P3_START ))
log "OLD sdb3=${OLD_P3_START}  NEW=${P3_START}  total=${TOTAL}  newdata=${P3_SIZE} sec"
[ -n "${OLD_P3_START}" ] || { log "ERROR: ${DISK}3 없음"; exit 1; }
[ ${P3_START} -gt ${OLD_P3_START} ] || { log "ERROR: 이동 방향 오류(이미 8G?)"; exit 1; }

log "--- Phase 1: btrfs -> LV -> PV -> md2 축소 ---"
$MDADM --assemble --run /dev/md2 ${DISK}3
$LVM vgchange -ay ${VG}
mkdir -p /mnt/d2; mount -t btrfs /dev/mapper/${VG}-${LV} /mnt/d2
USED_MiB=$(df -m /mnt/d2 | awk 'NF==5{print $2} NF==6{print $3}')
log "btrfs used ~${USED_MiB} MiB"
# [FIX 1] btrfs 축소는 청크 재배치 공간이 필요 -> 사용량 + 2560 MiB 여유 (512 로는 No space left)
BTRFS_SHRINK_MiB=$(( USED_MiB + 2560 ))
LV_SHRINK_MiB=$(( BTRFS_SHRINK_MiB + 256 ))   # 각 계층은 안쪽보다 크게
PV_SHRINK_MiB=$(( LV_SHRINK_MiB + 128 ))
MD2_SHRINK_MiB=$(( PV_SHRINK_MiB + 128 ))
log "축소 타겟 btrfs=${BTRFS_SHRINK_MiB} LV=${LV_SHRINK_MiB} PV=${PV_SHRINK_MiB} md2=${MD2_SHRINK_MiB} MiB"
[ ${MD2_SHRINK_MiB} -lt $(( P3_SIZE / 2048 )) ] || { log "ERROR: 축소 타겟이 새 데이터 파티션보다 큼"; umount /mnt/d2; exit 1; }
$BTRFS filesystem resize ${BTRFS_SHRINK_MiB}m /mnt/d2
umount /mnt/d2
$LVM lvreduce -f -y -L ${LV_SHRINK_MiB}M ${VG}/${LV}
echo y | $LVM pvresize --setphysicalvolumesize ${PV_SHRINK_MiB}M /dev/md2
$LVM vgchange -an ${VG}
$MDADM --grow /dev/md2 --size=$(( MD2_SHRINK_MiB*1024 ))
$MDADM --stop /dev/md2
swapoff ${DISK}2 2>/dev/null || true
$MDADM --stop /dev/md1 2>/dev/null || true
$MDADM --stop /dev/md0 2>/dev/null || true

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

log "--- Phase 4: md0 0.90 재생성 + ext4 8G 확장 (백업 없음: 0.90 은 데이터오프셋0 이라 시작부 ext4 보존) ---"
$MDADM --zero-superblock ${DISK}1 2>/dev/null || true
echo y | $MDADM --create /dev/md0 --metadata=0.90 --level=1 --raid-devices=1 --force --assume-clean ${DISK}1
$E2FSCK -f -y /dev/md0 || true
$RESIZE2FS /dev/md0
$MDADM --detail /dev/md0 | grep "Array Size"
# [주의] TinyCore 에서 --create 하면 슈퍼블록의 "this device" 가 /dev/sdb1(8:17) 로 기록됨.
# DSM 부팅 시 같은 파티션은 /dev/sata1p1(8:1) 로 보이기 때문에 device 불일치로
# "No devices found for /dev/md0 assembly" 주니어 모드 진입이 발생한다.
# 스크립트 완료 후 DSM 첫 주니어 부팅 환경에서 아래 명령으로 슈퍼블록을 갱신해야 한다:
#   mdadm --zero-superblock /dev/sata1p1
#   echo y | mdadm --create /dev/md0 --metadata=0.90 --level=1 \
#       --raid-devices=1 --force --assume-clean /dev/sata1p1
# 이후 재부팅하면 정상 조립된다. (ext4 데이터는 0.90 data-offset=0 으로 보존됨)

log "--- Phase 5: md2 조립 + LVM/btrfs 14G 재확장 ---"
# [FIX 3] 이동된 md2 슈퍼블록의 Avail Dev Size(옛 큰 파티션)를 새 파티션 크기로 갱신해야 조립됨
$MDADM --stop /dev/md2 2>/dev/null || true
$MDADM --assemble --run --update=devicesize /dev/md2 ${DISK}3
$MDADM --grow /dev/md2 --size=max
$LVM pvresize /dev/md2
$LVM vgchange -ay ${VG}
$LVM lvextend -l +100%FREE ${VG}/${LV}
mount -t btrfs /dev/mapper/${VG}-${LV} /mnt/d2
$BTRFS filesystem resize max /mnt/d2
df -h /mnt/d2 | tail -1
umount /mnt/d2; $LVM vgchange -an ${VG}

log "--- Phase 6: swap 재생성 ---"
echo y | $MDADM --create /dev/md1 --metadata=0.90 --level=1 --raid-devices=1 --force ${DISK}2
mkswap /dev/md1 >/dev/null

log "--- 검증 ---"
mount /dev/md0 /mnt/d2; df -h /dev/md0; umount /mnt/d2
$MDADM --detail /dev/md2 2>/dev/null | grep -E "Array Size"
log "===== 완료: md0 8G + 데이터 14G + swap (DSM 재부팅하여 인식 확인) ====="
