# alpine-redpill v1.4.3.1

## 📋 tcrpfriend v0.1.4r 동반 릴리즈

이번 릴리즈는 테스트 트랙에 있던 `/home/tc/user_config.json` 심볼릭 링크 기능을 안정 트랙으로 승격합니다. 단독으로도 동작하지만, 이후 xTCRP(FRIEND)로 부팅했을 때 아래에 설명한 권한 문제를 피하려면 [tcrpfriend v0.1.4r](https://github.com/PeterSuh-Q3/tcrpfriend/releases/tag/v0.1.4r)와 함께 사용해야 합니다.

## 🔗 `/home/tc/user_config.json`이 이제 진짜 심볼릭 링크입니다

- 🗂️ **별도로 동기화되던 두 파일이 하나로**: 모든 메뉴/빌드 로직이 읽고 쓰는 RAM 작업 사본 `/home/tc/user_config.json`과, 실제 영속 데이터인 파티션 사본 `/mnt/<disk>3/user_config.json`을 여기저기 흩어진 호출부에서 수동으로 맞춰줘야 했습니다 — 한 곳이라도 빠지면 두 파일이 어긋납니다. 이제 `/home/tc/user_config.json`은 파티션 사본을 가리키는 심볼릭 링크라, 파일은 늘 하나뿐입니다.
- 🎯 **디스크 열거 순서 변경에도 안전한 고정 `/mnt/tcrp` 별칭**: 심볼릭 링크가 가리키는 곳은 `/mnt/tcrp/user_config.json`이라는 고정 별칭이며, `ensure_loader_partition_mounted()`가 호출될 때마다 이 별칭이 현재 로더 파티션(`/mnt/<disk>3`)을 가리키도록 유지합니다 — 그래서 디스크명이 바뀌어도(예: 하드웨어 변경 후 `sda` → `sdb`) 깨진 링크나 엉뚱한 디스크를 가리키는 문제가 없습니다. `tcrpfriend`의 `boot.sh`가 이전부터 써온 고정 마운트 경로 `/mnt/tcrp`와 동일한 방식입니다.
- ✍️ **쓰기 작업이 심볼릭 링크를 유지**: `writeConfigKey()`/`sync_usb_line()`이 이전에는 설정 파일을 `mv`로 갱신했는데, 목적지가 심볼릭 링크일 때 `mv`는 링크를 통해 쓰지 않고 링크 자체를 일반 파일로 바꿔치기합니다. 설정을 저장할 때마다 조용히 심볼릭 링크가 끊어지고 있었던 것입니다. 이제 둘 다 `cp`(심볼릭 링크를 따라가 타깃 내용만 갱신)를 사용합니다.
- 🧹 **`general.usb_line`에 고아 항목이 더 이상 쌓이지 않습니다**: `sync_usb_line()`은 저장된 `usb_line` 문자열 안의 `extra_cmdline` 키(`sn`, `mac1`~`mac8`, `vid`, `pid`, `netif_num`)를 추가·갱신만 할 뿐 절대 제거하지 않았습니다. `extra_cmdline`에서 키가 삭제돼도(예: NIC 개수 자동 감지로 2번째 NIC이 사라지며 `mac2` 삭제) 처음부터 다시 조합하는 로직이 없어 옛 `mac2=...` 조각이 `usb_line`에 영구히 남았습니다. 두 단계로 수정했습니다: `DeleteConfigKey()`가 삭제 즉시 대응하는 `usb_line` 항목을 함께 정리하고, 재빌드 시점의 병합 단계인 `preserve_usb_line_options()`도 독립적으로 이 관리 키들 중 현재 `.extra_cmdline`에 없는 것은 버려서, 이 수정 이전에 이미 고아가 됐거나 다른 경로로 생긴 값도 다음 재빌드에서 자가 치유됩니다.

## ⚠️ 짝이 맞는 `boot.sh`가 필요합니다

`/mnt/tcrp`가 안정적으로 tc-writable한 별칭이 되려면 로더 파티션 마운트 자체가 tc-writable해야 합니다. `tcrpfriend`의 `boot.sh`는 v0.1.4r 이전에는 이 파티션을 `uid=/gid=` 옵션 없이 마운트해 root 소유로 남겨뒀고, 그 결과 xTCRP/FRIEND 환경에서 이 심볼릭 링크를 통한 쓰기가 `Permission denied`로 실패했습니다. v0.1.4r 이상을 사용하십시오.

위 내용 모두 실기에서 `usb_line` 고아 증상을 직접 재현하고 수정까지 검증했습니다.
