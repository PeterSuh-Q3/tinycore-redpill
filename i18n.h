#!/usr/bin/env bash

### Messages Contents

## ZZ gettext "tcrp"
function load_zz() {
MSGZZ00=$(gettext "tcrp" "Device-Tree[DT] Base Models & HBAs do not require SataPortMap,DiskIdxMap. DT models do not support HBAs")
MSGZZ01=$(gettext "tcrp" "Choose a Dev Mod handling method, DDSML/EUDEV")
MSGZZ02=$(gettext "tcrp" "Choose a Synology Model")
MSGZZ03=$(gettext "tcrp" "Choose a Synology Serial Number")
MSGZZ04=$(gettext "tcrp" "Choose a mac address")
MSGZZ05=$(gettext "tcrp" "Choose a DSM VERSION, Current")
MSGZZ06=$(gettext "tcrp" "Choose a loader Mode, Current")
MSGZZ10=$(gettext "tcrp" "Edit user config file manually")
MSGZZ11=$(gettext "tcrp" "Choose a keymap")
MSGZZ12=$(gettext "tcrp" "Format Disk(s) # Excluding Loader Disk")
MSGZZ13=$(gettext "tcrp" "Backup TCRP")
MSGZZ14=$(gettext "tcrp" "Reboot")
MSGZZ15=$(gettext "tcrp" "Power Off")
MSGZZ16=$(gettext "tcrp" "Max 24 Threads, any x86-64")
MSGZZ17=$(gettext "tcrp" "Max 8 Threads, Haswell or later,iGPU Transcoding")
MSGZZ18=$(gettext "tcrp" "Build the loader")
MSGZZ20=$(gettext "tcrp" "Max ? Threads, any x86-64")
MSGZZ21=$(gettext "tcrp" "Have a camera license")
MSGZZ22=$(gettext "tcrp" "Max 16 Threads, any x86-64")
MSGZZ23=$(gettext "tcrp" "Max 16 Threads, Haswell or later")
MSGZZ24=$(gettext "tcrp" "Nvidia GTX1650")
MSGZZ25=$(gettext "tcrp" "Nvidia GTX1050Ti")
MSGZZ26=$(gettext "tcrp" "EUDEV (enhanced user-space device)")
MSGZZ27=$(gettext "tcrp" "DDSML (Detected Device Static Module Loading)")
MSGZZ28=$(gettext "tcrp" "FRIEND (most recently stabilized)")
MSGZZ29=$(gettext "tcrp" "JOT (The old way before friend)")
MSGZZ30=$(gettext "tcrp" "Generate a random serial number")
MSGZZ31=$(gettext "tcrp" "Enter a serial number")
MSGZZ32=$(gettext "tcrp" "Get a real mac address")
MSGZZ33=$(gettext "tcrp" "Generate a random mac address")
MSGZZ34=$(gettext "tcrp" "Enter a mac address")
MSGZZ35=$(gettext "tcrp" "press any key to continue...")
MSGZZ36=$(gettext "tcrp" "Synology serial number not set. Check user_config.json again. Abort the loader build !!!")
MSGZZ37=$(gettext "tcrp" "The first MAC address is not set. Check user_config.json again. Abort the loader build !!!")
MSGZZ38=$(gettext "tcrp" "The netif_num and the number of mac addresses do not match. Check user_config.json again. Abort the loader build !!!")
MSGZZ39=$(gettext "tcrp" "Choose a language")
MSGZZ40=$(gettext "tcrp" "DDSML+EUDEV")
MSGZZ41=$(gettext "tcrp" "Choose a Storage Panel Size")
MSGZZ50=$(gettext "tcrp" "Mac-spoof Addon")
MSGZZ51=$(gettext "tcrp" "Prevent SataPortMap,DiskIdxMap initialization")
MSGZZ52=$(gettext "tcrp" "Show SATA(s) ports and drives for SataPortMap")
MSGZZ53=$(gettext "tcrp" "Show error log of running loader")
MSGZZ54=$(gettext "tcrp" "Burn TCRP Bootloader Img to USB or SSD")
MSGZZ55=$(gettext "tcrp" "Clone Current TCRP Bootloader to USB or SSD")
MSGZZ56=$(gettext "tcrp" "sata_remap processing for SataPort reordering")
MSGZZ57=$(gettext "tcrp" "nvmesystem Addon(NVMe single volume use)")
MSGZZ58=$(gettext "tcrp" "Boot the loader")
MSGZZ59=$(gettext "tcrp" "Additional Functions")
MSGZZ60=$(gettext "tcrp" "Change GRUB boot entry default value")
MSGZZ61=$(gettext "tcrp" "Inject Bootloader to Syno DISK")
MSGZZ62=$(gettext "tcrp" "Remove the injected bootloader partition")
MSGZZ63=$(gettext "tcrp" "Packing loader file for remote update")
MSGZZ07=$(gettext "tcrp" "Syno disk and partition handling")
MSGZZ08=$(gettext "tcrp" "Change DSM New Password")
MSGZZ09=$(gettext "tcrp" "Add New DSM User")
MSGZZ19=$(gettext "tcrp" "Clean System Partition(md0)")
MSGZZ64=$(gettext "tcrp" "Bootentry Update version correction")
MSGZZ65=$(gettext "tcrp" "Mount Syno Disk Volume(Ext4 only)")
MSGZZ66=$(gettext "tcrp" "Add Tinycore v9 menuentry for mount Syno Disk BTRFS Vol")
#MSX=$(gettext "tcrp" "No NIC found! - Loader does not work without Network connection.")
}
