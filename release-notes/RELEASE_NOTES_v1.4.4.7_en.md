# alpine-redpill v1.4.4.7

## Bug fixes

- **Reliable Alpine overlay updates:** the persistent P3 `localhost.apkovl.tar.gz` baseline now compares its SHA-256 checksum with the validated repository overlay. It updates only when the content differs, while an offline or failed download safely retains the existing baseline.
- **Reliable loader-partition writes:** Alpine now remounts an already-mounted loader partition read-write when required, and privileged P3 writes are performed safely. This fixes permission failures that could leave `initrd-dsm`, session metadata, cached PAT files, or loader configuration unchanged even though a build appeared to succeed.

The ramdisk is staged and validated before publication; a failed archive build or final write now stops the loader build instead of silently retaining an older `initrd-dsm`.
