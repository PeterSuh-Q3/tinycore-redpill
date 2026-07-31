# alpine-redpill v1.4.1.1

`alpine-redpill` 라인의 작은 후속 수정 릴리즈입니다.

<details>
<summary><b>xTCRP 박스가 더 이상 오래된 main 브랜치로 조용히 되돌아가지 않습니다 (클릭해서 펼치기)</b></summary>

<br>

xTCRP의 friend 커널 환경(Buildroot, Alpine이 아님)은 `/etc/alpine-release` 파일 존재 여부로 `functions.sh`를 받아올 브랜치를 결정하고 있었습니다. 이 파일은 실제 Alpine 박스에만 존재하기 때문에, xTCRP 박스는 항상 `main` 브랜치로 떨어졌는데 — `main`은 Alpine 마이그레이션 이전인 v1.3.1.1에서 멈춰 있는 브랜치입니다. 그 결과 xTCRP 설치본은 v1.4.x로 업데이트한 이후에도 새로고침할 때마다 1년 전 `functions.sh`를 조용히 다시 받아오고 있었습니다. `UPDATE_BRANCH`를 mshell/xTCRP 공통으로 실제 관리되는 유일한 브랜치인 `alpine-redpill`로 고정했습니다.

</details>

<details>
<summary><b>그 외 수정 사항 (클릭해서 펼치기)</b></summary>

<br>

- **저사양 스왑을 1GB에서 1.5GB로 상향.** `.pat` 복호화가 포함된 빌드 워크로드에서 기존 1GB 할당량의 67%를 넘게 쓰는 것이 실측 확인됐습니다.
- **메모리 정리가 빌드 성공 시에도 실행되도록 수정.** 이전에는 실패/클린업 경로에서만 실행돼서, 연속으로 성공한 빌드들에서 tmpfs/스왑 사용량이 계속 누적됐습니다.
- **redpill-load 다운로드 실패 원인을 진단할 수 있게 됨.** 원격 파일(`rpext-index.json` 등) 다운로드 실패 시 curl의 에러 출력이 통째로 버려지던 문제를 고쳐, 이제 HTTP 코드/DNS·연결·TLS 소요시간/curl 자체 에러메시지가 로그에 남습니다.
- **`tcrp-modules`/`tcrp-addons`/`rp-ext` 브랜치 참조 수정** — 존재하지도 않는 `master`에서 실제 브랜치인 `main`으로, 이 저장소와 `redpill-load` 양쪽 모두 수정했습니다. 기존 `master` 경로가 동작했던 건 GitHub의 비공식 레거시 브랜치 리다이렉트 덕분이었을 뿐입니다.
- **기본 터미널 색상 밝기 개선** (lxterminal 팔레트, "TCRP Extra Terminal" 창) — 기존 어두운 초록이 잘 안 보이는 문제를 해결했습니다.

</details>

## 참고

- 기존 v1.4.1.0 사용자는 직접 업데이트하지 않는 한 영향받지 않습니다.
