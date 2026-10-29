# alpine-redpill v1.4.6.0

## More reliable GitHub Issue builds

A GitHub-hosted builder cannot determine whether the destination NAS CPU supports BMI2. The custom-loader request now asks for the **target CPU's** BMI2 capability and carries that answer into the build. Choose “BMI2 supported” only after checking the NAS CPU; “Unknown” remains the safe choice when unsure. Builds requiring unconfirmed CPU features may be declined instead of producing an incompatible loader.

## Consistent kernel 5 platform selection

Kernel 5 platform choices now come from the reviewed DSM target policy instead of separate menu lists. The shared policy supports epyc7002, epyc7003, icelaked, v1000nk, r1000nk, and geminilakenk. It excludes epyc7003ntb. This does not add a new DSM model or version, and does not by itself certify other repositories' module packs or FRIEND images.

## DSM target selection (carried forward from v1.4.5.9)

Builds now proceed only for reviewed model, DSM version, and module combinations, reducing the chance of pairing a loader with a mismatched DSM kernel or module pack. A remote build may require the destination NAS CPU information; the builder's CPU is not treated as a substitute. This release does not add a new DSM version or model.

## jq compatibility fix

Some jq builds can reject the resolver's regular-expression syntax while parsing DSM release and kernel versions, which can stop the menu from starting or resolving a target. The resolver now validates numeric version components directly, without regex functions, to avoid that compatibility failure.
