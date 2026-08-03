# alpine-redpill v1.4.2.6

## 독립 로더 레코더

메인 메뉴에서도 사용하는 다이얼로그 기반 독립 로더 레코더 `burnloader.sh`를 추가했습니다.
UUID `6234-C863`를 가지면서 `alpine` 파티션이 없는 기존 TinyCore 로더 디스크에 Alpine
이미지를 기록할 수 있습니다.

해당 TinyCore 디스크를 덮어쓰기 전에 3번 파티션의 `user_config.json`을 백업하고, 기록 후
복원합니다. 이 파일이 없으면 설정 복원 없이 기록을 계속합니다.

## 대용량 이미지 메모리 요구 사항

5GB 이미지는 물리 메모리 8GB 이상이 필요합니다. 메모리가 부족하면 다운로드 전에 요구
사항을 안내하고 메뉴로 돌아갑니다.

## Alpine 전용 UEFI 부팅 경로

릴리스 이미지에 표준 이동식 매체 fallback 경로 `EFI/BOOT/BOOTX64.EFI`와 함께
`EFI/AlpineRedpill/grubx64.efi`를 추가했습니다. 기존 TinyCore 로더를 함께 사용하는
시스템에서는 이 전용 경로를 가리키는 `Alpine Redpill` UEFI NVRAM 부트 항목을 등록하고
펌웨어 부팅 순서의 최우선으로 두면, 공유 UUID `6234-C863`을 바꾸지 않고도 Alpine SSD를
명확하게 선택할 수 있습니다.

## NVMe 부팅 매체 지원

Alpine initramfs에 NVMe 호스트 드라이버 스택(`nvme`, `nvme-core`, `hwmon`)을 포함했습니다.
Alpine GRUB 엔트리는 부팅 매체 마운트 전에 이 모듈을 명시적으로 적재합니다. 이로써 NVMe
로더 디스크의 부팅 실패를 해결하면서 기존 USB 및 SATA SSD 부팅 경로는 유지합니다.
