# TinyCore → Alpine Linux Diskless 이식 계획서

> **대상 릴리스:** tinycore-redpill **v1.4.0.0**
> **현재:** TinyCore 14.0 / 커널 6.1.2-tinycore64 / glibc 2.36
> **목표:** Alpine Linux (musl) diskless 로더 환경
> **근거:** 대상 box(192.168.45.95)에서 3회 실측으로 libc·명령·바이너리 의존성 규명

---

## 종합 판정

초기 4대 리스크(libc / i18n / toolchain / 영속화)가 실측과 두 가지 전제 확정으로 **사실상 해소**됐다.
남은 미결 변수는 **`kpatch`의 gcompat 기능 테스트 1건**뿐이며, 이는 재빌드 없이 동작할 가능성이 높은 최선의 시나리오다.

**차단성(showstopper) 리스크 없음.** 나머지는 전부 기계적 치환이다.

### 전제 조건 (v1.4.0.0 설계 확정 사항)
- toolchain을 로더에서 직접 빌드하지 않는다.
- 터미널을 **ttyd 단일 경로**로 통일한다 (urxvt/X11 경로 폐기).

---

## 1. 리스크 상태 요약

| 항목 | 상태 | 내용 |
|---|---|---|
| toolchain glibc 빌드 | **해소** | 직접 빌드 미수행. ABI 불일치 우려 소멸 |
| i18n · locale · 폰트 | **해소** | ttyd 단일화 + musl의 로케일 독립 `wcwidth`. 폰트는 브라우저(xterm.js)로 이관 |
| glibc 사전빌드 바이너리 | **경로 확정** | static·apk교체·DSM무관으로 대부분 처리. kpatch만 검증 대상 |
| ntpclient 부재 | 치환 | apk에 없음 → chrony / busybox ntpd (`settime.sh`, `ntp.sh`) |
| 영속화 모델 | 재설계 | `filetool.sh`(mydata.tgz) → `lbu commit` |
| kpatch (vmlinux 패처) | 검증 1건 | 의존성 `libc.so.6` 단일 → `apk add gcompat` 후보 |

---

## 2. 명령어 → apk 매핑표

스크립트가 실제 호출하는 명령(괄호 = 리포 내 호출 빈도)과 Alpine 대응 패키지.
`ntpclient`와 glibc 로케일을 제외하면 전부 1:1 대응이 존재한다.

| 사용 명령 (빈도) | Alpine apk 패키지 | 비고 |
|---|---|---|
| awk (558) | `gawk` | busybox awk는 GNU 확장 미지원 → gawk 강제 |
| jq (322) · curl (224) | `jq` `curl` | 그대로 |
| dialog (134) | `dialog` `ncurses` | CJK 폭은 musl wcwidth가 처리, 렌더는 ttyd |
| cpio (76) | `cpio` | initramfs 조작 → GNU cpio 권장 |
| fdisk·sgdisk (68·6) | `util-linux` `gptfdisk` | 그대로 |
| losetup·blkid (39·32) | `util-linux` | 그대로 |
| pigz·xz·zstd (66·30·29) | `pigz` `xz` `zstd` | 그대로 |
| smartctl (38) | `smartmontools` | 그대로 |
| btrfs (38) | `btrfs-progs` | 그대로 |
| mdadm (28) · ip (24) | `mdadm` `iproute2` | 그대로 |
| resize2fs·mkfs.ext4 (21) | `e2fsprogs` `e2fsprogs-extra` | 그대로 |
| **ntpclient (17)** | `chrony` / busybox ntpd | apk에 없음 → 교체 필요 |
| gettext (13) | `gettext` | 번역 메시지 그대로 동작 |
| ethtool (11) · lvm (14) | `ethtool` `lvm2` | 그대로 |
| mkfs.vfat (8) | `dosfstools` | 그대로 |
| mksquashfs (2) | `squashfs-tools` | 그대로 |
| bash · sudo | `bash` `sudo`\|`doas` | 전 스크립트 bash 전제 → 필수 설치 |
| **glibc_i18n_locale** | 없음 → `LANG=C.UTF-8` | musl는 로케일 독립 UTF-8, 폐기 |

