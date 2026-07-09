18256b6608c7e3e196cef89a6cef68b12f020b5a
0b9dc57915b51a46d39db428978775b6f00bcd4f
f57d1b26457b7f08e81be21b4009f81db7c59f15

    1.3.1.0 Added FS6420 model support. FS6420 is epyc7003 platform (AMD EPYC 7303, single controller, DSM 7.4.0-90075).
Started support for DSM 7.4 official toolchain-based modules.

---

## 📦 v1.3.0.9 — DSM 7.4 official toolchain follow-up (module asset audit)

> Synology's DSM 7.4 official GPL toolchain announcement made it possible to replace several **7.3-as-7.4 placeholder assets** across `tcrp-modules` with real 7.4 builds. This entry documents the audit and the fixes that followed.

### ✅ What changed

| Repo / Module | Before | After |
|---|---|---|
| `tcrp-modules` / `all-modules` | 20 platforms, `_74_*` keys pointed at `-7.3.json` (fake) | ✔️ Real 7.4 tgz built for all 20 platforms, recipes repointed |
| `tcrp-modules` / `anodrm-modules` | 20 platforms, `_74_*` keys pointed at `-7.3.json` (fake) | ✔️ Real 7.4 tgz copied from `all-modules` (already DRM-free), 20 new recipes, index repointed |
| `tcrp-modules` / `amd-modules` | 10 platforms still fake (`_74_*` → `-7.3.json`) | ⏳ Pending — no real 7.4 build yet |
| `tcrp-modules` / `custom-modules` | 5 platforms still fake (`_74_*` → `-7.3.json`) | ⏳ Pending — no real 7.4 build yet |

### 🔍 How the anodrm fix works

`anodrm-modules` ships the same module set as `all-modules` **minus** the i915/amdgpu graphics (DRM) stack — for hosts where loading a GPU driver causes instability. Since the freshly-built `all-modules` 7.4 tgz already contain **zero** DRM modules, the fix was a direct copy rather than a strip-and-repack:

```
all-modules 7.4 tgz  (20 platforms, kernel 4.4.302 / 3.10.108 / 5.10.55)
        │
        │  verified: 0 DRM-related .ko files present
        ▼
anodrm-modules/releases/<same-name>.tgz   (copied as-is)
        +  <plat>-7.4.json recipe (new)
        +  rpext-index.json  _74_*  → repointed to the new recipe
```

A local simulation against the still-fake `epyc7002-7.3` pair confirmed the removal logic itself is correct before any live asset was touched: stripping the 26-module DRM set from `all-modules` (470 files) produced **exactly** the existing `anodrm-modules` build (444 files), module-for-module.

### 🛠️ New: `refresh_anodrm.yml` workflow

A reusable GitHub Actions workflow (`workflow_dispatch`) now exists to regenerate `anodrm-modules` assets from any `all-modules` release automatically:

| Input | Purpose |
|---|---|
| `release_tag` | Source `all-modules` release (defaults to latest) |
| `versions` | DSM version filter, e.g. `"7.4"` (defaults to all) |
| `release_body` | Extra commit message text |

