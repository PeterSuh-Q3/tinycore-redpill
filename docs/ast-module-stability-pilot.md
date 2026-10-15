# AST DRM stability pilot plan

## Evidence and scope

The 2026-10-15 SA6400 test loaded the Linux v6.5 AST driver against DSM 7.4.1
kernel 5.10.55+. The AST PCI probe succeeded, but the `kms-display` userspace
process repeatedly soft-locked CPU 2 while creating/mapping its dumb DRM
buffer. The trace passes through `drm_gem_shmem_mmap`,
`drm_gem_get_pages`, and kernel shmem page handling; RCU later reports stalls
on the same CPU. This is a stability failure, but the log does not show a fatal
kernel panic or an AST driver function in the stuck stack.

The current v6.5 AST port uses `DRM_GEM_SHMEM_DRIVER_OPS`. The matching DSM
7.4-90080 GPL source contains the kernel 5.10.55 AST implementation, which
uses `DRM_GEM_VRAM_DRIVER` and selects the VRAM/TTM helpers instead. The pilot
will test that source-level change against the exact existing DSM build inputs.
It will not alter the deployed source, rebuild unrelated providers from a
different kernel, or launch the prior mmap renderer on the test device.

## Build plan

1. Create an isolated source workspace at the current DRM source revision.
2. Replace only its AST source directory with
   `linux-5.10.x/drivers/gpu/drm/ast` from the existing
   `gpl-linux-7.4-90080-epyc7002.txz` archive.
3. Use Docker Desktop and `dante90/syno-compiler:7.4`, DSM 7.4.1 build 90080,
   the epyc7002 `.config`, `Module.symvers`, and the matching DSM toolchain.
   Compile the AST driver with the DRM core and VRAM/TTM dependency closure.
   Keep unrelated GPU drivers out of this stability-focused compile.
4. Verify AST module vermagic, PCI aliases, direct dependencies, and hash.
   Confirm AST no longer depends on `drm_shmem_helper` and instead declares
   the VRAM/TTM path. Do not treat this targeted module compile as a complete
   unified release build.

## Runtime gate

The build result alone cannot establish runtime stability. On a matching,
recoverable test machine, first load the AST dependency closure and verify PCI
binding, DRM card creation, connector state, and dmesg without starting
`kms-display`. Do not use the old KMS dumb-buffer `mmap` path on DSM 5.10.55+
until a separate, controlled validation has been designed for the VRAM-backed
driver. A successful build or probe does not count as a stable KMS output test.

## Results

- Docker Desktop compilation used `dante90/syno-compiler:7.4`, eight CPUs,
  the exact DSM 7.4-90080 epyc7002 kernel headers/configuration, and the
  matching GPL AST source. The first complete-stack attempt exposed AST API
  differences. The isolated AST source was then adapted to the backport DRM
  API and compiled with its DRM/VRAM/TTM dependency closure; AST and MODPOST
  both completed successfully.
- The resulting `ast.ko` reports vermagic `5.10.55+ SMP mod_unload`, PCI
  aliases for AST2000 (`1a03:2000`) and AST2100 (`1a03:2010`), and direct
  dependencies `drm, drm_kms_helper, drm_vram_helper, drm_ttm_helper, dmabuf,
  i2c-algo-bit`. It does not declare `drm_shmem_helper`.
- Local artifact:
  `/Users/yousuk/dual-gpu-backports-ast-stability-pilot/out/ast-stability/ast.ko`
  SHA-256 `ef3120c993ccb89b6a4090f51aaa5603d3e46a8534a83b4f29679328f0b30447`.
  The AST source changes were committed and pushed to
  `dual-gpu-backports/feature/amdgpu-merge` as `41f02ca`. The artifact remains
  local and was not deployed or runtime-loaded. The successful compile only
  establishes build/API compatibility. The previous soft-lockup failure
  remains unresolved until a separately controlled runtime test.
