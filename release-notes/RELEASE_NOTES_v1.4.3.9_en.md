# alpine-redpill v1.4.3.9

## GitHub access mode for constrained networks

- Adds **GitHub Access DNS Mode** to the main menu. Users can keep the normal DNS mode or enable an optional **DoH bypass mode for China**.
- When GitHub access fails before repository downloads begin, MSHELL can offer the DoH bypass interactively. The bypass resolves the required GitHub endpoints through Cloudflare DoH and applies the resulting temporary host mappings immediately.
- Returning to normal DNS mode removes only the MSHELL-managed resolver and host overrides.

## Locale guidance at startup

- Detects the current country after the loader network wait and, when the configured menu language is still English, offers a localized dialog to switch to the detected region's language.
- The prompt runs before the GitHub check and repository checkout, while avoiding the early-boot DHCP and DNS race that could suppress it during automatic SX startup.
- Extends the related dialog messages across all supported language catalogs.

## Download visibility

- Unifies visible progress reporting for staged SPK downloads, including MSHELL Manager, Syno Smart Info, Intel GPU Top, and AMDGPU packages.
