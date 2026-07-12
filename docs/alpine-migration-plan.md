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
| fdisk (68) | `util-linux` | 그대로 |
| sgdisk (6) | `sgdisk` | **정정(2026-07-12 실측)**: `gptfdisk`는 gdisk/cgdisk/fixparts만 제공, sgdisk 바이너리 없음 — apk에 `sgdisk`라는 별도 패키지 존재, 그것을 설치 |
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
| lspci | `pciutils` | **추가(2026-07-12 실측)**: menu_m.sh의 `lspci -d ::107`(scsi-tinycore64 분기) 호출, 원 매핑표에서 누락됐던 항목 |
| git (30, addon_gitdown 등) | `git` | **추가(2026-07-12 실측)**: functions.sh의 redpill-load/tcrp-addons git clone 경로 |
| udevadm (1) | `eudev` | **추가(2026-07-12 실측)**: functions.sh의 로더 디스크 버스 타입 판별(`udevadm info --query property`) |
| sed(-s 옵션) | `sed`(GNU sed 4.9) | **추가(2026-07-12 실측)**: busybox sed는 `-s` 미지원(`unrecognized option`) → apk sed로 교체 필요. `/usr/bin` PATH 우선순위로 자동 해결 |
| bspatch | 없음(gcompat) | **추가(2026-07-12 실측)**: apk에 bsdiff/bspatch 패키지 자체가 없음 → `tools/bspatch`(glibc)를 gcompat+libbz2 SONAME 심볼릭 링크로 실행(§5-A) |
| strip | `binutils` | **추가(2026-07-12 실측)**: functions.sh의 redpill 커널 모듈 `strip --strip-debug` 호출(§ REDPILL_MOD_NAME 빌드 경로), 미설치 상태였음 |
| rsync (2) | `rsync` | **추가(2026-07-12 실측)**: pat 추출/백업 fallback 경로 |
| bash · sudo | `bash` `sudo`\|`doas` | 전 스크립트 bash 전제 → 필수 설치 |
| **glibc_i18n_locale** | 없음 → `LANG=C.UTF-8` | musl는 로케일 독립 UTF-8, 폐기 |

---

## 2-A. 동적 fstab 생성 — rebuildfstab 이식

`getloaderdisk()`가 UUID(`6234-C863`)로 찾아낸 실제 디바이스명(`sda`/`vda`/`vdb` 등, 하드웨어·가상화
구성에 따라 달라짐)에 맞춰 `/mnt/${loaderdisk}1,2,3`을 대상 경로 없이 `mount /dev/X1`만으로
마운트하려면, TinyCore와 동일하게 **부팅마다 연결된 디스크를 스캔해 `/etc/fstab`을 동적 재생성**하는
메커니즘이 필요하다. TinyCore는 `/etc/init.d/tc-config`가 부팅 시 `/usr/sbin/rebuildfstab`을 호출해
이 작업을 수행한다 (`# Added by TC` 마커로 자기 관리 항목만 매 부팅 갱신, `/dev/`로 시작하는
커스텀 항목은 보존).

