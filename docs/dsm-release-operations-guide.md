# DSM 차기 버전 운영 가이드

이 문서는 DSM 신규 정식 버전 또는 update build가 공개됐을 때 MSHELL에서
지원 여부를 추가하고 검증하는 순서다. 새 버전을 발견했다고 자동 지원하지 않는다.
PAT 목록만 추가하면 메뉴에는 나타나지 않으며, exact target과 검증된 모듈 조합이
resolver catalog에 있어야 MSHELL이 빌드를 허용한다.

## 작업 전 원칙

- 현재 기준으로 작업하고 있는지 확인한다: `alpine-redpill`과 관련 저장소의
  branch/status/HEAD를 기록한다. 기존 사용자 변경은 보존한다.
- version, build number, smallfix, 모델별 PAT URL/MD5, platform, kernel.release,
  DSM kernel config/Module.symvers와 GPL source를 확인한다. 하나라도 모르면 그
  값은 추측하지 말고 해당 모델/조합을 `candidate`로 둔다.
- 커널 버전 문자열이 같아도 module ABI가 같다고 단정하지 않는다. module recipe나
  `_74_` 인덱스가 기존 버전을 가리키는 것만으로 새 DSM 호환성을 승인하지 않는다.
- `inherited-supported`는 현재 catalog에 있던 호환 범위의 이전 상태다. 새 release는
  검증 근거가 준비되기 전까지 `candidate`로 두고 resolver에서 빌드되지 않게 한다.
- Linux 기능 모듈을 새로 만들면 일치하는 target의 `.config`, `Module.symvers`,
  Synology GPL source로 빌드하고 provider closure까지 검증한다.

## 수정 파일 지도

| 변경 상황 | 수정할 파일/저장소 | 내용 |
|---|---|---|
| DSM build만 추가되고 모델·커널은 그대로 | `redpill-load/config/pats.json`, `pats_t.json` | 모델별 정확한 release key, PAT URL과 checksum. test track은 검증된 test PAT를 별도로 둔다. |
| PAT를 loader build에 사용할 수 있게 함 | `redpill-load/config/<platform>/<DSM-version>-<build>/config.json` | 새 DSM release의 실제 config와 patch-set 연결. 이전 config를 복사한 뒤 문자열만 바꾸는 것으로 끝내지 말고 PAT의 kernel/initrd/ramdisk에 맞는지 검토한다. |
| 새 모델 또는 플랫폼이 생김 | `tinycore-redpill/models.json`, `redpill-load/config/<platform>/`, `redpill-load/config/pats*.json` | 모델→플랫폼/커널 계열, 모델별 PAT 및 platform config. 모델 식별 문자열과 PAT 파일의 모델도 맞춰 확인한다. |
| kernel release 또는 ABI가 바뀜 | `mshell-modules` build source/workflow와 release asset; `tcrp-modules/{all-modules,custom-modules,anodrm-modules}/releases/`와 `rpext-index.json` | 새 kernel을 대상으로 필요한 pack을 빌드·검증하고 immutable asset URL/SHA-256 및 index key를 등록한다. 필요한 pack이 없으면 mode를 catalog에 넣지 않는다. |
| RedPill LKM ABI/hook에 변화가 있음 | `mshell-lkm` 생산 workflow와 `redpill-lkm` 배포 asset; `tinycore-redpill/functions.sh`, `functions_t.sh`의 소비 경로 | 정확한 커널 대상으로 재생산하고 hook/load를 확인한다. 두 functions 파일은 항상 동기화한다. |
| ramdisk·linuxrc·init 동작이 바뀜 | `redpill-load/config/_common/ramdisk/patch-sets.json`, 영향받는 patch 파일, 해당 release config의 `ramdisk_sets` | 새 PAT에 dry-run 및 적용 후 검증. 새 profile은 범위를 명시하고 기존 profile을 무조건 넓히지 않는다. |
| DSM runtime/package 설치 API가 바뀜 | 영향받는 `tcrp-addons` 및 `tcrp-modules/aeudev` recipe/installer, 필요 시 GPU·Manager/SPK 생산 저장소 | 관련 addon만 업데이트하고 실제 DSM에서 install/start/retry를 확인한다. loader support와 package support는 각각 승인한다. |
| 지원 target/mode 승인 결과를 등록 | `redpill-load/config/catalog/dsm-targets.v1.json` | 사람이 검토하는 원본 catalog. |
| resolver runtime snapshot 갱신 | `tinycore-redpill/config/dsm-targets.v1.json` | compiler로 원본에서 생성. 직접 편집하지 않는다. | 정확한 모델, release, channel, kernel, PAT/config reference, 허용 pack+IML/PML 조합, CPU flags, recipe reference를 추가한다. 검증 후에만 `verified`로 변경한다. |
| resolver의 데이터 형식/판정 자체를 바꿈 | `tools/dsm-target-resolver.jq`, `tools/dsm-target-resolver.sh`, `tools/dsm-resolver-bridge.sh`, compiler/schema 및 tests | 정상 버전 추가만으로 resolver 코드 수정은 필요하지 않다. 스키마/판정 규칙의 변경에 한해 수정한다. functions 변경이면 두 track을 같이 고친다. |
| 새 파일 또는 resolver dependency 변경 | `.github/workflows/alpine-make.my.sh.gz.yml`, `menu.sh`의 helper refresh/previous-release bundle 처리 | `my.sh.gz`, apkovl과 독립 updater/복원 경로에 같은 파일 세트를 넣는다. `my.sh.gz`는 추적 상태와 기존 URL을 유지한다. |

