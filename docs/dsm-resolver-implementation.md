# DSM resolver P0 implementation

The runtime now uses an offline catalog instead of the revision whitelist and
custom-module version cap. This is a loader selection gate, not certification of
DSM 7.4.2 or of the Friend update path.

## Files and contract

- `tools/dsm-target-resolver.sh`: stdin JSON → stdout JSON; exit 0/2/3/4/5/6.
- `tools/dsm-target-resolver.jq`: identity/options/list/validate, numeric tuple
  ordering and per-mode CPU requirements. No network or configuration writes.
- `tools/dsm-resolver-bridge.sh`: runtime CPU collection, CLI adapters, selected
  module recipe pinning through a local `file://` index.
- `config/dsm-targets.v1.json`: 1,940 model/release/channel targets and 180 shared
  recipes imported from committed local redpill-load/tcrp-modules revisions.
  Source SHAs are embedded. Existing uncommitted module recipe edits were not imported.
- `tools/compile-dsm-targets.py`: validates references and emits deterministic,
  reviewable catalog lines; `--source` accepts reviewed catalog data.
- `schemas/dsm-targets.v1.schema.json`: structural contract; the compiler also
  checks tuple identity, duplicate targets/modes, recipe references and file hashes.

Runtime failures leave selection settings intact. `identity` only resolves
metadata. `validate` is mandatory at CLI and common build entry points. IML/PML
is part of the mode identity. No-DRM general packs inherit the general pack's
conservative BMI2 requirement on the affected K5 release families.

The initial catalog is a migration snapshot, not a new runtime test result.
`inherited-supported` means prior supported policy plus matching committed
PAT/config/recipe records. Missing platform configs or recipes are not invented.
No new DSM release is enabled by online discovery or an existing `_74_` key.

For a reviewed future release, add an exact target with its PAT, platform config,
kernel and approved modes; mark it `verified` only after the required validation.
Then run:

```sh
python3 tools/compile-dsm-targets.py --source reviewed-catalog.json --output config/dsm-targets.v1.json
python3 -m unittest discover -s tests/dsm-resolver -p 'test_*.py' -v
```

`--import-legacy /path/to/repository-parent` is a one-time migration facility, not
a release discovery or approval command. It uses HEAD objects of adjacent repos.
The compiled snapshot is currently maintained here; moving its reviewed source
into redpill-load's central catalog remains the later cross-repository phase.

## CPU input for remote builds

Local builds intersect all CPU flag records from `/proc/cpuinfo`. Missing CPU data
is unknown, not BMI2 present. Docker and block-device build environments default
to unknown and do not assume the builder CPU represents the destination.

Set `MSHELL_TARGET_CPU_JSON` to a target-collected JSON file for remote builds:

```json
{"flags_known":true,"flags":["bmi2"],"source":"target-snapshot"}
```

The example is a format example, not a statement about any device. Collect the
actual destination capabilities before using it. Unknown CPUs may select only
modes with explicit empty extra CPU requirements. Existing remote launchers do
not automatically collect/transport this new file yet.

## Recipe and distribution behavior

The chosen module recipe is stored in `/home/tc/dsm-selection/selection.lock.json`
and a local index is applied after extension collection, before build-loader.
The existing ext-manager verifies payload SHA-256. Raw tcrp-modules payload URLs
are pinned to the catalog's source commit when online; an offline mirror retains
its existing path mapping and must still satisfy the pinned payload hashes.
Other addon/LKM/patch catalogs are outside this P0 lock.

The my.sh.gz/apkovl workflow includes the new readers and catalog. Standalone
menu.sh helper updates first stage and validate their dependencies. An interrupted
dependency installation leaves a marker that blocks builds. Recovery bootstrap
is still available. Previous-release restore includes dependencies when the
selected release uses the resolver. my.sh.gz remains tracked at its original URL;
no binary release archive was regenerated or published during implementation.

## Validation and limits

Local tests cover missing/unknown releases, cross-build mismatches, BMI2/unknown
CPU modes, legacy kernel identities, data-only hypothetical release extension,
numeric sorting, bad schema/missing recipe, paired helpers, stale-global cleanup,
remote CPU behavior and canceled selection. Compiler round-trip is deterministic.

The Linux-only ext-manager integration test uses local payloads and no NAS. It
is included in the added CI workflow (not dispatched). On this macOS host the
initial integration attempt stopped at GNU cp options; Docker daemon was not
reachable. That test is explicitly skipped on non-Linux hosts. Real loader image
creation, NAS boot, remote launcher capability transport and Friend auto-update
have not been validated by these tests.
