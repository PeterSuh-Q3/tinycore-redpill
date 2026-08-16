# alpine-redpill v1.4.3.0

## 📋 Companion release for MSHELL Manager v1.0.7

These fixes are required for [MSHELL Manager](https://github.com/PeterSuh-Q3/mshell-manager) v1.0.7's new **"Restart to Auto Rebuild Mode"** feature to work end to end — a one-click, fully automated loader rebuild that runs entirely headless (no console, no keyboard) from the moment the box reboots into the loader-config environment.

> [!WARNING]
> Must be used together with [tcrpfriend v0.1.4q](https://github.com/PeterSuh-Q3/tcrpfriend/releases/tag/v0.1.4q). The auto-rebuild flow spans both repos — this release alone, or the friend kernel alone, is not sufficient. Mismatched versions will not exercise these fixes.

## 🔧 Non-interactive / friend-kernel build fixes

- 🔐 **TLS bypass for prerelease tag lookup**: the friend repo's pre-release tag check (used in test mode) failed TLS verification on devices without a CA certificate bundle, silently falling back to the latest release instead of the intended pre-release. `curl` now uses `-k` for this lookup, matching the file-download calls in the same function.
- 📦 **PAT cache & extension file permissions on friend kernels**: on any host named `tcrpfriend`, `FRKRNL` auto-detects to `YES`, which routes several file copies through `sudo cp` — leaving the PAT cache and extension index/recipe files root-owned and unreadable to the `tc` user that needs to read them next. Builds failed partway through with `Permission denied` / "index file ... is not readable". Fixed by loosening read/traverse permissions right after each `sudo` write, without touching ownership or the `FRKRNL` branching itself.
- 🖥️ **Build progress bar no longer errors without a controlling terminal**: `show_progress_bar()` unconditionally wrote to `/dev/tty`, which doesn't exist in a headless build (e.g. driven over `su -c` with no tty attached) — every write failed with `No such device or address`. Now falls back to stdout when no controlling terminal is available, so headless callers work cleanly and the output stays capturable by `tee`.

All three were found and verified end to end on real hardware while building and testing the auto-rebuild feature.
