# Alpine 3.8 BTRFS 복구 이미지 빌드 설계서

## 목적

이 저장소의 `btr.sh`는 Synology 비상 복구용 Alpine Linux 3.8 기반 initramfs를 만든다. 대상 커널은 Linux 4.14 계열이며, 이미지에는 BTRFS/LVM/MD RAID 복구 도구와 `mountvol.sh` 대화형 메뉴가 포함된다.

이 이미지는 일반 Alpine 부팅 디스크가 아니다. 로더 파티션에서 GRUB가 `vmlinuz-4.14`와 `btr-recovery-x86_64.initramfs`를 함께 로드하는 디스크리스 복구 환경이다. TinyCore 9.0용 경로와 `mydata.tgz` 백업 방식은 이 Alpine 경로에 사용하지 않는다.

## 소스와 산출물

- `btr.sh`: 전체 rootfs와 initramfs를 생성하는 빌드 스크립트
- `mountvol.sh`: 부팅 후 실행되는 BTRFS/LVM 복구 메뉴
- `alpine_3.8/btr-recovery-x86_64.initramfs`: 생성된 self-contained initramfs
- `alpine_3.8/vmlinuz-4.14`: 일치하는 4.14 커널 이미지
- 빌드 실행 시 `rootfs-source.txt`, `kernel-source.txt`도 출력 디렉터리에 생성되어 입력을 기록한다.

initramfs는 Alpine의 초기 ramdisk만 만드는 것이 아니라 `/sbin/init`, 사용자 공간, 복구 도구, 일치하는 커널 모듈, 메뉴 스크립트를 모두 cpio로 묶는다. 따라서 `modloop-lts`나 별도의 Alpine rootfs를 부팅 시 추가로 요구하지 않는다.

## 빌드 환경

빌드는 macOS가 아니라 Linux Alpine 3.8 빌드 VM 또는 동일한 Linux 환경에서 root 권한으로 수행한다. 실기 빌드 예시는 loader 파티션을 `/mnt/sda3`에 마운트하고 `/mnt/sda3/btr-build`에 다음 자산을 준비하는 방식이다.

- `/mnt/sda3/btr-build/pkg/boot/vmlinuz-vanilla`
- `/mnt/sda3/btr-build/pkg/lib/modules/4.14.167-0-vanilla/`
- `/mnt/sda3/btr-build/linux-vanilla.apk`
- `/mnt/sda3/btr-build/btr.sh`
- `/mnt/sda3/btr-build/mountvol.sh`

필수 호스트 명령은 `curl`, `tar`, `chroot`, `apk`이며, 네트워크와 Alpine 3.8 저장소 접근이 필요하다. 빌드 VM에서 일시적으로 `sudo apk add --no-cache curl`을 설치할 수 있다.

## 표준 빌드

비밀번호는 문서나 커밋에 기록하지 말고 환경변수로 전달한다.

```sh
cd /mnt/sda3/btr-build
sudo env \
  WORK_DIR=/tmp/btr-work \
  BTR_ROOT_PASSWORD='개별 root 비밀번호' \
  BTR_TC_PASSWORD='개별 tc 비밀번호' \
  KERNEL_IMAGE=/mnt/sda3/btr-build/pkg/boot/vmlinuz-vanilla \
  KERNEL_MODULES=/mnt/sda3/btr-build/pkg/lib/modules/4.14.167-0-vanilla \
  KERNEL_PACKAGE=/mnt/sda3/btr-build/linux-vanilla.apk \
  OUTPUT_DIR=/tmp/btr-out \
  ./btr.sh
```

완료 후 `/tmp/btr-out/btr-recovery-x86_64.initramfs`를 loader의 `btr-build/out/`에 복사하고, 저장소 작업 디렉터리의 `alpine_3.8/`으로 회수한다.

```sh
sudo cp /tmp/btr-out/btr-recovery-x86_64.initramfs \
  /mnt/sda3/btr-build/out/btr-recovery-x86_64.initramfs
```

`WORK_DIR`는 이전 실패에서 남은 bind mount와 충돌할 수 있다. 재빌드 전에 해당 작업 디렉터리의 `rootfs/dev`, `rootfs/dev/shm`, `rootfs/proc`, `rootfs/sys`가 마운트되어 있지 않은지 확인하고, 남은 마운트만 해제한 뒤 작업 디렉터리를 정리한다. 호스트의 `/dev`, `/proc`, `/sys` 자체를 대상으로 해제 명령을 실행하지 않는다.

## 스크립트가 수행하는 단계

1. Alpine 3.8 x86_64 minirootfs를 다운로드한다.
2. `/dev`, `/dev/shm`, `/proc`, `/sys`를 임시 bind mount한다. minirootfs에 `/dev/shm`이 없을 수 있으므로 반드시 먼저 생성한다.
3. Alpine 3.8 main/community 저장소에서 `alpine-base`, `btrfs-progs`, `mdadm`, `lvm2`, `device-mapper`, `util-linux`, `kmod`, `openssh`, `sudo`, `dialog`, `bash` 등을 설치한다.
4. `root`와 `tc` 계정을 만들고 sudo 및 비밀번호를 설정한다. `tc`의 홈 디렉터리는 `tc:tc` 소유여야 한다.
5. serial 콘솔(`ttyS0`)과 기본 콘솔만 사용하도록 inittab을 조정한다. 존재하지 않는 `tty2`~`tty6` getty를 제거해 반복 오류를 방지한다.
6. `/home/tc/mountvol.sh`와 `mountvol.start`를 설치한다. 기본 runlevel의 local 서비스에서 장치 settle 후 메뉴를 실행한다.
7. SSH와 DHCP 네트워크를 활성화한다.
8. 저장장치, RAID, LVM, BTRFS, SD 카드 리더, USB, NIC 및 콘솔 모듈을 `/etc/modules-load.d/btr-recovery.conf`에 기록한다.
9. `KERNEL_MODULES`를 rootfs에 복사한다. 모듈 목록에 `af_packet.ko`가 없으면 일치하는 `linux-vanilla.apk`에서 복원한다. BusyBox DHCP에 필요하다.
10. 전체 rootfs를 newc cpio와 gzip으로 압축하고, 커널 및 입력 경로 기록 파일을 생성한다.

