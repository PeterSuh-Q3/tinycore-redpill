# detourbmi2 all-modules:PML module overlay

## Scope and gate

The regular MSHELL menu and build path support this detour for DSM 7.3/7.4 on
kernel 5.10 only when the resolver rejects `all-modules:PML` solely because the
target CPU lacks BMI2. The replacement kernel and detour module overlay are
selected from exact model/platform/release/kernel metadata and pinned
SHA-256 manifests. Ordinary selections, custom-modules, and targets with BMI2
remain on their existing build paths.

For a detour build, MSHELL prepares the detour-capable loader files in the
existing `redpill-load/master` checkout. It must not fetch, reset, or switch
that checkout to another branch. Missing or incompatible loader files fail the
build rather than falling back to an unverified kernel.

## Artifact contract

There are ten platform/release archives under
`tcrp-modules/all-modules/releases/`, named
`<platform>-<DSM major.minor>-<kernel>-detour.tgz`. Select exactly one; never
embed all ten. Fetch it from the repository's main branch, validate its
SHA-256 against a published manifest, test gzip/tar integrity, and reject
absolute/traversal paths, non-module payloads, and ambiguous filename matches.
Failure must stop the build before overwriting the final initrd. Stage the
verified file at `/addons/<exact archive name>` in `initrd-dsm`.

## Two extraction points

The loader build already expands the main all-modules archive into the DSM
initrd's `usr/lib/modules` for PML. Expand the detour archive *after* the main
archive into the same directory, then verify the required early modules.
Thus the early DSM boot path sees the same overlay as the running kernel.

At the all-modules `modules` event, expand the existing main pack first and,
only when `/addons/pml_on` and the exact detour archive exist, expand that
archive into `/lib/modules` before the existing single `depmod`. A detour
marker/manifest in `/addons` must distinguish an intentional detour build from
an ordinary PML build; missing or corrupt marked packs are fatal.

At `late`, retain the current PML backup/fingerprint/restore flow. Copy the
already combined `/usr/lib/modules` tree to `/tmpRoot/usr/lib/modules` and run
the existing `depmod` there; do not extract either pack again. The IML path
and restoration of a previous PML-polluted tree remain unchanged.

## Validation

Check all ten manifest/archive pairs, path safety, duplicate module names and
vermagic/dependency compatibility. Test ordinary PML, detour PML, custom PML
and IML in isolated fixtures. On a BMI2-absent Alpine test host, verify the
chosen zImage, `/addons` marker and pack, early and late module trees,
`modules.dep`, successful loader build and backup. DSM boot/load testing is a
separate final gate; do not infer it from a successful build.

## DSM volume recovery reboot helper (design only)

### Purpose and observed evidence

On a DSM 7.4.1 migration from `epyc7002` to `geminilakenk`, vanilla modules
installed during migration may run before the loader's detour modules take
effect. A first DSM boot may consequently leave a data volume offline. The
helper may request one controlled reboot only for a persistent, recoverable
volume assembly/mount failure. It must not repair storage metadata or loop on
reboots.

The helper is gated to CPUs that do **not** advertise BMI2, and to DSM module
configurations `all-modules (PML)` or `custom-modules (PML)` as recorded in
`/usr/mshell/MODULE_TYPE`. `/usr/mshell/VERSION` must parse as DSM 7.3.0 or
later. IML, other module types, BMI2-capable CPUs, absent markers, and
unparseable versions are no-ops. Version comparison uses numeric components.
This is a dedicated addon, not a loader `on_os_load` callback or a hand-edited
`/etc/rc` script.

### Independent addon and DSM startup hook

Create a standalone addon in `tcrp-addons` with its own recipe, installer,
runtime helper, tests, and checksums. Follow the established
`junior-realtime-helper` pattern:

1. The addon's loader-time `on_os_load` installer only stages files into the
   DSM image under `/tmpRoot`; it does not perform runtime volume detection.
2. Stage the runtime helper under a dedicated path such as
   `/usr/local/libexec/mshell-volume-recovery/` and install a small
   `/usr/local/etc/rc.d/S99mshell-volume-recovery.sh` entry point.
3. DSM executes that entry point during its own boot sequence. It starts the
   runtime helper asynchronously or through a bounded wait so normal boot
   services are not blocked. The helper waits for the storage stack to settle
   and performs repeated read-only checks.

