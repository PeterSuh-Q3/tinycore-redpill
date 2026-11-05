# alpine-redpill v1.4.7.0

## all-modules PML path for CPUs without BMI2

On some older CPUs, the default "all-modules" kernel/module combination cannot be used; however, switching to "custom-modules" may result in the omission of modules required for the selected DSM target.

This version introduces a mechanism for cases where a test build detects a lack of BMI2 support: it will automatically select "all-modules (PML)" and apply a verified alternative DSM kernel, paired with a "detour" module pack tailored for the specific target.
