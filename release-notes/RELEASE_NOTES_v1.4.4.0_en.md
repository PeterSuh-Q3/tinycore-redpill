# alpine-redpill v1.4.4.0

## Reliable loader command-line handling

- Unifies menu-driven updates of USB IDs, MAC addresses, SATA DOM, i915 PSR, NetConsole, SATA mapping, and manual `user_config.json` edits through shared command-line synchronization logic.
- Keeps `extra_cmdline`, `general.usb_line`, and legacy `general.sata_line` consistent by replacing duplicate tokens and removing stale managed values.
- Preserves the `user_config.json` symbolic-link target while updating configuration, then synchronizes the persisted loader configuration.

## Build-time consistency validation

- Adds strict validation before the loader configuration is copied into the build output and before the generated `CMD_LINE` is accepted.
- Detects invalid JSON, duplicate or stale managed tokens, mismatched `extra_cmdline` values, incomplete SATA mapping pairs, MAC and `netif_num` mismatches, malformed NetConsole settings, invalid SATA DOM values, missing i915 PSR settings, and malformed command-line text.
- A command-line validation failure now stops the build with a nonzero status instead of being treated as a warning.
- The menu preserves the builder exit status through the build log pipeline and displays the validation details in a dedicated error dialog.

## Scope

- The checks cover the loader build inputs and the generated build command line. Runtime validation of the separate FRIEND `boot.sh` kexec command line is intentionally deferred for further validation.
