# alpine-redpill v1.4.0.0

The first release built on the new **alpine-redpill** branch. Starting with this version, the loader's runtime environment has been migrated from TinyCore Linux (glibc) to **Alpine Linux (musl)**.

`tinycore-redpill` on the `main` branch is now frozen at **v1.3.1.1** and will receive no further feature updates (existing v1.3.1.1-and-earlier users keep receiving automatic updates through that line as before). Anyone starting fresh from v1.4.0.0 onward follows the `alpine-redpill` line.

## Why did the image size change from 2GB/4GB to 3GB/5GB?

Short answer: **a new 4th partition was added, and it adds 1GB.**

The loader image previously shipped 3 partitions:

| # | Contents |
|---|---|
| 1 | GRUB (BIOS + UEFI), `grub.cfg` |
| 2 | (unchanged) |
| 3 | Reserved (previously carried TinyCore runtime files; now left empty) |

Building/regenerating the redpill loader itself now requires an actual Alpine Linux runtime environment (this is what the old TinyCore desktop environment used to provide). Rather than depending on an internet connection every time, a **4th partition (label `alpine`, 1024MB)** was added, containing:

- `vmlinuz-lts` / `initramfs-lts` / `modloop-lts` — a full Alpine Linux diskless boot set
- `repo-main` / `repo-community` — a local, offline mirror of the Alpine package repositories
- `localhost.apkovl.tar.gz` — the pre-configured environment overlay (users/services/tools needed for loader building)

GRUB's new **"Alpine Redpill Image Build"** menu entry boots straight into this partition, giving you a fully self-contained Alpine environment for building/rebuilding the loader — no separate USB, no internet dependency, no manual setup.

That extra 1GB partition is the entire reason the base sizes moved:
- **2GB variant → 3GB** (2GB original content + 1GB Alpine partition)
- **4GB variant → 5GB** (4GB original content + 1GB Alpine partition)

Nothing else about the original partition layout's *capacity* changed — partition 3, which used to carry TinyCore-era files, is now left completely empty (no more copying legacy content into it during the build).

## What do we gain by moving to Alpine Linux?

- **Far smaller footprint.** Alpine is built on musl libc + BusyBox, a small fraction of the size of TinyCore's glibc-based userland for equivalent functionality.
- **Modern, fast package management.** `apk` replaces TinyCore's `.tcz` extension system, with proper dependency resolution and a much more actively maintained package set.
- **Actively maintained upstream.** Alpine ships frequent security and kernel updates; TinyCore's release cadence had slowed considerably in comparison.
- **Modern kernel, broader hardware support.** The `-lts` kernel line brings current driver support out of the box, compared to TinyCore's aging kernel base.
- **Cleaner init system.** OpenRC service management replaces a pile of ad-hoc `bootlocal.sh`/`bootsync.sh` shell logic, making the boot sequence easier to reason about and extend.
- **A config model built for exactly this use case.** Alpine's `apkovl` overlay + `lbu commit` mechanism is *designed* for diskless/live systems — the entire user/service configuration compresses into one portable file, which maps naturally onto how a loader's "build environment" partition works.
- **Built-in offline package restore.** The new 4th partition doubles as a local apk mirror, so package restoration at boot no longer strictly depends on internet access.
- **More robust hardware detection.** As part of this migration, disk (`rebuildfstab`) and now network interface (`rebuildnetifaces`) configuration are generated dynamically at every boot from what's actually detected — rather than relying on static, hardcoded device lists that silently miss additional disks or NICs.

## About the xTCRP variant — it has nothing to do with Alpine

If you're using the `xtcrp` image variant, note that **xTCRP is unrelated to the Alpine migration.** It's the same mechanism as before: a separate "friend" kernel (`bzImage-friend` / `initrd-friend`, built from a different, Buildroot-based project) is bundled alongside the loader for a quick-configure boot path. Nothing about that mechanism changed — only the build scripts that assemble the image were bumped to v1.4.0.0 along with everything else. xTCRP does not use Alpine Linux, does not have a 4th `alpine` partition, and is unaffected by anything described above.

## Other fixes worth knowing about

- **Dual-NIC boot support.** Previously, only the first detected NIC (`eth0`) was automatically brought up and given a DHCP address at boot; any additional NICs (`eth1`, etc.) were left completely unconfigured. A new boot-time script (`rebuildnetifaces`, mirroring the existing disk-detection script `rebuildfstab`) now scans all detected network interfaces at every boot and configures any that are missing — multi-NIC hardware now gets a working IP on every interface out of the box.
- **Menu no longer exits on ESC/Cancel.** The main mshell menu used to drop straight back to the shell if you pressed Esc or Cancel by mistake. It now simply redraws the menu instead; the only way to exit is the explicit "Exit" menu item.

## Notes

- Existing v1.3.1.1 users are unaffected and continue to receive updates on the `main`/v1.3.x line.
- The `master` branch has been recreated as a permanent, protected snapshot of v1.3.1.1 to safely serve any legacy client code that still references it by name.
