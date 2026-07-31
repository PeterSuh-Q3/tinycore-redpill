# alpine-redpill v1.4.2.2

A stability and consistency follow-up release.

## Fixed the revision-picker still hiding the oldest supported version

The `tags=(a..k)` lookup array used by `selectversion()` had only 11 letters even after last release's `.[:12]` slice fix, so the 12th (oldest) revision entry's tag was empty and the item silently disappeared from the menu on some models. Extended the array to 12 letters.

## Unified BMI2 version gating everywhere

`all-modules` requires a BMI2-capable CPU starting DSM 7.3.0, but the BMI2-free `custom-modules` alternative is only actually built through DSM 7.3.2 (Synology has not released the DSM 7.4 GPL kernel source needed to build a BMI2-free variant past that point). Previously only the version-picker enforced this; the module-name and loader-mode pickers used a looser "DSM >= 7.3.0" check that could still offer `custom-modules` at DSM 7.4.0+, where it doesn't actually exist.

All three pickers now share the same named thresholds, so a BMI2-less CPU consistently sees only `< 7.3.0` (all-modules) or `7.3.0-7.3.2` (custom-modules) as usable, everywhere. A stale stored DSM version past 7.3.2 is also corrected automatically the moment a BMI2-less model is selected, instead of only being caught later at the version-picker step.

## Alpine-branded /etc/motd

Replaced the TinyCore-era `/etc/motd` (fetched from a stale `main`-branch path from the pre-fork days) with a colored alpine-redpill logo. It's now baked directly into the apkovl at build time, so it shows from the very first boot instead of only after `menu.sh` has run once. This only affects mshell; xTCRP has no `/etc/motd` mechanism.

## Notes

- Existing v1.4.2.1 users are unaffected unless they update.
