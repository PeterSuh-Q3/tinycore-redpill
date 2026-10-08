# alpine-redpill v1.4.5.4

## Prevent incomplete remote loader updates

An update package made while the source loader is missing files can leave the remote machine unable to boot. The packaging menu now stops and explains what is missing instead of handing out an incomplete update. It also preserves an existing package rather than silently replacing it.

The `xtcrp.tgz` loader backup now travels with the update. If that backup is absent or damaged, repair the source loader backup before trying to create the package again.

## Protect the NAS during Docker-assisted builds

When a loader is built inside a Docker container on a NAS, confusing the build image with a host disk could put the NAS's own storage at risk. Docker builder mode now refuses to proceed unless the designated image is available, and avoids disturbing the host's modules, swap, and caches. It also stops if the required Alpine persistence backup was not actually created. This applies only when Docker builder mode is explicitly enabled; normal on-device builds are unchanged.
