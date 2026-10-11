# alpine-redpill v1.4.5.5

## MSHELL Manager 원격 Docker 재빌드 패키지 준비

MSHELL Manager가 DSM 커널 교체를 위해 로더를 원격 재빌드할 때, 결과물을 완전하고 검증 가능한 업데이트 패키지로 전달해야 합니다. 이번 버전은 이 연동을 위한 로더 측 패키징 흐름을 마련합니다. 원격 패키지에는 현재 Alpine P4 영속화를 넣지 않으며, 로더에서 직접 수행하는 일반 백업의 Alpine 영속화 처리는 별도로 유지됩니다.

## QEMU Guest Agent 지원 메뉴 구분 개선

빌드 옵션 이름을 목적이 분명한 `vmtools-qemuga`로 변경했습니다. 기존 `vmtools` 선택값은 자동으로 이전되므로 사용자가 다시 선택할 필요가 없습니다.
