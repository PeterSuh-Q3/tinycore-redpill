# alpine-redpill v1.4.7.2

## Alpine OpenSSH security

Alpine OpenSSH password authentication can be affected by CVE-2026-123158. The loader now requires version `10.3_p1-r2` or later for both `openssh` and `openssh-server`, so the server itself receives the security fix. This applies to Alpine, not DSM's SSH service.

## Offline Wi-Fi scanning tool

New Alpine loader images include the `iw` utility and its dependencies in the local package repository. This makes the tool available without downloading it at boot. Scanning still requires a compatible wireless adapter and driver; `iw` alone does not connect to Wi-Fi.
