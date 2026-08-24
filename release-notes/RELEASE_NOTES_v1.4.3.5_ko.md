# alpine-redpill v1.4.3.5

## 오프라인 고정 IP 설정

로더가 인터넷 연결을 세 번 시도한 뒤에도 연결하지 못하면 고정 IP를 설정할지 묻습니다. `Yes`를 선택하면 저장소 복제나 모델 다운로드 또는 로더 빌드 없이 정적 네트워크 설정 화면으로 바로 진입합니다. 입력값은 `/mnt/tcrp/user_config.json`에 직접 저장되고, 이어서 즉시 재부팅 여부를 선택할 수 있습니다.

오프라인 진입 시에도 gettext fallback 메시지를 먼저 초기화하도록 수정해 초기 `MSGUS147` 오류를 제거했습니다.

## 패키지 매니페스트 중앙화

MSHELL Manager Syno Smart Info AMD GPU 패키지 조회는 가능한 경우 `tcrp-modules`의 `aeudev` `latest.json` 매니페스트를 우선 사용하고, 없을 때만 Raw GitHub를 fallback으로 사용합니다. 플랫폼별 매니페스트 경로는 동적으로 탐색하며, 패키지 선택은 오래된 jq 환경에서도 동작하도록 정규식 대신 `endswith`를 사용합니다.

## user_config 영속화 처리 중앙화

user_config 백업 처리를 `functions.sh`와 tcrpfriend boot 경로에서 함께 사용할 수 있도록 공용화했습니다. 메뉴 진입 시점과 종료 시점의 SHA 256 스냅샷을 비교해 변경을 판정하며, 각 메뉴 동작은 스냅샷만 갱신하고 실제 백업 여부는 최종 재시작 또는 종료 경로에서 한 번만 결정합니다.

이번 변경은 v1.4.3.4 이후 소스 보완이며 기존 로더 빌드 및 릴리즈 자산 구조는 유지합니다.
