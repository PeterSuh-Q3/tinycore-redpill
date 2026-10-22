# DSM post-boot SPK delivery design

## Goal

Do not embed the MSHELL Manager, Syno Smart Info, or conditionally selected
AMD GPU Runtime `.spk` payloads in `initrd-dsm`. Keep only their small,
build-time-pinned installation metadata and the `aeudev` bootstrap scripts in
the loader. Download, verify, and install the SPKs after DSM has started.

The AMD GPU Runtime remains conditional: the loader records its metadata only
when AMD GPU, DSM 7.4, supported-platform, and kernel checks pass. This does
not expand the published compatibility matrix. Runtime staging is limited to
supported platforms on kernel `5.10.55`; kernel `4.4.x` remains excluded.

## Current behavior confirmed in source

- `buildloader()` in `functions.sh` reads
  `tcrp-modules/aeudev/recipes/latest.json`, downloads the MSHELL Manager and
  Syno Smart Info SPKs into the ramdisk `/addons`, and writes small JSON
  metadata beside them.
- The same function calls `tools/install-amdgpu-addon.sh`. When its hardware,
  platform, and kernel checks pass, that helper currently downloads the AMD
  Runtime SPK into `/addons` and writes its metadata.
- `aeudev/releases/install.sh` runs at `on_os_load`, copies metadata into DSM's
  `/usr/local/etc/rc.d`, and generates DSM startup hooks. The new shared
  `postboot-spk-install.sh` worker is installed under `/usr/local/libexec`.
  Hooks are generated from metadata alone; no `.spk` payload is copied into
  DSM's system root.
- `aeudev/recipes/latest.json` already records release URLs, names, sizes, and
  SHA-256 values. `aeudev/recipes/universal.json` delivers `install.sh` and
  `latest.json` to the extension.

## Target flow

1. **Build time:** select and validate package metadata from the pinned
   `latest.json`; do not download any of the three SPK payloads. Write the
   selected package metadata to `/addons` in the ramdisk. Metadata must include
   package ID, version, file name, immutable release URL, expected byte size,
   SHA-256, and applicable platform/kernel constraints.
2. **AMD selection:** preserve the current PCI detection and compatibility
   gates. `tools/install-amdgpu-addon.sh` becomes a metadata-selection/writer
   helper; it must not fetch the large runtime SPK during loader construction.
   Write no AMD metadata when no supported AMD GPU/asset combination is found.
3. **DSM root staging:** `aeudev/releases/install.sh` stages each available
   metadata record and creates its package-specific DSM hook from metadata
   alone. No `.spk` is copied from `/addons` because none should be present.
4. **DSM runtime:** each hook waits for DSM package services, a usable network,
   and an available package-install destination. It downloads to a temporary
   file on persistent storage, verifies size and SHA-256, then atomically
   finalizes the cache file before invoking `synopkg`.
5. **Lifecycle and retries:** keep package jobs independent and idempotent.
   Preserve the current Manager version/legacy package-ID migration behavior
   and the Smart Info version behavior. Add the same safe download, validation,
   and retry lifecycle to AMD Runtime. A transient failure must leave enough
   metadata/worker state for a bounded retry during the current boot and on a
   later boot; it must not cause an endless boot-blocking loop. Record the
   state and actionable failure reason in DSM logs.
6. **Trust boundary:** DSM consumes only the URL and digest pinned into the
   loader at build time. Do not fetch a mutable `latest.json` at DSM boot.
   Prefer strict HTTPS certificate validation; checksum and size mismatches
   must discard the temporary payload and prevent installation.

## Files and functions affected

