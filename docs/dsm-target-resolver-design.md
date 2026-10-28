# 공통 DSM target resolver 상세 설계

2026-10-28 / 제안 상태. 상위 설계: dsm-next-release-dynamic-design.md.
범위: revision 허용 목록과 custom-modules 7.4.1 상한의 대체.
실제 7.4.2 metadata/호환성은 미확인. 이 문서의 인터페이스·파일은 구현 제안이다.

## 1. 결정 사항

- POSIX sh wrapper + jq의 순수 조회기로 구현한다. Python은 catalog 생성/검증에만 사용.
- 버전 문자열로 kernel이나 CPU 요구를 추론하지 않는다.
- 정확한 model + release + channel에서 kernel과 허용된 module/method 조합을 찾는다.
- metadata 조회(identity)와 선택 검증(selection), 파일 검증(artifact preflight)을 분리한다.
  커널 표시만 필요한 호출에서 CPU/다운로드 실패까지 섞지 않는다.
- resolver는 네트워크, user_config 쓰기, sudo, source/eval, partition 변경을 하지 않는다.
- 지원 여부는 데이터화하지만 새 build 등록에는 검증 근거가 필요하다.
  PAT나 _74_ recipe가 존재한다는 사실만으로 지원 승인하지 않는다.
- 기존 알려진 조합은 이행 기준으로 보존한다. 기존 잘못된 fallback/우회는 보존하지 않는다.

## 2. 확인한 호출부 문제

| 현재 위치 | 관찰 | 교체 |
|---|---|---|
| functions.sh/functions_t.sh getvarsmshell():2873 이후 | revision 목록 뒤 플랫폼별 KVER 덮어쓰기; 알 수 없는 revision에 exit 0 | identity 결과를 성공 시에만 기존 전역 변수에 반영 |
| menu_m.sh resolveLiveKver():625 | 전체 getvarsmshell 호출 후 KVER/platform 출력; 실패 상태를 명시적으로 다루지 않음 | identity 직접 조회 + 오류 전파 |
| menu_m.sh:61–62 및 78 | BMI2 기준 버전/7.4.1 상한, 저장 버전 강제 하향 | mode별 CPU 조건 평가; 기존 선택 부적합 상태 표시 |
| checkAndResetModuleName():633 | 경우에 따라 비-BMI2 CPU를 all-modules로 fallback | 허용 mode가 없으면 빌드 불가. 부적합 mode로 fallback 금지 |
| selectldrmode():706 | kernel/version 범위로 all/custom/anodrm 메뉴 구성 | allowed_modes만 렌더링 |
| selectversion():827 | PAT keys 문자열 역순; 자르기 후 CPU 필터 | 선택 가능한 release를 숫자 정렬한 뒤 표시 개수 제한 |
| modelMenu():977–998 | cap 및 module 보정 후 PAT keys/max를 다시 저장 | 새 모델의 완성된 selection을 구성한 뒤 한 번 저장 |
| functions.sh my():9590, 9723 이후 | identity 호출 후 module 설정 읽기/기본값 저장이 뒤따름 | 입력/옵션/설정을 먼저 읽고 selection validate 후 변경 시작 |
| functions.sh inject_loader():8951 | getvarsmshell 뒤 오류 확인 없이 계속할 수 있음 | 실패 시 즉시 반환, 디스크 변경 진행 금지 |

anodrm의 이름은 CPU 호환성 근거가 아니다. 확인한 epyc7002-7.4 recipe는 일반 모듈
archive를 참조한다. DRM 제외 여부와 일반 모듈의 BMI2 요구 여부를 독립 필드로 관리한다.
현재 recipe의 CPU 요구가 무엇인지는 추가 artifact 검증이 필요하다.

## 3. 파일 배치와 소유권

초기 실행 파일은 tinycore-redpill에 둔다.

```text
tools/dsm-target-resolver.sh        # CLI, 입출력/exit contract
tools/dsm-target-resolver.jq        # 공통 판정, 정렬, reason 생성
config/dsm-targets.v1.json          # 배포용 compiled snapshot
schemas/dsm-targets.v1.schema.json  # CI schema
tools/compile-dsm-targets.py        # 개발/CI에서만 사용
tests/dsm-resolver/                # fixtures 및 의미 있는 회귀 테스트
```

원본 catalog는 상위 설계대로 redpill-load/config/catalog/에 두고 compiled snapshot만
MSHELL 번들에 포함한다. snapshot에 source commit/hash와 reader 최소 버전을 기록한다.
처음부터 두 저장소에 수동 편집 원본을 만들지 않는다.
P0에는 전체 addon/SPK lock 도입까지 요구하지 않되, 선택한 module recipe 식별자와
hash를 고정하고 실제 fetch가 해당 결과를 소비하도록 연결해야 한다.

