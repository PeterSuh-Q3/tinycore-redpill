# alpine-redpill v1.4.3.2

## 📡 New: NetConsole early log — see boot logs in real time, no serial cable needed

On modern boards without a serial port, if the loader hung or rebooted unexpectedly during boot, there was simply no way to find out what happened. The screen showed nothing, and diagnosing the problem was next to impossible.

Starting with this release, you can **stream the boot log to another PC in real time, from the very first moment the board powers on all the way to the last line before it fails** — over the network, no cable required.

> **"Isn't a network feature going to need internet and a working router?"** — No. This feature needs neither internet access nor a working DHCP server. All it needs is for the board and the PC receiving the logs to be **plugged into the same switch/router with an ethernet cable**. It works even if the internet is down or the router itself is misbehaving.

### How to use it

1. A new menu item now sits at the top of the **Environment** section in the main menu.
2. All you have to enter is the **IP address of the PC that will receive the logs**. Everything else (the board's own network details, the receiving PC's hardware address) is filled in automatically.
3. On the receiving PC, open a terminal and run the single command shown on screen (`nc` on macOS/Linux, `ncat` on Windows) to start listening.
4. Save the setting and rebuild the loader. From then on, every line of the boot log — from power-on to the moment something goes wrong — appears live on the receiving PC's screen.

### Walkthrough

1. The new menu item at the top of the Environment section ([screenshot](../docs/netconsole/01_main_menu.png))
2. The screen for turning it on or off — it also shows whether it's currently enabled ([screenshot](../docs/netconsole/02_setup_dialog.png))
3. If the other PC's address can't be found automatically, it walks you through entering it by hand ([screenshot](../docs/netconsole/03_mac_not_found.png))
4. Before saving, it shows the final setting one more time, along with the command to run on the receiving PC ([screenshot](../docs/netconsole/04_save_confirm.png))
5. Saved — with a reminder that you need to rebuild right now for it to take effect ([screenshot](../docs/netconsole/05_saved.png))

The whole menu is translated into **18 languages** (Korean, English, Japanese, Chinese, and more), so all of the screens above show up in whichever language you've selected.

This feature was installed and tested repeatedly on real physical hardware before release.

## 🌐 Small but important: updates now always land correctly

Improved how the loader fetches its own update files, so a fix pushed by the developers is now guaranteed to take effect on the very next rebuild. (Previously, in rare cases, a rebuild could briefly pick up a version from a few minutes earlier instead of the latest fix.)

## 🧹 Other small fixes

- Pre-filled more sensible default SATA port settings, and improved auto-detection accuracy.
- Fixed serial number/MAC address generation occasionally showing an incorrect value on screen.
- Build version info shown in the System Info tab (MSHELL Manager) is now more accurate.
- Cleaned up leftover old settings that used to linger in the config file (`usb_line`) instead of being removed.
- Fixed a case where a failed source-code download could go unnoticed and silently continue; it now stops immediately and reports the failure.
- Fixed CPU detection being inaccurate on some real hardware (it could misidentify a modern CPU as older, hiding some newer models from the model list).
