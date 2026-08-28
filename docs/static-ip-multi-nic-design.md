# 고정 IP: 단일 NIC → 멀티 NIC(최대 8포트) 설계 변경

tinycore-redpill / tcrpfriend 저장소에서 진행한 변경 설계서입니다.
`user_config.json`의 `ipsettings`(고정 IP 관련 블록)를 직접 읽거나
표시하는 외부 도구(MSHELL Manager, SynoSmartInfo 등)가 있다면 아래
스키마 변경을 반영해야 합니다.

## 1. user_config.json 스키마 변경

### 이전 (단일 NIC, flat object)
```json
{
  "ipsettings": {
    "ipset": "static",
    "ipiface": "eth0",
    "ipaddr": "192.168.45.15/24",
    "ipgw": "192.168.45.1",
    "ipdns": "8.8.8.8",
    "ipproxy": "http://192.168.1.10:3128"
  }
}
```

### 이후 (멀티 NIC, 배열 + 전역 블록 분리)
```json
{
  "ipsettings": [
    {
      "ipset": "static",
      "ipiface": "eth0",
      "ipaddr": "192.168.45.15/24",
      "ipgw": "192.168.45.1",
      "primary": true
    },
    {
      "ipset": "static",
      "ipiface": "eth1",
      "ipaddr": "192.168.45.16/24",
      "ipgw": "",
      "primary": false
    }
  ],
  "netproxy": { "ipproxy": "" },
  "netdns": { "ipdns": "8.8.8.8" }
}
```

### 핵심 변경점

- **`ipsettings`가 object → array.** 최대 8개(NIC당 1개, 커널 cmdline의 `mac1`~`mac8` 상한과 동일)까지 들어갈 수 있습니다.
- **`primary` 필드 신설.** 배열 안에서 정확히 1개 항목만 `primary:true`이며, 이 NIC만 기본 게이트웨이(`ip route add default`)를 소유합니다. 나머지는 `ipgw`를 비워둘 수 있습니다(같은 서브넷일 때만 실질적 의미가 있음 - 다른 서브넷이면 그 NIC은 로컬 서브넷 밖과 통신이 제한됨).
- **`ipdns`가 NIC별 필드에서 빠짐.** Linux `resolv.conf`는 인터페이스 개념이 없어서 NIC별 DNS 값이 실제로는 그 NIC 전용으로 격리되지 않았기 때문에, 최상위 `netdns.ipdns` 전역 값 하나로 통합했습니다. **NIC이 1개라도 static으로 설정되면 이 값은 필수**입니다.
- **`ipproxy`도 NIC별 필드에서 빠짐.** 프록시는 애초에 NIC 개념이 아니므로 최상위 `netproxy.ipproxy`로 분리했습니다(선택 사항).

### 하위 호환(마이그레이션)

기존 flat object 설정을 만나면 자동으로:
1. `primary:true`를 붙인 1-원소 배열로 감쌈
2. `ipproxy` → `netproxy.ipproxy`로 이관
3. `ipdns` → `netdns.ipdns`로 이관

이 마이그레이션은 `migrate_ipsettings_schema()` 함수가 수행하며, **멱등**(몇 번을 다시 호출해도 안전)합니다. tinycore-redpill의 `functions_t.sh`와 tcrpfriend의 `boot.sh`에 동일한 로직이 각각 독립적으로 구현되어 있습니다(서로 다른 rootfs라 소스 공유 불가).

`ipsettings`를 직접 파싱하는 외부 도구가 있다면:
- `type` 체크를 먼저 해서 object/array/null 세 가지 모두 방어적으로 처리하거나
- 위 마이그레이션 로직과 동일한 jq 필터를 적용해 항상 배열로 정규화한 뒤 읽는 것을 권장합니다.

## 2. 메뉴 연동 (menu_m.sh)

### 메뉴 위치
- 예전: 추가기능(`additional()`) 하위메뉴 안에 있었음
- 현재: **메인 메뉴**로 이동, "추가기능" 항목 바로 위(`i` 키)에 위치. 상태 라벨은 `<iface> <addr> (+N)` 형식(N개 이상이면 primary만 대표로 표시).

