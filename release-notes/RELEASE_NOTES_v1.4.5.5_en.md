# alpine-redpill v1.4.5.5

## Prepare remote Docker rebuild packages for MSHELL Manager

When MSHELL Manager rebuilds a loader remotely to replace its DSM kernel, the result needs to be delivered as a complete, verifiable update package. This release adds the loader-side packaging flow for that handoff. The active Alpine P4 persistence is kept out of the remote package; ordinary on-loader backups continue to preserve Alpine persistence.

## Find QEMU Guest Agent support more easily

The build option is now named `vmtools-qemuga` to make its purpose explicit. Existing `vmtools` selections are migrated automatically, so users do not need to select the option again.
