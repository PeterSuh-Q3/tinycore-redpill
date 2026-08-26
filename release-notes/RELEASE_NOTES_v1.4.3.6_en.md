# alpine-redpill v1.4.3.6

## 🌐 A saved static IP is now applied automatically on every boot

Previously, a static IP was only ever put to use at the moment it was first saved - through the offline setup dialog that appears after 3 failed DHCP attempts. On every later boot, `menu.sh` ignored the static settings already sitting in `user_config.json` and went through the full DHCP wait/retry dance again regardless, even though it could never succeed on that network.

- 🔌 A new `apply_saved_static_ip()` check runs at the very start of the network setup section, before any DHCP attempt. If `ipsettings.ipset` is already `"static"`, it applies the saved IP/gateway/DNS/proxy directly to the live loader session.
- ⏭️ When a saved static IP is applied, the 3-attempt NIC-kick/DHCP retry loop is skipped entirely - it was never going to succeed on a network with no DHCP server, so there's no reason to wait through it every boot.
- 🚫 The offline static-IP setup dialog no longer reappears in this case either, since it would just be asking the user to re-enter a value that's already in effect.

This closes the gap between the offline first-boot setup path (added in v1.4.3.5) and every subsequent boot afterward - once a static IP is saved, it now takes effect consistently on every boot, not just the one where it was configured.
