# DSM 7.4.2 가정: MSHELL 저장소 연계 및 동적 버전 처리 설계

작성: 2026-10-28. 설계 제안이며 구현·배포 완료를 의미하지 않는다.
7.4.2의 실제 출시 여부, 빌드 번호, 지원 모델, 커널 및 PAT 형식은 확인하지 않았다.
아래 내용은 로컬 소스에 근거한다. 새 빌드 번호는 B로 표기한다.

## 1. 조사 범위와 근거

로컬 HEAD: tinycore-redpill 0cf7a9da(alpine-redpill), redpill-load 73ca67b,
tcrpfriend 298b317, tcrp-modules 13761f2, tcrp-addons 5bf5a1a,
mshell-modules 9ad4c64a4, mshell-lkm 1a18221.
redpill-load/tcrpfriend/tcrp-modules는 로컬 origin 추적 정보보다 뒤처져 있다.
원격 fetch 없이 현재 작업 트리를 읽었으므로 최신 원격 전체 감사는 아니다.
tcrp-modules의 epyc7002-7.4 recipe 등 기존 미커밋 변경은 그대로 보존했다.
GPU/SPK 생산 저장소는 연계 대상으로 식별했으며 내부 전체 감사는 후속 범위다.

현재 흐름:

```text
redpill-load/config/pats*.json → MSHELL 메뉴 → getvarsmshell()
 → 모델/버전/커널 선택 → redpill-load/config/<platform>/<release>/config.json
 → ramdisk patch sets + addon index/recipe + redpill LKM + module packs
 → loader build → tcrpfriend의 업데이트 감지/재패치 → DSM 부팅
 → aeudev SPK 설치 및 각 addon 동작
```

현재 데이터는 단일 기준이 아니다. PAT 목록은 모델별 전체 버전, models.json은
플랫폼별 major.minor, addon은 platform_74_kernel, 모듈 파일은 platform-7.4-kernel,
메뉴 일부는 7.4.1 상한, 빌드 진입은 빌드 번호 목록을 각각 사용한다.

## 2. 저장소별 수정·검증 대상