`config/dsm-targets.v1.json`은 현재 컴파일된 배포 catalog다. 사람이 검토하고 편집하는
원본은 `redpill-load/config/catalog/dsm-targets.v1.json`이다. 검토 복사본을
수정한 다음 compiler로 runtime snapshot을 재생성한다. 새 release를 추가할 때의 임시 review workflow는 다음과 같다.

```sh
cp ../redpill-load/config/catalog/dsm-targets.v1.json /tmp/dsm-targets-reviewed.json
# JSON의 정확한 target/mode 기록을 검토해 편집한다.
python3 tools/compile-dsm-targets.py \
  --source /tmp/dsm-targets-reviewed.json \
  --output config/dsm-targets.v1.json
```

변경 전 catalog와 diff를 확인하고, release/model/mode별 evidence를 함께 PR/change
review에 기록한다. Compiler의 `--import-legacy`는 초기 이관 도구다. 매 신규 release에
실행하면 안 된다. `schema_version`을 바꾸거나 새로운 required field를 도입하는 변경은
별도 migration과 이전 catalog reader 호환 검토가 필요하다.

## 순서대로 수행

### 1. 공식 release metadata를 확정한다

Synology 공식 배포 자료와 실제 PAT에서 version/build/smallfix, 지원 모델, 다운로드
URL, 파일 checksum을 확인한다. 각 모델별 PAT 키는 `X.Y.Z-BUILD-SMALLFIX` 형태로
기록하고, key의 모델·build가 PAT 파일 내부 식별과 맞는지 검사한다. test channel은
`pats_t.json`과 target의 `channel: "test"`에 분리한다. Stable 자료를 test로 복사하거나
반대로 승격해 채널 구분을 없애지 않는다.

기존 릴리스 목록에 아직 없는 버전은 redpill-load에서 임의 release 입력으로 수집할 수
있다. 예를 들어 실제 build 번호를 확인한 뒤
`python3 tools/update_pats_from_archive.py --release 7.4.2-BUILD SA6400 --dry-run`으로
먼저 모델별 공식 archive URL과 MD5를 검토한다. `BUILD`는 문서 예시 자리표시자이므로
실제 공식 build 번호로 바꾸고, `--dry-run` 결과가 맞을 때만 적용한다.

### 2. 플랫폼 config와 kernel 차이를 분류한다

