# alpine-redpill v1.4.2.1

A small follow-up release adding DSM revision support.

## Added DSM 7.4.1-90080 (official) support

Extended the supported revision whitelist to include DSM 7.4.1-90080 for all supported models. It shares the same DSM 7.4 (`_74_`) module/addon recipes and kernel line as the existing 7.4.x entries, so no new module packs were needed.

Adding a 12th revision bucket per model also meant the revision-picker menu's `.[:11]` slice started truncating the oldest supported version (e.g. DS918+ 6.2.4-25556) off the list. Fixed to `.[:12]` so the full set of supported revisions is shown again.

## Notes

- Existing v1.4.2.0 users are unaffected unless they update.