## 4. 데이터 계약

정규 release key: major.minor.patch-build-smallfix, 각 숫자를 별도 필드로도 저장.
예: 7.4.1-90080-0. major.minor 누락 patch는 0으로 정규화한다.
legacy version 별칭(7.2/7.2.0 등)과 config directory는 별도 명시 필드다.
smallfix 생략은 0을 뜻하며 최신 update를 임의 선택하지 않는다.
실제 파일 경로/버전 alias는 기존 config에서 수집해 검증하고 추측하지 않는다.

compiled snapshot 필수 개체:

| 개체 | 필드/규칙 |
|---|---|
| header | schema_version, catalog_id, source revisions, min_reader_version |
| models | model → platform, legacy model slug; 중복 platform 매핑 거부 |
| releases | canonical ID, 숫자 tuple, channel, PAT 종류 |
| targets | model + release + channel의 정확한 키; kernel.release, legacy_kver, config_ref, PAT ref, status |
| modes | target별 module_name + load_method + recipe_ref + compatibility_ref + requirements |
| recipes | immutable ref/hash 및 asset 목록. mutable URL도 hash 없이 허용하지 않음 |
| compatibility | 해당 exact target 승인, evidence ref, accepted channels, CPU requirement 근거 |

mode ID는 all-modules:IML, all-modules:PML, custom-modules:PML,
anodrm-modules:IML처럼 pack과 method를 결합한다. LDRMODE/Friend/Jot와 혼동하지 않는다.
기존 boot/bus/devmod 제한은 이번 단계에서도 별도 preflight가 계속 적용된다.
resolver의 selection 허용은 전체 장치 부팅 가능성 보장이 아니다.

CPU 요구는 target(kernel/LKM 포함)와 mode의 요구를 합친다.
requirements.cpu_flags=[bmi2]는 해당 feature가 confirmed-present일 때만 통과한다.
requirements.cpu_flags=[]는 알려진 추가 요구가 없다는 명시적 선언이다.
요구 metadata 누락은 빈 배열로 처리하지 않고 unknown으로 거부한다.
범용 platform/kernel family만 보고 mode의 지원을 확장하지 않는다.

상태는 inherited-supported / candidate / verified / blocked로 구분한다.
inherited-supported는 기존 배포의 허용 범위를 옮긴 상태이며 새 실기 검증을 뜻하지 않는다.
stable에서 기존 inherited-supported 및 verified를 허용하되 데이터 무결성과 CPU 조건은
모두 검사한다. 새 build는 inherited-supported로 생성할 수 없고 verified 근거가 필요하다.
test는 명시된 candidate를 보여줄 수 있지만 schema/hash/CPU 실패를 우회하지 않는다.

## 5. 입력·출력 API

JSON request를 파일/stdin으로 받고 JSON 한 개만 stdout으로 출력한다.
셸 로그는 stderr. 사용자 값으로 jq 코드를 조립하지 않고 --arg/--slurpfile을 사용한다.
기존 monolithic functions.sh를 source하지 않는다.

```json
{
  "operation": "validate",
  "model": "SA6400",
  "release": "7.4.1-90080",
  "channel": "stable",
  "mode": {"module": "custom-modules", "method": "PML"},
  "cpu": {"source": "target-local", "flags_known": true, "flags": []}
}
```

위 예시는 요청 형식이며 해당 조합이 승인됐다는 의미가 아니다.

| operation | 의미 | 0 반환 조건 |
|---|---|---|
| identity | 정규 버전/platform/kernel/legacy 경로 조회 | 정확한 등록 record가 있음. selection 승인이 아님 |
| options | 한 model/release의 허용 mode와 거부 사유 반환 | 조회 및 평가 성공. allowed_modes=[]도 정상 조회 |
| list | model에 대해 선택 가능한 release와 각 mode 열거 | 조회 성공. 결과 0개도 정상 조회 |
| validate | 명시된 release/mode의 빌드 선택 승인 여부 | 해당 선택이 허용됨 |

모든 응답은 schema_version, catalog_id, ok, reasons 배열을 갖는다.
identity의 ok는 metadata 조회 성공, validate의 ok는 선택 승인으로 의미가 다르므로
operation도 응답에 포함한다. options/list는 selectable/allowed_modes를 별도 검사한다.
성공한 validate 결과에는 canonical release, config/PAT ref, kernel, mode, recipe hash,
compatibility ref, request digest를 넣고 selection.lock.json으로 저장할 수 있게 한다.
실패 응답에는 허용 가능한 같은 릴리스 대안을 넣을 수 있으나 자동 적용하지 않는다.

