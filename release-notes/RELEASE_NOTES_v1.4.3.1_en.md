# alpine-redpill v1.4.3.1

## 📋 Companion release for tcrpfriend v0.1.4r

This release promotes the test-track `/home/tc/user_config.json` symlink feature to the stable track. It works standalone, but to avoid the permission problem described below when the box later boots into xTCRP (FRIEND), it should be paired with [tcrpfriend v0.1.4r](https://github.com/PeterSuh-Q3/tcrpfriend/releases/tag/v0.1.4r).

## 🔗 `/home/tc/user_config.json` is now a real symlink

- 🗂️ **One file instead of two, separately-synced copies**: `/home/tc/user_config.json` (the RAM working copy every menu/build helper reads and writes) and `/mnt/<disk>3/user_config.json` (the persistent partition copy) used to be kept in sync by hand at scattered call sites — miss one, and the two drift apart. `/home/tc/user_config.json` is now a symlink onto the partition copy, so there is only ever one file.
- 🎯 **Stable `/mnt/tcrp` alias, immune to disk-enumeration changes**: the symlink target is `/mnt/tcrp/user_config.json`, a fixed alias that `ensure_loader_partition_mounted()` keeps pointed at the current loader partition (`/mnt/<disk>3`) on every call — so a disk renumbering (e.g. `sda` → `sdb` after a hardware change) can't leave it dangling or pointed at the wrong disk. This mirrors the fixed `/mnt/tcrp` mount path `tcrpfriend`'s own `boot.sh` has always used.
- ✍️ **Writes preserve the symlink**: `writeConfigKey()` / `sync_usb_line()` previously used `mv` to update the config file, which — when the destination is a symlink — replaces the link itself with a plain file instead of writing through it. Every config save was silently breaking the symlink. Both now use `cp` (which follows the symlink and updates the target in place) instead.
- 🧹 **`general.usb_line` no longer accumulates orphaned entries**: `sync_usb_line()` only ever adds or updates `extra_cmdline` keys (`sn`, `mac1`–`mac8`, `vid`, `pid`, `netif_num`) inside the stored `usb_line` string — it never removed one. Deleting a key from `extra_cmdline` (e.g. the NIC-count auto-detect dropping `mac2` when a second NIC disappears) left the old `mac2=...` fragment sitting in `usb_line` forever, since nothing re-derives it from scratch. Fixed in two layers: `DeleteConfigKey()` now strips the matching `usb_line` entry immediately, and `preserve_usb_line_options()` (the rebuild-time merge step) independently drops any of these managed keys that no longer exist in `.extra_cmdline`, so even entries that went stale before this fix — or through any other path — self-heal on the next rebuild.

## ⚠️ Requires a matching `boot.sh`

`/mnt/tcrp` being a stable, tc-writable alias depends on the loader-partition mount itself being tc-writable. `tcrpfriend`'s `boot.sh` mounted this partition without `uid=/gid=` options prior to v0.1.4r, leaving it root-owned — writing through the symlink under xTCRP/FRIEND then failed with `Permission denied`. Use v0.1.4r or later.

All of the above was found and verified end to end on real hardware, including reproducing and fixing the `usb_line` orphan symptom live.
