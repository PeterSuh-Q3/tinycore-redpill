# alpine-redpill v1.4.4.2

## DVA7400 플랫폼 지원

- 지원 모델 목록과 모델 추천 메뉴에 DVA7400을 추가했습니다.
- DVA7400을 Denverton 커널 4.4가 아닌 V1000NK 플랫폼과 커널 5.10 계열로 올바르게 매핑했습니다.
- CPU: AMD Ryzen 1780B.
- AI 가속: NVIDIA RTX 2000 Ada 또는 RTX PRO 2000 Blackwell급 외장 그래픽카드.
- 성능: 최대 100대 카메라와 실시간 AI 분석 작업 최대 40개.
- 용도: 얼굴·번호판 인식, 사람·차량 속성 또는 행동 분석, 침입·배회 감지, 자연어 기반 영상 검색.
- 정품 NVIDIA 런타임 라이브러리를 설치하면, 참고 시스템에서 확인된 것처럼 NVIDIA 페이지에 NVIDIA-SMI 580.126.09 및 CUDA 13.0이 표시될 수 있습니다.

![DVA7400 NVIDIA 런타임 상태](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/assets/DVA7400-nvidia-smi.png)

## 로더 파티션 별칭 안정성

- 안정 경로인 `/mnt/tcrp` 로더 파티션 별칭을 반복해서 안전하게 갱신하도록 개선했습니다.
- 기존 `/mnt/tcrp` 링크를 따라 FAT 로더 파티션 내부에 링크를 생성하지 않고, 별칭 링크 자체를 교체하도록 수정했습니다.
- 별칭 생성 뒤 대상 경로를 검증하고, 유지에 실패하면 호출부에도 실패를 전달하도록 보완했습니다.

## 일관성

- V1000NK 플랫폼 이력 정정을 포함해 운영용과 테스트용 functions 파일을 동기화 상태로 유지했습니다.
