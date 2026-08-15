# alpine-redpill v1.4.2.9

## ⚠️ BTRFS 비상 복구 안내

Synology의 공식 PC 복구 문서는 DSM BTRFS 및 ext4 볼륨 복구 환경으로 Ubuntu 18.04를 지정합니다. Ubuntu 18.04는 Linux 4.15 커널 계열을 사용합니다.

Synology는 커널 버전의 기술적 이유를 공개하지 않았습니다. 실제로 DSM BTRFS 동작은 표준 Linux BTRFS와 완전히 호환되는 것은 아니며, 더 높은 범용 Linux 커널에서는 DSM BTRFS 볼륨과의 호환성 문제가 나타날 수 있습니다.

이번 릴리즈는 사용할 수 있는 가장 근접한 하위 커널 계열인 Linux 4.14.167을 호환성 중심 Alpine 복구 구현으로 사용합니다. Synology가 지원하는 Ubuntu 절차를 대체한다고 주장하지는 않습니다.

> [!WARNING]
> 먼저 원본 디스크를 백업하십시오. 읽기 전용 degraded 마운트를 우선 사용해야 하며, 검증된 복구 계획 없이 `btrfs check --repair`와 같은 파괴적인 명령을 실행하면 안 됩니다.

## 🛠️ Alpine 3.8 복구 환경

[TinyCore v1.2.5.1](https://github.com/PeterSuh-Q3/tinycore-redpill/releases/tag/v1.2.5.1)에서 도입한 복구 설계를 Alpine으로 이식했습니다.

- 기존 TinyCore 복구 경로를 독립형 Alpine 3.8 이미지로 교체했습니다.
- DSM BTRFS 비상 접근에 Linux 4.14.167을 사용합니다.
- 전체 Alpine rootfs, BTRFS 도구, md RAID 조립, LVM 활성화를 포함합니다.
- 선택한 BTRFS 볼륨을 `/mnt` 아래에 `ro,degraded` 읽기 전용으로 마운트합니다.
- Alpine 호환 `blkid` 파싱으로 BTRFS와 ext4 시그니처를 탐지합니다.

## 📦 스토리지 및 네트워크 준비

- 복구 동작 전에 OpenRC 모듈 서비스를 시작합니다.
- 일반 SATA, NVMe, SCSI, SAS RAID, USB 스토리지, SD 카드, 가상 스토리지, RAID, device mapper, BTRFS, ext4, FAT 모듈을 로드합니다.
- BusyBox DHCP에 필요한 누락된 `af_packet` 모듈을 일치하는 커널 패키지에서 복원했습니다.
- 부팅 후 SSH 접속을 위해 `eth0` DHCP 네트워크를 자동으로 시작합니다.
- devtmpfs와 sysfs를 초기화하고, 콘솔을 기본 로컬 및 시리얼 콘솔로 제한하며, TinyCore 전용 마운트 및 process substitution 가정을 제거했습니다.

## 🖼️ 복구 흐름 참고 화면

아래 기존 TinyCore v1.2.5.1 캡처는 이번 Alpine 구현이 재사용한 복구 흐름을 보여줍니다. 캡처의 메뉴와 부트 엔트리 명칭은 기존 명칭이며 현재 Alpine 3.8 메뉴와는 다릅니다.

**1. 논리 볼륨 선택**

![기존 mountvol 볼륨 선택 화면](https://github.com/user-attachments/assets/c3c6d3d5-b012-4969-8f0e-9b8a40e26a5b)

**2. 읽기 전용 BTRFS 마운트 확인**

![기존 mountvol BTRFS 마운트 성공 화면](https://github.com/user-attachments/assets/46251bfc-35d3-4eee-bcfc-74397a5c4934)

**3. 마운트된 볼륨 내용 접근**

![기존 마운트된 BTRFS 볼륨 내용](https://github.com/user-attachments/assets/3a70ba2f-406c-4ab6-8646-2c4465b68980)
