# alpine-redpill v1.4.3.3

## 💽 "Inject Bootloader to Syno DISK" repaired end-to-end, including >2TB GPT disks

This menu feature builds a bootable FRIEND-kernel entry directly onto a Synology data disk's leftover SHR/GPT space, without needing a separate USB/SATA loader. It had accumulated several bugs that only showed up on real hardware; all of them were found and fixed this round through repeated live testing, including a full successful run on a >2TB GPT disk.

- 🔧 **GPT (>2TB) disks now inject correctly.** A hardcoded `/usr/local/sbin/gdisk` path left over from TinyCore made `sudo` fail outright on Alpine (`gdisk` actually lives at `/usr/bin/gdisk`), and the `tce-load` compatibility shim only ever installed `gptfdisk`, never the separate `sgdisk` package `remove_loader()` needs — both are fixed.
- 🧭 **New partitions now land in the right free space.** On newer `fdisk` (util-linux 2.42.1+), the old fixed sector-offset math could get rejected ("Sector X is already allocated"), which desynced the script's automated answers and made it silently fall back to the wrong, undersized gap. Sector math is now computed dynamically, and the interactive "wipe existing filesystem signature?" prompt no longer desyncs automation either.
- 🩹 **Fixed a cluster of real-hardware crashes**: missing `sudo` on partition-boundary calculations, `blockdev --rereadpt` failing with "Resource busy" against a still-assembled md/LVM stack (new automatic stop-and-retry), `mkfs.vfat -F16` silently failing on small partitions, `remove_loader()` leaving stale mounts behind, and an unbound-variable crash when running this feature standalone.
- 🧹 **Removed a doomed step**: the old `xtcrp.tgz` download + grub entry never actually fit in the space available and has been dropped from the injection path entirely.
- 📊 **Clearer space accounting**: partition 4 now shows a per-file size breakdown for the FRIEND kernel files (matching how partition 7 already showed it), and the "space used" log for partition 7 no longer reports the whole loader partition's usage as if it were the transfer size.
- 🖱️ Disk selection and confirmation prompts now use the dialog UI instead of plain text prompts.

## 📦 MSHELL Manager and Syno Smart Info now update themselves automatically

Both add-on packages now fetch their latest release directly from their own public GitHub Releases at build time — the same mechanism already used for the AMD GPU runtime add-on — instead of a version-pinned copy that had to be manually re-committed into this repo on every release. Nothing changes for end users; new versions of either package now simply show up in the next loader rebuild, with no lag.

## 🧹 Other small fixes

- `firmwareamdgpu.tgz` (roughly 28% of the DSM ramdisk) is now only included when an AMD GPU is actually detected on the build machine, instead of unconditionally.
- Fixed a stale hardware-exclusion list in the default SATA port mapping that had drifted out of sync with the platforms it was supposed to cover (epyc7002/epyc7003/epyc7003ntb/icelaked were missing).

All of the disk-injection fixes above were verified end to end on real hardware, including a full disk-injection run that completed without errors.