exit code: 0 성공, 2 잘못된 요청, 3 catalog 누락/손상/schema 미지원,
4 model/release/target 없음, 5 selection 거부, 6 로컬 처리 실패.
실제 원인은 reasons[].code로 구별한다:
UNKNOWN_RELEASE, MODEL_RELEASE_UNSUPPORTED, TARGET_NOT_APPROVED,
MODE_UNAVAILABLE, METHOD_UNSUPPORTED, CPU_FEATURE_MISSING, CPU_FEATURE_UNKNOWN,
RECIPE_UNVERIFIED, CATALOG_INCONSISTENT.
identity 실패 시 이전 KVER/ORIGIN_PLATFORM 값 재사용 금지.

## 6. 판정 알고리즘

1. request와 catalog schema/reader version을 검사한다.
2. 입력 버전을 numeric tuple로 파싱하고 alias를 정규화한다. 공백/음수/추가 suffix 거부.
3. 모델·릴리스·channel exact target를 찾고 참조 무결성을 확인한다.
4. identity는 여기서 반환. 나머지는 target 상태 및 CPU 공통 요구를 평가한다.
5. 각 mode의 승인 record, recipe ref, method, CPU 요구를 평가한다.
6. options는 통과 mode와 각 거부 사유를 모두 반환한다.
7. list는 통과 mode가 하나 이상인 release만 기본 표시하고 numeric tuple 내림차순 정렬.
   UI는 평가 후 12개 제한 적용; 진단 옵션은 제외된 release와 이유도 제공한다.
8. validate는 요청한 exact mode만 평가한다. 자동 최신 선택/다른 mode 대체 없음.

CPU present/absent/unknown을 구분한다. 로컬 장비는 대상의 /proc/cpuinfo에서 수집하되
읽기 실패는 unknown이다. 여러 CPU의 feature는 공통 집합으로 계산한다.
Docker/CI 원격 빌드는 빌더 CPU가 아닌 적용 대상 장비의 capability snapshot을 입력한다.
기존 전달 경로가 없으면 추가해야 하며, 빌더의 BMI2를 자동으로 대신 사용하지 않는다.
검증 뒤 대상 capability가 달라지면 적용 단계에서 다시 확인한다.

## 7. 호출부 변경 방식

getvarsmshell은 호환 wrapper로 남긴다. identity 결과를 local 변수로 읽고 모두 검증한 후
MODEL/TARGET_REVISION/TARGET_VERSION/ORIGIN_PLATFORM/TARGET_PLATFORM/SYNOMODEL/KVER 및
ZPADKVER를 반영한다. 기존 serial 생성 부분은 유지한다. exit 대신 return을 사용한다.
functions.sh/functions_t.sh에 동일하게 적용하고 모든 호출부가 return code를 확인한다.
DSMVER는 cut -c 1-3 대신 정규 major.minor로 생성한다(functions.sh:8212 포함).

resolveLiveKver는 identity reader만 호출한다. 오류 시 빈 kernel을 숫자 0으로 바꾸지 않고
메뉴에 판정 불가를 표시한다. main loop 등 모든 호출부의 오류 처리를 같이 바꾼다.

modelMenu/selectversion/selectldrmode는 다음 순서를 공유한다:

```text
입력 선택 → 임시 selection 구성 → options/list → validate
 → user_config 관련 필드 한 번 반영 → bundled-exts 동기화 → 저장 결과 알림
```

모델 변경 시 이전 release/mode가 여전히 허용되면 유지한다. 허용되지 않으면 호환 후보를
메뉴에 제시한다. 기존 저장 버전을 조용히 낮추지 않는다. 명시적인 신규 모델 설정 과정에서
기본값은 numeric 최신 supported release + catalog default mode로 제안한다.
기존에 선택한 invalid 설정은 상태로 표시하고 빌드만 막는다. 취소하면 기존 설정 유지.
메뉴 화면에 들어왔다는 이유만으로 파일을 쓰지 않는다.

enforceBmi2VersionCap은 제거하고 reconcileSelection으로 대체한다.
checkAndResetModuleName은 자동 쓰기 함수가 아니라 validation/UI adapter로 바꾼다.
modelMenu 후반 PAT keys|max 저장 분기를 제거해 위 단일 commit 경로를 보장한다.
설정과 bundled-exts는 다중 파일이므로 단순 rename만으로 전체 원자성을 주장하지 않는다.
임시 생성/검증, 이전본 보관, 실패 복구를 수행하고 불일치 상태에서 build를 막는다.

