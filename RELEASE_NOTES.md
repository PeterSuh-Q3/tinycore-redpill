617b1d4e9b8a2e49285dfda64dfd3ab4198b5205
42474f08883622086b7596d14e1d4c9d055ca560
a958169e7eb292104eee58da2d3f9296d4b3e9a8

    1.3.0.4 Delivered a Linux 5.4 LTS OOT backport of i915 and amdgpu as a unified dual-DRM build, 
    enabling Intel iGPU (up to GEN11/Ice Lake) and AMD dGPU (Polaris~RDNA1) to coexist on DSM 4.4.302 without kernel rebuilding.
    Full coverage across 10 platforms × DSM 7.2/7.3 (20 builds), sharing a single `drm.ko` to eliminate ABI conflicts between drivers.

## Dual DRM (i915 + amdgpu): Full Platform Rollout — 10 Platforms × DSM 7.2/7.3

### 🎯 Core Achievement: Intel iGPU Coverage Leap via OOT Backport

The stock DSM 4.4.302 kernel ships with an i915 driver frozen at **GEN9 (Skylake, 6th gen)**. Any Intel CPU newer than Skylake — Apollo Lake, Gemini Lake, Denverton, Coffee Lake, Comet Lake — is **not recognized at all**.

This release delivers a **Linux 5.4 LTS OOT i915 backport** that brings full native support up to **GEN11 (Ice Lake, 10th gen)** and extends further to **Comet Lake-H/S** via cherry-picks. The OOT driver runs on top of DSM 4.4.302 without kernel rebuilding.

---

### ✅ Intel iGPU — Before vs. After

| Generation | Codename | iGPU | Stock 4.4.302 | **This Release (5.4 OOT)** |
|---|---|---|:---:|:---:|
| 5th gen | Broadwell | HD 5500 / Iris 6100 | GEN8 ✅ | ✅ |
| 6th gen | Skylake | HD 510~580 / Iris 540 | GEN9 ⚠️ | ✅ |
| 7th gen | Kaby Lake | HD 610~650 / Iris 640 | ❌ | ✅ |
| 8th gen | Coffee Lake / Whiskey Lake | UHD 620~630 | ❌ | ✅ |
| 9th gen | Coffee Lake Refresh | UHD 630 | ❌ | ✅ |
| **10th gen** | **Ice Lake** | **Iris Plus (GEN11)** | ❌ | **✅ Native** |
| **10th gen** | **Comet Lake-U** | **UHD 620/630 (GEN9.5)** | ❌ | **✅ Native** |
| **10th gen** | **Comet Lake-H/S** | **UHD 630 GT1/GT2** | ❌ | **✅ Cherry-pick** |
| Atom | Apollo Lake / Gemini Lake | HD 500/505/600 (GEN9) | ❌ | ✅ |
| Atom | Denverton (C3000) | — | ❌ | ✅ |

> PCI Device ID Override (the old workaround) is **eliminated** — the OOT driver recognizes all these GPUs natively through the correct `intel_device_info` path, ensuring proper GUC/HUC firmware, correct Display Engine init, and stable runtime PM.

---

### ✅ AMD GPU — Supported Range (5.4 OOT amdgpu)

| Generation | Products | Support |
|---|---|:---:|
| GCN4 / Polaris (RX 400·500) | RX 460~590, WX 2100~7100 | ✅ |
| GCN5 / Vega | RX Vega 56/64, Radeon VII, APU: Carrizo~Renoir | ✅ |
| RDNA1 / Navi (RX 5000) | RX 5500~5700 XT | ✅ |
| RDNA2+ (RX 6000+) | — | ❌ (needs 5.10+) |

---

### 🔀 Dual DRM: Single `drm.ko` for i915 + amdgpu

A single NAS can now run **Intel iGPU (QuickSync)** and **AMD dGPU (VA-API)** simultaneously. Both drivers are built from the same 5.4 OOT source tree, sharing one `drm.ko` — eliminating the ABI conflicts that made co-existence impossible with separately built modules.

