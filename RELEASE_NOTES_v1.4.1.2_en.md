# alpine-redpill v1.4.1.2

Diagnostics and low-RAM swap improvements, plus a small menu usability fix.

## Build failures now show what actually went wrong

Previously, a failed build only showed the last 10 lines of the log — usually just a generic "Loader creation failed" wrapper message, with the real cause (cpio failure, download failure, memory exhaustion) scrolled off-screen. This happened regardless of Verbose Mode, since the summary screen only ever tailed the log.

Build failures now always display (independent of Verbose Mode):
- Error-relevant lines extracted from the build log (not just the last 10)
- cpio/ramdisk-repack failure detail (previously captured to `/tmp/strerr.log` but never shown)
- Download failure diagnostics (HTTP code, DNS/connect/TLS timing, curl's own error message)
- A memory/ramdisk snapshot taken at the moment of failure: RAM, swap, tmpfs usage, and whether the kernel's OOM-killer fired — with a one-line verdict so you can immediately tell whether the failure was memory-related

`monitor()` also now shows ramdisk (tmpfs) size and usage alongside RAM, not just RAM/swap.

This was validated by deliberately reproducing a real OOM (and, on real hardware, a kernel panic — `System is deadlocked on memory`) under a 2.2GB RAM configuration.

## Low-RAM swap: zram added as a fast first tier

Low-RAM (≤2.1GB) configurations now layer a zram device (priority 200) in front of the existing disk-backed swapfile (priority 100, 1.5GB). Light swapping is absorbed by fast, RAM-based zram first; only genuine overflow spills to the disk swapfile. This reduces swap latency and cuts down on writes to the USB/SD boot media, while the disk swapfile still provides the real capacity headroom beyond physical RAM that zram alone cannot (zram merely compresses within existing RAM).

`cleanupmemory()` was updated to cycle all active swap devices (not just one), preserving each device's priority.

## Other fixes

- Fixed xTCRP (Buildroot friend-kernel) boxes silently falling back to a year-old `main` branch for `functions.sh` instead of the actively-maintained `alpine-redpill` branch.
- Added a "메뉴종료 (exit menu)" item to the main menu, for exiting back to the shell without powering off the machine (previously the only exit option was Power Off).
- Corrected `tcrp-modules`/`tcrp-addons`/`rp-ext` branch references from `master` (which doesn't exist in those repos) to `main`.

## Notes

- Existing v1.4.1.1 users are unaffected unless they update.
