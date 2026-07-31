# alpine-redpill v1.4.2.4

A localization and menu-polish release.

## Menu localization completed

Every remaining hardcoded English string across the main menu and its submenus has been translated into all 18 supported languages. Previously a number of items — the NVIDIA transcoding submenu, Verbose Mode, Rebuild Previous Version, the TCB/FKC auto-update manager, and several entries under the Additional Functions and Syno disk handling submenus — stayed in English no matter which language was selected.

Version numbers and technical identifiers (`NVIDIA`, `ffmpeg`, `Jellyfin`, `DDSML/EUDEV`, `Status`, `ON`/`OFF`, `ENABLED`/`DISABLED`) remain in English in every language, matching how the rest of the menu already reads.

## Verbose Mode submenu is now a dialog window

The Verbose Mode screen was a plain text prompt drawn with `echo`, which looked out of place next to every other menu and could be overwritten by console output. It is now a proper dialog window like the rest of the interface, keeping the same 1/2/3 option indices.

This also fixes a sizing bug found during testing: with automatic height the box could exceed a 24-row console, causing dialog to fail and the submenu to close the instant it opened.

## Low-memory notice for Rebuild Previous Version

Rebuilding a previous version needs at least 6GB of RAM. The message explaining that used to print straight to the console, where it was easily missed — it could be drawn over by the menu redraw or scroll away before it was read. It is now a dialog popup that waits for acknowledgement before returning to the main menu.

## Documentation

The README Instructions section was rewritten against the current v1.4.2.3+ menu structure, moved to the top of the page, and now includes live screenshots of the main menu and the `z` / `g` / `n` / `x` submenus with per-item descriptions. A Korean translation is available at [README_instruction_ko.md](README_instruction_ko.md).

## Notes

- Existing v1.4.2.3 users are unaffected unless they update.
