# alpine-redpill v1.4.7.1

## Minimum Alpine OpenSSH version

Alpine restores its packages during startup from the configured repository. Without a minimum version in the package list, the OpenSSH version was left entirely to repository resolution. This release sets a floor of `10.3_p1-r2` for OpenSSH while allowing newer compatible versions to be selected automatically. The requirement applies when the updated persistence archive is used and its package-restore step runs; it does not change DSM's SSH package or SSH configuration.
