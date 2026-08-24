# Handoff: alpine-redpill v1.4.3.4 이후 상태 정리

세션 인수인계 문서. 새 세션에서 이어받을 때 이 문서 하나로 맥락이 잡히도록 작성.

## 1. 지금까지 상황

`tinycore-redpill`(alpine-redpill 브랜치)의 v1.4.3.4는 고정 IP 지정 기능(정식 릴리즈 완료)을 담고 있다. 그 이후 `functions.sh`/`functions_t.sh`/`menu.sh`/`menu_m.sh`에 총 11개 커밋이 이 세션 밖에서(사용자가 직접, 혹은 다른 세션에서) 추가로 반영되었다. 아직 버전 번호는 올라가지 않았고 릴리즈도 안 됐다 — 소스만 alpine-redpill에 푸시된 상태.

## 2. v1.4.3.4 이후 커밋 목록 (시간순)

### 2-1. 오프라인 고정 IP 설정 경로 (2026-08-24 00:37 ~ 01:58, 3커밋)

| 커밋 | 내용 |
|---|---|
| `c6d6975b` | `menu.sh`가 인터넷 연결 3회 재시도 후 모두 실패하면 GitHub 접근 확인을 건너뛰고 고정 IP 설정 다이얼로그 표시. `FORCE_STATIC_IP_SETUP=true`면 `menu_m.sh`가 메인 루프 없이 `staticIpMenu()`로 진입하고 저장 후 재부팅 여부를 묻는다. |
| `59cadf95` | 오프라인 경로가 git clone 및 모델 초기화 등 인터넷 의존 로직을 거치지 않도록 `menu.sh`가 플래그를 보자마자 `menu_m.sh`를 직접 실행한다. `menu_m.sh` 분기도 `staticIpMenu()` 바로 뒤로 이동했다. |
| `ea9edd7d` | `langMenu()`가 아직 실행되지 않아 `tz`가 비어 `MSGUS147`을 참조하던 버그를 수정했다. `tz="ZZ"`와 `load_zz`로 gettext fallback을 먼저 채운다. |

### 2-2. MSHELL Manager/Syno Smart Info/AMD GPU 패키지 조회 중앙화 (2026-08-24 16:59 ~ 20:01, 6커밋)

| 커밋 | 내용 |
|---|---|
| `46625077` | 빌드마다 GitHub API를 3번 따로 호출하던 것을 `tcrp-modules`의 `aeudev/recipes/latest.json` 하나로 통합했다. |
| `f03dbd64` / `1bca2e8f` | `aeudev` extension이 로컬에 받아둔 매니페스트를 우선 사용하고, 없으면 Raw GitHub로 fallback한다. `functions.sh`와 `functions_t.sh`에 동일하게 적용했다. |
| `195d69a5` / `da240498` | 로컬 매니페스트가 `aeudev/<platform>_<kernel>/latest.json` 하위에 있을 수 있으므로 `find`로 동적 탐색한다. |
| `230f020b` | `jq`의 `test()` 정규식 대신 `endswith(".spk")`를 사용해 jq 버전 차이에 대응했다. |

### 2-3. user_config.json 백업 트리거 로직 중앙화 (2026-08-24 20:55, 1커밋)

`3a013360` Centralize user config backup check

- `sync_part_config()`와 `chk_filetime_n_backup()`을 `menu_m.sh`에서 공용 `functions.sh`로 이동했다. `tcrpfriend`의 `boot.sh` 자동 재빌드 경로도 같은 로직을 재사용할 수 있다.
- 판정을 로컬 파일과 파티션 파일의 md5 비교에서 메뉴 진입 시점과 종료 시점의 sha256 스냅샷 비교로 전환했다.
- `keymapMenu()`/`satadom_edit()`/`i915_edit()`/`showAutoUpdateMenu()`의 즉시 `backuploader()` 호출을 `refresh_userconfig_hash()`로 교체했다. 실제 백업은 `restart()`/`byebye()`의 중앙 판정에서만 수행한다.
- 이전 세션에서 감사했던 `menu_m.sh` 백업 트리거 목록은 이 커밋을 기준으로 다시 감사해야 한다.

