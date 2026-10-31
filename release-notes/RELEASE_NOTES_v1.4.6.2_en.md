# alpine-redpill v1.4.6.2

## Boot compatibility for older x86 processors

Some systems with older processors, including the Intel Celeron J1900, could not start the v1.4.6.1 UEFI loader because its GRUB bootloader contained instructions their CPUs do not support. The image build now targets a broadly compatible x86 baseline and checks the GRUB EFI executable and installed modules for the instruction families involved. This is intended to let affected systems reach the Alpine loader again; booting the rebuilt release on the affected hardware is still recommended to confirm the fix.

## More dependable DSM system-partition checks

The status screen could report the loader's selected model instead of the DSM model actually installed on the system partition. It now reads the installed model from md0. The md0 expansion action also handles auto-assembled, read-only system arrays more carefully: it only releases arrays made exclusively from the selected system partitions, refuses mounted or mixed arrays, and verifies that the filesystem grew before reporting success. These checks help users diagnose model mismatches and avoid a false “expansion complete” result when a small DSM system filesystem can block installation or upgrades.

## SataPortMap and DiskIdxMap assistant

Disk order can be difficult to plan when a system uses multiple SATA controllers or an SAS HBA. The new assistant displays the storage controllers and detected disks, and helps prepare SATA mapping candidates for review before saving them. When the SATA bootloader location is detected, its controller and ATA position are shown and its physical port is included in the controller's suggested count; the bootloader disk is not treated as a DSM data disk.

The controller order and port counts must be independently verified against DSM. Detected disks and loader enumeration do not establish DSM slot order, the number of usable ports, or the position of SAS disks. The initial port-count suggestion is based on detected disks and may need correction, especially when ports are empty.

The assistant preserves existing SAS settings and can restore the previous SATA mapping. Mapping changes can affect disk order; review the proposed values and keep a recoverable backup before applying them.

When booting DSM through FRIEND, saved command-line settings are read at the next boot without rebuilding the loader. Direct GRUB boot and `sata_remap` delivery through FRIEND remain to be verified; do not rely on them until tested.

The monitor display also aligns the board version consistently and makes GPU names easier to read.
