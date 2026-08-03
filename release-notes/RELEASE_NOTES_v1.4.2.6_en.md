# alpine-redpill v1.4.2.6

## Standalone loader burner

Added `burnloader.sh`, a dialog-based standalone loader burner that is also used by the main menu.
It can overwrite a legacy TinyCore loader with an Alpine image when the disk has UUID `6234-C863`
but no `alpine` partition.

Before overwriting a qualifying TinyCore disk, the burner backs up `user_config.json` from its
third partition and restores it after recording. If that file does not exist, recording continues
without configuration restoration.

## Large image memory requirement

Selecting the 5GB image now requires at least 8GB of physical RAM. The burner displays the
requirement and returns to the menu before downloading when memory is insufficient.

## Dedicated Alpine UEFI boot path

Release images now include `EFI/AlpineRedpill/grubx64.efi` in addition to the standard removable
media fallback at `EFI/BOOT/BOOTX64.EFI`. On systems that retain a legacy TinyCore loader, register
an `Alpine Redpill` UEFI NVRAM boot entry pointing to the dedicated path and place it first in the
firmware boot order. This selects the Alpine SSD deterministically without changing the shared
`6234-C863` partition UUID.
