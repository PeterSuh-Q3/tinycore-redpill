# alpine-redpill v1.4.2.9

## ⚠️ BTRFS emergency recovery guidance

Synology's official PC recovery guide designates Ubuntu 18.04 for DSM BTRFS and ext4 volume recovery. Ubuntu 18.04 uses the Linux 4.15 kernel family.

Synology does not publish the kernel-version rationale. In practice, DSM BTRFS behavior is not fully interchangeable with standard Linux BTRFS, and newer generic kernels can show compatibility problems with DSM BTRFS volumes.

This release uses Linux 4.14.167, the closest available lower kernel family, as a compatibility-focused Alpine recovery implementation. It does not claim to replace Synology's supported Ubuntu procedure.

> [!WARNING]
> Back up source disks first. Prefer read-only degraded mounts. Do not run destructive commands such as `btrfs check --repair` without a verified recovery plan.

## 🛠️ Alpine 3.8 recovery environment

This is the Alpine adaptation of the recovery design introduced for [TinyCore v1.2.5.1](https://github.com/PeterSuh-Q3/tinycore-redpill/releases/tag/v1.2.5.1).

- Replaces the former TinyCore rescue path with a self-contained Alpine 3.8 image.
- Uses Linux 4.14.167 for DSM BTRFS emergency access.
- Includes the complete Alpine rootfs, BTRFS tools, md RAID assembly, and LVM activation.
- Mounts selected BTRFS volumes read-only with `ro,degraded` under `/mnt`.
- Detects BTRFS and ext4 signatures with Alpine-compatible `blkid` parsing.

## 📦 Storage and network readiness

- Starts the OpenRC module service before recovery actions.
- Loads common SATA, NVMe, SCSI, SAS/RAID, USB storage, SD-card, virtual-storage, RAID, device-mapper, BTRFS, ext4, and FAT modules.
- Restores the missing `af_packet` module from the matching kernel package so BusyBox DHCP works.
- Starts DHCP automatically on `eth0` for SSH access after boot.
- Initializes devtmpfs and sysfs, limits consoles to the primary local and serial consoles, and avoids TinyCore-specific mount and process-substitution assumptions.

## 🖼️ Recovery workflow reference

The following legacy TinyCore v1.2.5.1 captures show the workflow reused by this Alpine implementation. The menu and boot-entry labels in the captures are legacy labels, not the current Alpine 3.8 menu.

**1. Select a logical volume**

![Legacy mountvol volume selector](https://github.com/user-attachments/assets/c3c6d3d5-b012-4969-8f0e-9b8a40e26a5b)

**2. Confirm the read-only BTRFS mount**

![Legacy mountvol successful BTRFS mount](https://github.com/user-attachments/assets/46251bfc-35d3-4eee-bcfc-74397a5c4934)

**3. Access the mounted volume contents**

![Legacy mounted BTRFS volume contents](https://github.com/user-attachments/assets/3a70ba2f-406c-4ab6-8646-2c4465b68980)
