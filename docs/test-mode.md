# `menu.sh test` — my.sh.gz/정식 릴리즈 승격 없이 실기에서 전체 체인 검증하기

> **대상:** tinycore-redpill(로더/FRIEND 빌드 로직) + tcrpfriend(FRIEND 커널/initrd)
> **목적:** 소스를 수정한 뒤, `my.sh.gz` 재빌드(모든 실사용자에게 즉시 자동배포됨)나
> tcrpfriend 릴리즈의 "Latest" 승격 없이도 실기 한 대에서 안전하게 end-to-end 검증하는 방법 정리.

---

## 왜 필요한가

`my.sh.gz`는 `getlatestmshell()`을 통해 (1) 사용자가 대화형 `menu.sh`를 열 때
(`tcbautoupd` 설정이 켜져 있으면), (2) **FRIEND가 자동재빌드할 때마다**
(`mshell_auto_rebuild()`가 `TCB=true`를 항상 명시적으로 세팅하므로 예외 없이 매번)
자동으로 다운로드·적용된다. 즉 `my.sh.gz`를 재빌드하는 건 CI 루틴이 아니라
**실사용자에게 즉시 배포하는 행위**다. 검증되지 않은 기능을 이 경로로 내보내면
모든 실사용자가 그대로 받는다(실제로 2026-08-23 고정 IP 기능 개발 중 이 사고가
한 번 있었고, 직전 버전으로 되돌린 사례가 있다).

이 문서는 그런 위험 없이 실기에서 검증하는 방법을 정리한다.

## 1. 로더 쪽: `menu.sh test`

`menu.sh`에 `test` 인자를 주고 실행하면(`menu.sh:450-499`):

```sh
if [ "$1" = "test" ]; then
  rm -f /tmp/test_mode && touch /tmp/test_mode
  oldver="test"
fi
...
if [ "$oldver" = "test" ]; then
  gitdownload   # redpill-load clone/pull
  safe_fetch ".../alpine-redpill/functions_t.sh" "/home/tc/functions.sh" "rploaderver="
  safe_fetch ".../alpine-redpill/menu_m.sh"      "/home/tc/menu_m.sh"    "kver5explatforms"
  safe_fetch ".../alpine-redpill/burnloader.sh"  "/home/tc/burnloader.sh" "burnloader()"
  safe_fetch ".../alpine-redpill/i18n.h"         "/home/tc/i18n.h"       "function load_zz"
  cp build-loader_t.sh build-loader.sh   # redpill-load 쪽 test 변형본으로 교체
  cp ext-manager_t.sh  ext-manager.sh
  cp pats_t.json       pats.json
  cp bundled-exts_t.json bundled-exts.json
fi
```

핵심: **`functions_t.sh`(테스트 트랙)를 GitHub raw content에서 직접 받아
`/home/tc/functions.sh`(라이브 파일명)에 덮어쓴다.** `menu_m.sh`/`i18n.h`/`burnloader.sh`도
각각 `alpine-redpill` 브랜치에서 직접 받는다 — **`my.sh.gz`를 전혀 거치지 않는다.**
`safe_fetch()`(menu.sh:46)가 다운로드 후 non-empty / sentinel 문자열 포함 /
`bash -n` 문법 체크를 통과해야만 실제 파일을 교체하므로 최소한의 안전장치는 있다.

`functions.sh`와 `functions_t.sh`를 항상 byte-identical하게 유지해두면, `alpine-redpill`
브랜치에 push만 해도 곧바로 `menu.sh test`로 검증 가능하다 — 별도로 "test 브랜치에만
반영"하는 절차가 필요 없다.

이 경로는 **그 세션에서 명시적으로 `test` 인자를 준 경우에만** 실행되는 1회성·로컬
fetch라서, 다른 실사용자에게 전혀 영향이 없다.

## 2. FRIEND 쪽: `curlfriend()`의 pre-release 자동 조회

`/tmp/test_mode`가 있으면 `functions.sh`의 FRIEND 다운로드 경로 자체가 분기한다.
`curlfriend()`(`functions.sh:6171`, `bringoverfriend()`가 호출)의 실제 구현:

