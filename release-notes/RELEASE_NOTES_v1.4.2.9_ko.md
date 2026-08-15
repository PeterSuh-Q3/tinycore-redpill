# alpine-redpill v1.4.2.9

## BTRFS 비상 복구의 중요한 요구 사항

Synology의 공식 PC 복구 문서는 DSM BTRFS 및 ext4 볼륨 복구 환경으로 Ubuntu 18.04를 지정합니다. Ubuntu 18.04는 Linux 4.15 커널 계열을 사용합니다. Synology는 커널 버전의 기술적 이유를 공개하지 않았지만 DSM BTRFS 동작은 표준 Linux BTRFS 구현과 완전히 호환되는 것은 아닙니다. 실제로 더 높은 범용 Linux 커널에서는 DSM BTRFS 볼륨과의 호환성 문제가 나타날 수 있습니다. Linux 4.14.167은 이번 Alpine 복구 구현에서 사용할 수 있는 가장 근접한 하위 커널 계열이므로 비상 읽기 전용 접근을 위한 호환성 중심의 대안으로 사용합니다. 이번 릴리즈는 Synology가 지원하는 Ubuntu 절차를 대체한다고 주장하지 않습니다. 먼저 원본 디스크를 백업하고 읽기 전용 degraded 마운트를 우선 사용해야 하며 검증된 복구 계획 없이 `btrfs check --repair`와 같은 파괴적인 수리 명령을 실행하면 안 됩니다.

## Alpine 3.8 kernel 4.14 복구 환경

[TinyCore v1.2.5.1](https://github.com/PeterSuh-Q3/tinycore-redpill/releases/tag/v1.2.5.1)에서 도입한 복구 설계를 Alpine으로 이식했습니다. 기존 TinyCore 복구 경로를 Linux 4.14.167을 사용하는 독립형 Alpine 3.8 복구 이미지로 교체했습니다. 별도의 Ubuntu 부트 미디어 없이도 DSM BTRFS 볼륨을 탐지하고 비상 데이터 접근용으로 마운트할 수 있는 다른 Linux userspace를 제공합니다.

복구 이미지에는 전체 Alpine rootfs와 BTRFS 도구, md RAID 및 LVM 활성화 기능, 읽기 전용 `ro,degraded` BTRFS 마운트가 포함됩니다. 볼륨 메뉴는 Alpine 호환 `blkid` 파싱으로 BTRFS 및 ext4 시그니처를 탐지하고 선택한 논리 볼륨을 `/mnt` 아래에 마운트합니다.

## 복구 흐름 참고 화면

아래 이미지는 이번 Alpine 구현이 재사용한 TinyCore v1.2.5.1의 복구 흐름을 보여줍니다. 볼륨 선택, 읽기 전용 마운트 성공, 마운트된 볼륨 내용 확인 순서입니다. 캡처의 메인 메뉴와 부트 엔트리 명칭은 기존 TinyCore 명칭이므로 현재 Alpine 3.8 메뉴를 그대로 나타내지는 않습니다.

![기존 mountvol 볼륨 선택 화면](https://github.com/user-attachments/assets/c3c6d3d5-b012-4969-8f0e-9b8a40e26a5b)

![기존 mountvol BTRFS 마운트 성공 화면](https://github.com/user-attachments/assets/46251bfc-35d3-4eee-bcfc-74397a5c4934)

![기존 마운트된 BTRFS 볼륨 내용](https://github.com/user-attachments/assets/3a70ba2f-406c-4ab6-8646-2c4465b68980)

## 스토리지와 네트워크 준비

OpenRC가 복구 동작 전에 모듈 서비스를 시작하도록 보완했습니다. 이미지에는 일반 SATA, NVMe, SCSI, SAS RAID, USB 스토리지, SD 카드, 가상 스토리지, RAID, device mapper, BTRFS, ext4 및 FAT 모듈을 로드합니다. BusyBox DHCP에 필요한 누락된 `af_packet` 모듈도 일치하는 커널 패키지에서 복원했습니다. eth0 DHCP 네트워크를 자동으로 시작하므로 복구 환경 부팅 후 SSH 접속이 가능합니다.

devtmpfs와 sysfs를 초기화하고 콘솔을 기본 로컬 및 시리얼 콘솔로 제한했으며 정상적인 tc 계정을 유지하고 TinyCore 전용 마운트 및 process substitution 가정도 제거했습니다.
