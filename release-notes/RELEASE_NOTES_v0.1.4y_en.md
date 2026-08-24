# v0.1.4y (Pre-release)

## Automatic rebuild and package update improvements

- Added the automatic rebuild path used by MSHELL Manager's headless loader rebuild.
- The rebuild flow now explicitly enables non-interactive mode before calling `my()`, allowing `getlatestmshell()` to run with `noask` and complete without waiting for terminal input.
- Improved latest-package resolution and checksum handling so the rebuild can stage the exact SPK selected by the release metadata instead of relying on an old local copy.
- Added clearer handling and logging when release metadata, downloads, or SHA-256 verification fail. A failed optional package download no longer silently breaks the rest of the loader build.
- Refreshed the model and release metadata used by automated builds so a stale session copy is not reused accidentally.

This release is intended for validation of the automatic rebuild/update flow. It is a pre-release and should not be treated as the stable loader release until the full real-hardware test cycle is complete.
