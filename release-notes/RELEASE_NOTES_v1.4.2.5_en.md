# alpine-redpill v1.4.2.5

## Retired the legacy TinyCore NIC reorder

This branch no longer ships TinyCore. The old startup workaround that reordered `eth*` interfaces by PCI bus and then reset DHCP/default routes is now disabled. Alpine and xTCRP already enumerate NICs in PCI order, so avoiding the reset preserves active SSH management sessions and removes needless link interruption at menu startup.

## Expanded BMI2-free custom-modules support

On kernel-5 platforms, BMI2-free `custom-modules` builds are now available through DSM 7.4.1. The DSM version cap, stale-version correction during model selection, version-picker filtering, and module-mode validation all use the same 7.4.1 limit.
