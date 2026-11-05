# detourbmi2 all-modules:PML module overlay

## Scope and gate

This is a test-track change for `functions_t.sh`, not `functions.sh`. Apply the
detour archive only when the existing resolver has selected the verified
`detourbmi2` kernel profile, `all-modules:PML`, and the matching DSM platform,
release and kernel. Ordinary PML and custom-modules must remain unchanged.

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
