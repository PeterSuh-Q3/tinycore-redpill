# alpine-redpill v1.4.4.3

## Alpine startup reliability

- Removes the fixed `/dev/vda` to `/media/vda` mount entry from the Alpine overlay. Systems without a virtio disk no longer report a boot-time local-filesystem mount failure.
- Synchronizes the system clock with NTP before the first HTTPS package restore. This avoids package-repository and GitHub certificate validation failures when an appliance RTC/BIOS clock is years behind.
- If time synchronization cannot succeed, HTTPS package restoration is skipped with a clear message while the local recovery environment remains available.

## Fresh-install ramdisk patch family migration

- Updates the 006 fresh-install disk-ready wait bypass to use two patch families that match the DSM `linuxrc.syno.impl` source layout.
- DSM 7.0.1 through 7.2.2 use the legacy-family patch, while DSM 7.3.0 through 7.4.1 use the modern-family patch.
- Retires the former DSM 7.4.1-only and 90080-plus-only patch paths. The two existing atomic patch-set names remain unchanged and now resolve to their corresponding family path.
- All supported platform configuration files now select the appropriate family for DSM 7.0.1, 7.1.x, 7.2.x, 7.3.x, 7.4.0, and 7.4.1.
- Both families were verified with dry-run application against real DSM source samples.

## Upgrade and validation notes

- The V2 ramdisk patch-family structure is intended to become the default configuration when the related `redpill-load` branch is promoted to `master`.
- DSM 6.2.4-25556 remains outside this migration because an original source sample was not available for dry-run validation.
- New DSM releases must be added only after dry-run validation against their original ramdisk source; do not assume compatibility from the nearest existing release family.
