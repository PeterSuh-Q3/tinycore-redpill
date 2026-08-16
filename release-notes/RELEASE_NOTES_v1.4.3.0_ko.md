# alpine-redpill v1.4.3.0

## 📋 MSHELL Manager v1.0.7 동반 릴리즈

이번 수정 사항들은 [MSHELL Manager](https://github.com/PeterSuh-Q3/mshell-manager) v1.0.7의 신규 기능 **"Restart to Auto Rebuild Mode"**(버튼 한 번으로 로더 재부팅부터 재빌드까지 콘솔·키보드 조작 없이 완전 자동 수행)가 처음부터 끝까지 정상 동작하려면 필요합니다.

> [!WARNING]
> [tcrpfriend v0.1.4q](https://github.com/PeterSuh-Q3/tcrpfriend/releases/tag/v0.1.4q)와 함께 사용해야 합니다. auto-rebuild 흐름은 두 저장소에 걸쳐 있어서, 이 릴리즈만 있거나 friend 커널만 있는 상태로는 충분하지 않습니다. 버전이 서로 맞지 않으면 이번 수정 사항들이 발동하지 않습니다.

## 🔧 비대화형 / friend 커널 빌드 수정

- 🔐 **프리릴리즈 태그 조회 TLS 우회**: friend 저장소의 프리릴리즈 태그 확인(test 모드에서 사용)이 CA 인증서 번들이 없는 장비에서 TLS 검증에 실패해, 의도한 프리릴리즈 대신 조용히 최신 정식 릴리즈로 대체되던 문제였습니다. 같은 함수 내 파일 다운로드 호출과 동일하게 `curl -k`를 사용하도록 수정했습니다.
- 📦 **friend 커널에서 PAT 캐시 및 확장 파일 권한 문제**: 호스트명이 `tcrpfriend`인 모든 환경에서 `FRKRNL`이 자동으로 `YES`로 판정되는데, 이 경우 일부 파일 복사가 `sudo cp`를 거치면서 PAT 캐시와 확장 인덱스/레시피 파일이 root 소유로 생성되어, 뒤이어 이를 읽어야 하는 `tc` 유저가 읽지 못하는 문제가 있었습니다. 빌드 도중 `Permission denied` / "index file ... is not readable" 오류로 중단됐습니다. 소유권이나 `FRKRNL` 분기 로직은 그대로 두고, `sudo` 쓰기 직후 읽기/탐색 권한만 완화해 해결했습니다.
- 🖥️ **제어 터미널이 없을 때 빌드 진행바 오류 해결**: `show_progress_bar()`가 무조건 `/dev/tty`에 쓰던 것이, tty가 연결되지 않은 헤드리스 빌드(예: tty 없이 `su -c`로 구동)에서 매번 `No such device or address`로 실패하던 문제였습니다. 이제 제어 터미널이 없으면 stdout으로 자동 폴백하여, 헤드리스 환경에서도 깨끗하게 동작하고 `tee`로 로그 캡처도 계속 가능합니다.

세 가지 모두 auto-rebuild 기능을 실기에서 개발·검증하는 과정에서 끝까지 확인했습니다.
