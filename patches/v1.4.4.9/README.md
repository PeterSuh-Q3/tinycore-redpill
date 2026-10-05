# v1.4.4.9 script patch set

This directory preserves the historical loader changes intended to restore the
previous-version rebuild behavior on top of the v1.4.5.0 baseline.

- Base: `bbac714771e6bde244dc87d733ea137b79649bc0`
  (`1.4.5.0 Restore v1.4.4.8 loader behavior`)
- Target: `8ab1d8739c2ad1bc5e3732979c8a8ad50fd13168`
  (`Route historical module release assets through curl`)
- Paired helper scripts are both included: `functions.sh` and
  `functions_t.sh`.
- The artifacts are Git unified diffs. Additions appear as `+` lines and
  modifications retain their surrounding context, so the historical edits
  remain reviewable and can be selectively applied.
- These are source patches only. Generated archives/binaries such as
  `my.sh.gz`, `localhost.apkovl.tar.gz`, and `xtcrp.tgz` are intentionally
  excluded and should be regenerated after applying the source changes.

The four patches were dry-run against the final restored v1.4.5.0 baseline
`7b13f74b68f0f82852a7db07917d2cc59b252901`; all hunks applied cleanly.

From a checkout of that baseline, apply a selected patch with:

```sh
patch --dry-run -p1 < patches/v1.4.4.9/menu_m.sh.v1449patch
patch -p1 < patches/v1.4.4.9/menu_m.sh.v1449patch
```

Review all four patches together before applying them to a release branch.
