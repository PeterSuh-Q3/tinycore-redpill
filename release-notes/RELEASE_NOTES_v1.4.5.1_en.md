# alpine-redpill v1.4.5.1

## Why this emergency update is needed

Loader updates since v1.4.4.6 could leave the writable P3 mount/config link or the P4 Alpine persistence archive with incorrect ownership. Because the archive is restored at startup, the damage could recur and later prevent reliable menu updates or persistence backups.

## What changes

At menu startup, MSHELL now checks P3 and P4 independently before making another automatic persistence backup. If both are healthy, it skips recovery and does not rewrite the archive. If either check fails, it repairs the affected state, validates the resulting P4 archive, and stops before further updates if recovery cannot be verified. The recovery helper is included in both the loader image overlay and `my.sh.gz`.

To run the same safe check manually, use:

```sh
curl -fsSL 'https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/tools/recover-alpine-p3.sh' | sudo sh -s -- --ensure
```

The `--apply` option remains available to force recovery; routine and startup use should use `--ensure` so healthy partitions are left untouched.
