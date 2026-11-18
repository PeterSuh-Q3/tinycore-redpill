# Alpine WLAN auto-connect menu design

Status: proposed; this document does not imply that the menu is implemented.

## Goal and placement

Add `WLAN (Wi-Fi) Auto Connect` immediately after `Static IP Settings` in
the `menu_m.sh` main menu. The menu configures the existing DSM junior Wi-Fi
connection flow; it does not automatically connect the running Alpine loader.
Support WPA2-Personal as in the existing configuration. Do not advertise
open, enterprise or WPA3-only networks as supported.

## User flow

- Show the configured SSID and whether credentials exist, never the password.
  Offer scan/select, manual SSID entry, remove configuration and cancel.
- Detect interfaces using `/sys/class/net/*/phy80211`, not names such as
  `wlan0` or `eth80`. If more than one is present, offer a device selection.
- Check availability of `ip` and `iw`; if absent, report the limitation and
  retain manual entry. An unavailable device, permission failure, busy scan,
  rfkill block or empty result must likewise allow manual entry or cancel.
- With the user's scan action, bring a selected DOWN interface UP. Do not
  disrupt existing supplicant ownership, connections, addresses or routes.
  After scanning, restore DOWN only if this menu brought it UP and doing so
  will not disrupt a connection or another process that appeared meanwhile.
- Present SSID, band/frequency, signal and security in a dialog. Group equal
  SSIDs where useful while preserving per-BSSID details for mixed security.
  SSIDs are untrusted bytes: avoid shell evaluation, dialog-option injection,
  terminal control characters and delimiter-based corruption. Preserve the
  exact selected SSID bytes supported by the current JSON configuration. For
  hidden or nonrepresentable SSIDs provide safe manual entry or a clear error.
- Prompt for a masked password. Validate SSID length in UTF-8 bytes (1–32)
  and the existing supported WPA2 passphrase constraints (8–63 printable
  ASCII characters). Do not expose secrets in process arguments, logs, shell
  tracing, temporary files, dialog output, or confirmation messages.
- Commit `.wifi.ssid` and `.wifi.password` to the existing `user_config.json`
  schema only after all validation and confirmation. Use private temporary
  files, atomic replacement and the existing backup/sync flow. Cancel or
  error preserves the previous configuration. Removing Wi-Fi is an explicit
  action, not a side effect of a cancelled or failed scan.
- Explain that rebuilding the loader is required for changes to reach junior.
  Both the source configuration and the initrd-derived PSK are credentials;
  do not share them. Never place credentials on the kernel command line.

## Boundaries and integration

Reuse or refactor `tools/configure-wifi.sh` validation and safe storage rather
than maintaining incompatible validation rules. Add localized menu strings
following existing translation conventions. The junior `wifi-tools` addon
remains responsible for connection and DHCP coordination; driver and firmware
availability must be checked separately in both environments. Do not assume
that successful Alpine scanning proves the DSM kernel has the same driver,
firmware, regulatory channels or interface name.

Do not overwrite or restart another supplicant; do not change the wired
default route or DNS. A future optional Alpine connection test should be
designed separately with explicit ownership and rollback of network state.

## Verification plan

Test parser handling for duplicate and hidden SSIDs, mixed security, Unicode,
quotes and control characters; no device or `iw`; scan errors; rfkill; multiple
radios; and cancellation at every dialog. Verify secret redaction, restrictive
permissions, atomic writes and unchanged previous settings on failure. Check
both originally-UP and originally-DOWN interfaces and ensure existing wired
and wireless connectivity is preserved. On a physical Alpine target, scan,
select and save a WPA2 network, rebuild, then verify that junior authenticates
and receives an address without exposing credentials.
