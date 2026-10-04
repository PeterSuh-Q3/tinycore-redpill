# alpine-redpill v1.4.5.0

v1.4.4.9 was withdrawn because of Alpine persistence instability on P3/P4. v1.4.5.0 restores the v1.4.4.8 loader behavior and P3/P4 persistence-file layout.

- P3 `localhost.apkovl.tar.gz` handling and naming remain as in v1.4.4.8.
- No rename to `localhost.apkovl.baseline.tar.gz` or automatic migration of existing files is included.
- Changes to P4 persistence ownership are deferred until the `lbu commit` behavior and resulting archive metadata are sufficiently validated.
- The image workflow skips withdrawn releases without assets and uses the v1.4.4.8 image as its base.
