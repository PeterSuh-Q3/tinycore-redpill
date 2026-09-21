# alpine-redpill v1.4.4.6

## Alpine persistence and configuration reliability

- Reworked Alpine overlay persistence to stage and validate the generated archive before replacing the active copy.
- Preserved `/home/tc/user_config.json` as a symlink to the loader partition during updates and reboots.
- Routed all user configuration writes through one validated safe-write helper, preventing stale temporary files and permission regressions.
- Preserved existing configuration ownership and avoided replacing symlinks with regular files.
- Refreshed the persistence baseline after a loader build so an immediate reboot does not trigger a duplicate backup.

## Image build consistency

- The image build workflow now copies the workspace `localhost.apkovl.tar.gz` into the generated p3 partition as well as the Alpine partition.
- This keeps newly generated images aligned with the exact Alpine overlay used by the build workspace.
