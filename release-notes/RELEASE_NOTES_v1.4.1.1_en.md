# alpine-redpill v1.4.1.1

A small follow-up fix release on the `alpine-redpill` line.

## xTCRP boxes no longer silently fall back to the stale `main` branch

xTCRP's friend-kernel environment (Buildroot, non-Alpine) determined which branch to fetch `functions.sh` from by checking for `/etc/alpine-release`. Since that file only exists on actual Alpine boxes, xTCRP boxes always fell through to the `main` branch — which has been frozen at v1.3.1.1 since before the Alpine migration. This meant xTCRP installs kept silently re-downloading a year-old `functions.sh` on every refresh, even after updating to v1.4.x. `UPDATE_BRANCH` is now hardcoded to `alpine-redpill`, the only actively maintained branch for both mshell and xTCRP.

## Other fixes

- **Low-RAM swap raised from 1GB to 1.5GB.** A build workload that includes `.pat` decryption was observed pushing swap usage past 67% of the previous 1GB allocation.
- **Memory cleanup now also runs after successful builds.** It previously only ran on the failure/cleanup path, so a build that succeeded left tmpfs/swap usage to accumulate across consecutive builds.
- **redpill-load download failures are now diagnosable.** Remote fetch failures (e.g. `rpext-index.json`) used to discard curl's error output entirely; failures now log HTTP code, DNS/connect/TLS timing, and curl's own error message.
- **`tcrp-modules`/`tcrp-addons`/`rp-ext` branch references corrected** from `master` (which doesn't exist in those repos) to `main`, across both this repo and `redpill-load`. The old `master` paths happened to keep working only because of GitHub's unofficial legacy-branch redirect.
- **Default terminal colors brightened** (lxterminal palette and the "TCRP Extra Terminal" window) — the previous dark green was hard to read.

## Notes

- Existing v1.4.1.0 users are unaffected unless they update.
