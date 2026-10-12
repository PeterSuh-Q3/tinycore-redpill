# alpine-redpill v1.4.5.6

## Keep Alpine persistence safe during updates

An Alpine persistence archive can appear valid while one of its files has lost its original owner or permissions. That can leave privileged files unusable after reboot. Before replacing the P4 archive, this release now checks every staged entry's owner, group, mode, type, and path against a fresh extraction. If any metadata is missing or changed, it keeps the existing P4 archive instead of activating the candidate. The latest repository overlay and current system settings are still combined before a verified archive is written.

There was also a way for an older `rebuildnetifaces` copied from the running system to overwrite the updated repository version while refreshing persistence. P4 could then keep booting the stale helper even after an update. Persistence refresh now preserves the repository-managed helper and verifies its ownership and executable mode before saving it.

## Match network settings to the Ethernet ports that actually exist

The saved `ethN` configuration could reflect the interface count detected on the previous boot. If Ethernet ports were added or removed, that stale list did not follow the hardware's current state: Alpine could try to bring up a missing device or fail to configure a newly present port. Startup now enumerates the interfaces available on each boot, preserves settings for present ports, removes stale entries, and adds DHCP configuration for newly detected ports. Thank you to **@gericb** for reporting the Ethernet issue that helped identify this case.

## Recover the console login if its helper is missing

If the tty1 automatic-login helper is missing or damaged, `getty` can repeatedly print “can't execute” instead of presenting a usable console. Startup now validates and restores the helper from its protected copy before getty starts; if recovery is not possible, it falls back to a normal login prompt.