---

## 3. 사전빌드 바이너리 분류

리포 전체 ELF 실측 결과, 동적 링크는 예외 없이 glibc(`/lib64/ld-linux-x86-64.so.2`).
단 **실행 위치**와 **apk 대체 가능성**으로 나누면 실제 작업은 kpatch 하나로 좁혀진다.

### A. 그대로 유지 — static, libc 무관
정적 링크라 musl에서 그대로 동작. 이식 전략의 핵심인 터미널 본체가 여기 속함.
- `ttyd` · `tools/socat-static` · `tools/set_baud` · `tools/vmlinux`

### B. apk 네이티브로 교체 — 범용 유틸
glibc 링크지만 전부 표준 유틸 → 바이너리를 들고 다닐 이유가 없음. apk 설치로 대체.
- `tools/{pigz,xxd,losetup,find,tar,cpio,patch,dtc,stty,crc32,bspatch,kexec}`
- `lrz`/`lsz` → apk `lrzsz`

### C. DSM 내부 실행 — loader와 무관
DSM(glibc) 안에서 동작하는 주입 페이로드. Alpine loader의 libc와 무관 → 건드릴 필요 없음.
- `tmp/libsyno*.so.7` · `tmp/*.ko` · `opencl/*.so`

### D. redpill 전용 커스텀 — 검증 필요
loader에서 실행되고 apk 대체가 없는 유일 항목.
`kpatch`는 의존성이 `libc.so.6` 하나뿐 — glibc 바이너리 실행 중 가장 유리한 케이스.
- `rootpatch/kpatch` (= `tools/kpatch`, 복사 사용)
- `tools/amdgpu_top` (선택 기능, 우선순위 낮음)

---

## 4. 폐기 스택

ttyd 단일화로 X11/콘솔 로케일 경로 전체가 불필요해진다. 이식 시 제거 대상:

`glibc_apps` · `glibc_i18n_locale` · `unifont` · `rxvt`/`urxvt` · `setfont` · `kmaps` · `.xsession` · X11 전체 · `LANG`/`LC_ALL` 로케일 설정

---

## 5. kpatch · gcompat 검증 절차

정적 판정만으로는 gcompat 심볼 커버리지를 보장할 수 없다.
실제 vmlinux를 넣어 **패치 산출물이 정상인지 기능 테스트 1회**가 반드시 필요하다.

```sh
# 1) Alpine PoC에 gcompat 설치
apk add gcompat

# 2) kpatch 실행 — 실제 vmlinux 패치 (rootpatch/init.sh 와 동일 형태)
./kpatch vmlinux vmlinux-mod   # 종료코드 0 + 산출물 크기/헤더 확인
```

**실패 시 폴백 순서**
1. sgerrand glibc-compat 패키지(실제 glibc를 `/usr/glibc-compat`에 설치)
2. glibc chroot에서 실행
3. musl static 재빌드 (소스 필요)

---

## 6. 영속화 전환 · filetool.sh → lbu

```sh
# /etc/lbu/lbu.conf 에서 저장 매체 지정
LBU_MEDIA=<uuid-of-loader-part3>

# 백업 대상 재매핑 (.filetool.lst / .xfiletool.lst → lbu include)
lbu include /home/tc/redpill-load /home/tc/functions.sh

# 커밋 시점 교체 (preoff.sh / menu_m.sh 의 filetool.sh -b 치환)
lbu commit -d
```

---

## 7. 착수 체크리스트

