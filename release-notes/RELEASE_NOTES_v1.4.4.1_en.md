# alpine-redpill v1.4.4.1

## Configuration save guidance

- Adds consistent user-facing save-result dialogs after interactive configuration changes.
- Clearly distinguishes settings applied immediately, command-line settings synchronized for the next FRIEND to DSM boot without rebuilding, settings used by a later related action, and settings that require a loader rebuild.
- Keeps the standard MODEL, DSM version, serial number, and MAC address build workflow free of redundant save dialogs.

## Safe command-line configuration updates

- Command-line changes now use a configuration transaction. The previous `user_config.json` is retained while the synchronized command line is validated.
- If validation fails, the previous configuration is restored automatically. The error dialog displays the previous value, rejected value, and validation reason.
- Applies this protection to SATA DOM, i915 PSR, NetConsole, SATA remapping, and manual `user_config.json` edits.
- Correctly accepts the `+` suffix in valid `syno_hw_version` model values, while continuing to reject malformed command-line concatenation elsewhere.

## Runtime and build guidance

- Static IP and GitHub DNS or DoH changes report immediate application in the active loader session.
- Addon, module profile, and device-management changes explicitly report when rebuilding the loader is required.

## Language catalog reliability

- Fixes language-catalog keys for the new save-result dialogs so Korean and other translated menus do not fall back to English.
- The language build now rejects a bare `\n` escape in PO message bodies; catalog entries must use the established literal `\\n` form before MO compilation.