```sh
function curlfriend() {
    REPO="PeterSuh-Q3/tcrpfriend"
    FRTAG=""
    if [ -f /tmp/test_mode ]; then
        cecho g "This is Test Mode"
        PRERELEASE_TAG=$(curl -sk "https://api.github.com/repos/$REPO/releases" | \
          jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)
        [ -n "$PRERELEASE_TAG" ] && FRTAG="$PRERELEASE_TAG"
        writeConfigKey "general" "friendautoupd" "false"   # 아래 3번 참고
    fi
    if [ -z "$FRTAG" ]; then
        # test_mode가 아니거나 pre-release가 없으면 "latest"(정식)를 사용
        LATESTURL=$(curl ... "https://github.com/$REPO/releases/latest")
        FRTAG="${LATESTURL##*/}"
    fi
    curl ... "https://github.com/$REPO/releases/download/${FRTAG}/{chksum,bzImage-friend,initrd-friend}"
}
```

즉 **test_mode일 때는 `tcrpfriend`의 "latest"(정식 stable 릴리즈)가 아니라,
`prerelease: true`로 마킹된 가장 최근 pre-release 태그를 GitHub API로 찾아서
그 자산(`bzImage-friend`/`initrd-friend`/`chksum`)을 받아온다.**
`redpill-lkm`(커널 모듈)도 `getredpillko()`에서 같은 패턴(test_mode 시 pre-release
우선 조회)을 쓴다.

일반 사용자는 `/tmp/test_mode` 없이 항상 "latest"(non-prerelease)만 보므로,
**pre-release 자산에는 절대 노출되지 않는다.**

## 3. 안전장치: `friendautoupd=false`로 pre-release가 정식판에 덮이지 않게 함

`curlfriend()`가 test_mode에서 pre-release를 받아올 때
`writeConfigKey "general" "friendautoupd" "false"`로 **영구 설정**을 같이 남긴다.
이걸 FRIEND 자신의 `boot.sh`가 소비한다.

`upgradefriend()`(tcrpfriend `boot.sh`, FRIEND 자체 부팅/`updateauto` 디스패치
시점마다 실행되는 자기-업데이트 체크 함수)의 첫 동작:

```sh
function upgradefriend() {
    ...
    if [ "${friendautoupd}" = "false" ]; then
        echo -en "\r$(msgwarning "TCRP Friend auto update disabled")\n"
        return   # "latest"(정식) 체크섬 비교/다운로드를 아예 건너뜀
    else
        friendwillupdate="1"
    fi
    # 여기부터 tcrpfriend/releases/latest 와 체크섬 비교 → 다르면 다운로드 후 reboot
    ...
}
```

즉 test_mode로 한 번 pre-release FRIEND를 받아오면, 그 순간 `friendautoupd=false`가
저장되어 **FRIEND가 이후 스스로 도는 정식 "latest" 자동업데이트 체크를 건너뛴다** —
어렵게 받아온 pre-release 테스트 빌드가 FRIEND의 정상 자동업데이트 로직에 의해
조용히 정식 릴리즈로 되돌아가 버리는 일이 없다. `curlfriend()`(다운로드)와
`upgradefriend()`(자기-업데이트 억제)가 `friendautoupd` 하나로 정확히 짝을 이루는 설계다.

## 4. 조합: 실사용자 영향 없이 전체 체인 검증하는 절차

1. `functions.sh`/`menu_m.sh`/`i18n.h` 등을 수정 → `alpine-redpill` 브랜치에 push
   (`functions.sh`/`functions_t.sh` byte-identical 유지 필수)
2. `tcrpfriend`(`boot.sh` 등)를 수정 → buildroot로 빌드 → **pre-release 태그**
   (예: `v0.1.4u`, GitHub 릴리즈에서 prerelease 플래그 켜진 상태)에 자산 업로드,
   "Latest"로 승격하지 않음
3. 실기에서 `menu.sh test` 실행 → `/tmp/test_mode` 생성, 로더 소스 최신화
4. FRIEND 모드로 빌드 → `curlfriend()`가 자동으로 pre-release FRIEND 바이너리를
   받아오고 `friendautoupd=false` 저장
5. 이 상태로 재부팅해도 FRIEND는 정식판으로 되돌아가지 않으므로, 반복적으로
   end-to-end(로더 → FRIEND → DSM) 동작을 확인할 수 있다

`my.sh.gz` 재빌드나 tcrpfriend 릴리즈의 "Latest" 승격은 이 검증이 끝난 뒤,
별도로 명시적인 배포 결정을 거쳐 진행한다.
