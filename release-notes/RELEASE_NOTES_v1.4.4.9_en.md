# alpine-redpill v1.4.4.9

> **Withdrawn — do not use.** P3/P4 Alpine persistence partition instability was found after release. All v1.4.4.9 downloadable assets have been removed. Use v1.4.4.8 until a corrected version is available.

Improved previous-version selection and build.

## Previous release selection

- Replaced the hard-coded previous-version list with a live catalog of stable GitHub releases.
- Releases are shown from `v1.2.7.7` onward, grouped into screen-sized ranges with no more than 20 tags per range.
- Each tag uses the first release-note line after the three dependency commit hashes as its menu description.
- Before switching versions, the loader now validates the selected tag, all three dependency hashes, and the downloaded shell files. It stops with an error instead of silently falling back to current scripts when validation or downloads fail.
- The existing 6 GB minimum-memory requirement remains in effect.
