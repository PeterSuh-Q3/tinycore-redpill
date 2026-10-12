# Bare-metal Redpill self-tester: SA6400 pilot

## Goal and scope

Boot an uninstalled bare-metal machine into the DSM junior installer and show
whether it received a DHCP address, serves TCP port 5000, and exposes block
devices. The pilot fixes the model to SA6400 and DSM to 7.4.1. There is no
user-facing model or module menu and no DSM installation or disk write.

## Loader preparation (next phase)

The Alpine stage detects `bmi2` in `/proc/cpuinfo`. It chooses `all-modules`
with IML when present and `custom-modules` with PML otherwise. It must verify
the exact epyc7002/DSM 7.4.1 pack exists before using it. The existing SN and
MAC generators provide stable values saved to the loader configuration. The
normal loader build path then creates the SA6400 image and includes the
`junior-selftest` addon. A failed preflight stops before reboot and reports why.
This stage is not implemented by the initial addon work.

## Junior helper

`tcrp-addons/junior-selftest` starts at the addon `on_patches` hook, only in
junior mode. A background monitor reads kernel network and block-device state,
probes the machine's own port 5000, and writes `/var/log/junior-selftest.log`.
It displays a text status panel on the active Linux virtual console, normally
`tty1`. Character output does not require a framebuffer; a framebuffer is only
needed for pixel-based graphics. The helper redraws the panel periodically.

The IP shown is the address currently assigned inside junior. TCP readiness
means the local port accepts a connection; it is not proof of successful DSM
installation. Disk counts are kernel-visible block devices, not a claim that
DSM can install onto every one. The loader disk must be excluded from a later
DSM-usable-disk assessment.

## Validation gates

The VMware Fusion pilot confirmed that DSM junior can lack `/dev/fb0` while
`tty1` remains active and writable. Verify the text panel on the VM and on a
physical SA6400; then refine disk classification to exclude the loader and
confirm the displayed list against DSM's own disk view. Only after that should
the Alpine zero-choice build and reboot path be added. No automatic DSM install
belongs in this pilot.
