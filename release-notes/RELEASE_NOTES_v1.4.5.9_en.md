# alpine-redpill v1.4.5.9

## Safer DSM build selection

This maintenance release helps prevent a loader from being built with a mismatched DSM kernel or module pack. Builds now proceed only for reviewed model, DSM version, and module combinations. A remote build may require the destination CPU information; the builder's CPU is no longer treated as a substitute. **This release does not add a new DSM version or model.**
