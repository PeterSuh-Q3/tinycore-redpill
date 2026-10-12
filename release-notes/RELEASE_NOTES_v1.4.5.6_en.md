# alpine-redpill v1.4.5.6

## Keep Alpine persistence safe during updates

An Alpine persistence archive can appear valid while one of its files has lost its original owner or permissions. That can leave privileged files unusable after reboot. Before replacing the P4 archive, this release now checks every staged entry's owner, group, mode, type, and path against a fresh extraction. If any metadata is missing or changed, it keeps the existing P4 archive instead of activating the candidate. The latest repository overlay and current system settings are still combined before a verified archive is written.

## Match network settings to the Ethernet ports that actually exist

When an Ethernet port is removed, its saved `ethN` stanza can remain and Alpine may repeatedly try to bring up a nonexistent device. Startup now reconciles those entries against the interfaces detected on that boot: settings for present ports are preserved, stale entries are removed, and newly detected ports receive DHCP configuration. Thank you to **@gericb** for reporting the Ethernet issue that helped identify this case.

## Recover the console login if its helper is missing

If the tty1 automatic-login helper is missing or damaged, `getty` can repeatedly print “can't execute” instead of presenting a usable console. Startup now validates and restores the helper from its protected copy before getty starts; if recovery is not possible, it falls back to a normal login prompt.