- [ ] **infra** — Alpine diskless PoC 부팅 + 로컬 `apks/` 오프라인 리포지토리 구성
- [ ] **apk** — 필수 패키지 일괄 설치: `bash gawk coreutils sed grep util-linux` + 매핑표 전체
- [ ] **ui** — ttyd(static) 기동 + xterm.js 한국어 렌더링 + dialog CJK 정렬 확인
- [ ] **verify** — kpatch gcompat 기능 테스트(§5) — 이식의 유일한 미결 변수
- [ ] **patch** — ntpclient → chrony/busybox ntpd 치환 (`settime.sh`, `ntp.sh`)
- [ ] **verify** — lbu 영속화 전환 + 재부팅 후 설정 유지 검증(§6)
- [ ] **cleanup** — 폐기 스택 제거 및 X11/locale 의존 코드 경로 정리(§4)
- [ ] **kernel** — 커널 `modules.alias` 매핑을 Alpine `-lts` 커널 버전과 대조

---

*사전조사 완료 — 실측 3회 (192.168.45.95). tinycore-redpill v1.4.0.0 이식 착수 기준 문서.*

---

## 8. main 메뉴 기반 일회성 전환 설계

### 목표와 범위

`main`의 `menu_m.sh` Misc 섹션에서 기존 `n`(추가 기능) 바로 위에
`o "알파인 리눅스로 업그레이드"` 항목을 둔다. 이 항목은 **TinyCore에서
Alpine으로 되돌릴 수 없이 전환하는 일회성 작업**이다. TinyCore의 파일과
설정은 보존하지 않으며, 성공 후에는 Alpine만 로더 빌드 환경으로 사용한다.

Alpine 런타임은 `/dev/alpine`이라는 고정 장치 파일이 아니라, 로더 디스크의
새 **4번 파티션**(`/dev/sdX4`, `/dev/nvmeXn1p4`, `/dev/mmcblkXp4`)에
`LABEL=alpine`을 설정해 식별한다. Alpine 쪽은 `blkid -L alpine`으로 장치를
찾아 `/mnt/alpine`에 마운트한다. 따라서 장치명이 달라도 동작한다.

### 대상 디스크 레이아웃

| 파티션 | 전환 전 | 전환 후 |
|---|---|---|
| 1 | GRUB/EFI | 변경하지 않음 |
| 2 | DSM/loader boot files | 변경하지 않음 |
| 3 | TinyCore와 영속 데이터, `/mnt/${loaderdisk}3` | 기존 끝에서 정확히 1 GiB 축소 후 빈 예약 FAT 파티션으로 재생성 |
| 4 | 없음 | 1 GiB FAT32, `LABEL=alpine`, Alpine diskless payload |

`p3`는 TinyCore의 FAT 기반 저장소이므로 `resize2fs` 같은 ext 파일시스템
축소를 사용하지 않는다. 전환의 의도는 TinyCore 폐기이므로, 안전한 절차는
마운트 해제 후 파티션 3을 보존 축소하는 것이 아니라 **동일한 시작 섹터에서
더 작은 빈 p3를 다시 만들고, 그 뒤에 p4를 만든다**는 것이다. 이는
지원되지 않는 FAT in-place 축소와 TinyCore 데이터의 잔존을 모두 피한다.

### 실행 순서

1. **사전 검증:** `getloaderdisk` 결과를 `lsblk --json`/`findmnt`로 교차
   확인하고, 파티션 1·2·3이 모두 같은 물리 디스크에 있으며 p3가 마지막
   파티션임을 확인한다. p3 크기는 1 GiB보다 커야 하고, 디스크에 p4가
   이미 있거나 GPT/MBR 파티션 번호가 예상과 다르면 중단한다.
2. **명시적 승인:** 한국어/영어 경고에서 대상 디스크, 기존 p3 크기,
   삭제될 TinyCore 데이터 및 최종 레이아웃을 보여 준다. 사용자가 디스크
   경로 또는 전환 문구를 정확히 입력해야 계속한다. 이 단계에서는
   `/mnt/${loaderdisk}3`의 사용자 설정과 현재 GRUB 설정을 외부 저장소로
   백업할 기회를 제공한다.