It downloads each module tgz, removes a fixed **35-module DRM/framebuffer set** (union across platforms — safe no-op for modules that aren't present), repacks, recomputes `sha256`, regenerates the recipe JSON, and commits.

### 📋 Remaining work

- `amd-modules` and `custom-modules` still reference `-7.3.json` under their `_74_*` keys — a real 7.4 build has not been produced for either yet.
- No action was needed for `disks.sh`/DTS-level code — this was purely an asset/recipe bookkeeping pass.

<details>
<summary>🇰🇷 한글 버전 펼치기 · Korean version</summary>

<br>

> Synology 의 DSM 7.4 정식 GPL 툴체인 공지 덕분에, `tcrp-modules` 전반에 남아있던 **7.3 자산을 7.4 처럼 대신 쓰던 fake 케이스**들을 실제 7.4 빌드로 교체할 수 있게 되었습니다. 이번 항목은 그 전수 조사와 후속 조치를 기록합니다.

#### ✅ 변경 사항

| 저장소 / 모듈 | 이전 | 이후 |
|---|---|---|
| `tcrp-modules` / `all-modules` | 20개 플랫폼, `_74_*` 키가 `-7.3.json` 을 가리킴(fake) | ✔️ 20개 플랫폼 전체 실제 7.4 tgz 빌드, recipe 재지정 완료 |
| `tcrp-modules` / `anodrm-modules` | 20개 플랫폼, `_74_*` 키가 `-7.3.json` 을 가리킴(fake) | ✔️ `all-modules` 에서 실제 7.4 tgz 복사(이미 DRM 미포함), recipe 20개 신규, 인덱스 재지정 완료 |
| `tcrp-modules` / `amd-modules` | 10개 플랫폼 여전히 fake(`_74_*` → `-7.3.json`) | ⏳ 보류 — 실제 7.4 빌드 아직 없음 |
| `tcrp-modules` / `custom-modules` | 5개 플랫폼 여전히 fake(`_74_*` → `-7.3.json`) | ⏳ 보류 — 실제 7.4 빌드 아직 없음 |

#### 🔍 anodrm 수정 방식

`anodrm-modules` 는 `all-modules` 와 동일한 모듈 구성에서 i915/amdgpu 그래픽(DRM) 스택만 **제외**한 자산입니다 — GPU 드라이버 로드가 불안정을 일으키는 환경을 위한 것입니다. 새로 빌드된 `all-modules` 7.4 tgz 는 이미 DRM 모듈이 **0개**였기 때문에, 재압축이 아니라 그대로 복사하는 방식으로 처리했습니다:

```
all-modules 7.4 tgz  (20개 플랫폼, 커널 4.4.302 / 3.10.108 / 5.10.55)
        │
        │  확인됨: DRM 관련 .ko 파일 0개
        ▼
anodrm-modules/releases/<동일 파일명>.tgz   (그대로 복사)
        +  <plat>-7.4.json recipe (신규)
        +  rpext-index.json  _74_*  → 신규 recipe 로 재지정
```

실제 자산을 건드리기 전, 아직 fake 상태였던 `epyc7002-7.3` 쌍으로 로컬 시뮬레이션을 돌려 제거 로직 자체를 먼저 검증했습니다: `all-modules`(470개 파일)에서 26개 DRM 모듈 셋을 제거한 결과가 기존 `anodrm-modules` 빌드(444개 파일)와 **모듈 단위로 완전히 일치**했습니다.

#### 🛠️ 신규: `refresh_anodrm.yml` 워크플로우

어떤 `all-modules` 릴리즈로부터도 `anodrm-modules` 자산을 자동 재생성할 수 있는 GitHub Actions 워크플로우(`workflow_dispatch`)를 추가했습니다:

| 입력 | 용도 |
|---|---|
| `release_tag` | 소스 `all-modules` 릴리즈 (기본값: latest) |
| `versions` | DSM 버전 필터, 예: `"7.4"` (기본값: 전체) |
| `release_body` | 커밋 메시지 추가 문구 |

각 모듈 tgz 를 내려받아 **35개 DRM/프레임버퍼 모듈 셋**(플랫폼별 관측치의 합집합 — 없는 모듈은 안전하게 스킵)을 제거하고 재압축, `sha256` 재계산, recipe JSON 재생성, 커밋까지 자동으로 수행합니다.

#### 📋 남은 작업

- `amd-modules` 와 `custom-modules` 는 여전히 `_74_*` 키가 `-7.3.json` 을 참조 중 — 아직 실제 7.4 빌드가 만들어지지 않았습니다.
- `disks.sh`/DTS 레벨 코드 변경은 필요 없었습니다 — 이번 작업은 순수하게 자산/recipe 정리 작업이었습니다.

</details>
