# alpine-redpill v1.4.2.9

## Important BTRFS emergency recovery requirement

Synology's official PC recovery guide specifies Ubuntu 18.04 for DSM BTRFS and ext4 volume recovery. Ubuntu 18.04 uses the Linux 4.15 kernel family. Synology does not publish the kernel-version rationale, but DSM BTRFS behavior is not fully interchangeable with the standard Linux BTRFS implementation. In practice, newer generic Linux kernels can show compatibility problems with DSM BTRFS volumes. Linux 4.14.167 is the closest available lower kernel family for this Alpine recovery implementation, so it is used as the compatibility-focused alternative for emergency read-only access. This release does not claim to replace Synology's supported Ubuntu procedure. Back up the source disks first, prefer read-only degraded mounts, and do not run destructive repair commands such as `btrfs check --repair` without a verified recovery plan.

## Alpine 3.8 kernel 4.14 recovery environment

This is the Alpine adaptation of the recovery design introduced for [TinyCore v1.2.5.1](https://github.com/PeterSuh-Q3/tinycore-redpill/releases/tag/v1.2.5.1). The former TinyCore rescue path is replaced by a self-contained Alpine 3.8 recovery image that uses Linux 4.14.167. This provides an alternative Linux userspace for discovering and mounting DSM BTRFS volumes for emergency data access without requiring a separate Ubuntu boot medium.

The recovery image includes the complete Alpine rootfs, BTRFS tools, md RAID and LVM activation, and read-only `ro,degraded` BTRFS mounting. The volume menu detects BTRFS and ext4 signatures using Alpine-compatible `blkid` parsing and mounts the selected logical volume under `/mnt`.

## Recovery workflow reference

The following legacy TinyCore v1.2.5.1 captures document the recovery workflow reused by this Alpine implementation. They show the volume selector, a successful read-only mount, and the mounted volume contents. The main menu and boot-entry labels in those captures are legacy labels and do not represent the current Alpine 3.8 menu.

![Legacy mountvol volume selector](https://github.com/user-attachments/assets/c3c6d3d5-b012-4969-8f0e-9b8a40e26a5b)

![Legacy mountvol successful BTRFS mount](https://github.com/user-attachments/assets/46251bfc-35d3-4eee-bcfc-74397a5c4934)

![Legacy mounted BTRFS volume contents](https://github.com/user-attachments/assets/3a70ba2f-406c-4ab6-8646-2c4465b68980)

## Storage and network readiness

OpenRC now starts the module service before recovery actions. The image loads common SATA, NVMe, SCSI, SAS/RAID, USB storage, SD card, virtual storage, RAID, device-mapper, BTRFS, ext4 and FAT modules. The missing `af_packet` module is restored from the matching kernel package so BusyBox DHCP works. Networking starts automatically with DHCP on eth0, enabling SSH access after the recovery environment boots.

The image also initializes devtmpfs and sysfs, limits consoles to the primary local and serial consoles, preserves a usable tc account, and avoids TinyCore-specific mount and process-substitution assumptions.
