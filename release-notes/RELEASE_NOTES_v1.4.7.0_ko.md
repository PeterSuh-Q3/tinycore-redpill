# alpine-redpill v1.4.7.0

## BMI2 미지원 CPU용 all-modules PML

일부 구형 CPU에서는 기본 all-modules 커널·모듈 조합을 사용할 수 없고, custom-modules로 전환하면 선택한 DSM 대상에 필요한 모듈이 빠질 수 있습니다. 

이번 버전은 테스트 빌드에서 BMI2 미지원이 확인되면 all-modules (PML)를 선택하고, 검증된 대체 DSM 커널과 해당 대상용 detour 모듈팩을 함께 적용하는 경로를 마련합니다.
