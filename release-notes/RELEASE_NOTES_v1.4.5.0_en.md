# alpine-redpill v1.4.5.0

> **Use v1.4.5.0 instead of v1.4.4.9.** The v1.4.4.9 downloads were withdrawn after some systems developed unstable P3/P4 mounts and Alpine persistence or file-ownership problems. This release keeps the proven v1.4.4.8 loader behavior while addressing those failures. The previous-version selection changes introduced in v1.4.4.9 are not included.

## Why this release matters

- **Keep loader settings and Alpine startup reliable.** A comparison copy of the Alpine persistence archive on P3 could be mistaken for a boot overlay. P3 now keeps that copy under a distinct baseline name; P4 remains the active boot-persistence location. Existing P3 comparison files are renamed only after validation, without overwriting the active P4 archive.
- **Avoid losing administrative access after a backup.** Earlier persistence operations could capture incorrect ownership for protected system files, leaving `sudo` unusable after reboot. The backup path now checks ownership and the archive before replacing P4, and stops if the result is unsafe. Copying the baseline to FAT also avoids an unsupported ownership-preservation operation that could make a loader build fail at its final backup step.
- **Prevent competing startup processes from mounting the same loader partition twice.** The Menu and Monitor can start together. Their shared mount operation now serializes the check and mount, so the second process reuses the mount made by the first. On the test system, P1–P3 each had one mount after reboot, and the configuration remained writable.
- **Recover affected installations deliberately.** A manual P3 recovery script is available for systems already left with duplicate or incorrect mounts. It checks the target before changing it; this release does not silently repair an existing damaged filesystem.

If your loader already has an incorrect P3 mount, run this from its Alpine shell. The command applies the recovery and writes a verified Alpine persistence backup:

```sh
curl -fsSL 'https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/tools/recover-alpine-p3.sh' | sudo sh -s -- --apply
```

The image workflow also skips withdrawn releases without downloadable images, allowing the next image to be based on the last usable release. A loader image or backup made with v1.4.4.9 should not be reused as the basis for this release.