my()는 CLI 인수/옵션과 설정을 읽은 뒤 validate한다. 다운로드/설정 갱신/디스크 쓰기 전에
실패를 반환한다. module 기본값도 검증된 options에서만 선택한다. getvarsmshell(identity)
성공만으로 빌드를 진행하지 않는다. P0에서는 boot/bus 기존 검사를 별도로 유지한다.
module 다운로드 단계가 recipe hash를 검증하고 성공해야 실제 build를 계속한다.

## 8. 배포 및 이행

현재 my.sh.gz workflow는 파일을 명시적으로 열거한다. resolver sh/jq/catalog를
.github/workflows/alpine-make.my.sh.gz.yml의 tar 목록과 apkovl 복사 단계에 모두 포함한다.
Docker/원격 build package, 복구/이전 릴리스 경로도 파일 포함 여부를 검사한다.
menu.sh는 functions.sh/functions_t.sh를 단독 갱신하는 경로가 있어 특히 주의한다.

전환 순서:
1. schema/compiler/resolver를 먼저 번들에 제공. 기존 판정과 나란히 비교하는 shadow 모드.
2. 기존 model/release/mode 전체 차이를 분류. catalog 불일치를 먼저 수정.
3. menu와 CLI adapter를 동시에 활성화하고 functions 쌍을 같이 배포.
4. 새 버전 helper가 dependency 없는 장치에서 단독 실행되지 않도록 reader bundle
   readiness 검사. 누락 시 진단/복구 메뉴를 유지하되 build는 중단.
5. fallback으로 과거 숫자 whitelist를 되살리지 않는다. 이전 릴리스 복원은 해당 helper와
   metadata 세트를 함께 복원하고 기존 my.sh.gz URL은 그대로 유지한다.

P0에서 Friend 코드는 아직 이 resolver를 사용하지 않는다. 따라서 이 단계 완료를
DSM 제어판 업데이트 후 자동 부팅 호환성 완료로 표현하지 않는다.

## 9. 검증과 완료 조건

| 테스트 | 기대 결과 |
|---|---|
| 기존 K3/K4/K5 및 broadwell 6.2 예외 | 기존 kernel 결과 보존, 잘못된 교차 버전/build 거부 |
| 7.4.2 신규 record 없음 | unknown/unsupported, 기존 7.4 모듈 자동 재사용 없음 |
| 테스트 fixture에서 7.4.2 + 승인된 custom pack + 비-BMI2 | 코드 수정 없이 허용 |
| 같은 fixture에서 승인/recipe 제거 | 메뉴 제외, 직접 CLI validate 거부 |
| all-pack이 BMI2 필요하고 CPU absent | all 거부; custom은 자체 조건이 맞을 때만 허용 |
| anodrm이 BMI2 필요 | No DRM 명칭과 무관하게 거부 |
| CPU unknown | feature 요구 mode 거부; 명시적으로 추가 요구 없는 mode만 평가 가능 |
| 7.4.2 / 7.4.10 / 7.9 / 7.10 및 update | 숫자 정렬, exact matching, smallfix 구별 |
| 모델 변경 뒤 latest 저장 회귀 | invalid build가 후반 코드로 다시 저장되지 않음 |
| IML/PML 잘못된 조합 | METHOD_UNSUPPORTED, pack만 같다고 통과하지 않음 |
| getvarsmshell 실패 | stale 전역변수 사용/빌드/디스크 쓰기 없음; nonzero 전파 |
| resolver dependency 누락/손상/신 schema | build 중단, 기존 설정·복구 진입 보존 |
| Docker CPU와 대상 CPU 다름 | 대상 snapshot 기준 판정 |
| 메뉴 취소/조회/options 빈 배열 | 설정 불변, 빌드 가능으로 오판하지 않음 |

fixture는 가상 7.4.2에 승인 데이터를 주입한 테스트이며 실제 호환성 검증을 뜻하지 않는다.
compiler는 모델→플랫폼 중복, dangling refs, 중복 tuple, alias 충돌, 잘못된 hash,
승인된 mode의 CPU 요구 누락을 거부해야 한다.
실제 recipe/asset 연결 확인까지 된 기존 조합을 기준 fixture로 확보한다.

완료 기준: runtime에 revision 숫자 목록/CUSTOM_MODULES_MAX_DSM 상한이 남지 않고,
동일 입력의 menu/CLI 결과가 같으며 새 승인 fixture가 코드 수정 없이 처리된다.
함수 쌍 동기화, 번들 포함, 오프라인/단독 업데이트/이전 릴리스 복구 검증을 포함한다.
현재는 설계와 호출부 조사만 수행했다. 구현 및 테스트 실행은 다음 작업이다.