| 저장소/소유 범위 | 직접 확인한 대상 | 7.4.2 대응 | 동적 처리 방향 |
|---|---|---|---|
| tinycore-redpill: 사용자 선택/빌드 조율 | functions.sh:2880 getvarsmshell(), 2920대 revision 분기; functions_t.sh 쌍 | 새 B를 모르면 거부(exit 0). 플랫폼별 KVER 보정도 확인 | 정확한 release record 조회, 미지원 시 nonzero; 두 helper 동기화 |
| tinycore-redpill: CPU/모드 제한 | menu_m.sh:61–62, enforceBmi2VersionCap(), selectversion():827 | custom-modules 7.4.1 상한 때문에 비-BMI2 K5 사용자는 제외/이전 버전 선택 발생 | CPU 요구사항과 검증된 모듈 가용성의 교집합으로 선택 |
| tinycore-redpill: 플랫폼 데이터 | models.json productvers, functions.sh platforms/kver5platforms | 7.4.2라서 무조건 수정하지 않음. 모델·커널 변화 시 수정 | 플랫폼 특성과 릴리스별 커널/ABI 분리 |
| tinycore-redpill: PAT 경로 | functions.sh:9926 이후 URL/sum startswith + 첫 항목, 캐시 SYNOMODEL=model_build | PAT URL/hash 및 config 일치 확인 | full release ID 정확 일치, checksum 기반 캐시, 기존 캐시도 재검증 |
| redpill-load: PAT/config | config/pats.json, pats_t.json, <platform>/7.4.1-90080/config.json | 제공되는 모델만 새 release 추가, test-track 차이 보존 | 하나의 manifest에서 두 트랙과 per-platform config 생성 |
| redpill-load: 패치 엔진 | config/_common/ramdisk/patch-sets.json, build-loader.sh:542 | linuxrc/init.post/root-password/global 패치를 새 rd.gz에서 검증 | 버전 문자열 치환 대신 patch profile과 입력/출력 조건 사용 |
| redpill-load: 생성 도구 | config/replicate-config.sh, get_md5_json_macos.sh | platform73 목록 복사 및 전역 sed는 새 플랫폼/패치 범위에 부적합 | 모델별 수집, JSON 구조 단위 생성, preview diff |
| redpill-load: addon 해석 | ext-manager.sh 및 ext-manager_t.sh, bundled-exts*.json | 기존 _74_ 키는 계속 선택될 수 있음; build별 검증이 추가로 필요 | manifest의 정확한 recipe/asset hash를 resolver에 전달 |
| tcrp-modules: 배포 계약 | all/custom/anodrm-modules/rpext-index.json 및 releases/*.json; aeudev | 커널/ABI 유지가 검증되면 기존 asset 재사용; 변화 시 별도 자산 | legacy index 유지 + build/ABI 단위 immutable recipe |
| mshell-modules: 모듈 생산 | src/full.sh, .github/workflows/main-tar-modules.yml, pack-drm-overwrite.yml, copy-nodrm-modules.yml | toolchain/config/symvers 비교, 일반/DRM/custom pack 및 의존성 검증 | 승인된 target matrix 생성; 7.3→7.4 alias 등은 명시적 호환 관계로 관리 |
| mshell-lkm / redpill-lkm | mshell-lkm main_all_kver.yml; functions.sh:8210 getredpillko()는 redpill-lkm 배포 소비 | 생산 workflow와 배포 저장소 연결 확인; LKM hook 및 ABI 검증 | source commit/toolchain/target/asset hash 기록. 두 저장소 역할 혼동 금지 |
| tcrpfriend: 업데이트 후 재부팅 | buildroot/board/tcrpfriend/rootfs-overlay/root/boot.sh:629, 760대, 821, 2860대 | 중복 KVER 추론, LKM filename fallback, 모듈 이름, 업데이트 재패치 검증 | MSHELL과 같은 lock/target 해석 규칙; 부팅 시 latest 자동 조합 금지 |
| tcrp-addons: DSM 의존 동작 | patch-md0/src/patch.sh, localrss/src/pats.json 및 install.sh, nvidiadriver/src/nvidia-spk-index.json | 새 스크립트 구조, localrss의 version-build-0 lookup, SPK 범위 해석 점검 | capability/정확한 release ID, catalog 파생 PAT, typed package constraints |
| GPU/패키지 생산 저장소 | quad-gpu-backports, redpill-dual-drm-backports, syno_nvidia_driver, syno-amdgpu-driver; mshell-manager/SynoSmartInfo 등 | DRM provider/consumer ABI와 사용자 공간·설치 API 변화가 있을 때 수정/재빌드 | kernel pack과 userspace SPK 호환성 별도 기록; 출처 확인 후 재사용 |

7.4.2가 나와도 위 모든 저장소를 반드시 수정하는 것은 아니다.
필수는 새 release 등록과 검증 결과 연결이다. 코드/바이너리 수정은 실제 차이에 따른다.

## 3. 특히 먼저 제거할 하드코딩

1. **revision → 기본 KVER 분기**: 새 B는 기존 커널이어도 거부된다.
   models.json만 조회하는 교체도 충분하지 않다. 같은 7.4에서 커널이 바뀔 수 있으므로
   model/platform + full release에 연결된 kernel 정보를 사용한다.
2. **custom-modules 최대 7.4.1**: 7.4.2로 숫자만 올리지 않는다.
   해당 CPU, 플랫폼, build, 선택 mode에 맞는 검증된 custom pack이 실제 존재해야 한다.
   메뉴에 남은 “7.4 GPL 미공개” 문구도 실제 실패 이유로 교체한다.
3. **문자열 버전 정렬/접두사 매칭**: menu_m.sh는 keys/reverse로 최신순을 만든다.
   7.4.10/7.4.2, 7.10/7.9, build/smallfix를 숫자 tuple로 비교하고 중복을 제거한다.
   12개 표시 제한은 정렬·필터링 후 적용한다. URL과 checksum은 동일 record에서 가져온다.
4. **KVER와 asset 이름 혼용**: models.json의 일부 K5 값은 7.4-5.10.55이다.
   kernel.release, ABI 식별자, legacy filename을 별도 필드로 분리한다.
5. **7.4* wildcard**: tools/install-amdgpu-addon.sh:61 및
   tcrp-modules/aeudev/releases/postboot-spk-install.sh:62는 7.40도 매칭할 수 있다.
   major/minor 파싱과 플랫폼·ABI·패키지 요구조건 검증으로 바꾼다.
   NVIDIA dsm_max=7.4도 major.minor 계열 상한인지 exact version인지 스키마에 명시한다.
6. **두 자리 버전 결합/복원**: ext-manager.sh:990의 ${2:0:1}.${2:1}는
   한 자리 major 전제다. legacy key 생성은 호환 adapter로 한정하고 새 내부 표현은
   major/minor 정수 또는 구분된 문자열을 사용한다.
7. **latest/branch raw 참조**: functions.sh의 LKM/Friend/aeudev 조회 및 recipe가
   다른 시점의 데이터를 섞을 수 있다. 후보 검색 후 빌드 시작 전 전체 closure를 고정한다.
8. **버전이 들어간 patch-set 이름**: 7.4.1이라는 이름 자체가 실행 상한인 것은 아니다.
   기존 profile을 새 build에 연결하려면 실제 입력에 patch가 적용되는지 확인해야 한다.
   단순 전역 치환으로 과거 지원 범위와 경로까지 바꾸면 안 된다.

## 4. 권장 데이터 설계

초기에는 새 저장소를 만들지 않고 redpill-load/config/catalog/에 표준 catalog를 둔다.
PAT/config를 소유한 저장소가 release 기준을 관리하고 생산 저장소들은 검증 manifest를 제공한다.
MSHELL 및 Friend는 배포 번들에 포함된 catalog/lock을 소비한다.

분리할 데이터:

- releases: version major/minor/patch, build, smallfix, channel, full-PAT/update-PAT 구분,
  모델별 PAT URL/size/MD5(기존 호환)/SHA-256, 실제 VERSION 검증 결과.
- targets: model, platform, arch, kernel.release, kernel image hash, config/symvers hashes,
  toolchain image digest, source commit, CPU flags, DT/부팅 특성.
- compatibility: exact target와 patch profile/LKM/module pack/addon/SPK 조합,
  상태(discovered → staged → static-verified → pilot-verified → supported), 시험 근거.
- artifacts: repository commit 또는 immutable release URL, bytes, SHA-256,
  dependency closure, 제공 module/symbol/firmware 목록.
- channels: stable/test가 선택할 catalog snapshot. pats_t.json의 의도된 override를 보존한다.

개념 예시(실행 가능한 7.4.2 설정이 아니며 null은 미확인):

```json
{
  "schema_version": 1,
  "release": {"version": "7.4.2", "build": null, "smallfix": 0},
  "model": "SA6400",
  "platform": "epyc7002",
  "status": "discovered",
  "pat": null,
  "kernel": {"release": null, "abi_id": null},
  "patch_profile": null,
  "artifacts": {},
  "validation": {"static": false, "clean_boot": false, "upgrade": false}
}
```

null/미검증 항목은 stable 메뉴나 loader build를 허용하지 않는다.
ABI fingerprint는 동일성을 비교하는 자료이지 runtime 안전성 증명은 아니다.
같은 uname/vermagic라도 CRC, kernel config, backport 구조체/API가 다를 수 있다.
재사용은 명시적인 exact-build 호환 레코드로 승인하고 가장 가까운 버전으로 fallback하지 않는다.

## 5. 스크립트와 저장소 간 계약

개발/CI 측 Python 도구와 loader/Friend 측 sh+jq reader를 분리한다.
부팅 환경에 Python이나 온라인 API 호출을 필수화하지 않는다.

부분 구현:

- `redpill-load/tools/update_pats_from_archive.py`는 repeatable `--release
  X.Y[.Z]-BUILD`를 받아 기존 기본 목록에 없는 release도 명시적으로 조회하고,
  exact model URL 및 공식 MD5 sidecar를 merge한다. `--dry-run`으로 검토할 수 있다.
  PAT 내부 VERSION, SHA-256, kernel/config 분석 및 config 생성은 아직 하지 않는다.

아직 구현하지 않은 제안 도구:

- collect-dsm-release: 명시된 후보 릴리스의 모델별 공식 자료/PAT를 수집하고
  실제 VERSION/GRUB_VER/rd.gz/kernel을 분석. 자동 발견 결과는 discovered 상태만 생성.
  공식 목록 수집 adapter 실패 시 수동 URL 입력을 지원하고 이전 정상 snapshot을 유지.
- validate-dsm-target: metadata schema, hash, 모델/platform 일치, patch dry-run와
  적용 후 의미 검사, provider closure, symbol CRC, LKM/CPU/패키지 조건을 검증.
- generate-legacy-config: pats.json/pats_t.json, per-platform config, 필요한 index를 생성.
  --check/--dry-run 지원, 기존 파일 무조건 복사/덮어쓰기 금지, 생성 결과 diff 재현성 검사.
- resolve-dsm-target: exact model/release/mode/CPU/channel로 조회하고
  target.lock.json 생성. 메뉴·CLI·Friend에서 동일한 판정 및 reason code 사용.
- audit-dsm-hardcodes: 버전 분기/중복 플랫폼 목록을 점검하되 역사적 changelog,
  기존 fixture, 검증된 과거 compatibility rule은 허용 목록으로 분리.

lock에는 catalog schema/hash, 모델/full release, kernel ABI, 모든 artifact의 URL/hash,
patch profile, 모듈 mode, 생산 source revision을 포함한다. 필수 자산을 모두 검증한 뒤
임시 디렉터리에서 빌드를 마치고 loader 변경을 반영한다. 불완전한 다운로드로 현재
부팅 세트를 교체하지 않는다. lock과 진단 결과는 loader backup에 함께 보관한다.

오프라인은 캐시된 supported snapshot과 완전한 artifact closure가 있을 때만 진행한다.
미지원 DSM 업데이트를 Friend가 감지하면 임의 이전 모듈을 고르는 대신 명확한 복구 경로를
안내한다. DSM 시스템 자체의 downgrade가 가능하다고 가정하지 않는다.

여러 저장소 배포는 원자적이지 않으므로 producer artifact 배포 → hash 검증 →
consumer catalog snapshot 생성 → 통합 검증 → stable pointer 승격 순서를 사용한다.
새 CLI/부팅 스크립트가 필요한 snapshot에는 최소 reader 버전을 명시한다.
기존 my.sh.gz raw URL과 추적 상태를 유지하고 legacy JSON은 이행 기간 계속 제공한다.

## 6. 자동화 범위의 경계

| 처리 | 자동화 수준 | 승인/검증 조건 |
|---|---|---|
| 후보 릴리스 발견, PAT 다운로드/해시, VERSION 추출 | 높음 | 후보 등록이며 지원 선언 아님 |
| 메뉴 목록/버전 파싱/정렬, config와 CI matrix 생성 | 높음 | schema와 referential integrity 통과 |
| addon index/legacy key 생성 | 높음 | target별 명시된 recipe만 연결 |
| 기존 patch profile 재사용 후보 비교 | 부분 | dry-run + 적용 결과 검사 + 실제 boot |
| 기존 LKM/DRM/모듈 재사용 | 부분 | 정확한 target ABI/의존성 검증 + clean boot |
| 새 kernel/ABI, LKM hook, DRM backport 수정 | 낮음 | 일치하는 GPL/config/symvers로 개발·시험 |
| 기존 설치 DSM upgrade/파티션 요구 변화 | 부분 | fresh install과 별도 upgrade 실기 검증 |

## 7. 단계별 실행 계획과 완료 기준

P0 — 현재 버전의 동작을 데이터로 옮긴다.
- 기존 지원 모델/build/CPU/mode 결과를 fixture로 고정하고 catalog schema/resolver를 작성.
- revision whitelist와 BMI2 상한을 resolver로 교체하고 functions 쌍을 동기화.
- 과거 릴리스 선택 결과가 같고 미지원 입력이 nonzero로 거부되면 완료.

P1 — redpill-load의 config/PAT/patch 생성을 정리한다.
- 기존 patch-set을 profile로 유지하며 release mapping만 데이터화.
- 모델별 URL/hash/실제 VERSION 교차 검증, numeric sort/exact lookup 도입.
- stable/test 생성 결과에 의도하지 않은 차이가 없고 재생성 결과가 동일하면 완료.

P2 — module/LKM/addon 생산·배포 정보를 연결한다.
- mshell-modules/mshell-lkm/GPU 생산물 manifest와 tcrp-modules recipe를 연결.
- 필수 provider 누락, 다른 ABI 섞임, CPU feature 불충족을 build 전에 거부.
- artifact별 hash 및 빌드 출처와 dependency closure를 추적할 수 있으면 완료.

P3 — Friend 업데이트 경로와 오프라인 일관성을 맞춘다.
- 중복 KVER 판정 제거, lock reader 및 이전 버전 reader 호환 도입.
- 다운로드 중단/manifest 불일치/캐시 누락에서 현재 부팅 파일 보존을 확인.

P4 — 실제 7.4.2가 확보되면 후보를 검증한다.
- B와 모델 목록을 확정하고 K3/K4/K5 및 특수 플랫폼별 차이를 분석.
- ABI/patch 유지: 데이터 등록 및 호환 승인 중심. 변경: 해당 생산 저장소만 수정/재빌드.
- stable 승격은 검증한 모델·CPU·mode 조합으로 제한. 일부 성공을 전체 지원으로 확대하지 않음.

## 8. 검증 매트릭스

정적: 7.4.2/7.4.10/7.10.0 및 smallfix, 잘못된 버전, 중복 PAT, checksum 오류,
없는 model/config/recipe, 변한 ABI, 누락 provider/firmware, CPU 미충족, offline cache 누락.
7.4→7.40 wildcard 회귀도 포함한다.

통합: clean fresh install / 7.4.1→후보 upgrade / 기존 DSM 감지 / Friend 자동 재패치,
USB/SATA/block, UEFI/legacy(지원 조합), all/custom/anodrm, BMI2 유무,
K3/K4/K5 대표 및 코드 경로가 다른 플랫폼. 전체 Cartesian product 대신 공유 경로를 묶되
검증하지 않은 조합은 supported로 표시하지 않는다.

실기: 부팅 성공, rootfs/md0 요구사항, 스토리지 열거, NIC, 모듈 import/provider,
DSM 서비스 시작, SPK 설치/재시도, GPU 선택 조합의 KMS와 userspace를 분리 검증.
static import 검사가 성공해도 DRM 구조체 ABI나 런타임 안정성을 보증하지 않는다.

현재 수행한 것은 로컬 코드/데이터 조사와 설계 문서 작성이다. PAT 다운로드,
공식 릴리스 조회, 빌드/워크플로우 실행, 장비 접속, 커밋/푸시/배포는 하지 않았다.
