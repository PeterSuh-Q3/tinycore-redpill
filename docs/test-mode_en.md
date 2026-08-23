# `menu.sh test` — Verifying the Full Chain on Real Hardware Without Rebuilding my.sh.gz or Promoting a Release

> **Scope:** tinycore-redpill (loader/FRIEND build logic) + tcrpfriend (FRIEND kernel/initrd)
> **Purpose:** After changing source, verify end to end on a single real box without
> rebuilding `my.sh.gz` (which auto-deploys to every live user instantly) or promoting
> a tcrpfriend release to "Latest".

---

## Why this matters

`my.sh.gz` gets downloaded and applied automatically via `getlatestmshell()` whenever
(1) the user opens the interactive `menu.sh` (if `tcbautoupd` is on), or (2) **every time
FRIEND auto-rebuilds** (`mshell_auto_rebuild()` always explicitly sets `TCB=true`, with no
exception). In other words, rebuilding `my.sh.gz` is not a routine CI step — it's an act
of **shipping straight to every live user.** Pushing an unverified feature through that
path means every live user gets it immediately (this actually happened once, on
2026-08-23, while developing the static IP feature; the previous `my.sh.gz` had to be
restored).

This document lays out how to verify changes on real hardware without that risk.

## 1. Loader side: `menu.sh test`

Running `menu.sh` with the `test` argument (`menu.sh:450-499`):

```sh
if [ "$1" = "test" ]; then
  rm -f /tmp/test_mode && touch /tmp/test_mode
  oldver="test"
fi
...
if [ "$oldver" = "test" ]; then
  gitdownload   # clone/pull redpill-load
  safe_fetch ".../alpine-redpill/functions_t.sh" "/home/tc/functions.sh" "rploaderver="
  safe_fetch ".../alpine-redpill/menu_m.sh"      "/home/tc/menu_m.sh"    "kver5explatforms"
  safe_fetch ".../alpine-redpill/burnloader.sh"  "/home/tc/burnloader.sh" "burnloader()"
  safe_fetch ".../alpine-redpill/i18n.h"         "/home/tc/i18n.h"       "function load_zz"
  cp build-loader_t.sh build-loader.sh   # swap in redpill-load's test variants
  cp ext-manager_t.sh  ext-manager.sh
  cp pats_t.json       pats.json
  cp bundled-exts_t.json bundled-exts.json
fi
```

The key point: **it fetches `functions_t.sh` (the test track) straight from GitHub raw
content and overwrites it onto `/home/tc/functions.sh` (the live filename).**
`menu_m.sh`/`i18n.h`/`burnloader.sh` are each fetched directly from the `alpine-redpill`
branch the same way — **`my.sh.gz` is never touched.** `safe_fetch()` (`menu.sh:46`) only
replaces the real file after the download passes a non-empty check, a sentinel-string
check, and a `bash -n` syntax check, so there's at least a minimal safety net.

As long as `functions.sh` and `functions_t.sh` are kept byte-identical, pushing to
`alpine-redpill` is immediately verifiable via `menu.sh test` — there's no separate
"land it on a test branch first" step needed.

This path only runs when `test` was explicitly passed in that session — a one-shot, local
fetch with zero effect on any other live user.

## 2. FRIEND side: `curlfriend()`'s automatic pre-release lookup

When `/tmp/test_mode` exists, `functions.sh`'s FRIEND download path branches on its own.
The actual implementation of `curlfriend()` (`functions.sh:6171`, called by
`bringoverfriend()`):

```sh
function curlfriend() {
    REPO="PeterSuh-Q3/tcrpfriend"
    FRTAG=""
    if [ -f /tmp/test_mode ]; then
        cecho g "This is Test Mode"
        PRERELEASE_TAG=$(curl -sk "https://api.github.com/repos/$REPO/releases" | \
          jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)
        [ -n "$PRERELEASE_TAG" ] && FRTAG="$PRERELEASE_TAG"
        writeConfigKey "general" "friendautoupd" "false"   # see section 3 below
    fi
    if [ -z "$FRTAG" ]; then
        # Not test_mode, or no pre-release exists: use "latest" (stable)
        LATESTURL=$(curl ... "https://github.com/$REPO/releases/latest")
        FRTAG="${LATESTURL##*/}"
    fi
    curl ... "https://github.com/$REPO/releases/download/${FRTAG}/{chksum,bzImage-friend,initrd-friend}"
}
```

In other words: **in test_mode, it doesn't fetch `tcrpfriend`'s "latest" (stable) release
at all — it queries the GitHub API for the most recent tag marked `prerelease: true` and
downloads that release's assets (`bzImage-friend`/`initrd-friend`/`chksum`) instead.**
`redpill-lkm` (the kernel module) follows the same pattern in `getredpillko()`
(prefer the pre-release when test_mode is on).

Regular users never set `/tmp/test_mode`, so `curlfriend()` always resolves to "latest"
(non-prerelease) for them — **they are never exposed to pre-release assets.**

## 3. The safety net: `friendautoupd=false` keeps a pre-release from being overwritten

When `curlfriend()` fetches a pre-release under test_mode, it also persists
`writeConfigKey "general" "friendautoupd" "false"` into `user_config.json`. FRIEND's own
`boot.sh` consumes that flag.

The first thing `upgradefriend()` does (tcrpfriend's `boot.sh`, run on every FRIEND boot /
`updateauto` dispatch as FRIEND's own self-update check):

```sh
function upgradefriend() {
    ...
    if [ "${friendautoupd}" = "false" ]; then
        echo -en "\r$(msgwarning "TCRP Friend auto update disabled")\n"
        return   # skips the "latest" checksum comparison/download entirely
    else
        friendwillupdate="1"
    fi
    # from here on: compare against tcrpfriend/releases/latest, download+reboot if different
    ...
}
```

So the moment test_mode pulls a pre-release FRIEND build, `friendautoupd=false` is saved,
and **FRIEND's own routine "latest" auto-update check is skipped from then on** — the
pre-release test build you went to the trouble of fetching doesn't get silently
overwritten by FRIEND's normal auto-update logic on a later boot. `curlfriend()`
(the download) and `upgradefriend()` (suppressing FRIEND's own self-update) are exact
counterparts, wired together by a single `friendautoupd` flag.

## 4. Putting it together: verifying the whole chain with zero impact on live users

1. Change `functions.sh`/`menu_m.sh`/`i18n.h` etc. → push to the `alpine-redpill` branch
   (keeping `functions.sh`/`functions_t.sh` byte-identical is required)
2. Change `tcrpfriend` (`boot.sh` etc.) → build with buildroot → upload the assets to a
   **pre-release tag** (e.g. `v0.1.4u`, with the prerelease flag set on the GitHub
   release) — do not promote it to "Latest"
3. On real hardware, run `menu.sh test` → creates `/tmp/test_mode`, refreshes the loader
   source
4. Build in FRIEND mode → `curlfriend()` automatically fetches the pre-release FRIEND
   binaries and saves `friendautoupd=false`
5. Even after rebooting in this state, FRIEND won't fall back to the stable release, so
   you can repeatedly verify the end-to-end (loader → FRIEND → DSM) behavior

Rebuilding `my.sh.gz` or promoting a tcrpfriend release to "Latest" happens only after
this verification is done, as a separate, explicit deployment decision.