모델이 속한 platform과 기존/신규 kernel.release를 확인한다. 해당 모델의 release
config 디렉터리를 추가하고, 실제 PAT의 zImage/initrd/ramdisk에서 patch 적용 조건을
검사한다. Patch profile을 재사용하는 경우에도 각 patch의 입력 파일과 변경 결과가
맞는지 검증한다. config는 있는데 PAT가 없거나 그 반대인 조합을 지원 처리하지 않는다.

### 3. 모듈·LKM·CPU mode 가용성을 확정한다

각 model/release에 사용할 `all-modules`, `custom-modules`, `anodrm-modules`와
적재 방식 `IML`, `PML` 조합을 개별 판단한다. `anodrm`도 일반 모듈 CPU 요구사항을
가질 수 있다. 필요한 provider/firmware 누락, symbol CRC 불일치, CPU feature 누락,
recipe SHA 부재가 있으면 그 조합은 제외한다. 같은 kernel.release라는 이유만으로
이전 DSM recipe를 자동 복사하지 않는다.

새 release가 기존에 등록된 kernel recipe를 재사용하더라도, 해당 release/config에
관한 compatibility 검토 evidence가 있어야 catalog target을 승인한다. Kernel ABI가
바뀌었다면 해당 modules/LKM 생산 저장소에서 새 asset을 만들고 `tcrp-modules` index 및
recipe를 갱신한다. Immutable release asset의 SHA-256을 검증한다.

원격 빌드는 빌더 CPU를 목적지 CPU로 간주하지 않는다. 목적지 DSM에서
`tools/capture-target-cpu.sh`를 실행해 결과 JSON을 얻고, loader의
`user_config.json`에 `.general.target_cpu`로 저장한다. 이 스크립트는 여러 CPU의
feature flag를 교집합 처리하므로 가장 제한적인 CPU를 기준으로 mode를 고른다.
스냅샷이 없거나 불완전하면 resolver는 CPU 조건이 없는 mode만 허용한다.

### 4. Catalog target을 추가한다

`config/dsm-targets.v1.json`에 **모델마다, 채널마다, full release마다 하나의 target**을
추가한다. 한 release가 여러 모델을 지원해도 model별 PAT/config/kernel은 따로 기록한다.
`tuple`은 `[major, minor, patch, build, smallfix]`이며 `release`는 이 숫자들의
정규형 `X.Y.Z-BUILD-SMALLFIX`다. `version`은 기존 CLI/PAT 설정과 연결할 release/build
표기, `legacy_version`은 platform config directory 호환값이다. 기존 7.2 alias처럼
숫자 버전과 directory 이름이 다르면 기존 경로 규칙을 확인해 필드를 분리한다.

각 `modes[]` entry의 `id`는 `module:method`여야 한다. `recipe_sha256`은 catalog의
`recipes` 객체에 있는 실제 recipe key를 참조해야 한다. `cpu_flags`는 검증된 추가 요구를
적는다. 대상 CPU feature 정보가 없으면 BMI2 같은 필수 조건을 통과한 것으로 보지 않는다.

초기 추가 상태는 `candidate`다. PAT/config consistency, module closure/hash, CPU/mode,
patch, 실제 부팅 증거를 확인하기 전에는 `verified`로 바꾸지 않는다. 현재 compiler가
schema/참조/해시 형식 오류를 거부한다.

### 5. 검증 및 빌드 테스트를 실행한다

```sh
bash -n functions.sh functions_t.sh menu.sh menu_m.sh tools/dsm-resolver-bridge.sh
sh -n tools/dsm-target-resolver.sh
python3 tools/compile-dsm-targets.py \
  --source /tmp/dsm-targets-reviewed.json \
  --output /tmp/dsm-targets-check.json
python3 -m unittest discover -s tests/dsm-resolver -p 'test_*.py' -v
```

컴파일 검증 뒤 생성 결과를 `config/dsm-targets.v1.json`에 반영하고 diff를 확인한다.
추가로 다음 항목을 release별로 테스트한다.

