# alpine-redpill v1.4.1.0

A follow-up fix release on the `alpine-redpill` line, focused on making the Alpine build environment usable on low-memory hardware and cleaning up a handful of rough edges found after v1.4.0.0.

## Low-RAM (2GB) build environment no longer runs out of memory

The most significant fix in this release. On systems with 2GB of RAM allocated to the build environment, the loader-build process (`redpill-load`) could run out of memory partway through and get silently killed by the kernel's OOM killer — sometimes as an outright crash of the GUI session, sometimes as a package-install failure ("No space left on device").

Root cause: Alpine's diskless root filesystem is tmpfs-backed, and by default the kernel caps it at 50% of total RAM. TinyCore, by comparison, allowed its tmpfs root to grow to roughly 90% of RAM and additionally shipped its own compressed, read-only extension mounts, giving it a much larger effective working set on the same hardware.

Fix, applied automatically only when total RAM is 2.1GB or less:
- The root tmpfs ceiling is raised from the kernel default (50%) to 90%, matching TinyCore's behavior.
- A 1GB disk-backed swap file is created on the existing reserved 3rd partition (previously left empty) — real disk capacity beyond physical RAM, unlike RAM-backed alternatives such as zram, which was tried first and found insufficient under real memory pressure.

Verified with a full, unattended DSM loader build (SA6400 platform) completing successfully on 2GB of RAM, with no OOM-killer events, before and after this fix (the "before" run reliably failed).

## Other fixes

- **Menu no longer exits on ESC/Cancel.** Pressing Esc or Cancel in the main mshell menu used to drop straight back to the shell. It now just redraws the menu; exiting is only possible through the menu's own "Exit" item.
- **GRUB background image path.** The loader-build boot menu's background image lookup pointed at the (now-empty) 3rd partition instead of the 4th (`alpine`) partition where it actually lives, so the background was silently missing.
- **Removed a dead, unreachable code branch** in the fdisk path-resolution logic that referenced an undefined variable.

## Notes

- Existing v1.3.1.1 (TinyCore) and v1.4.0.0 users are unaffected unless they explicitly update.
- The RAM/swap tuning only activates on systems with ≤2.1GB RAM; systems with more memory are untouched.
