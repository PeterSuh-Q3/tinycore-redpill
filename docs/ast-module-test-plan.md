# AST DRM module pilot test plan

## Goal

Verify that the AST DRM driver built for the unified DSM 7.4 pack can bind to
an ASPEED display controller and provide a connected KMS output for the Junior
Realtime Helper. Separate module loading, connector detection, and visible
helper output into distinct checks so a failure is easy to locate.

This is a runtime test plan. The current pilot archive has only been built and
statically checked; it has not been deployed or loaded on a DSM system.

## Existing pilot artifact

- Target: `epyc7002`, DSM 7.4.1 build `90080`, kernel `5.10.55+`.
- Build: Docker Desktop, `dante90/syno-compiler:7.4`, eight CPUs.
- Archive:
  `/Users/yousuk/dual-gpu-backports/out/local-docker-ast-unified-pilot/epyc7002-7.4-5.10.55-drm.tgz`
- Archive SHA-256:
  `a38d4abbefb14d8f3200d67a1a2165a26c1c65a8614dbf82b4a4ea99b7710a50`
- `ast.ko` SHA-256:
  `733c21f51c456fe67545e2a48c437612dd64530435008e4d2f76712b03f38217`
- The built `ast.ko` declares PCI aliases `1a03:2000` and `1a03:2010`, has
  `5.10.55+ SMP mod_unload` vermagic, and directly depends on `drm`,
  `drm_kms_helper`, `drm_shmem_helper`, `dmabuf`, and `i2c-algo-bit`.
- The archive is a 22-module unified pack containing AST, AMDGPU, Bochs, i915,
  backlight, and DRM support modules. Do not install or load all 22 modules for
  an AST-only test.

## 1. Select and qualify the test host

Use a disposable or explicitly designated DSM test machine with a monitor
connected to the ASPEED/BMC video output and a reliable SSH or TTYD recovery
path. The candidate host must satisfy all of these before copying modules:

1. It runs `epyc7002` DSM 7.4.1 build `90080` and reports kernel `5.10.55+`.
2. `lspci -nn` shows an ASPEED display controller matching one of the PCI IDs
   embedded in this pilot (`1a03:2000` or `1a03:2010`).
3. The physical monitor is attached to that controller's output; note the
   output connector type and current screen resolution.
4. Remote recovery remains available if the graphical console blanks. Do not
   use the machine for this test if it is carrying production workloads or if
   no remote recovery path is available.

If no prepared host satisfies the platform, kernel, and PCI checks, stop and
prepare a matching host or rebuild for its exact DSM target. Do not try this
pilot on Alpine, Proxmox, another DSM platform, or another kernel build.

Record before-state evidence: `uname -a`, DSM build/platform, `lspci -nnk`,
`lsmod`, `/proc/modules`, `dmesg`, existing `/dev/dri` nodes, and connector
status under `/sys/class/drm`. Save these through the remote session so the
test can be compared and recovered without relying on the physical screen.

## 2. Validate and stage the AST dependency closure

1. Verify the archive and `ast.ko` SHA-256 values above. Inspect the archive's
   `manifest.txt`, module vermagic, aliases, and declared dependencies on the
   test host or in the matching toolchain environment.
2. Resolve the complete dependency closure from this exact archive's module
   metadata. Stage only `ast.ko` and its required DRM providers, including any
   transitive providers. Preserve a copy of the host's original module files
   and dependency metadata before changing them.
3. Compare each staged module against the host kernel. Stop if vermagic,
   platform, symbol-version, or provider checks do not match.
4. Check whether any module in the planned closure is already loaded, built in,
   or owned by another active graphics driver. Do not force-unload existing
   GPU/DRM modules or overwrite an active provider. If a collision exists,
   stop and resolve it on a separate test boot or host.

The unified archive includes unrelated drivers. Keep AMDGPU, Bochs, i915, and
backlight out of the AST test unless the computed AST dependency closure proves
one is required (the current AST direct dependency list does not).

## 3. Load AST and verify kernel binding

Load through the test host's normal module/dependency mechanism, using the
staged AST dependency closure. Do not launch the display helper yet.

Pass this stage only if all of the following are true:

- `ast.ko` loads without unresolved symbols or version errors.
- `dmesg` shows the expected AST device probe and no fatal initialization
  errors.
- The ASPEED PCI device is bound to the AST driver in sysfs.
- A DRM card and at least one AST connector appear under `/dev/dri` and
  `/sys/class/drm`.