## 3. 병행 진행된 다른 저장소 작업

- **`tcrpfriend`(main)**: `boot.sh` v0.1.4w에서 v0.1.4x로 변경. `buildStaticNetworkCmdline()`가 MAC 스푸핑 모델에서 kexec 이전 MAC을 읽던 버그를 수정해 `extra_cmdline.mac<N>`을 직접 읽는다. 45.84(DS425+)에서 원인을 확인했다. v0.1.4x 릴리즈는 Latest로 배포되었으나 이후 `initramfs unpacking failed`가 발생해 자산 손상 또는 체크섬 문제로 추정되었다. 사용자가 pre-release로 되돌리고 재빌드 테스트 중이며 안정화 확인 보고까지 받았다. 다시 Latest로 승격할지는 미결정이다.
- **`tcrp-addons`(main)**: `misc` addon의 GNU sed `\L` 버그를 `tr`로 교체하고, 없는 `set_key_value`를 `set_ifcfg_kv()`로 대체했으며, `mshell-network.service`를 추가했다. 45.34/45.2/45.5/45.84 실기에서 검증했다.
- **`diskcompat` addon**: RR의 `diskcompat`를 저장소 규칙에 맞게 이식했다. `tcrp-addons`에는 커밋했지만 `redpill-load`의 `bundled-exts.json`에는 아직 등록하지 않았다. 실기 검증도 아직 하지 않았다.
- **`redpill-load`(master)**: `.gitignore`에 `.DS_Store` 무시 규칙만 추가했다.

## 4. 표준 릴리즈 절차

`RELEASE_NOTES.md` 루트 파일은 직접 편집하지 않는다. CI(`alpine-deploy.yml`)가 소비한다.

1. `release-notes/RELEASE_NOTES_v{VERSION}_en.md`와 `_ko.md`를 작성한다.
2. `functions.sh`와 `functions_t.sh`의 버전번호, builddate, history 함수, showlastupdate 함수, 두 함수 사이의 문서용 history 주석을 함께 갱신한다. 두 파일은 byte-identical 상태를 유지한다.
3. 버전 히스토리 3곳의 요약에는 특수문자를 넣지 않는다. `showlastupdate()` 항목 사이에는 빈 줄 하나를 둔다.
4. `.github/workflows/alpine-make.my.sh.gz.yml`을 `workflow_dispatch`로 실행해 `my.sh.gz`를 빌드한다. 이 파일은 빌드 즉시 사용자에게 배포되므로 미검증 상태에서 실행하지 않는다.
5. GitHub Release를 생성하고 영문 릴리즈 노트 다음에 한글 릴리즈 노트를 이어 붙여 본문으로 사용한다.

커밋 및 푸시는 사용자가 명시적으로 요청한 경우에만 수행한다. 워크플로우 생성 커밋 때문에 원격이 앞서 있을 수 있으므로 push 전 `git fetch origin alpine-redpill` 후 rebase한다. `git reset --hard`로 사용자 변경을 버리지 않는다.

## 5. 다음 세션에서 판단할 것

1. v1.4.3.4 이후 변경을 v1.4.3.5로 묶을지 결정한다.
2. `functions.sh`/`functions_t.sh` 버전 업과 changelog 4곳 반영이 아직 필요하다.
3. `tcrpfriend` v0.1.4x를 Latest로 승격할지 결정한다.
4. `diskcompat` addon의 실기 검증을 수행한다.
5. `45.9` IP 중복 의심 건은 `tcpdump` 기반 정밀 검증이 필요하다.
6. ttyd 7681 리슨 장비와 IP 중복 의심의 관련성을 후속 확인한다.

