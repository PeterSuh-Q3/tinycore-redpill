# alpine-redpill v1.4.3.5

## Offline static IP setup

If the loader cannot reach the Internet after three attempts, it now asks whether a static IP should be configured. Choosing **Yes** enters the static network form directly without cloning repositories, downloading models, or starting a loader build. The values are written directly to `/mnt/tcrp/user_config.json`, followed by an optional immediate reboot.

The offline path now initializes the gettext fallback messages before opening the form, preventing the early-start `MSGUS147` error.

## Centralized package manifest

MSHELL Manager, Syno Smart Info, and AMD GPU package discovery now uses the bundled `aeudev` `latest.json` manifest from `tcrp-modules` whenever available, with a Raw GitHub fallback. Platform-specific manifest locations are discovered dynamically. Package selection avoids jq regular-expression features and uses `endswith(".spk")` for compatibility with older jq builds.

## Centralized user configuration persistence

User configuration backup handling is now shared by `functions.sh` and the tcrpfriend boot path. Change detection uses SHA-256 snapshots taken when the menu opens and closes, instead of comparing independent local and partition copies. Menu actions refresh the snapshot, while the final restart or exit path performs the backup decision once.

These changes are source updates after v1.4.3.4 and do not change the existing loader build or release asset layout.