- Connector status and available modes are recorded. A disconnected connector
  is a cabling/port or display-detection issue; it is not a successful output
  test.

If loading or binding fails, capture the complete relevant `dmesg`, `lsmod`,
`modinfo`/module metadata, `modules.dep`, and PCI driver binding. Do not respond
to an unknown symbol by substituting modules from another DSM platform or
kernel.

## 4. Verify visible KMS output with the helper

Only after the kernel-binding checks pass, launch the existing Junior Realtime
Helper KMS renderer manually for this controlled test. Confirm it selects the
AST DRM card and a connected connector, reports the selected mode, and draws
the live status panel. Keep SSH/TTYD connected while checking the physical
screen. Verify that the screen remains readable and refreshes for at least one
minute, then record the connector, mode, helper log, and final `dmesg`.

Do not yet add AST to an automatic addon or module-loading path. Successful
manual KMS output is the gate for that separate integration change.

## 5. Recovery and pass criteria

The pilot passes only when module loading, PCI binding, DRM card/connected
connector discovery, and visible helper output all succeed on the exact target
combination. Preserve logs and before/after module state with the result.

For recovery, stop the test renderer first. Unload only modules that this test
loaded and only when the kernel reports them unused; never force-remove shared
DRM providers or modules that were already active before the test. If the
display or module state cannot be safely restored remotely, reboot the test
host and verify the original driver state before reusing it. Keep the original
archive and staged-file checksums until post-reboot verification is complete.

## Test record

Fill this section after the runtime test; the values are intentionally blank
until they are observed on the target:

- Host / DSM platform and build:
- Host: SA6400 / `synology_epyc7002_sa6400`, DSM 7.4.1 build `90080`.
- Kernel release: `5.10.55+`.
- ASPEED PCI ID and bound driver: `1a03:2000`, bound to `ast`.
- Monitor port and detected connector/mode: `VGA-1` appeared, but sysfs
  reported `unknown` and exposed no modes.
- Modules loaded by the test: `ast`, `drm`, `drm_kms_helper`,
  `drm_shmem_helper`, `drm_mipi_dsi`, `drm_panel_orientation_quirks`,
  `i915_compat`, and `dmabuf`; the pre-existing `i2c_algo_bit` provider was
  retained.
- AST probe result and relevant `dmesg`: AST 2300 detected, analog VGA selected,
  and DRM initialized on minor 0. No unresolved-symbol or vermagic error was
  reported during module loading. Full dmesg later confirms recurring
  `watchdog: BUG: soft lockup - CPU#2 stuck for 22s! [kms-display:10307]`
  reports every ~28 seconds from uptime 696 through 896 seconds, plus RCU
  self-detected stalls on CPU 2 at 729 and 909 seconds. This is a serious
  stability failure, though no fatal `Kernel panic - not syncing` is shown.
- The stack points to the userspace KMS renderer blocked in the DRM GEM/shmem
  buffer mmap path (`shmem_read_mapping_page_gfp`, `drm_gem_get_pages`,
  `drm_gem_shmem_mmap`, `drm_gem_mmap`), with later samples in page-cache
  locking functions. The helper creates/maps a dumb buffer in
  `kms-display.c`. `ast` is present in the loaded-module list but its driver
  functions do not appear in the captured stacks; the log therefore implicates
  the GEM/shmem path triggered by the renderer, not conclusively `ast.ko`.
  Isolate DRM backport/kernel compatibility from the renderer before another
  DSM KMS mmap test.
- Helper result and visible-output confirmation: `selftest.sh` and the KMS
  binary were staged under `/tmp` and launched. The status snapshot populated
  network, TCP/5000, ping, disk, and AST GPU fields. Visible KMS output was not
  confirmed; with connector status `unknown` and no modes, the current renderer
  has no eligible connector to modeset.
- Recovery / post-reboot result: not run. A TTYD stop request for the helper
  was sent, but no command result came back, so its process state is unknown.
  The modules and helper were loaded from volatile `/tmp` paths for this
  session; do not force-unload the shared DRM stack while the display state is
  uncertain.
- Overall result: failed for stability. AST module binding passed, but the KMS
  renderer triggers repeated soft lockups and RCU stalls. Visible helper output
  remains unverified; do not repeat the current mmap/rendering path on this DSM
  kernel until the fault is isolated.
