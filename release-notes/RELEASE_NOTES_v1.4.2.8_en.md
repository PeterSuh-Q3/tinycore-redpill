# alpine-redpill v1.4.2.8

## AMD runtime and Jellyfin preparation

All modules builds now detect supported AMD display controllers and stage a matching platform and DSM specific AMDGPU runtime package from the latest release when one is available. The build remains optional and continues safely when no matching package exists.

## MSHELL Manager and configuration reliability

The bundled MSHELL Manager package was updated through version 1.0.4. Its release metadata is passed to the DSM installation hook, and addon preparation now reliably includes the package before the loader build. User configuration writes preserve custom USB cmdline parameters and repair incorrect ownership before updates.

## Menu and boot display fixes

The multi NIC MAC menu now selects the next interface after each completed entry and selects x after the final interface. The initial Alpine image GRUB template now uses gfxpayload keep, matching generated Alpine GRUB entries and avoiding unsupported fixed resolution failures on physical displays.
