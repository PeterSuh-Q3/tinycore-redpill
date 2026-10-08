# alpine-redpill v1.4.5.4

## Prevent incomplete remote loader updates

An update package made while the source loader is missing files can leave the remote machine unable to boot. The packaging menu now stops and explains what is missing instead of handing out an incomplete update. It also preserves an existing package rather than silently replacing it.

The `xtcrp.tgz` loader backup now travels with the update. If that backup is absent or damaged, repair the source loader backup before trying to create the package again.

## Preparing Docker-based remote builds for MSHELL Manager

We are preparing a way for MSHELL Manager to rebuild a loader remotely in Docker, without entering the loader itself, so that the original loader's DSM kernel can be replaced. This release provides the loader-side groundwork for that build. Manager is designed to validate the result and require user approval before applying it to the original loader; this is not yet a release of the complete remote-build feature.

In Docker builder mode, the build stops if its designated image is missing and does not change the NAS host's disks, modules, swap, or caches. Normal on-device builds are unchanged.
