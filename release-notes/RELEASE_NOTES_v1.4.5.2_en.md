# alpine-redpill v1.4.5.2

An update can leave an older menu process running while it starts a persistence backup, before the updated startup checks take effect. Alpine backups now verify and repair P3/P4 first, and are cancelled if that recovery check cannot be completed. This helps prevent a damaged partition or persistence archive from being saved again.

The previous-release rebuild option also returns, letting users select an older loader release from the main menu when a rollback is needed. Stable releases are loaded dynamically and validated before use; this option requires at least 6 GB of memory.

- v1.4.4.9 is excluded from selectable and buildable releases because P3/P4 persistence instability was identified in that version.
- v1.4.4.8 remains the last known stable rollback point.
