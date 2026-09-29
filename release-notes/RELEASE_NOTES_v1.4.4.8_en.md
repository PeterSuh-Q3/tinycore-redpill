# alpine-redpill v1.4.4.8

## New: optional fan-sensor compatibility setting

**Menu path:** Main Menu → **n Additional Functions** → **v Improve fan sensor detection (relax ACPI resource checks)**.

This switch adds or removes `acpi_enforce_resources=lax` in the DSM kernel command line. It is **off by default** and is intended for systems where a sensor module such as `it87` detects the chip but cannot bind because of an ACPI resource conflict. In a Gigabyte H370N WIFI-CF pilot, enabling it allowed the IT8628E sensor module to load and exposed fan RPM inputs.

**No loader rebuild is required.** The setting is saved directly to the loader configuration and is applied on the next FRIEND-to-DSM boot; it does not change the DSM kernel that is already running. Enabling it shows a warning because relaxing ACPI resource checks affects the whole system and may cause instability on some hardware. Turn it on only when needed.

Fan RPM inputs are the immediate goal. We also plan to use those readings for an RPM display in **MSHELL Manager** and, through the **cpuinfo addon**, in the DSM Control Panel's **Info Center**. These display integrations are planned follow-up work, not features delivered by this release.

The menu and warning are translated into all 18 supported languages.

## Other changes since v1.4.4.7

- Expanded model selection for DS725neo+, DS925neo+, DS1525neo+, DS1825neo+, FS200T, RS1226+, RS1226RP+, RS2423RP+II, RS2825RP+, RS826+, and RS826RP+; removed the unstable PAS7700 and RS11626xs+ entries.
- Removed the separate storage-panel-size preselection. The model's panel size remains visible in the menu.
- Corrected the MSHELL Manager SPK filename check to accept the current lowercase asset name.