**소스**: [tinycorelinux/Core-scripts `usr/sbin/rebuildfstab`](https://github.com/tinycorelinux/Core-scripts/blob/master/usr/sbin/rebuildfstab)
(box의 `/usr/sbin/rebuildfstab`과 바이트 단위로 동일 — 최신 upstream 확인됨, 2026-07-12).
Alpine 전용 배포본은 upstream에도, Alpine 커뮤니티에도 존재하지 않음(검색 확인) — TinyCore와
Alpine은 별개 배포판 프로젝트라 공식 크로스 포팅이 없다.

**이식 판정**: 순수 busybox ash + `blkid`/`mkdir`/`printf`/`read`만 사용 — 둘 다 busybox 계열이라
**TC 전용 의존성 2줄만 제거하면 원본 그대로 이식 가능**:
- `. /etc/init.d/tc-functions` + `useBusybox` 소싱 제거 (TC 전용 셸 헬퍼, 불필요)
- 그 외 로직 전체(파티션 스캔, `# Added by TC` 마커 기반 자기 관리, 커스텀 항목 보존) 무수정 이식

**배치**: `alpine/rebuildfstab` → 대상 `/usr/local/sbin/rebuildfstab`,
`alpine/local.d-restore-packages.start` → 대상 `/etc/local.d/restore-packages.start`
(OpenRC `local` 서비스가 부팅마다 `rebuildfstab` 호출 → apk world 패키지 재설치 순으로 실행).

**실측 검증**: Alpine PoC VM에서 수동 UUID 하드코딩(`/mnt/vdb1,2,3`)을 완전히 걷어내고
`rebuildfstab` 단독으로 대체 → 재부팅 후 `mount /dev/vdb1`(대상 경로 생략)이 자동 생성된
fstab만으로 정상 동작 확인.

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

## 4. 폐기 스택 (개정: X11은 유지, urxvt만 교체)

> **2026-07-12 결정 번복**: 초기엔 "X11을 쓰면 musl에서 glibc 로케일이 강제된다"고 판단해
> X11 전체를 폐기 대상으로 잡았으나, 이는 **TinyCore 특유의 구식 urxvt+glibc 조합 문제였지
> X11 자체의 제약이 아님**이 실측으로 확인됨. Alpine은 musl 위에서 `xorg-server`를 apk
> 네이티브로 지원하고, `lxterminal`(GTK/VTE, Pango+fontconfig 렌더링)은 glibc 로케일
> 없이도 CJK를 정상 렌더링한다(스크린샷 실측 — "안녕하세요_한글테스트" 정상 표시,
> Xvfb+xwd로 캡처 확인). 따라서 **X11은 유지하고 urxvt/aterm만 lxterminal로 교체**하는
> 쪽으로 방향을 수정한다. ttyd는 원격 접속 경로로 계속 병행 유지.

폐기 대상은 다음으로 축소된다 — **glibc 커플링 패키지만** 제거하고 X11 자체는 유지:

`glibc_apps` · `glibc_i18n_locale` · `unifont` · `rxvt`/`urxvt` · `aterm` · `setfont` · `kmaps` · `localedef` 호출부

**교체**: `urxvt`/`aterm` → `lxterminal` (`apk lxterminal xorg-server musl-locales musl-locales-lang`).
`~/.Xdefaults`의 `URxvt.*` 리소스 설정은 GTK 앱에 적용되지 않으므로 함께 제거 —
lxterminal 설정은 `~/.config/lxterminal/lxterminal.conf` 사용.

**menu_m.sh 반영 지점** (`is_alpine()` 가드):
- `writexsession()` — 아래 4-A 참조. `.xsession`/`.xinitrc`/`.xserverrc` 3파일 재작성
- 태그 재실행부 — 직접 `urxvt -e menu.sh` 호출을 `lxterminal --command=...`로 교체
- glibc_apps 설치 분기 — `tce-load glibc_apps glibc_i18n_locale unifont rxvt` 대신
  `apk add lxterminal musl-locales musl-locales-lang xorg-server xf86-video-fbdev xinit flwm`
- `~/.Xdefaults`/`localedef` 블록 — lxterminal에 무의미하므로 `is_alpine`이면 전체 skip

---

## 4-A. .xsession 전체 이식 상세 (Xfbdev/waitforX/flwm)

box(192.168.45.95)의 실제 `.xsession`을 열어보니 `writexsession()`이 생성하는 urxvt/aterm
호출부 외에, **X 세션 부팅 자체를 담당하는 헤더가 별도로 존재**했다(TC의 X.tcz가 미리 깔아둔
베이스 템플릿). 이 헤더가 없으면 애초에 X도, WM도, 터미널도 뜨지 않는다 — urxvt→lxterminal
교체보다 선행되어야 할 더 근본적인 부분이었다.

| TC 원본 구성요소 | 정체(실측) | Alpine 대응 |
|---|---|---|
| `Xfbdev -mouse ...` | kdrive 계열 **setuid glibc 동적 바이너리** X서버 | `xorg-server` + `xf86-video-fbdev`(apk 네이티브, musl) |
| `waitforX` | `XOpenDisplay` 폴링하는 **glibc 동적 바이너리**(strings로 확인) | `xinit`이 내부적으로 처리 — 별도 폴링 스크립트 불필요 |
| `flwm`(WM) | glibc 동적 바이너리인 줄 알았으나 **apk에 musl 네이티브 빌드로 이미 존재** | `apk add flwm` 그대로 사용(재빌드 불필요) |
| `urxvt`/`aterm` | glibc_i18n_locale 의존 | `lxterminal` (§4 상단 참조) |
| `LANG`/`localedef` | glibc 전용 | `musl-locales`/`musl-locales-lang` |
| `/usr/local/etc/X.d`, `~/.X.d` 훅 디렉터리 | TC 관례, 확장 포인트 | 동일 경로 관례 그대로 이식(현재 비어있어 no-op) |
| `.profile`의 `startx` 자동기동 트리거(TERMTYPE 체크) | tty1 콘솔 로그인 시 자동 실행 | **미이식** — `.profile`은 이번 범위 밖, 별도 작업 필요 |

**이식 방식 변경 이력**: 처음엔 TC 원본처럼 `Xorg &` + `until xdpyinfo; do sleep; done` 수작업
폴링으로 이식했으나, **비-tty(SSH/nohup) 환경에서 xdpyinfo가 무기한 행(hang)되는 현상을 실측**
(정상 상태의 X에 대해 인터랙티브 SSH 명령으로는 즉시 성공하는데 스크립트 내부에서는 걸림).
TC가 실제로는 `waitforX` 수작업이 아니라 **`.profile` → `startx`(xinit 래퍼)로 기동**한다는
사실을 뒤늦게 확인하고, `xinit`이 이미 안전하게 처리하는 Xauthority/타이밍 로직을 재발명하지
않도록 **`startx`/`xinit` 기반으로 교체**했다. 이 과정에서 Alpine 고유의 추가 장벽 2개를
발견해 제거함:
1. `/usr/libexec/Xorg.wrap`의 기본 정책이 **"console 사용자만 X 서버 실행 허용"** —
   TC의 `Xfbdev`는 이런 제약이 없는 setuid 바이너리였으므로 `/etc/X11/Xwrapper.config`에
   `allowed_users=anybody`로 동등하게 완화.
2. Xorg.wrap(suid)이 **`-config`에 절대경로를 거부**(`With elevated privileges -config
   must specify a relative path`) — `/etc/X11/xorg.conf.d/10-fbdev.conf` 스니펫으로
   전환해 `-config` 플래그 자체를 제거(Xorg가 자동 로드).

**실측 검증 상태**:
- ✅ **완료**: Xorg(fbdev)+flwm+lxterminal 조합의 실제 렌더링 — Xvfb/수동 Xorg 기동으로
  한글 CJK 정상 표시 스크린샷 2매 확보(`docs/assets/lxterminal-korean-render-poc.png` 외)
- ⚠️ **미완료**: `startx` 자동 기동 체인의 완전한 end-to-end 검증. 원인은 이식 결함이
  아니라 **이 PoC VM이 `console=ttyS0 -display none`(시리얼 전용) 구성이라 실제 VT가
  없기 때문** — Alpine의 Xorg.wrap/xinit은 진짜 콘솔(VT) 세션을 전제로 동작한다.
  물리 하드웨어 또는 `-vga std` 등 실제 그래픽 콘솔이 있는 qemu 구성에서 재검증 필요.

**리포 자산**: `alpine/xorg.conf.d-10-fbdev.conf`, `alpine/Xwrapper.config`
(둘 다 `writexsession()`이 동일 내용을 인라인 생성하므로 참조용 사본).

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

**§5-A. gcompat 실측 성공 사례 — bspatch (2026-07-12)**: kpatch와 동일 카테고리(glibc
동적 바이너리)인 `tools/bspatch`로 gcompat 경로를 실제 검증. `apk add gcompat`만으로는
`libc.so.6`/`ld-linux`는 해결됐으나 `libbz2.so.1.0`이 없어 실패 — Alpine의 `libbz2`
패키지는 SONAME이 `libbz2.so.1`(`.1.0.8`로 심볼릭)이라 정확한 문자열이 불일치했던 것.
`ln -sf /usr/lib/libbz2.so.1.0.8 /usr/lib/libbz2.so.1.0` 호환 심볼릭 링크로 완전 해결,
`bspatch` 정상 실행 확인(사용법 메시지 출력). **kpatch도 유사한 SONAME 불일치 가능성을
염두에 두고 같은 패턴(gcompat + 필요 시 심볼릭 링크 보정)으로 접근할 것.**

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
