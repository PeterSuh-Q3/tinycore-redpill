# alpine-redpill v1.4.3.7

## 🔀 Static IP now supports up to 8 NICs, with a single primary gateway

The Static IP menu used to configure exactly one NIC. It's now a list that lets you configure up to 8 (matching the loader's `mac1`..`mac8` cmdline ceiling), each added independently and left unconfigured (DHCP) ports simply staying out of the list.

- 🧩 `ipsettings` in `user_config.json` changes from a flat single-NIC object to an array, one entry per configured NIC. Old single-NIC configs are migrated automatically the first time the menu (or the loader) touches the file.
- 🚦 Exactly one entry is flagged `primary` and owns the default route, so multiple static NICs never fight over `ip route add default`. The gateway may be left blank on any non-primary NIC - this only works correctly if that NIC shares the primary NIC's subnet, otherwise it can only reach hosts on its own local subnet.
- ⬆️ Promoting a NIC to primary (by typing its own gateway, or via the dedicated "Set as primary gateway" action) automatically carries over the previous primary's gateway if the promoted NIC's own gateway field was left blank, so promoting a NIC never silently drops the default route.

## 🌐 DNS becomes one global setting instead of a per-NIC field

Linux's `resolv.conf` has no concept of interfaces, so a DNS value entered on a non-primary NIC was never actually isolated to that NIC in the first place.

- DNS moves to a single `netdns.ipdns` value at the top level of `user_config.json`, applied once regardless of how many NICs are configured, and sits right above HTTP Proxy in the Static IP menu.
- It's required as soon as at least one NIC has a static IP - leaving the Static IP menu is blocked with a message until it's set.
- `netproxy`/`netdns` now always appear in `user_config.json` as empty placeholders, instead of being entirely absent until a value is first saved.

## 📋 Menu reshuffle

Static IP Settings moves out of the Additional Functions submenu and up to the main menu, right above the Additional Functions entry. TCB/FKC Auto-update Management and Rebuild Previous Version move the other way, from the main menu into Additional Functions.

## ⚡ Static IP now applies the moment you leave the menu

Saving static IP settings and exiting via Done now calls into the same live-apply path used by the offline first-boot setup, so it takes effect on the running FRIEND kernel immediately - not just on the next boot.

This closes out the loader-side half of a larger multi-NIC static IP effort; the companion tcrpfriend (boot-time cmdline builder, console IP display) and misc add-on (a `mshell-network.service` false-failure fix) changes ship separately in their own repos.
