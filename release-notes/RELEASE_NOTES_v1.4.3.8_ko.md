# alpine-redpill v1.4.3.8

## 고정 IP와 DHCP 혼용 환경의 네트워크 안정성 개선

v1.4.3.7에서 도입한 멀티 NIC 고정 IP 기능을 실제 혼용 네트워크 환경에 맞게 보완했습니다.

- 고정 IP를 적용할 때 해당 NIC의 DHCP 클라이언트만 중지하고, 다른 NIC은 DHCP를 계속 유지합니다.
- DHCP가 선택된 Primary 고정 게이트웨이와 DNS를 덮어쓰지 못하도록 했으며, NIC별 source routing으로 DHCP NIC의 응답 경로도 유지합니다.
- 고정 IP 항목을 삭제하면 기존 주소가 남지 않고 해당 NIC이 즉시 DHCP로 복귀합니다.
- 저장된 멀티 NIC 설정을 현재 배열 기반 구성 형식으로 부팅 시 올바르게 적용합니다.

## AMD GPU 감지 및 패키지 내장 개선

- AMD GPU 감지 범위를 PCI display class `0300`, `0302`, `0380`으로 확대했습니다. 일반 VGA로 표시되지 않는 헤드리스 및 서버 GPU도 감지합니다.
- 지원되는 AMD display 장치가 감지되면 필요한 AMD 펌웨어를 유지해, 런타임만 내장되고 커널 드라이버용 펌웨어가 빠지는 문제를 방지합니다.
- AMDGPU Runtime과 `amdgpu_top`을 독립된 패키지로 각각 내장하고 검증합니다.

## Intel GPU Top 자동 포함

이제 모든 로더 빌드에서 `syno-intel-gpu-top`을 `/addons`에 내장하고 DSM 자동 설치 대상으로 등록합니다. Intel GPU 감지 결과나 로더 커널 계열에 따라 제외하지 않습니다.

![Intel GPU Top](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/assets/07-intel-GPU.png)
