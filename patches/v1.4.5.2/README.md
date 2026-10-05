# v1.4.5.2 previous-release rebuild patch

This patch restores the previous-version rebuild feature on the current
v1.4.5.1 code line without replacing its P3/P4 recovery or ACPI behavior.

- Patch base: current v1.4.5.1 source, commit
  `3aee1bd4` (local checkout; includes post-tag P3/P4 safety fixes).
- Feature source: v1.4.4.9 final feature snapshot
  `8ab1d8739c2ad1bc5e3732979c8a8ad50fd13168`.
- The patch changes only `menu.sh` and `menu_m.sh`: release/tag validation,
  historical shell and dependency pin loading, and the dynamic release picker.
- ACPI menu changes are deliberately excluded. Current `functions.sh` and
  `functions_t.sh` are also left untouched; the historical-session safeguards
  are inserted into the downloaded legacy files by the patched `menu.sh`.
- Binary/generated artifacts are excluded.

The patch was dry-run against the published v1.4.5.1 tag
`3f3df590`, local source `3aee1bd4`, and fetched branch head `a600f704`.
The fetched head differs from the local source only in generated binary
artifacts. Re-run the dry-run against the exact release commit before applying
to a release branch:

```sh
patch --dry-run -p1 < patches/v1.4.5.2/restore-previous-release-rebuild.v1452patch
patch -p1 < patches/v1.4.5.2/restore-previous-release-rebuild.v1452patch
```

Review the resulting shell changes and test the historical-build flow before
publishing. This is a source patch record, not an automatically activated
feature.
