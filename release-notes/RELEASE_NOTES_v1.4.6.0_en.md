# alpine-redpill v1.4.6.0

## More reliable GitHub Issue builds

A GitHub-hosted builder cannot determine whether the destination NAS CPU supports BMI2. The custom-loader request now asks for the **target CPU's** BMI2 capability and carries that answer into the build. Choose “BMI2 supported” only after checking the NAS CPU; “Unknown” remains the safe choice when unsure. Builds requiring unconfirmed CPU features may be declined instead of producing an incompatible loader.

## Consistent kernel 5 platform selection

Kernel 5 platform choices now come from the reviewed DSM target policy instead of separate menu lists. This helps keep unsupported platform combinations out of loader selection. It does not add a new DSM model or version, and does not by itself certify other repositories' module packs or FRIEND images.