---

### ✅ Platform Coverage (4.4.302 kernel)

| Platform | DSM 7.2 | DSM 7.3 |
|---|:---:|:---:|
| apollolake | ✅ | ✅ |
| broadwell | ✅ | ✅ |
| broadwellnk | ✅ | ✅ |
| broadwellnkv2 | ✅ | ✅ |
| broadwellntbap | ✅ | ✅ |
| denverton | ✅ | ✅ |
| geminilake | ✅ | ✅ |
| purley | ✅ | ✅ |
| r1000 | ✅ | ✅ |
| v1000 | ✅ | ✅ |

---

### 📦 Modules per Platform

`drm.ko` · `drm_kms_helper.ko` · `i915.ko` · `amdgpu.ko` · `ttm.ko` · `gpu-sched.ko`
*(+ `drm_panel_orientation_quirks.ko` on apollolake/geminilake where not kernel built-in)*

**Additional: `interval_tree.ko`** (OOT, broadwell/broadwellnk/broadwellnkv2/broadwellntbap/denverton/purley/r1000/v1000 × 7.2+7.3)
> The 4.4.302 kernel does not export `interval_tree_*` symbols — drm_mm.c in i915/amdgpu had unresolved dependencies. Fixed by providing an OOT `interval_tree.ko`.
> apollolake/geminilake excluded (kernel built-in on Atom platforms).

---

### ⚠️ Notes

- AMD transcoding: **VA-API (radeonsi)** only — not AMF.
- On dual-GPU systems `renderD128`/`renderD129` follows PCI enumeration order.
- 11th gen (Tiger Lake) and later require kernel 5.9+ and are out of scope.
- `for n in /dev/dri/renderD*; do echo "$n -> $(basename $(readlink /sys/class/drm/$(basename $n)/device/driver))"; done`
`/dev/dri/renderD128 -> i915`
`/dev/dri/renderD129 -> amdgpu`

---
---

## 듀얼 DRM (i915 + amdgpu): 전 플랫폼 배포 완성 — 10개 플랫폼 × DSM 7.2/7.3

### 🎯 핵심: iGPU 지원 범위의 대도약

DSM 4.4.302 기본 커널의 i915 드라이버는 **6세대 Skylake (GEN9)** 에서 멈춰 있습니다. 그보다 신형인 Apollo Lake, Gemini Lake, Denverton, Coffee Lake, Comet Lake 는 **기본 커널에서 전혀 인식되지 않습니다.**

이번 릴리즈는 **Linux 5.4 LTS OOT i915 백포트**를 통해 **GEN11 (10세대 Ice Lake)** 까지 네이티브 지원을 제공하고, Cherry-pick으로 **Comet Lake-H/S** 까지 확장합니다. 커널 재빌드 없이 DSM 4.4.302 위에서 동작합니다.

---

### ✅ Intel iGPU — 전후 비교

| 세대 | 코드명 | iGPU | 기본 4.4.302 | **이번 릴리즈 (5.4 OOT)** |
|---|---|---|:---:|:---:|
| 5세대 | Broadwell | HD 5500 / Iris 6100 | GEN8 ✅ | ✅ |
| 6세대 | Skylake | HD 510~580 / Iris 540 | GEN9 ⚠️ | ✅ |
| 7세대 | Kaby Lake | HD 610~650 / Iris 640 | ❌ | ✅ |
| 8세대 | Coffee Lake / Whiskey Lake | UHD 620~630 | ❌ | ✅ |
| 9세대 | Coffee Lake Refresh | UHD 630 | ❌ | ✅ |
| **10세대** | **Ice Lake** | **Iris Plus (GEN11)** | ❌ | **✅ 네이티브** |
| **10세대** | **Comet Lake-U** | **UHD 620/630 (GEN9.5)** | ❌ | **✅ 네이티브** |
| **10세대** | **Comet Lake-H/S** | **UHD 630 GT1/GT2** | ❌ | **✅ Cherry-pick** |
| Atom | Apollo Lake / Gemini Lake | HD 500/505/600 (GEN9) | ❌ | ✅ |
| Atom | Denverton (C3000) | — | ❌ | ✅ |