`rc.temp` is not the runtime hook name established by this design. The DSM
hook is the installed `/usr/local/etc/rc.d/S99...` script. Its ordering
relative to DSM volume assembly/mount must be confirmed on DSM 7.3 and 7.4;
`S99` naming alone does not prove that volumes are ready. Do not edit
`/etc/rc` directly.

`migrated=false` is not a sufficient trigger: it was observed on both a system
with `/volume1` mounted and writable and one where it remained unmounted.
`can_reboot_assemble=true`, `missing=false`, no faulty disks, and pool
compatibility `yes` also appeared in both states. One healthy boot logged
transient early “volume not mounted” errors before recovering. These fields
must not independently trigger a reboot.

### Detection and decision

After a bounded startup grace period, enumerate expected data volumes from
`/var/lib/space/space_table`; do not hard-code `/volume1` or mistake an
existing mountpoint directory for a mounted filesystem. The primary failure
condition is a registered, non-missing volume that remains unmounted, or is
mounted but reported unwritable by DSM's supported read-only volume check.
Verify the actual mount with `/proc/mounts`. If a volume becomes mounted and
writable during the grace period, treat the boot as healthy despite transient
early errors.

Corroborating evidence is collected, not treated as a separate reboot trigger:

- Compare the expected RAID/LVM devices and UUIDs in `space_table` with live
  `/proc/mdstat` and PV/VG/LV inventory. Missing or contradictory devices
  indicate a storage integrity/configuration issue; do not auto-reboot on
  that evidence alone.
- Review current-boot `space_operation.log`, `synobootup.log`, `messages`,
  and related DSM logs for failed/unfinished assembly or mount and ensure no
  later successful writable/mount event exists.
- Record `migrated`, `can_reboot_assemble`, `missing`, `faulty_disks`, and
  pool compatibility for diagnosis. `migrated=false` is context only.

Request reboot only when the primary failure persists and evidence shows the
expected volume metadata and devices are present and consistent, with no
missing/faulty members or later recovery event. If evidence is incomplete,
inconsistent, or indicates disk/RAID damage, log the diagnosis and leave the
system running for manual recovery.

### Bounded retry state and audit

Do not use a permanent `reboot-attempted` marker. A stale marker on the test
system blocked a later migration because every subsequent run exited before
making a new decision. The helper now ignores that legacy file and uses a persistent
retry ledger scoped to DSM release/build, model, module type, and registered
pool/RAID/volume identities.

The retry ledger permits at most two automatic reboot requests for one
unresolved identity and only one request per kernel boot ID. A healthy,
mounted-and-writable volume set clears it. A changed identity or a new
`IS_FIRST_LOGIN_AFTER_UPGRADE=1` event in `synobootup.log` begins a fresh retry
series. The test-system log contained such an event at 15:38, after its stale
marker was created at 13:10. After the two-attempt budget is exhausted, leave the
system running until health returns or a new migration/identity event is
observed. The addon implementation and detailed limitations are documented in
`tcrp-addons/mshell-volume-recovery/DESIGN.md`.

Write a timestamped `/var/log` record with the gate results, DSM version,
module type, CPU BMI2 result, volume IDs/mount paths, state flags, mount and
writability checks, RAID/LVM consistency summary, relevant storage events,
retry count, identity/event reset reason, and reboot decision. Do not log
credentials or mutate storage metadata. Persist retry state atomically before
requesting reboot; if it cannot be written and verified, do not reboot.

### Validation still required

- Compare same-device post-migration and post-reboot snapshots of
  `space_table`, pool compatibility, mount state, RAID/LVM inventory, and
  storage event logs.
- Confirm a reliable read-only volume-writability command on DSM 7.3/7.4,
  including exit codes when the mount is absent.
- Verify the rc.d hook's execution identity and timing relative to
  `syno-volume.target` and package-volume readiness, system-volume
  writeability, retry-state persistence, and event detection across migration
  boots.
- Exercise healthy delayed mount, persistent recoverable failure, BMI2-capable
  CPU, each eligible PML type, ineligible module types/version, exhausted retry
  budget, new upgrade event, changed identity, missing/faulty RAID member, and
  malformed state in a disposable environment. Do not invoke real-device
  reboot until these checks pass.

This document is design guidance; the runtime implementation is in the
`tcrp-addons/mshell-volume-recovery` addon. The bounded retry changes described
here are source-side only and have not been deployed to a DSM device. Validate
the retry-state and migration-event behavior before relying on automatic
reboots outside the disposable test environment.