- 메뉴 목록의 numeric sort와 exact build 선택. `7.4.10`과 `7.4.2`처럼 문자열 순서가
  뒤집힐 수 있는 버전도 포함한다.
- target에 없는 build, 잘못된 platform/config, 미승인 mode, recipe hash 오류가 모두
  거부되는지 확인한다.
- 대상 CPU의 BMI2 유무/unknown 상태에서 선택 가능한 pack이 정확한지 확인한다.
- module import 및 declared provider closure, kernel symbol CRC, firmware 포함 여부를 확인한다.
- fresh install, 기존 DSM에서 update, boot/update path를 구분해 검증한다.
- 실기 DSM에서 부팅·스토리지·NIC·서비스·선택 addon을 확인한다. 테스트하지 않은 모델,
  mode, channel은 `verified`로 표시하지 않는다.

현재 개발 Mac에서 resolver unit/adapter 테스트는 동작하지만, ext-manager 실통합 테스트는
Linux GNU utilities가 필요하다. Linux CI 통과 전에는 통합 테스트를 완료했다고 기록하지
않는다. CI 외 실제 loader image나 DSM boot 검증도 별도 결과로 기록한다.

### 6. 배포 bundle과 추적 상태를 확인한다

Resolver 코드 변경이 없어도 catalog와 신규 PAT/config/recipe 파일이 각 소비 저장소의
선택 branch에 포함되어야 한다. `my.sh.gz` 압축 목록 및 apkovl 복사 목록, `menu.sh` 독립
helper refresh와 previous-release 복원 경로가 같은 파일 세트를 보유하는지 확인한다.
이 절차에서 실제 release 준비를 하게 되면 `tools/prepare_release.py`를 사용하고 양쪽
release notes를 사용자 관점에서 검토한다.

## 변경 규모 판단표

| 관찰 결과 | 코드 수정 범위 |
|---|---|
| 동일 모델/platform/kernel, 기존 module recipe와 patch가 새 PAT에서 검증됨 | PAT/config + exact catalog target. 검증 근거 기록. |
| DSM build만 달라지고 kernel은 같지만 config/patch 차이가 있음 | 위 항목 + 영향받은 redpill-load patch/config 변경 및 검증. |
| kernel.release가 달라짐 | PAT/config + target + 영향받는 modules/LKM 재빌드 및 `tcrp-modules` recipe/index. 필요한 경우 Friend의 kernel 선택 경로도 별도 수정. |
| 모델/platform이 신규 | 모델/platform 데이터, PAT, platform config, modules/LKM build target과 recipes, target catalog, 메뉴/스토리지 특성 검증. |
| DSM 서비스나 패키징 API만 바뀜 | 영향받은 addon/SPK 저장소와 package compatibility 기록. Kernel mode 지원은 별도로 유지/승인. |
| 새 자료나 호환 검증이 아직 없음 | 관련 target/mode를 catalog에 두지 않거나 `candidate`로 두어 빌드를 막는다. 근접한 이전 버전으로 자동 대체하지 않는다. |

지원 상태를 업데이트한 뒤에도 commit/push/release/workflow dispatch는 별도 운영 지시와
릴리스 절차에 따라 수행한다. 신규 DSM 등록만으로 published release가 만들어지지는 않는다.


## 커널 5 플랫폼 정책 갱신

검토 원본 `redpill-load/config/catalog/dsm-targets.v1.json`의 `platform_policy`에서
`kernel5_platforms`와 별도로 검토한 `dt_platforms`를 수정한다. 제외 대상인
`epyc7003ntb`는 추가하지 않는다. 대상별 정확한 커널과 모듈 recipe도 등록해야 한다.
컴파일 후 `python3 tools/sync-platform-policy.py`로 redpill-load와 Friend의
오프라인 정책을 생성하고 `--check`로 일치 여부를 확인한다. 각 저장소의
인덱스와 실제 제공 파일을 검증한 후 관련 저장소를 함께 배포한다. Friend는
새 이미지가 필요하며, 구버전은 새 정책을 사용하지 않는다.
