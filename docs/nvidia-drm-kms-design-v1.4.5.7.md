# v1.4.5.7 design: NVIDIA DRM/KMS for Junior Realtime Helper

## Goal

Junior Realtime Helper can render through DRM/KMS, but a system whose NVIDIA
GPU has no usable `nvidia-drm` KMS module cannot use that display path. The
user has already loaded the published NVIDIA release assets for KMS and
completed a helper test successfully. This establishes that the asset-based
approach can work with the helper; it does not by itself define the supported
GPU, platform, or kernel matrix for the release.

For v1.4.5.7, provide an explicit, optional way to include the matching NVIDIA
DRM modules when the helper is selected, while keeping ordinary NVIDIA driver
installation behavior separate and unchanged.

## Design decisions

1. Add a new standalone addon named `nvidia-drm`. Do not make KMS installation
   an implicit side effect of `nvidiadriver`: that addon manages the full DSM
   NVIDIA driver/package path, while this addon supplies the helper's DRM/KMS
   prerequisite.
2. Reuse the NVIDIA PCI-device and GPU-support detection already used by the
   NVIDIA Driver menu in `menu_m.sh`. In particular, reuse its lookup of
   `nvidiadriver/src/nvidia-gpu-support.json` for PCI ID, architecture, branch,
   and GSP requirements. Do not maintain a second GPU-generation table in the
   menu, addon, or build script. If the existing detection is embedded in the
   menu body, extract the smallest shared helper/data interface needed so both
   consumers use the same classification.
3. Ask about KMS inclusion only when `junior-realtime-helper` is selected and
   the detected GPU has a matching, supported asset for the target platform
   and DSM kernel. The prompt must explain that this is for the helper's
   NVIDIA DRM/KMS display output, show the detected GPU and selected asset
   variant, and allow an explicit opt-out. Do not force-install KMS on systems
   without a supported NVIDIA GPU or when the helper is not selected.
4. Use separate NVIDIA DRM module assets and lifecycle from the full
   `nvidiadriver` SPK/userspace path. Do not silently install NVIDIA userspace,
   an SPK, or a complete driver stack just to enable helper KMS.

## GPU and asset selection

- Use the shared support metadata to classify the PCI device, then validate
  the exact platform and DSM kernel against the published asset index before
  offering inclusion.
- For supported Maxwell-through-pre-Turing devices, select the 580
  proprietary module archive. For Turing and later, prefer the 580 open
  archive only when the GPU/branch's GSP requirements and the published GSP
  firmware asset are satisfied. “Turing or newer” alone is not sufficient:
  unsupported or missing-GSP combinations must be rejected, not guessed.
- The currently inspected release assets are for kernel 5.10.55 and a finite
  set of platforms. Kernel 4.4 and any absent platform/variant remain
  unsupported until matching assets are published and validated.
- Pin the chosen archive and any required firmware to exact release URLs and
  SHA-256 values in the addon/build metadata. Verify checksums before unpacking;
  the running loader must not depend on downloading assets from GitHub.
- Unknown PCI IDs, missing support metadata, unsupported architecture, missing
  asset, checksum failure, or kernel/platform mismatch must fail closed: omit
  the optional addon with a clear build-time explanation rather than loading a
  potentially incompatible module.

## Proposed lifecycle

1. During loader configuration, detect the GPU using the shared NVIDIA menu
   logic and present the optional KMS prompt only when the helper and a
   compatible asset are both present.
2. At build time, stage the selected module archive (and required firmware),
   verify its checksum and embedded platform/kernel/version metadata, and
   include only the required KMS payload in the `nvidia-drm` addon.
3. In the DSM `modules` event, install the module files in the expected module
   tree and run `depmod` so provider/dependency metadata is ready. Do not load
   `nvidia-drm` at this early event: it can run on ordinary DSM boots too, and
   an early load could claim the GPU or conflict with the user's normal NVIDIA
   driver/package selection.
4. Immediately before `junior-realtime-helper` starts in the Junior fallback
   path, load the matching modules with the required KMS setting (equivalent to
   `modprobe nvidia-drm modeset=1`) and only then launch the helper. Keep this
   operation scoped to the Junior helper path; normal DSM boots must not
   acquire a new unconditional NVIDIA module load.
5. If a compatible NVIDIA module is already loaded, do not unload or replace it
   to force a parameter. Check the active module/version and KMS parameter;
   report an incompatibility and let the helper retain its existing fallback
   behavior rather than risking the active display/driver stack.

The final event wiring must respect the addon framework's actual event order:
KMS initialization must complete before the helper attempts DRM discovery, and
the regular `nvidiadriver` addon must not be accidentally pulled in or
overwritten.

## Runtime checks and failure behavior

Before declaring KMS ready, check at least:

- the expected `nvidia`, `nvidia-modeset`, and `nvidia-drm` modules are present
  and load without unresolved dependencies;
- `/sys/module/nvidia_drm/parameters/modeset` reports enabled;
- a usable `/dev/dri/card*` node appears, and DRM reports a connected output
  when the hardware/display provides one.

Log the detected PCI ID, selected variant, module-load result, modeset state,
and DRM-node result. A failure must not turn a failed module load into a
successful addon status. It should leave the helper's non-KMS/console fallback
available and provide a concise diagnostic; it must not trigger repeated
unbounded retries or unload another active NVIDIA stack.

## Validation plan

1. Unit/mock checks for supported and unsupported PCI IDs, unknown IDs,
   missing GSP/firmware, absent platform/kernel assets, and checksum mismatch.
2. Build checks for archive metadata, module vermagic/dependency closure,
   `depmod` output, and an explicit `modeset=1` load path.
3. Runtime test on each initially supported GPU/asset family: confirm module
   load, modeset state, DRM card/connector discovery, and visible
   Junior-Realtime-Helper output.
4. Negative/control tests: no NVIDIA GPU, helper not selected, unsupported
   GPU, normal DSM boot, and full `nvidiadriver`/SPK already active. Confirm
   there is no unintended KMS load, driver replacement, or false success.
5. Record the exact platform, DSM kernel, GPU PCI ID, archive URL/version,
   checksums, and test result before expanding the support matrix.

## Release scope and open implementation check

The initial release must be limited to combinations with published, checksum-
verified assets and a successful runtime test. The reported successful
asset-based helper test is a positive feasibility result; the exact tested
combination should be recorded during implementation before it is advertised
as a supported matrix entry.

Before coding, inspect the addon's recipe/event conventions and determine how
to make the helper wait for KMS initialization without changing ordinary DSM
boot behavior. Keep this work isolated to the new `nvidia-drm` addon plus the
smallest necessary shared GPU-detection/configuration change. Do not modify
the full NVIDIA SPK installation policy as part of this feature.