### 주요 함수 (menu_m.sh)
- `staticIpMenu()` — 목록 화면(각 NIC 항목 + DNS + HTTP Proxy + 새 NIC 추가 + 완료). **NIC이 1개라도 있는데 DNS가 비어있으면 "완료" 처리를 막습니다.**
- `staticIpAddEntry()` — 아직 배열에 없는 실물 NIC만 후보로 보여줌(최대 8개 제한)
- `staticIpManageEntry()` — 기존 항목 편집/주(primary) 지정/삭제 서브메뉴
- `staticIpEditForm()` — IP/게이트웨이 2필드 폼(DNS는 여기 없음, 전역으로 분리됨). 승격되는 NIC의 gw가 비어있으면 이전 primary의 gw를 자동으로 물려받음
- `staticIpSetPrimary()` — "이 NIC을 주 게이트웨이로 지정" 액션, 동일하게 gw 자동 이관
- `staticIpDeleteEntry()` — 삭제, primary였으면 남은 첫 항목을 자동 승격
- `staticIpDnsMenu()` / `staticIpProxyMenu()` — 전역 DNS/프록시 입력(각각 IPv4/`http(s)://` 검증)

### 즉시 적용
- `staticIpMenu()`에서 "완료"로 나가는 순간 `apply_static_ip_now()`(functions_t.sh)를 호출해 **실행 중인 FRIEND 커널에 즉시 반영**합니다. 저장만 하고 끝나지 않습니다.
- `apply_static_ip_now()`는 배열을 순회하며 각 NIC의 IP를 적용하고, 기본 라우트는 primary만, DNS는 전역 값을 1회만 적용합니다.

## 3. 부팅 시 실제 적용 (tcrpfriend boot.sh)

- `buildStaticNetworkCmdline()` — NIC마다 `network.<MAC>=ip/netmask/gw/dns` 커널 cmdline 토큰을 1개씩 생성(공백으로 이어붙임). non-primary는 gw를 비우고, dns는 전역 값을 primary 토큰에만 실음(misc addon이 NIC마다 중복으로 `rc.network_routing`을 호출하지 않도록).
- `setnetwork()` — FRIEND 커널 단계에서 실제 적용(배열 순회, DNS는 루프 밖에서 1회).
- 두 함수 모두 시작 시 `migrate_ipsettings_schema()`를 호출해 항상 최신 스키마를 보장합니다.

## 4. 콘솔 표시 (getip())

기본 라우트가 없는 인터페이스(=non-primary static NIC, 또는 기본 라우트를 못 받은 DHCP NIC)를 더 이상 숨기지 않습니다. IPv4가 잡힌 모든 인터페이스를 훑어 `.ipsettings[]` 멤버십으로 Static/DHCP를 나눠 `-- Static IP --` / `-- DHCP --` 두 섹션으로 표시합니다(해당 섹션에 실제 항목이 있을 때만 헤더 출력).

## 5. misc addon (tcrp-addons)

`install-all.sh`의 `fixnetwork()`/`mshell-network.sh`는 `/proc/cmdline`의 `network.<MAC>=` 토큰을 파싱하는 방식이라 `user_config.json` 스키마 변화와 무관하게 그대로 동작합니다(이미 다중 토큰 순회 구조였음). 단, `mshell-network.sh`에 있던 "마지막 처리 인터페이스가 static이면 systemd가 오탐으로 failed 표시" 버그는 `exit 0` 추가로 별도 수정했습니다(스키마와 무관, 참고용).

## 참고 커밋 (tinycore-redpill, alpine-redpill 브랜치)
- `b91e057b` — 멀티 NIC(최대 8포트) 지원, primary 개념 도입
- `bb3e6943` — DNS 전역화 + primary 승격 시 gw 자동 이관
- `70f1f628` — 메뉴 종료 즉시 적용 + netproxy/netdns 스캐폴드
- `fe10e9a6` — 메뉴 위치 재배치(메인 메뉴로 이동)
- `3a96b622` — 18개 언어 번역

## 참고 커밋 (tcrpfriend, main 브랜치)
- `cae8037` — 멀티 NIC cmdline 빌더/런타임 적용
- `5f850e6` — DNS 전역화
- `b7b94d2` — getip() Static/DHCP 분리 표시
- `3a4345d` — netproxy/netdns 스캐폴드
