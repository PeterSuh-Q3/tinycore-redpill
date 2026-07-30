# alpine-redpill v1.4.2.3

A release centered on NVIDIA hardware-transcoding support and a menu-structure overhaul.

## NVIDIA hardware transcoding, end to end

The no-auth NVIDIA driver (physical / passthrough GPUs only — no vGPU, no license server) is now selectable straight from the main menu under `g`. Pick a driver version, optionally add an NVENC-capable ffmpeg for the Jellyfin package, and enable the addon; the loader build carries it into DSM from there. When the ffmpeg layer is included, a boot hook automatically repoints the Jellyfin package's `--ffmpeg` argument from the stock `ffmpeg7` binary (no NVENC) to the NVENC-capable one — no manual path change in the Jellyfin UI needed.

The submenu resolves what it offers from the live catalog rather than a fixed list, so it only ever shows drivers that actually exist for your platform **and** your kernel:

- **kernel 5.10.55** platforms get all four branches (470 / 535 / 550 / 580).
- **kernel 4.4** platforms get 550 only. This is NVIDIA's own floor, not a packaging choice — from 560 onward `nv-linux.h` hard-fails with `does not support kernels older than Linux 4.15`, confirmed by actually building 560/570/575/580 against a 4.4 tree.
- **kernel 3.10** platforms show `(Not Supported)` in the main menu and cannot enter the submenu at all, rather than opening an empty list.

GSP firmware is accounted for too: 580 needs it on Turing and newer, and only the Turing / consumer-Ampere blobs ship with NVIDIA's `.run`. On an Ada or Blackwell card the menu quietly stops recommending 580 and points at 550 instead, since 580 there would install cleanly and then fail to initialise.

Verified on real hardware — a Quadro P620 driving Jellyfin transcodes on both `epyc7002` (kernel 5.10.55) and `geminilake` (kernel 4.4.302).

## Addon preservation is now generic

Loader builds reset `bundled-exts.json` from upstream, and user-toggled addons previously survived that reset only if they were named in a hardcoded capture list — meaning every new addon needed its own line of code to be preserved.

Preservation now works by diffing the current file against the freshly-fetched upstream default (minus module packs) into `merged-addons.json`, then merging it back after the reset. Any addon survives, including ones added later, with no per-addon code.

## Menu restructure

The main menu was flattened and reordered to follow the actual build workflow:

- `k` (loader mode) and `c` (DDSML/EUDEV) moved under `z` as its first two items, with the loader-mode picker pre-selected on entry.
- `dtsmapping` moved from the `n` submenu to `z`'s third slot.
- `c` (kernel-module handling) sits directly above `p` (build the loader) instead of leading the menu.
- Index letters are all lowercase now — `N` became `g`, `X` became `o`. There was plenty of room once `k` freed up.

MAC address selection became its own submenu supporting up to 8 interfaces, indexed sequentially `a` through `h` by however many NICs are actually present. On a single-NIC box it skips the list entirely and goes straight to the address picker, since there is nothing to choose from.

The panel-size indicator replaced the keymap readout in the title bar, so the currently selected storage panel (e.g. `RACK_12_Bay`) is visible at a glance.

## Mesa DRI drivers for X

The `apk add` list installed `xorg-server` and `lxterminal` but no Mesa DRI drivers, leaving `/usr/lib/dri/` empty. AIGLX could not find `swrast_dri.so` and glamor failed to initialise, so X, openbox, tint2 and lxterminal all ran while the framebuffer sat frozen — confirmed on a Proxmox VM by capturing two screendumps and finding identical md5 sums. Added `mesa-dri-gallium`, `mesa-gl`, `mesa-egl` and `mesa-gbm` to restore a working software-rendering path.

## Localization

Two new strings were added and translated across all 18 supported languages: the MAC menu title (now noting up-to-8 support) and the exit item, which had been hardcoded Korean regardless of the selected language.

## Notes

- Existing v1.4.2.2 users are unaffected unless they update.
- The NVIDIA driver addon re-downloads its layers on every boot, as all redpill-load extensions do. For this addon that is a large transfer (roughly 420 MB with the ffmpeg layer), which is worth knowing on a slow link.
- Kernel 4.4 driver builds pass vermagic checks and load correctly on `geminilake`, but the headless 4.4 platforms (`broadwell*`, `purley`, `r1000`, `v1000`) have not been verified on real hardware yet.

