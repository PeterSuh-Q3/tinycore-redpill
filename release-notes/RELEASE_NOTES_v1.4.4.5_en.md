# alpine-redpill v1.4.4.5

## New RS11626xs+ Model Support

- Added RS11626xs+ to the epyc7003 Device Tree model group.
- The model uses the kernel 5.10 platform profile and a RACK_20_Bay storage layout.

## Responsive Alpine Desktop Session

- The four Alpine SX terminals now use a responsive two by two layout based on the active display resolution.
- Terminal dimensions, positions, and font size are scaled for the available screen area.
- The MSHELL Menu terminal is raised and activated after startup to improve initial keyboard focus.
- Persistent Alpine user configuration files are preserved with the tc staff ownership required after reboot.

## Reliable Build Backup

- A successful loader build backup now refreshes the menu configuration baseline.
- Rebooting immediately after a completed build no longer runs the same backup a second time.
- A failed build backup is returned as a build failure instead of being treated as successful.

## Optional SAN Manager Repair

- sanmanager-repair is no longer included by default in the base extension bundles.
- It can be enabled or removed from the build pre option menu when a SAN Manager package issue occurs.