3. **전환 입력물 확보:** 파티션을 변경하기 전에 검증된
   `alpine-partition.tar.gz`, `localhost.apkovl.tar.gz`, Alpine 전용
   `grub.cfg`를 RAM 또는 p1/p2의 임시 안전 위치에 내려받고 SHA-256을
   확인한다. 네트워크/서명/공간 확인 실패 시 디스크에 쓰지 않는다.
4. **마운트 해제와 테이블 변경:** `sync` 후 p3의 모든 하위 마운트를
   확인하고 해제한다. p3 시작 섹터는 유지하고 끝을 `old_end - 1 GiB`로
   계산해 재생성하며, p4는 그 다음 섹터부터 정확히 1 GiB로 생성한다.
   `partprobe`/`blockdev --rereadpt`와 udev 정착을 기다린 뒤 실제 시작·끝
   섹터를 재검증한다. p3은 새 FAT로 포맷해 TinyCore 데이터를 제거한다.
5. **Alpine 배치:** p4를 FAT32 `LABEL=alpine`으로 포맷하고 임시
   마운트한다. 검증된 Alpine payload와 apkovl을 풀고, `vmlinuz-lts`,
   `initramfs-lts`, apk repository 및 overlay의 존재를 검사한다.
6. **부트 전환(마지막 쓰기):** p1의 기존 GRUB 설정을 백업한 후 Alpine
   전용 설정을 원자적 임시 파일 교체로 설치한다. BIOS와 EFI 경로가 모두
   있는 경우 두 설정을 함께 바꾸며, 새 항목은 `search --label alpine`으로
   p4를 찾고 Alpine 커널/initramfs만 로드한다. TinyCore menuentry와
   TinyCore build 경로는 이 시점에 제거한다.
7. **완료:** 모든 마운트를 해제하고 `sync`한 뒤, 최종 `lsblk -f`,
   `blkid -L alpine`, GRUB 파일 검증 결과를 표시한다. 성공 메시지는
   재부팅만 안내하며 TinyCore 메뉴로 돌아가지 않는다.

### 실패 처리와 중단 지점

- 파티션 테이블을 쓰기 전 실패는 즉시 중단하며 현재 TinyCore를 그대로
  유지한다.
- p3 재생성 이후에는 TinyCore 복구를 약속하지 않는다. 대신 p1의 기존
  GRUB 백업과 Alpine 입력물은 유지하여 p4 포맷/배치/GRUB 설치를 재시도할
  수 있게 한다.
- GRUB 교체는 Alpine payload 검증 이후의 마지막 단계여야 한다. p4에
  부팅 가능 payload가 없으면 기존 GRUB을 바꾸지 않는다.
- 실행 중에는 `set -euo pipefail`과 단계별 상태 파일을 사용하고, `trap`
  에서 임시 마운트만 해제한다. 실패를 성공으로 보이게 하는 무시된 오류나
  광범위한 `|| true`는 사용하지 않는다.

### 구현 단위와 수용 기준

1. `functions.sh`에 디스크 레이아웃 검사, 섹터 산술, 파티션 생성,
   Alpine payload 검증/배치, GRUB 원자 교체를 담당하는 전용 함수를 둔다.
2. `menu_m.sh`는 `o` 항목과 전환 함수 호출만 추가하고, 완료 시 재부팅을
   강제한다. 기존 `n` 추가 기능의 키와 동작은 유지한다.
3. 테스트는 loopback 디스크의 MBR과 GPT, `sdX`/`nvmeXn1` 이름을 각각
   사용해 p1·p2 불변, p3 1 GiB 축소, p4 크기·FAT32·`alpine` 레이블,
   payload 파일, BIOS/EFI GRUB 항목을 확인한다. 실제 매체 테스트는
   백업 가능한 USB에서 수행한다.
