# alpine-redpill v1.4.2.7

## Cache panel size selector

The Build Pre-Option menu now includes **f — Choose a Cache Panel Size**, directly below the storage panel size selector. The chosen layout is stored in `user_config.json` as `general.ssdbay`.

Available layouts, derived from the ChangePanelSize image templates, are: `1X1`, `1X2`, `1X3`, `1X4`, `1X6`, `1X8`, `2X2`, `2X3`, `2X4`, `2X6`, `2X8`, `3X4`, and `4X4`. The existing NVMe and vmtools entries moved to `g` and `h`. The new UI is translated and compiled for all 18 supported languages.

## Hardware and build metadata

Menu startup now records the release build date in `general.builddate`. It also refreshes `general.board` from the physical motherboard DMI vendor and board name on every start. System monitoring now displays motherboard DMI fields instead of frequently unpopulated chassis or system fields.

## Loader burner and boot display reliability

The standalone loader burner now unmounts every partition on the chosen target before writing, and aborts safely if unmounting fails. It continues to support converting legacy TinyCore media while preserving `user_config.json` when available.

Alpine GRUB now uses `gfxpayload=keep` instead of forcing 1280x960, avoiding unsupported-resolution failures on physical FHD and HD monitors. GRUB-generation comments were moved outside the generated heredoc to keep `grub.cfg` clean.

## Menu behavior

Section headers in the main menu are decorative entries and no longer force cursor jumps. When the default `en_US` locale detects a country code, the unattended timeout now accepts the detected locale automatically.
