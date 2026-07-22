# alpine-redpill v1.4.2.0

A stability milestone. This batch grew large enough (multiple structural fixes across both mshell and xTCRP, plus one major architectural improvement) that it warranted a version jump rather than another `.1.4.1.x` point release.

## DSM `.pat` files are now radically slimmed down

A downloaded Synology `.pat` is typically 300-400MB — almost entirely a DSM OS installation payload (`hda1.tgz`, bundled `.spk` packages, etc.) that the loader-build process never touches. A full scan of every platform config in `redpill-load` confirmed the build only ever needs 5 files out of a real `.pat`: `zImage`, `rd.gz`, `GRUB_VER`, `grub_cksum.syno`, and `VERSION` (roughly 9MB combined).

This release applies that finding in two places:
- **The permanently-cached copy** (kept on disk for rebuilding the same model/revision later) is now repacked down to just those 5 files instead of the full original — about **97% smaller** (~400MB → ~10MB per cached model).
- **The build itself** now selectively extracts only those 5 files from the `.pat` instead of unpacking the entire archive into tmpfs, cutting the single largest source of low-RAM build-time OOM.

Both changes fall back safely to the original full-extraction behavior if any of the 5 expected files can't be found (verified against the archive's real listing, not assumed), so this can't silently produce a broken loader for an unusual platform/version combination.

## Other stability fixes (all reproduced and fixed on real hardware)

- **curl `-n` (`--netrc`) typo** in `redpill-load`'s extension downloader caused bundled-extension downloads (e.g. `eudev`) to fail every single time on any box without a `~/.netrc` file — not intermittent network flakiness, a structural bug. Exposed by the new download diagnostics added in v1.4.1.2.
- **`/lib64` symlink checks** used the wrong test (`-h`/`-d` on `/lib64` itself) in an environment where `/lib64` is already a real directory (from `gcompat`), causing `ln: File exists` errors on every rebuild.
- **`dialog` silently hanging on SSH sessions** to xTCRP boxes: this environment's sshd doesn't negotiate `TERM` correctly over SSH, leaving `TERM=dumb`, under which `dialog` fails to initialize and the menu loop retries forever with no visible output. `menu.sh` now falls back to `TERM=linux` when `TERM` is missing or `dumb`.
- **xTCRP regressing to the year-old `main` branch** — found and fixed twice more this round: the `xtcrp.tgz` restore URL, and `functions.sh`'s own `$build` variable (both were still branching on `is_alpine()`, a premise that no longer applies now that xTCRP and mshell share the same `alpine-redpill` branch).
- **`bspatch` losing its execute bit**: `sudo cp` doesn't preserve source permissions, and this environment's root umask stripped it down to `0700` — invisible to the `tc` user, causing "Some tools weren't available" build failures.

## Notes

- Existing v1.4.1.x users are unaffected unless they update.
- All fixes in this release were first validated in the `_t` test track (`functions_t.sh` / `build-loader_t.sh`) on real hardware (xTCRP + mshell) before being merged into production.
