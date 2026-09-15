# alpine-redpill v1.4.4.4

## Loader Runtime Metadata Integrity

- Boot-entry runtime synchronization now preserves the loader payload version and Update metadata. DSM runtime information is stored separately only when it matches the installed loader payload.

## Alpine Console Startup Reliability

- LBU persistence now recreates and explicitly includes the `mshell-autologin-tc` helper and its tty1 `inittab` entry. This prevents a missing helper from leaving getty unable to start the MSHELL desktop session after reboot.
- LBU persistence also repairs the `sxrc` launch order so the interactive MSHELL Menu terminal remains the final terminal created.
- Alpine overlays now include `xdotool`. After the desktop terminals map, MSHELL locates the Menu window by title and retries raising and activating it, improving initial keyboard focus reliability on bare-metal systems.