| Repository / file | Function or section | Required change |
|---|---|---|
| `tinycore-redpill/functions.sh` | `buildloader()` package-manifest staging block | Stop downloading Manager and Syno Smart Info `.spk` files. Write metadata including size. Keep manifest validation and pinned release URL/SHA checks. Continue invoking the AMD helper only for the existing conditional selection. |
| `tinycore-redpill/functions_t.sh` | Paired `buildloader()` package-manifest staging block | Apply the same change as `functions.sh`; the two helper tracks must remain synchronized. |
| `tinycore-redpill/tools/install-amdgpu-addon.sh` | `stage_amdgpu_package()` and AMD selection flow | Preserve GPU/platform/kernel checks and asset selection, but emit metadata (including size) instead of downloading the SPK. No metadata when the current compatibility conditions fail. |
| `tcrp-modules/aeudev/releases/install.sh` | `on_os_load` staging and generated Manager, Smart Info, and AMD Runtime rc.d hooks | Copy metadata only, then generate independent launchers from metadata. |
| `tcrp-modules/aeudev/releases/postboot-spk-install.sh` | Shared DSM runtime worker | Download to a mounted DSM volume, validate size/SHA-256, atomically finalize the cache, wait for DSM/package-volume readiness, install through `synopkg`, preserve Manager legacy migration and AMD start behavior, and leave a bounded retry hook on transient failure. |
| `tcrp-modules/aeudev/recipes/latest.json` | package asset records | Source of pinned version, URL, file name, size, and SHA-256. Keep the records current and valid; this file is already consumed at build time. |
| `tcrp-modules/aeudev/recipes/universal.json` | `files` list and checksums | Ship the new post-boot worker with `install.sh` and `latest.json`; refresh checksums whenever either script changes. |
| `tcrp-modules/aeudev/tests/test-postboot-spk-delivery.sh` | Mock DSM delivery test | Verify metadata-only staging, no SPK copied into the system tree, successful post-boot install, pending retry on no-volume/network/checksum/install failures, cache reuse, and AMD compatibility gating. |

The following are explicitly out of scope unless implementation reveals a
dependency: `nvidiadriver`, `nvidia-spk-index.json`, NVIDIA package delivery,
AMD GPU module loading, `models.json`, and general DSM package policy.

## Risks and mitigations

- **DSM has no internet or GitHub access:** the new SPK cannot be installed.
  Keep the loader usable, report the pending package clearly, retain the
  installer metadata, and retry without blocking DSM startup indefinitely.
- **Volume/package services are late:** wait for them before downloading or
  calling `synopkg`; do not store the large AMD SPK on the DSM system partition
  or in a memory-limited temporary filesystem.
- **Mutable or corrupted release asset:** pin URL, expected size, and SHA-256
  at build time; install only after all checks pass.
- **Partial download or interrupted boot:** use a `.part` file and atomic
  rename; never treat an incomplete file as cached or installed.
- **Regression in package ownership/lifecycle:** preserve the Manager's
  install-before-uninstall migration behavior, and test already-installed,
  current-version, upgrade, and retry paths for all package types.
- **Incorrect AMD inclusion:** keep the existing no-GPU, unsupported-platform,
  and kernel-4 exclusions and verify them at build time; recheck the recorded
  platform/kernel and hardware condition before installation where practical.

## Validation and acceptance criteria

1. For Manager and Syno Smart Info builds, inspect the final `initrd-dsm` CPIO
   listing and verify that neither `.spk` is present while both metadata files
   and the `aeudev` worker are present.
2. For a qualifying AMD GPU + supported platform + kernel `5.10.55`, verify
   that AMD Runtime metadata is present and its `.spk` is absent from
   `initrd-dsm`. For no AMD GPU, unsupported platform, kernel `4.4.x`, or
   missing release asset, verify no AMD Runtime metadata is emitted.
3. Test DSM runtime with network available, network unavailable, no available
   package volume, unavailable `synopkg`, HTTP failure, wrong size, wrong
   SHA-256, interrupted download, and successful install. The checked-in mock
   harness covers representative delivery, checksum, volume, and install
   retry paths; real DSM is still needed to validate Synology service timing.
4. Test already-current and upgrade behavior, each package independently, and
   verify that a failure in one package does not suppress the other jobs.
5. Confirm logs make it clear whether each package is skipped, waiting,
   downloading, verified, installed, or pending retry.
6. Compare the final `initrd-dsm` size with the baseline. The expected savings
   are approximately 14.16 MiB for Manager + Smart Info, plus approximately
   189.10 MiB on builds that currently include the kernel-5 AMD Runtime SPK;
   exact savings vary with CPIO record overhead and artifact versions.

## Implementation and test status

Implementation now spans the `tinycore-redpill` and `tcrp-modules`
repositories. The checked-in aeudev mock test exercises hook generation,
payload-free root staging, verified volume download/install, and retry paths.
That test does not substitute for a real DSM boot: actual `synopkg` readiness,
the package-volume symlink/free-space decision, and DSM rc.d timing still need
validation on a disposable DSM 7.4 test instance.
