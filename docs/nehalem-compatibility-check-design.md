# Nehalem compatibility checks: design

## Objective and scope

Provide two separate checks for the binaries used by MSHELL loader builds and
release images. This is a design, not evidence that these checks are implemented.
DSM SPK packages are outside scope. The target is Nehalem-compatible execution;
the existing, stricter generic x86-64 GRUB baseline check remains independent.
Nehalem and generic x86-64 baseline are not interchangeable claims.

## 1. Loader-build check

Proposed entry point: `tools/check-loader-build-nehalem.sh`.

After selected addons and modules have been assembled and before final boot
payload publication, inspect the actual generated build artifacts. Determine the
safe insertion point after tracing the current build's temporary files, commits,
failure handling, and paired `functions.sh` / `functions_t.sh` behavior. A check
failure must not damage or silently replace a previously working loader.

Default `--auto` mode reads CPU features exposed **inside the running builder**:

| Builder AVX | Builder BMI2 | Action |
| --- | --- | --- |
| present | present | Skip; report the reason and observed features. |
| absent | either | Run compatibility checks. |
| either | absent | Run compatibility checks. |
| unknown | unknown or partial | Report `UNTESTED` with reason; do not claim pass. |

Use `/proc/cpuinfo` with exact flag token matching and consider all CPUs visible
to the builder, not just the first record. Missing or inconsistent records are
unknown, not proof of support. VM CPU masking and Docker's shared host kernel
affect what the builder observes. This gate says nothing about a different target
machine. `--force` runs the checks regardless of the observed features.

Inspect actual selected files in `initrd-dsm`'s `/exts`, applicable `custom.gz`,
and FRIEND payloads where present. Identify executable ELF files and libraries,
record architecture, linkage and hashes. Record `.ko` metadata separately;
kernel-module ABI/loadability requires testing on the target DSM kernel. Record
`zImage-dsm`, DSM `rd.gz`, and other kernel/ramdisk identities without declaring
kernel compatibility from user-space instruction checks.

No automatic package install or arbitrary binary execution. Missing optional
inspection tools produce an explicit `UNTESTED` warning; the ordinary loader
build continues by default. Confirmed failures and safe publication/rollback
behavior require explicit integration testing before enforcing a hard stop.

### Always-visible final build summary

Keep detailed inspection output governed by the existing `VERBOSE` setting, but
retain the result separately and print a concise compatibility summary at the
very end of the user-visible loader build log, including when `VERBOSE` is OFF.
Integrate at the actual outer build completion/failure boundary, after ordinary
build output, rather than inside a subshell whose output may be suppressed.
Preserve the original build exit status and avoid duplicate summaries on nested
traps or multiple return paths. Record the same final result in the build log and
show the report path when a report was actually created.

The summary states observed AVX/BMI2 availability, outcome, counts of checked,
warning and untested items, and report location where available. Use `SKIPPED`
with the AVX/BMI2 reason when auto mode does not run; use `UNTESTED` for unknown
CPU features or unavailable inspection tools, with the specific reason. If the
build fails before reaching the check, show `NOT RUN — loader build failed before
compatibility check`, not PASS or SKIPPED. Final output is best effort: forced
termination, power loss, or an uncatchable signal can prevent the summary.
Verification must cover VERBOSE ON/OFF, normal success, auto skip, unavailable
features/tools, confirmed failure, build failure before the check, and unchanged
exit codes; assert that no subsequent build output displaces the final summary.

## 2. Release-image check

Proposed entry point: `tools/check-release-image-nehalem.sh`.

Always inspect the final release candidate `.img`, regardless of the build
server's CPU. Attach only the image being checked through a private loop device,
mount partitions read-only, use bounded private temporary storage, and clean up
only resources created by the check. Verify the image hash before and after.

- P1: call the existing `tools/check-grub-x86-baseline.sh` and inspect EFI/GRUB
  contents. Its compressed BIOS core and embedded EFI contents are not fully
  inspected; static success is not proof of a successful boot.
- P2: inventory present DSM boot payloads and hashes.
- P3: inventory actual FRIEND and loader payloads; inspect compressed contents
  when format and tooling permit, without assuming optional files exist.
- P4: inventory Alpine boot files and actual overlay contents, including ELF
  executables and libraries. Distinguish archive contents from installed files.

Initially inspect the raw candidate image before `.img.gz`/VMDK publication;
record provenance and checksums of derived artifacts. A VMDK conversion success
alone is not proof of equivalence. If a mandatory image, partition, GRUB check,
or required inspection tool is absent, fail the release check rather than claim
success. Uninspected nested code must remain explicitly `UNTESTED`.

## Shared inspection and safety

The two entry points may use a shared library for file identification, hashing,
safe archive handling and reporting, while retaining different inputs and
policies. Bound archive expansion, size and recursion; reject unsafe paths and
links, do not follow links outside the private extraction root, and avoid
extracting special files. Treat externally supplied image contents as untrusted.

Instruction occurrence alone is not a failure: statically linked libraries can
contain AVX/BMI code selected only on capable CPUs. Report location and evidence
as `WARN` unless the unsupported path is proven executed. Run binaries under a
Nehalem emulator only using a reviewed allowlist and safe test inputs in an
isolated environment. Never indiscriminately run installers, device utilities,
or `powersched`, which can alter RTC wake alarms. Record QEMU/CPU model, command,
exit status and `SIGILL` evidence; dynamically linked executables need a
compatible isolated runtime. Tests of selected paths do not prove all paths.

## Results and release policy

Use human-readable output plus a machine-readable JSON report. Per file and
check, distinguish `PASS`, `FAIL`, `WARN`, `UNTESTED`, and `SKIPPED`; include
source/partition/archive path, SHA-256, file type, tools and versions, CPU profile,
test scope and omissions. Store reports outside the inspected image.

`FAIL` denotes an observed failure such as a required file being missing or a
safe Nehalem execution producing `SIGILL`. Static findings alone are not proof of
execution failure. `UNTESTED` and `SKIPPED` must never be presented as `PASS`.
The release candidate should be published only after its mandatory checks pass;
the tested image and distributed artifacts must be traceable by hash.

## Implementation and validation sequence

1. Trace loader build integration and existing release workflows without changing
   behavior; identify outputs and non-destructive failure boundaries.
2. Implement file inventory, classification, bounded extraction and reports;
   preserve the current GRUB check and explicitly report its coverage limits.
3. Implement the image check and verify read-only behavior and cleanup on success,
   interruption and failure; validate image hashes before/after inspection.
4. Implement loader `--auto`/`--force` gating and test missing, mixed and masked
   feature records, absent tools, selected and unselected addons, and Docker/VM.
5. Test safe fixtures: baseline ELF, AVX-executing ELF, runtime-dispatched ELF,
   invalid ELF, nested archives, corrupt images, missing tools, and failed mounts.
6. Validate representative actual images and DSM builds. Test Nehalem execution
   and physical boot where available; test `.ko` loading on matching DSM kernels.

No implementation, package rebuild, release, or deployment is authorized by this
design document alone.
