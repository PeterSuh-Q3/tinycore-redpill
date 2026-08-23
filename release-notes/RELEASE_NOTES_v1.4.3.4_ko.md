# alpine-redpill v1.4.3.4

## 🌐 고정 IP 지정 기능

이제 메뉴에서 바로 로더의 DSM 부팅용 고정 IP를 지정할 수 있습니다 — 공유기의 DHCP가 매번 같은 주소를 준다는 보장에 더 이상 기대지 않아도 됩니다.

`Additional Functions` → `Static IP Settings`로 들어가면 순서대로 안내합니다: `Configure Static IP`를 선택하거나 `Use DHCP`로 되돌아가고, 인터페이스를 고른 뒤 IP 주소(CIDR), 게이트웨이, DNS 서버, 그리고 선택 항목인 HTTP 프록시를 입력합니다. 프록시 항목은 그 자리에서 검증되어 `http://`/`https://` 스킴이 없으면 저장 전에 바로 알림을 띄웁니다.

| | | |
|---|---|---|
| ![메인 메뉴 Additional Functions](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/01-main-menu-additional-functions.png) | ![Static IP Settings 항목](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/02-additional-functions-static-ip-item.png) | ![Configure 또는 DHCP 선택](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/03-static-ip-configure-or-dhcp.png) |
| ![인터페이스 선택](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/04-select-interface.png) | ![고정 네트워크 값 입력](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/05-enter-static-network-settings.png) | |

내부적으로는 실기에서 여러 차례 시행착오를 거쳐 실제로 동작하는 설계에 도달했습니다.

- 메뉴에서 입력한 값은 `user_config.json`에 저장되고, kexec 시점에 `network.<MAC>=address/netmask/gateway/dns` 형태의 커널 cmdline 파라미터로 변환됩니다 — 다른 redpill 계열 로더들과 동일한 방식입니다. 처음 시도했던, DSM ramdisk에 static `ifcfg-ethN`을 직접 굽는 방식은 실기 테스트에서 DSM 자체의 부팅 후 네트워크 매니저가 어떻게 쓰든 조용히 덮어써버리는 것으로 확인되어 채택하지 않았습니다.
- `tcrp-addons`의 `misc` addon이 이 cmdline 파라미터를 두 번 소비합니다 — ramdisk 패치 단계에서 한 번, 그리고 DSM 자체 네트워크 서비스가 끝난 직후 재적용하는 새 지속형 서비스 `mshell-network.service`에서 다시 한 번 — 그래서 이후 재부팅에서 DSM 자체 DHCP 클라이언트가 조용히 덮어쓰는 경쟁에서 이기지 못하게 막습니다.
- 실기에서 종단 간(end-to-end) 검증 완료: 요청한 고정 IP로 로더가 부팅되고, DSM 완전 부팅 후에도 그 IP가 유지됩니다.

## 🧹 그 외 자잘한 수정사항

- `menu.sh test` 모드의 `safe_fetch()`/`models.json` 조회가 CDN 캐시를 무효화하지 않아, 방금 푸시한 수정이 한동안 예전 파일로 서빙되던 문제를 고쳤습니다.
- `buildloader()`의 `USB_LINE`/`CMD_LINE` 조립에서 `+`를 문자열 연결 연산자처럼 쓰던 버그를 고쳤습니다(bash에는 그런 연산자가 없습니다) — kernel 5 미만의 SATA 부팅 구성에서 실제 부팅 커널 cmdline에 리터럴 `+`/`"` 문자가 그대로 주입될 수 있었습니다. `functions.sh`와 `tcrpfriend`의 `boot.sh` 모두 이제 수동 공백 문자열 연결 대신 작은 `cmdline_append()` 헬퍼로 커널 cmdline을 조립합니다.
- "Prevent SataPortMap/DiskIdxMap initialization" 토글을 고쳤습니다: `menu_m.sh`가 `my()`에 `prevent_init`을 전달했는데, `my()`의 인자 파서는 이 토큰을 인식하지 못해(오직 `prevent_param`만 인식) 토글을 켜면 그냥 문법 오류로 빌드가 죽었고, 꺼둔 상태(기본값)에서는 사용자가 수동으로 설정한 `SataPortMap`/`DiskIdxMap`을 매 재빌드마다 조용히 넉넉한 기본값으로 되돌리고 있었습니다.
- `nic_link_kick()`(부팅 시 NIC down/up + DHCP 재시도)이 이제 케이블이 꽂혀있지 않은(`carrier=0`) 인터페이스나 이미 정상적인(APIPA가 아닌) 주소를 가진 인터페이스는 건너뜁니다 — 이전에는 매 시도마다 모든 물리 NIC을 무조건 흔들어 재시도하느라 효과 없이 수 초씩 낭비했습니다. 실제로 아무것도 흔들지 않은 경우에는 호출부의 `check_internet` 폴링 루프도 통째로 건너뛰어, NIC kick으로 결과가 바뀔 수 없는 네트워크에서는 3번의 재시도 전체에서 최대 약 70초를 절약합니다.
- `rploader()`의 헤드리스 빌드 경로(MSHELL Manager의 자동 xTCRP 재빌드가 사용)도 이제 대화형 `my()` 경로와 마찬가지로 `models.json`을 새로 내려받습니다 — 이전에는 그 세션에 우연히 남아있던 예전 사본을 조용히 계속 재사용했습니다.
- `docs/test-mode.md`(`menu.sh test` + FRIEND pre-release 테스트 워크플로우 설명 문서)를 `docs/test-mode_en.md`와 `docs/test-mode_ko.md`로 분리했습니다.
