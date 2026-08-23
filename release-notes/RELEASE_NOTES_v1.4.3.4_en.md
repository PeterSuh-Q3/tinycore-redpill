# alpine-redpill v1.4.3.4

## 🌐 Static IP assignment

You can now set a fixed IP for the loader's DSM boot straight from the menu — no more depending on your router's DHCP handing out the same address every time.

`Additional Functions` → `Static IP Settings` walks you through it: choose `Configure Static IP` or fall back to `Use DHCP`, pick the interface, then fill in the IP address (CIDR), gateway, DNS server, and an optional HTTP proxy. The proxy field is validated on the spot and rejects anything missing the `http://`/`https://` scheme before you can save.

| | | |
|---|---|---|
| ![Additional Functions](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/01-main-menu-additional-functions.png) | ![Static IP Settings item](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/02-additional-functions-static-ip-item.png) | ![Configure or DHCP](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/03-static-ip-configure-or-dhcp.png) |
| ![Select interface](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/04-select-interface.png) | ![Enter static network settings](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/setstaticip/05-enter-static-network-settings.png) | |

Under the hood, this went through several real-hardware iterations before landing on a design that actually works:

- The setting is captured into `user_config.json` by the menu and turned into a `network.<MAC>=address/netmask/gateway/dns` kernel cmdline parameter at kexec time — the same convention used by other redpill-family loaders — rather than baking a static `ifcfg-ethN` directly into the DSM ramdisk (which real-hardware testing showed gets silently overwritten by DSM's own post-boot network manager regardless of how it's written).
- The `tcrp-addons` `misc` add-on now consumes that cmdline parameter twice: once during the ramdisk patch stage, and again through a new persistent `mshell-network.service` that reapplies it right after DSM's own network service finishes — so DSM's own DHCP client can't quietly win the race on a later boot.
- Verified end-to-end on real hardware: the loader boots with the requested static IP and stays on it after a full DSM boot.

## 🧹 Other small fixes

- Fixed `safe_fetch()`/`models.json` fetching in `menu.sh test` mode not cache-busting against the CDN, so a just-pushed fix could still serve a stale file for a while.
- Fixed a `buildloader()` bug where `USB_LINE`/`CMD_LINE` assembly used `+` as if it were a string-concatenation operator (it isn't, in bash) — this could inject literal `+`/`"` characters into the real boot kernel cmdline on kernel<5 SATA-boot configurations. Both `functions.sh` and `tcrpfriend`'s `boot.sh` now build their kernel cmdlines through a small `cmdline_append()` helper instead of hand-spaced string concatenation.
- `docs/test-mode.md` (the `menu.sh test` + FRIEND pre-release testing workflow write-up) is now split into `docs/test-mode_en.md` and `docs/test-mode_ko.md`.
