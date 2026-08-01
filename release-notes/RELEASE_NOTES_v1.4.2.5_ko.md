# alpine-redpill v1.4.2.5

## TinyCore용 기존 NIC 재정렬 로직 비활성화

이 브랜치에서는 더 이상 TinyCore를 제공하지 않습니다. 과거 TinyCore 환경을 위해 메뉴 시작 시 PCI 버스 순서로 `eth*` 인터페이스를 재정렬하고 DHCP/default route를 다시 설정하던 로직을 비활성화했습니다. Alpine과 xTCRP는 이미 PCI 순서대로 NIC를 처리하므로, 불필요한 링크 단절을 없애고 활성 SSH 관리 세션을 보존합니다.

## BMI2 미지원 custom-modules DSM 지원 확대

커널 5 플랫폼에서 BMI2 미지원 CPU용 `custom-modules` 빌드를 DSM 7.4.1까지 지원합니다. DSM 버전 상한, 모델 선택 시 오래된 설정의 자동 보정, 버전 선택 목록 필터링, 모듈 모드 검증 모두 같은 7.4.1 기준을 사용하도록 정렬했습니다.
