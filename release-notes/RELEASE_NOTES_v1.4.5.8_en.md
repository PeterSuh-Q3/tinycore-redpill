# alpine-redpill v1.4.5.8

## See the installed DSM system while diagnosing a loader

When a loader boots but DSM is difficult to diagnose, the selected model alone does not show which DSM version is actually on the disks or which system partitions belong together. The system monitor now shows the selected Synology model alongside the installed DSM version, followed by the md0 RAID members on one line. If md0 cannot be assembled read-only, the monitor reads a matching RAID1 member without changing the disk and explicitly labels the array state **unverified**; the member list is not a health check. Missing or `None` board fields and systems without swap no longer produce empty monitor rows.

## Carry the board identity into DSM

Some DSM environments do not expose the physical board's DMI information, leaving tools without the identity captured during loader setup. A new loader build now places the saved `general.board` value in `/addons/DMI`. When the `cpuinfo` addon is included and that file exists, its boot hook copies the snapshot to `/usr/mshell/DMI` for DSM-side readers. **Rebuild the loader** to include this snapshot; an automatic build that has no saved `general.board` leaves DMI absent rather than inventing a board identity.

## Keep xTCRP image and disk operations easier to use

The xTCRP image workflow now authenticates its lookup for an earlier release with a downloadable base image, avoiding failures caused by an anonymous release query. Loader injection and removal are now grouped with the other Synology disk and partition actions, where users can find them when working on a disk.