## 반드시 유지해야 하는 모듈

USB 로더가 PCI xHCI 컨트롤러에서 인식되는 장비가 있으므로 `xhci_hcd`만으로 충분하지 않다. 다음 두 모듈을 모두 자동 로드해야 한다.

```text
xhci_hcd
xhci_pci
```

특히 Realtek 카드리더 또는 USB 로더가 보이지 않고 UUID `6234-C863`을 찾지 못하는 경우, 먼저 `xhci_pci` 로드 여부를 확인한다. `modprobe xhci_pci` 후 `/dev/sd*`와 해당 UUID가 나타나면 원인은 PCI xHCI 드라이버 누락이다.

또한 SATA/NVMe/SCSI/USB/SDHCI, MD RAID, device-mapper/LVM, BTRFS 모듈을 삭제하거나 임의로 축소하지 않는다. 실제 장비별 모듈이 다르므로 범용 복구 이미지에서는 현재 목록을 유지한다.

## 이미지 검증

쉘 문법과 변경 사항을 먼저 검사한다.

```sh
bash -n btr.sh
git diff --check
```

initramfs에 설정과 모듈이 실제 포함되었는지 검사한다.

```sh
inspect_dir="$(mktemp -d)"
gzip -dc alpine_3.8/btr-recovery-x86_64.initramfs | \
  (cd "$inspect_dir" && cpio -idm --quiet \
    etc/modules-load.d/btr-recovery.conf \
    lib/modules/4.14.167-0-vanilla/kernel/drivers/usb/host/xhci-pci.ko)
rg -n '^xhci_(hcd|pci)$' "$inspect_dir/etc/modules-load.d/btr-recovery.conf"
test -f "$inspect_dir/lib/modules/4.14.167-0-vanilla/kernel/drivers/usb/host/xhci-pci.ko"
```

QEMU에서는 4.14 커널과 새 initramfs를 함께 사용하고, 가능하면 `qemu-xhci`와 USB storage 디스크를 추가해 USB 장치 열거를 확인한다. DHCP가 필요한 경우 e1000 또는 virtio NIC를 붙이고 `eth0` 주소 및 SSH 접속을 확인한다.

실기에서는 다음을 확인한다.

- 부팅 시 `Linux 4.14.167-0-vanilla` 표시
- `lsmod` 또는 `dmesg`에서 `xhci_pci` 로드
- `blkid`에서 loader UUID `6234-C863` 확인
- `/dev/sd*` loader 장치 생성
- `tc` 로그인 및 `/home/tc/mountvol.sh` 실행
- `lvs`, `mdadm --assemble --scan`, BTRFS read-only/degraded mount 동작

`blkid -o value -s TYPE`는 Alpine 3.8에서 예상과 달리 전체 출력이 반환될 수 있다. `mountvol.sh`의 파일시스템 판별은 `blkid`의 `TYPE="..."` 필드를 파싱하는 현재 구현을 유지해야 한다.

## 부트 엔트리 관계

GRUB 엔트리는 loader 파티션에서 `alpine_3.8/vmlinuz-4.14`와 `alpine_3.8/btr-recovery-x86_64.initramfs`를 읽는다. `localhost.apkovl.tar.gz`, 일반 Alpine `modloop-lts`, TinyCore `mydata.tgz`는 이 Alpine 3.8 부트 흐름의 입력이 아니다. UUID `6234-C863`는 loader 파티션 탐색을 위한 값이며, 장치명이 고정되어 있다고 가정하지 않는다.

## 커밋 및 푸시

재생성한 바이너리와 스크립트를 함께 커밋한다. `my.sh.gz` 등 워크플로우 생성 파일 때문에 원격 브랜치가 앞서 있을 수 있으므로 푸시 거절 시 먼저 fetch 후 rebase한다. 사용자 변경을 버리기 위해 `git reset --hard`를 사용하지 않는다.

```sh
git add btr.sh alpine_3.8/btr-recovery-x86_64.initramfs
git commit -m 'fix: load xhci PCI controller in recovery'
git fetch origin alpine-redpill
git rebase origin/alpine-redpill
git push origin alpine-redpill
```

50 MiB가 넘는 initramfs는 GitHub에서 경고가 발생할 수 있지만 현재 저장소의 릴리즈 자산 관리 방식상 경고만으로 업로드를 중단하지 않는다. 푸시 후 원격 커밋과 이미지 파일 크기를 확인한다.

## 안전 규칙

- 실제 데이터 디스크에 `btrfs check --repair`, `btrfs rescue`, 강제 read-write mount를 자동 실행하지 않는다.
- 복구 메뉴 기본 동작은 read-only/degraded mount다.
- 사용자 비밀번호와 SSH 키를 문서·로그·커밋에 남기지 않는다.
- 빌드 실패 시 남은 bind mount만 정리하고 호스트의 `/dev`, `/proc`, `/sys`를 해제하지 않는다.
- TinyCore 전용 로직을 Alpine 3.8 빌드에 다시 섞지 않는다.