> 기존의 PCI Device ID Override(임시 우회) 방식을 **완전 제거**하고 OOT 드라이버 네이티브 인식으로 전환.  
> 올바른 `intel_device_info` 경로를 통해 GUC/HUC 펌웨어, Display Engine 초기화, 런타임 PM이 정상 동작합니다.

---

### ✅ AMD GPU — 지원 범위 (5.4 OOT amdgpu)

| 세대 | 제품 | 지원 |
|---|---|:---:|
| GCN4 / Polaris (RX 400·500) | RX 460~590, WX 2100~7100 | ✅ |
| GCN5 / Vega | RX Vega 56/64, Radeon VII, APU: Carrizo~Renoir | ✅ |
| RDNA1 / Navi (RX 5000) | RX 5500~5700 XT | ✅ |
| RDNA2+ (RX 6000+) | — | ❌ (5.10+ 필요) |

---

### 🔀 듀얼 DRM: i915 + amdgpu 단일 `drm.ko` 공유

하나의 NAS에서 **Intel iGPU (QuickSync)** 와 **AMD dGPU (VA-API)** 를 **동시에** 운용할 수 있습니다.  
두 드라이버가 동일한 5.4 OOT 소스 트리에서 빌드되어 단일 `drm.ko` 를 공유 — 모듈 ABI 충돌이 구조적으로 해소됩니다.

---

### ✅ 플랫폼 커버리지 (4.4.302 커널)

| 플랫폼 | DSM 7.2 | DSM 7.3 |
|---|:---:|:---:|
| apollolake | ✅ | ✅ |
| broadwell | ✅ | ✅ |
| broadwellnk | ✅ | ✅ |
| broadwellnkv2 | ✅ | ✅ |
| broadwellntbap | ✅ | ✅ |
| denverton | ✅ | ✅ |
| geminilake | ✅ | ✅ |
| purley | ✅ | ✅ |
| r1000 | ✅ | ✅ |
| v1000 | ✅ | ✅ |

---

### 📦 플랫폼별 제공 모듈

`drm.ko` · `drm_kms_helper.ko` · `i915.ko` · `amdgpu.ko` · `ttm.ko` · `gpu-sched.ko`  
*(apollolake/geminilake: 호스트 빌트인이 아닌 경우 `drm_panel_orientation_quirks.ko` 포함)*

**추가 모듈: `interval_tree.ko`** (OOT, broadwell/broadwellnk/broadwellnkv2/broadwellntbap/denverton/purley/r1000/v1000 × 7.2+7.3)
> 4.4.302 커널이 `interval_tree_*` 심볼을 빌트인으로 export하지 않아 i915/amdgpu drm_mm.c 의존성이 미해결로 남아 있던 문제를 OOT `interval_tree.ko` 제공으로 해결.
> apollolake/geminilake는 해당 심볼이 커널 빌트인이므로 제외.

---

### ⚠️ 참고 사항

- AMD 트랜스코딩: **VA-API(radeonsi)** 전용 — AMF 아님.
- 듀얼 GPU 시스템에서 `renderD128`/`renderD129` 할당은 PCI 열거 순서를 따릅니다.
- 11세대(Tiger Lake) 이상은 커널 5.9+ 필요, 본 릴리즈 범위 외.
- `for n in /dev/dri/renderD*; do echo "$n -> $(basename $(readlink /sys/class/drm/$(basename $n)/device/driver))"; done`
`/dev/dri/renderD128 -> i915`
`/dev/dri/renderD129 -> amdgpu`    
