# alpine-redpill v1.4.5.4

## Safer remote loader packages

Remote loader upgrades could be prepared from incomplete boot files, leaving the recipient with an unusable package. The packaging menu now checks that the loader partitions are mounted and all required files are present, verifies the completed archive, and refuses to overwrite an existing package.

The package now also includes the P3 `xtcrp.tgz` backup. If that backup is missing or damaged, packaging stops with a clear error instead of publishing an incomplete update.

## Docker builder safeguards

In Docker-assisted builds, mistaking a host disk for the mapped loader image could direct a build at the wrong device. With Docker builder mode explicitly enabled, MSHELL now requires the designated loop image and its four partition devices, uses the loop disk for partition calculations, and avoids probing the DSM host's MMC modules or cycling its swap and caches. The Alpine persistence step also checks that its temporary backup destination is configured and that a backup was actually produced.
