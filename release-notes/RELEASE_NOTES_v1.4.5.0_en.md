# alpine-redpill v1.4.5.0

This recovery release restores the loader scripts and bundled archives to the v1.4.4.8 baseline. v1.4.4.9 has been withdrawn because of P3/P4 Alpine persistence instability.

- P3 now stores the repository overlay only as `localhost.apkovl.baseline.tar.gz` for comparison. Its name is deliberately excluded from Alpine's `*.apkovl.tar.gz` boot discovery.
- P4 retains the active `localhost.apkovl.tar.gz` used for Alpine boot and `lbu` persistence.
- Image builds skip withdrawn releases without a base image; v1.4.5.0 can use the v1.4.4.8 image as its base.
- On existing installations, the former P3 overlay is validated and renamed before the next reboot. If a comparison baseline already exists, the former file is preserved as `localhost.apkovl.withdrawn.tar.gz`. A failed migration leaves the old file untouched and reports a warning.
- No loader rebuild is required to rename an existing P3 file, but the P3 mount must be writable. Verify the next boot log selects the P4 overlay before considering migration complete.
