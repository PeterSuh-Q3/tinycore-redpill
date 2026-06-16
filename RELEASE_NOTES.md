617b1d4e9b8a2e49285dfda64dfd3ab4198b5205
d632c6d15411de749e6bf5d7d7b92af2b8054e0e
a958169e7eb292104eee58da2d3f9296d4b3e9a8

    1.3.0.4 Delivered a Linux 5.4 LTS OOT backport of i915 and amdgpu as a unified dual-DRM build, 
enabling Intel iGPU (up to GEN11/Ice Lake) and AMD dGPU (Polaris~RDNA1) to coexist on DSM 4.4.302 without kernel rebuilding.
Full coverage across 10 platforms × DSM 7.2/7.3 (20 builds), sharing a single `drm.ko` to eliminate ABI conflicts between drivers.
