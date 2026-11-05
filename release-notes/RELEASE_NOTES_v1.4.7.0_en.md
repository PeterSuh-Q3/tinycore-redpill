# alpine-redpill v1.4.7.0

## Experimental all-modules PML path for CPUs without BMI2

Some older CPUs cannot use the standard all-modules kernel and module combination, while switching to custom-modules can omit modules needed by the selected DSM target. This test release adds a controlled detour: when the test build confirms that BMI2 is unavailable, it selects all-modules (PML) and pairs it with the verified replacement DSM kernel and matching detour module pack.

This remains a test-only path. It is gated to test builds and applies only when a matching kernel and module asset is available; it is not a general compatibility guarantee for every CPU or DSM target.
