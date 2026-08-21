# MSHELL Manager

이 `tools/` 디렉토리의 스크립트들은 대부분 부트로더/설치 단계에서 쓰는
저수준 유틸리티다. 정작 설치가 끝난 뒤 실기(DSM)에서 하드웨어 상태를
확인하거나(NVIDIA/AMDGPU, 시스템 정보 등) 관리하고 싶다면, 여기 있는
스크립트를 하나씩 손으로 돌리기보다 **MSHELL Manager** 패키지를 DSM에
설치하는 편이 낫다.

- 공개 릴리즈 미러: https://github.com/PeterSuh-Q3/mshell-manager-rel
- 릴리즈(.spk 다운로드): https://github.com/PeterSuh-Q3/mshell-manager-rel/releases/latest

`inject_loader` 단계는 이제 이 미러의 `releases/latest`를 GitHub API로
직접 조회해서 최신 `.spk`의 다운로드 URL/sha256을 가져온다
(`functions.sh`의 `MSHELL_MANAGER_RELEASE_API` 참고). `alpine-redpill/
tools`는 더 이상 MSHELL Manager 배포 경로가 아니므로, 여기 `.spk`
파일을 직접 커밋해 두지 않는다 - 최신 버전은 항상 위 링크에서 받을 것.
