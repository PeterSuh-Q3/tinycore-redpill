2599b8ced31c669d63a57429787c9025d932fd70
c9768bd967da8005ed23855b14be2ebca70ee621
a958169e7eb292104eee58da2d3f9296d4b3e9a8

## 1.3.0.3 — i915 + amdgpu Dual DRM & Expanded AMD Chipset Support in all-modules. (/dev/dri/renderD128, /dev/dri/renderD129)

### 🎯 Dual DRM (i915 ↔ amdgpu coexistence)

Previously, building the i915 and amdgpu modules separately produced **two incompatible `drm.ko`** files (ABI mismatch), so they could not coexist on one system.

Starting with this release, i915 and amdgpu are **built together from a single source tree against one `drm.ko`**.

- i915 and amdgpu **share the same `drm.ko`** (plus ttm / drm_kms_helper / drm_display_helper / gpu-sched, etc.) → the DRM ABI conflict is structurally eliminated
- **Verified on real hardware (geminilakenk DSM): `i915` and `amdgpu` load simultaneously** on a single shared `drm`
- An Intel iGPU (QuickSync) and an AMD GPU can be used together on the same NAS

### 🚀 amdgpu: MT65 (v6.5) backport greatly expands chipset support

The amdgpu source is backported from **Linux 6.5 (mainline-tracking, MT65)**, extending support to recent AMD chipsets on the DSM 5.10.55 kernel (DRM userspace API 3.40 → **3.54**).

| Generation | Examples | Supported |
|---|---|---|
| GCN3/4 (Polaris) | RX 460~590, WX 2100~7100 | ✅ |
| GCN5 (Vega) | RX Vega, Radeon VII, Carrizo~Renoir APU | ✅ |
| RDNA1 | RX 5000 | ✅ |
| RDNA2 | RX 6000 (Navi21~24) | ✅ |
| **RDNA3 (new)** | **RX 7600~7900, Phoenix APU (Ryzen 7040/8040)** | ✅ |
| **VCN4 (new)** | **AV1 decode/encode** | ✅ |

> RDNA3.5 (Strix) and RDNA4 (RX 9000) require kernel 6.10+ IP and are outside this (6.5) backport.

- The firmware package (`firmwareamdgpu.tgz`) adds the remaining RDNA2 and RDNA3 firmware (gc_11_0_*, psp_13_0_*, vcn_4_0_*, smu_13_0_*, etc.)
- Headless configuration (DC=n) optimized for **VA-API transcoding (Jellyfin / Plex)**
- `hdmi_video.ko` is included/excluded per platform based on the host CONFIG_HDMI (excluded on geminilakenk; included on epyc7002/r1000nk/v1000nk)

### 📦 Target platforms

`epyc7002` (SA6400) · `geminilakenk` (DS425+/DS225+) · `r1000nk` · `v1000nk` — DSM 7.1/7.2/7.3 (kernel 5.10.55)

### ⚠️ Notes

- AMD H/W transcoding works only via **VA-API (radeonsi)** (not AMF).
- On dual-GPU systems the render node (renderD128/129) ↔ GPU mapping depends on enumeration order. Check with `ls /dev/dri/by-path/` or `cat /sys/class/drm/renderD12X/device/uevent` (DRIVER=amdgpu/i915).

---

## 26.6.12 — i915 + amdgpu 듀얼 DRM & AMD 칩셋 지원 확장

### 🎯 듀얼 DRM (i915 ↔ amdgpu 공존)

기존에는 i915 모듈과 amdgpu 모듈을 따로 빌드하면 서로 **다른 `drm.ko`**(ABI 비호환)를 만들어 한 시스템에서 공존이 불가능했습니다.

이번 릴리즈부터 i915와 amdgpu를 **하나의 소스 트리에서 단일 `drm.ko`에 함께 빌드**합니다.

- i915와 amdgpu가 **동일한 `drm.ko`(+ttm/drm_kms_helper/drm_display_helper/gpu-sched 등)를 공유** → DRM ABI 충돌이 구조적으로 사라짐
- 실기(geminilakenk DSM)에서 `i915`·`amdgpu` **동시 적재 검증 완료** (단일 `drm` refcount 공유)
- Intel iGPU(QuickSync)와 AMD GPU를 같은 NAS에서 함께 활용 가능

### 🚀 amdgpu: MT65(v6.5) 백포트로 지원 칩셋 대폭 확장

amdgpu 소스를 **Linux 6.5(mainline-tracking, MT65)** 기반으로 백포트하여, DSM 5.10.55 커널 위에서 최신 AMD 칩셋까지 지원 범위가 넓어졌습니다. (DRM userspace API 3.40 → **3.54**)

| 세대 | 대표 제품 | 지원 |
|---|---|---|
| GCN3/4 (Polaris) | RX 460~590, WX 2100~7100 | ✅ |
| GCN5 (Vega) | RX Vega, Radeon VII, Carrizo~Renoir APU | ✅ |
| RDNA1 | RX 5000 | ✅ |
| RDNA2 | RX 6000 (Navi21~24) | ✅ |
| **RDNA3 (신규)** | **RX 7600~7900, Phoenix APU(Ryzen 7040/8040)** | ✅ |
| **VCN4 (신규)** | **AV1 디코드/인코드** | ✅ |

> RDNA3.5(Strix)·RDNA4(RX 9000)는 커널 6.10+ IP가 필요하여 본 백포트(6.5) 범위 밖입니다.

- 펌웨어 패키지(`firmwareamdgpu.tgz`)에 RDNA2 완성분 + RDNA3 펌웨어 추가 (gc_11_0_*, psp_13_0_*, vcn_4_0_*, smu_13_0_* 등)
- 헤드리스 구성(DC=n)으로 **VA-API 트랜스코딩(Jellyfin / Plex)** 전용 최적화
- 호스트 CONFIG_HDMI 여부에 따라 `hdmi_video.ko`를 플랫폼별로 포함/제외 (geminilakenk 제외, epyc7002/r1000nk/v1000nk 포함)

### 📦 대상 플랫폼

`epyc7002` (SA6400) · `geminilakenk` (DS425+/DS225+) · `r1000nk` · `v1000nk` — DSM 7.1/7.2/7.3 (커널 5.10.55)

### ⚠️ 참고

- AMD H/W 트랜스코딩은 **VA-API(radeonsi)** 로만 동작합니다 (AMF 아님).
- 듀얼 GPU 시스템에서 render 노드(renderD128/129) ↔ GPU 매핑은 열거 순서에 따라 달라질 수 있습니다. `ls /dev/dri/by-path/` 또는 `cat /sys/class/drm/renderD12X/device/uevent`(DRIVER=amdgpu/i915)로 확인하세요.
