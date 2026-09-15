# alpine-redpill v1.4.4.4

## 로더 런타임 메타데이터 정합성

- 부트엔트리 런타임 동기화가 로더 payload의 버전과 Update 메타데이터를 보존하도록 개선했습니다. DSM 런타임 정보는 설치된 로더 payload와 일치할 때만 별도 항목으로 기록합니다.

## Alpine 콘솔 시작 안정성

- LBU 영속화 과정에서 `mshell-autologin-tc` helper와 tty1 `inittab` 항목을 다시 생성하고 명시적으로 포함합니다. 재부팅 후 helper 누락으로 getty가 MSHELL 데스크톱 세션을 시작하지 못하는 문제를 방지합니다.
- LBU 영속화 과정에서 `sxrc` 실행 순서도 보정하여 대화형 MSHELL Menu 터미널이 항상 마지막에 생성되도록 합니다.
- Alpine 오버레이에 `xdotool`을 포함했습니다. 데스크톱 터미널이 생성된 뒤 MSHELL이 제목으로 Menu 창을 찾아 전면 표시와 활성화를 재시도하므로 베어메탈 환경의 초기 키보드 포커스 안정성이 향상됩니다.
