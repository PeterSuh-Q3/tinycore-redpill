# alpine-redpill v1.4.3.2

## 📡 NetConsole early log — boot-to-panic logs in real time, no serial port needed

On modern boards with no serial port, a kernel panic or boot failure left no way to find out why. This release integrates the Linux kernel's own **netconsole** feature into the loader, streaming kernel log output over UDP to another PC (the listener) in real time — right up to **the last line before a panic**.

> No internet, no DHCP required. All you need is one PC on the same switch/router and a single `nc` command.

- 🖥️ **One menu, fully configured (Environment, first item)**: the only thing the user has to type is the listener's IP address. Everything else (the loader's own interface/IP, the listener's MAC address) is filled in automatically — the listener's MAC is looked up via `ping` to populate the ARP table followed by `ip neigh`/`arp` (falling back to manual entry only if that fails). This lookup happens once, at configuration time, so it never depends on the notoriously unreliable ARP behavior during an actual boot or panic.
- 🧩 **Sourcing netconsole.ko from DSM's own `.pat`**: this module exists nowhere in the boot-time ramdisk family (rd.gz/all-modules) — only inside the DSM install image itself (`hda1.tgz`). It's extracted at the point the `.pat` gets reduced to a cache-saving "minipat," and embedded permanently into the minipat itself, so it survives even when that minipat cache is reused or re-repacked on later builds.
- ⏱️ **The earliest reachable execution point**: right after entering `Main()` in `linuxrc.syno` — a point where `/proc` is already mounted, yet still earlier than the DSM partition mount / main logic (`.impl`) — the loader attempts `insmod` in the background. Since the real `eth0` driver loads immediately after this point in the same sequence, it polls and retries for up to 60 seconds to catch the exact moment the driver comes up.
- 🔧 **Built for a near-empty environment**: at this point even `tr` doesn't exist yet (`tr: not found`), which was silently breaking the original parsing pipeline. Rewritten to parse the kernel command line using only shell builtins, no external utilities required.
- 🌍 **All 18 languages**: every string in the submenu — the menu label, the IP input prompt, error messages, the save confirmation — is translated into all 18 languages `langMenu()` supports (Korean, English, Japanese, Simplified/Traditional Chinese, Russian, French, German, Spanish, Italian, Portuguese, Hungarian, Indonesian, Turkish, Hindi, Arabic, Amharic, Thai).

All of the above was iterated and verified end-to-end on real physical hardware (SA6400) — auto-detection/ARP lookup, the save/delete cycle, module survival across minipat re-packing, `/proc` mount timing, the missing-`tr` workaround, and waiting for `eth0` to come up were each reproduced and fixed live on the box.

### Walkthrough

1. The new menu item at the top of the Environment section ([screenshot](../docs/netconsole/01_main_menu.png))
2. The entry dialog for configuring or disabling it — current status shown inline ([screenshot](../docs/netconsole/02_setup_dialog.png))
3. If automatic MAC lookup for the listener fails, it prompts for manual entry ([screenshot](../docs/netconsole/03_mac_not_found.png))
4. Before committing, it shows the final `netconsole=` value together with the listener-side command to wait with ([screenshot](../docs/netconsole/04_save_confirm.png))
5. Saved — with a reminder that a rebuild is required right now for it to take effect ([screenshot](../docs/netconsole/05_saved.png))

## 🌐 Busting the GitHub raw CDN cache

`raw.githubusercontent.com` caches by path for up to 5 minutes. Rebuilding right after a push was found, live, to serve the stale pre-push version instead of the fix just made — a confusing trap during iterative debugging. `curl` is now wrapped in a function that appends a fresh, per-request query string to every download targeting this domain (60+ call sites, including `.pat`/extractor/friend downloads), bypassing the cache unconditionally.

## 🧹 Other small fixes

- **SataPortMap/DiskIdxMap**: pre-fill generous defaults for non-DT models, and harden `showsata()`'s port-probing accuracy.
- **`getloaderdisk()`**: fixed debug stdout output polluting the captured values in `sngen.sh`/`macgen.sh`.
- **`MODULES_TAG`**: fixed an inaccurate tag display (since `tcrp-modules` downloads track `main` HEAD, not just the latest release tag) and an "Argument list too long" build failure. The build-time LKM/module tag and loading method are now recorded under `/addons/` so the MSHELL Manager System Info tab shows accurate values.
- **`usb_line` orphan entries**: cleaned up stray "LABEL: value" fragments that had leaked into `preserve_usb_line_options()`, and made sure `sync_usb_line()` runs after `prefillDefaultSataPortMap()` writes.
- **`redpill-load` clone validation**: audited every git-clone failure point to abort immediately on failure instead of continuing silently.
- **`checkcpu()`**: reads `/proc/cpuinfo` directly instead of `lscpu`, so CPU-generation detection works correctly even on real hardware where `lscpu` isn't installed.
