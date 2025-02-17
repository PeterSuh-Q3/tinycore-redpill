#!/usr/bin/env bash

set -u # Unbound variable errors are not allowed

rploaderver="1.2.1.5"
build="master"
redpillmake="prod"

modalias4="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/modules.alias.4.json.gz"
modalias3="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/modules.alias.3.json.gz"

timezone="UTC"
ntpserver="pool.ntp.org"
userconfigfile="/home/tc/user_config.json"
configfile="/home/tc/redpill-load/config/pats.json" 

gitdomain="raw.githubusercontent.com"
mshellgz="my.sh.gz"
mshtarfile="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/my.sh.gz"

#Defaults
smallfixnumber="0"

#Check if FRIEND kernel exists
if [[ "$(uname -a | grep -c tcrpfriend)" -gt 0 ]]; then
    FRKRNL="YES"
else
    FRKRNL="NO"
fi
 
function history() {
    cat <<EOF
    --------------------------------------------------------------------------------------
    0.7.0.0 Added build for version greater than 42218
    0.7.0.1 Added required extension parsing adding and downloading
    0.7.0.2 Added usb patch in patchdtc
    0.7.0.3 Added portnumber on patchdtc
    0.7.0.4 Make sure that local cache folder is created early in the process
    0.7.0.5 Enabled interactive
    0.7.0.6 Added save/restore session functions
    0.7.0.7 Added a check date function
    0.7.0.8 Added the ability to use local dtb file
    0.7.0.9 Added flyride satamap review
    0.7.1.0 Added the history, version and enhanced patchdtc function
    0.7.1.1 Added a syntaxcheck function
    0.7.1.2 Added sync time with NTP server : pool.ntp.org (Set timezone and ntpserver variables accordingly )
    0.7.1.3 Added the option to create JUN mod loader (By Jumkey)
    0.7.1.4 Added the use of the additional custom_config_jun.json for JUN mod loader creation
    0.7.1.5 Updated satamap function to support higher the 9 port counts per HBA.
    0.7.1.6 Updated satamap function to fix the broken q35 KVM controller, and to stop scanning for CD-ROM's
    0.7.1.7 Updated serialgen function to include the option for using the realmac
    0.7.1.8 Updated satamap function to fine tune SATA port identification and identify SATABOOT
    0.7.1.9 Updated patchdtc function to fix wrong port identification for VMware hosted systems
    0.8.0.0 Stable version. All new features will be moved to develop repo
    0.8.0.0 Stable version. All new features will be moved to develop repo
    0.8.0.1 Updated postupdate to facilitate update to update2
    0.8.0.2 Updated satamap to support DUMMY PORT detection 
    0.8.0.3 Updated satamap to avoid the use of 0 in first controller that cause KP
    0.9.0.0 Development version. Moving all new features to development build
    0.9.0.1 Updated postupdate to facilitate update to update2
    0.9.0.2 Added system monitor function 
    0.9.0.3 Updated satamap to support DUMMY PORT detection 
    0.9.0.4 More satamap fixes
    0.9.0.5 Added the option to get grub variables into user_config.json
    0.9.0.6 Experimental DVA1622 (geminilake) addition
    0.9.0.7 Experimental DVA1622 serialgen
    0.9.0.8 Experimental DVA1622 increase disk count to 16
    0.9.0.9 Fixed missing bspatch
    0.9.1.0 Added dtc depth patch
    0.9.1.1 Default action for DTB system is to use the dtbpatch by fbelavenuto
    0.9.1.2 Fixed a jq issue in listextension
    0.9.1.3 Fixed bsdiff not found issue
    0.9.1.4 Fixed overlaping downloadextractor processes
    0.9.1.5 Enhanced postupdate process to update user_config.json to new format
    0.9.1.6 Fixed compressed non-compressed RAMDISK issue 
    0.9.1.7 Enhanced build process to update user_config.json during build process 
    0.9.1.8 Enhanced build process to create friend files
    0.9.1.9 Further enhanced build process 
    0.9.2.0 Introducing TCRP Friend
    0.9.2.1 If TCRP Friend is used then default option will be TCRP Friend
    0.9.2.2 Upgrade your system by adding TCRP Friend with command bringfriend
    0.9.2.3 Adding experimental DS2422+ support
    0.9.2.4 Added the redpillmake variable to select between prod and dev modules
    0.9.2.5 Adding experimental RS4021xs+ support
    0.9.2.6 Added the downloadupgradepat action **experimental
    0.9.2.7 Added setting the static network configuration for TCRP Friend
    0.9.2.8 Changed all  calls to use the -k flag to avoid expired certificate issues
    0.9.2.9 Added the smallfixnumber key in user_config.json and changed the platform ids to model ids
    0.9.3.0 Changed set root entry to search for FS UUID
    0.9.4.3-1 Multilingual menu support 
    0.9.5.0 Add storage panel size selection menu
    0.9.6.0 To prevent partition space shortage, rd.gz is no longer used in partition 1
    0.9.7.0 Improved build processing speed (removed pat file download process)
    0.9.7.1 Back to DSM Pat Handle Method
    1.0.0.0 Kernel patch process improvements
    1.0.0.1 Improved platform release ID identification method
    1.0.0.2 Setplatform() function converted to custom_config.json reference method
    1.0.0.3 To prevent partition space shortage, custom.gz is no longer used in partition 1
    1.0.0.4 Prevents kernel panic from occurring due to rp-lkm.zip download failure 
            when ramdisk patching occurs without internet.
    1.0.0.5 Add offline loader build function
    1.0.1.0 Upgrade from Tinycore version 12.0 (kernel 5.10.3) to 14.0 (kernel 6.1.2) to improve compatibility with the latest devices.
    1.0.1.1 Fix monitor fuction about ethernet infomation
    1.0.1.2 Fix for SA6400
    1.0.2.0 Remove restrictions on use of DT-based models when using HBA (apply mpt3sas blacklist instead)
    1.0.2.1 Changed extension file organization method
    1.0.2.2 Recycle initrd-dsm instead of custom.gz (extract /exts), The priority starts from custom.gz
    1.0.2.3 Added RedPill bootloader hard disk porting function
    1.0.2.4 Added NVMe bootloader support
    1.0.2.5 Provides menu option to disable i915 module loading to prevent console blackout in ApolloLake (DS918+), GeminiLake (DS920+), and Epyc7002 (SA6400)
    1.0.2.6 Added multilingual support languages (locales) (Arabic, Hindi, Hungarian, Indonesian, Turkish)
    1.0.2.7 dbgutils Addon Add/Delete selection menu
    1.0.2.8 Added multilingual support languages (locales) (Amharic-Ethiopian, Thai)
    1.0.2.9 Release img image with gettext.tgz
    1.0.3.0 Integrate my, rploader.sh, myfunc.h into functions.sh, optimize distribution
    1.0.3.1 Added loader file packing menu for remote update
    1.0.3.2 Added dom_szmax for jot mode
    1.0.3.3 Boot entry order for jot mode synchronized with Friend's order, remove custom_config_jun.json
    1.0.3.4 Maintain boot-wait addon when using satadom in SA6400
    1.0.3.5 Remove getstaticmodule() and undefined PROXY variables (cause of lkm download failure in final release)
    1.0.3.6 Use intel_iommu on the command line
    1.0.3.7 Add command line native satadom support option change menu
    1.0.3.8 Sort netif order by bus-id order (Synology netif sorting method)
    1.0.3.9 NVMe-related function supplementation and error correction
            Discontinue use of sortnetif addon, discontinue use of sortnetif if there is only 1 NIC
    1.0.4.0 Added sata_remap processing menu for SataPort reordering.
    1.0.4.1 Added a feature to check whether the pre-counted number of disks matches when booting Friend
    1.0.4.2 Add Support DSM 7.2.2-72803 Official Version
    1.0.4.3 No separation between USB/SATA menus in Jot Mod (boot menu merge)
    1.0.4.4 Loader building is blocked when using Apollolake + proxmox(kvm)/qemu(kvm) (KP occurs in versions after lkm 24.8.29)
    1.0.4.5 Solved the KP occurrence issue when using SATA-type bootloader in proxmox(kvm), 
            SA6400(epyc7002) integration from lkm5 (lkm 24.9.8)
    1.0.4.6 Rearrange menu order, automatically enter Gen value when S/N or mac is not selected
    1.0.4.7 Fix from DSM 7.2.2-72803 to DSM 7.2.2-72806
    1.0.4.8 Enable mmc (SD Card) bus type recognition for the bootloader
    1.0.4.9 When mmc bus type is used, module processing method is applied with priority given to eudev instead of ddsml.
    1.0.5.0 Improved internet check function in menu.sh
    1.0.5.1 Added manual update feature to friend specified version, added disable/enable friend automatic update feature
    1.0.5.2 Upgraded grub version from 2.06 to 2.12 ( improved uefi, legacy boot compatibility [especially in jot mode] )
    1.0.6.0 Added the ability to choose between the integrated modules all-modules (tcrp) and rr-modules
    1.0.6.1 Improved bootloader boot partition detection method
    1.0.6.2 Changed to use only the first one when multiple bootloaders exist
    1.0.6.3 Added ability to force loading mmc and sd modules when loading Tinycore Linux
    1.0.6.4 Expanded MAC address support from 4 to 8.
    1.0.6.5 Includes tinycore linux scsi module for scsi type bootloader support.
    1.0.6.6 Discontinuing support for DS3615xs.
    1.0.6.7 Applying REDPILL background image to grub boot
    1.0.6.8 i915.modeset=0 menu processing improvement (FRIEND guidance console is activated when i915 transcoding is disabled)
    1.1.0.0 Added features for distribution of xTCRP (Tinycore Linux stripped down version)
    1.1.0.1 When using a single m.2 NVMe volume, the DDSML error issue has occurred, so menu usage has been excluded and related support has been strengthened.
    1.2.0.0 Added new platforms purley, broadwellnkv2, broadwellntbap and started supporting all models for each platform
    1.2.1.0 Create tinycore-mshell and xTCRP together in grub boot. Merge Re-install boot entries without USB/SATA distinction and fix KP bug.
    1.2.1.1 Renewal of SynoDisk bootloader injection function
    1.2.1.2 SynoDisk with Bootloader Injection Supports NVMe DISK
    1.2.1.3 SynoDisk with Bootloader Injection Supports Single SHR DISK
    1.2.1.4 SynoDisk with Bootloader Injection Stop Supports BASIC or JBOD DISK
    1.2.1.5 SynoDisk with bootloader injection uses UUID 8765-4321 instead of 6234-C863
    --------------------------------------------------------------------------------------
EOF
}

            
# Made by Peter Suh
# 2022.04.18                      
# Update add 42661 U1 NanoPacked 
# 2022.04.28
# Update : add noconfig, noclean, manual options
# 2022.04.30
# Update : add noconfig, noclean, manual combinatione options
# 2022.05.06   
# Update : add pat file sha256 check                         
# 2022.05.07      
# Update : Added dtc compilation function for user custom.dts file
# 2022.05.15
# Update : add jumkey's jun mode
# 2022.05.24
# Update : apply jumkey's dyn dtc upx
# 2022.05.25
# Update : apply jumkey's dyn dtc upx for option
# 2022.06.01
# Update : add rd.gz patch for 42661 U2
# 2022.06.03
# Update : Fixed Jun mode build option incorrectly applied
# 2022.06.06
# Update : Add jumkey's Jun mode (use jumkey repo)
# 2022.06.11
# Update : Adjunst Option Operation
# 2022.06.13
# Update : Add manual option for jun mode
# 2022.06.16
# Update : Add dtc mode for known as non-dtc model
# 2022.06.25
# Update : Add dtc model DS2422+ (v1000) support
# 2022.06.27
# Update : remove jumkey, poco oprtions
# 2022.06.30
# Update : Add DS2422+ jot mode
# 2022.07.02
# Update : Add DVA1622 jun mode (Testing)
# 2022.07.07
# Update : Add DS1520+ jun mode
# 2022.07.08
# Update : Add FS2500 jun mode
# 2022.07.10
# Update : function headers for my.sh and myv.shUse common function headers for my.sh and myv.sh
# 2022.07.11
# Update : Add REALMAC Option
# 2022.07.15
# Update : Add DS1621xs+ jun mode
# 2022.07.19
# Update : Add DS1621xs+ jot mode, Add RS4021xs+
# 2022.07.20
# Update : Add DVA3219 jot mode (Release 22.07.25)
# 2022.07.21
# Update : Active rploader satamap for non dtc model
# 2022.07.27
# Update : Add Re-Install DSM menuentry
# 2022.08.03
# Update : Apply fabio's redpill.ko
# 2022.08.04
# Update : Add Userdts Options
# 2022.08.06
# Update : Release FS2500 Jot / Jun Mode
# 2022.08.12
# Update : Add RS3618xs Jot / Jun Mode
# 2022.08.14
# Update : Add RS3413xs+ Jot / Jun Mode
# 2022.08.16
# Update : Added support for DSM 7.1.1-42962
# 2022.09.13
# Update : Add DS1019+ Jot / Jun Mode
# 2022.09.14
# Update : Release DS1520+ jot mode
# 2022.09.14
# Update : Release DVA3219 jun mode
# 2022.09.14
# Update : Sataportmap,DiskIdxMap to blank for VM with noconfig option
# 2022.09.14
# Update : Release TCRP FRIEND mode
# 2022.09.25
# Update : Change to stable redpill kernel ( DS1621xs+, DVA3221, RS3618xs )
# 2022.09.26
# Update : Synchronization according to the TCRP Platform naming convention
# 2022.10.22
# Update : Dropped support for TCRP Jot's Mod /Jun's Mod.
# 2022.11.11
# Update : Deploy menu.sh
# 2022.11.14
# Update : Added autoupdate script, Added Keymap function to menu.sh for multilingual keybaord support
# 2022.11.17
# Update : Added dual mac address make function to menu.sh
# 2022.11.18
# Update : Added ds923+ (r1000)
# 2022.11.25
# Update : Added gitee conversion function when github connection is not possible
# 2022.12.03
# Update : Added quad mac address make function to menu.sh
# 2022.12.04
# Update : Added independent JOT mode build menu to menu.sh
# 2022.12.06
# Correct serial number for DS1520+,DS923+, by Orphee
# 2022.12.13
# Update : Added ds723+ (r1000)
# 2023.01.15
# Update : Add buildable model limit per CPU max threads to menu.sh, add description of features and restrictions for each model
# 2023.01.28
# Update : DT-based model restriction function added to ./menu.sh
# 2023.01.30
# Update : Separation and addition to menu_m.sh for real-time reflection after menu.sh update
# 2023.01.30
# Update : 7.0.1-42218 friend correspondence for DS918+,DS920+,DS1019+, DS1520+ transcoding
# 2023.02.19
# Update : Inspection of FMA3 command support (Haswell or higher) and model restriction function added to menu.sh
# 2023.02.22
# Update :  menu.sh Added new function DDSML / EUDEV selection
#           DDSML ( Detected Device Static Module Loading with modprobe / insmod command )
#           EUDEV (Enhanced Userspace Device with eudev deamon)
# 2023.03.01
# Update : Added erase data disk function to menu.sh
# 2023.03.04
# Update : Increased build processing speed by using RAMDISK & pigz(multithreaded compression) when processing encrypted DSM PAT file decryption
# 2023.03.10
# Update : Improved TCRP loader build process
# 2023.03.14
# Update : Automatic handling of grub.cfg disable_mtrr_trim=1 to unlock AMD Platform 3.5GB RAM limitation
# 2023.03.17
# Update : AMD CPU FRIEND mode menu usage restriction release (except HP N36L/N40L/N54L)
# 2023.03.18
# Update : TCRP FRIEND / JOT menu selection method improvement
# 2023.03.21
# Update : Multilingual menu support started (Korean, Chinese, Japanese, Russian, French, German, Spanish, Brazilian, Italian supported)
# 2023.03.25
# Update : Add language selection menu
# 2023.03.29
# Update : Merging DDSML and EUDEV into one, Improved nic recognition speed by improving realtek firmware omission
# 2023.04.04
# Update : DSM Smallupdateversion Path Management
# 2023.04.15
# Update : Keymap now actually works. (Thanks Orphée)
# 2023.04.29
# Update : Add Postupdate boot entry to Grub Boot for Jot Postupdate to utilize FRIEND's Ramdisk Update
# 2023.05.01
# Update : Add Support DSM 7.2-64551 RC
# 2023.05.02
# Update : Added sa6400 (epyc7002)
# 2023.05.06
# Update : Add 5 models DS720+,RS1221+,RS1619xs+,RS3621xs+,SA3400
# 2023.05.08
# Update : 7.0.1-42218 menu open for all models
# 2023.05.12
# Update : Add Support DSM 7.2-64561 Official Version
# 2023.05.23
# Update : Add Getty Console to DSM 7.2
# 2023.05.26
# Update : Added ds916+ (braswell), 7.2.0 Jot Menu Creation for HP PCs
# 2023.06.03
# Update : Add Support DSM 7.2-64570 Official Version
# 2023.06.17
# Update : Added ds1821+ (v1000)
# 2023.06.18
# Update : Added ds1823xs+ (v1000), ds620slim (apollokale), ds1819+ (denverton)
# 2023.06.20
# Update : Add Support DSM 7.2-64570-1 Official Version
# 2023.07.07
# Update : Fix Bug for userdts option
# 2023.08.24 (M-SHELL for TCRP, v0.9.5.0 release)
# Update : Add storage panel size selection menu
# 2023.08.29
# Update : Added a function to store loader.img for DSM 7.2 for 7.2 automatic loader build of 7.0.1, 7.1.1
# 2023.09.26
# Update : Add Support DSM 7.2.1-69057 Official Version
# 2023.09.30
# Update : Fixed locale selection issue, modified some menu guidance text
# 2023.10.01
# Update : Add "Show SATA(s) # ports and drives" menu
# 2023.10.07
# Update : Add "Burn Anither TCRP Bootloader to USB or SSD" menu
# 2023.10.09
# Update : Add "Clone TCRP Bootloader to USB or SSD" menu
# 2023.10.17
# Update : Add "Show error log of running loader" menu
# 2023.10.18 v0.9.6.0
# Update : Improved extension processing speed (local copy instead of remote curl download)
# 2023.10.22 v0.9.7.0
# Update : Improved build processing speed (removed pat file download process)
# 2023.10.24 v0.9.7.1
# Update : Back to DSM Pat Handle Method
# 2023.10.27 v1.0.0.0
# Update : Kernel patch process improvements    
# 2023.11.04 
# Update : Added DS1522+ (r1000), DS220+ (geminilake), DS2419+ (denverton), DS423+ (geminilake), DS718+ (apollolake), RS2423+ (v1000)
# 2023.11.28
# Update : Turn off thread limits when displaying models (Thanks alirz1)
# 2023.12.01
# Update : Separate tcrp-addons and tcrp-modules repo processing methods
# 2023.12.02
# Update : Add offline loader build function
# 2023.12.18 v1.0.1.0
# Update : Upgrade from Tinycore version 12.0 (kernel 5.10.3) to 14.0 (kernel 6.1.2) to improve compatibility with the latest devices.
# 2023.12.31        
# Added SataPortMap/DiskIdxMap prevent initialization menu for virtual machines  
# 2024.02.03
# Created a menu to select the mac-spoof add-on and a submenu for additional features.
# 2024.02.06
# update corepure64.gz for tc user ttyS0 serial console works
# 2024.02.08
# Add Apollolake DS218+
# 2024.02.22 v1.0.2.0
# Remove restrictions on use of DT-based models when using HBA (apply mpt3sas blacklist instead)
# 2024.03.06 v1.0.2.2
# Recycle initrd-dsm instead of custom.gz (extract /exts)
# 2024.03.13 v1.0.2.3 
# Added RedPill bootloader hard disk porting function
# 2024.03.15
# Added RedPill bootloader hard disk porting function supporting 1 SHR Type DISK
# 2024.03.18
# Added RedPill bootloader hard disk porting function supporting All SHR & RAID Type DISK
# 2024.03.22 v1.0.2.4 
# Added NVMe bootloader support
# 2024.03.23
# Fixed bug where both modules disappear when switching between ddsml and eudev (Causes NIC unresponsiveness)
# 2024.03.24    
# Added missing mmc partition search function
# 2024.04.01 v1.0.2.5
# Provides menu option to disable i915 module loading to prevent console blackout in ApolloLake (DS918+), GeminiLake (DS920+), and Epyc7002 (SA6400)
# 2024.04.09 v1.0.2.6
# Added multilingual support languages (locales) (Arabic, Hindi, Hungarian, Indonesian, Turkish)
# 2024.04.09 v1.0.2.7
# dbgutils Addon Add/Delete selection menu
# 2024.04.14
# sortnetif Addon Add/Delete selection menu
# 2024.05.08 v1.0.2.8
# Added multilingual support languages (locales) (Amharic-Ethiopian, Thai)
# 2024.05.13
# Menu configuration for adding nvmesystem addon
# 2024.05.26 v1.0.3.0
# Integrate my, rploader.sh, myfunc.h into functions.sh, optimize distribution
# 2024.06.01 v1.0.3.1, 1.0.3.2
# Added loader file packing menu for remote update, Added dom_szmax for jot mode
# 2024.06.04 v1.0.3.3 
# Boot entry order for jot mode synchronized with Friend's order
# 2024.06.08 v1.0.3.4
# Maintain boot-wait addon when using satadom in SA6400
# 2024.06.09 v1.0.3.5 
# Remove getstaticmodule() and undefined PROXY variables (cause of lkm download failure in final release)
# 2024.06.10 v1.0.3.6 
# Use intel_iommu on the command line
# 2024.06.11 v1.0.3.7 
# Add command line native satadom support option change menu
# 2024.06.17 v1.0.3.8
# Sort netif order by bus-id order (Synology netif sorting method)
# 2024.07.06 v1.0.3.9 
# NVMe-related function supplementation and error correction
# Discontinue use of sortnetif addon, discontinue use of sortnetif if there is only 1 NIC
# 2024.07.07 v1.0.4.0 
# Added sata_remap processing menu for SataPort reordering.
# 2024.08.23 v1.0.4.1 
# Added a feature to check whether the pre-counted number of disks matches when booting Friend
# 2024.08.26 v1.0.4.2
# Update : Add Support DSM 7.2.2-72803 Official Version
# 2024.08.31 v1.0.4.3 
# No separation between USB/SATA menus in Jot Mod (boot menu merge)
# 2024.09.05 v1.0.4.4 
# Loader building is blocked when using Apollolake + proxmox(kvm)/qemu(kvm) (KP occurs in versions after lkm 24.8.29)
# 2024.09.08 v1.0.4.5 
# Solved the KP occurrence issue when using SATA-type bootloader in proxmox(kvm), 
# SA6400(epyc7002) integration from lkm5 (lkm 24.9.8)
# 2024.09.09 v1.0.4.6 
# Rearrange menu order, automatically enter Gen value when S/N or mac is not selected
# 2024.09.12 v1.0.4.7 
# Fix from DSM 7.2.2-72803 to DSM 7.2.2-72806
# 2024.10.14 v1.0.4.8 
# Enable mmc (SD Card) bus type recognition for the bootloader
# 2024.10.15 v1.0.4.9 
# When mmc bus type is used, module processing method is applied with priority given to eudev instead of ddsml.
# 2024.10.26 v1.0.5.0 
# Improved internet check function in menu.sh
# 2024.11.04 v1.0.5.1 
# Added manual update feature to friend specified version, added disable/enable friend automatic update feature
# 2024.11.05 v1.0.5.2 
# Upgraded grub version from 2.06 to 2.12 ( improved uefi, legacy boot compatibility [especially in jot mode] )
# 2024.11.14 v1.0.6.0 
# Added the ability to choose between the integrated modules all-modules (tcrp) and rr-modules
# 2024.11.16 v1.0.6.1 
# Improved bootloader boot partition detection method
# 2024.11.19 v1.0.6.2 
# Changed to use only the first one when multiple bootloaders exist
# 2024.11.27 v1.0.6.3
# Added ability to force loading mmc and sd modules when loading Tinycore Linux
# 2024.12.17 v1.0.6.4 
# Expanded MAC address support from 4 to 8.
# 2024.12.20 v1.0.6.5 
# Includes tinycore linux scsi module for scsi type bootloader support.
# 2024.12.22 v1.0.6.6 
# Discontinuing support for DS3615xs.
# 2024.12.23 v1.0.6.7
# Applying REDPILL background image to grub boot
# 2025.01.01 v1.0.6.8
# i915.modeset=0 menu processing improvement (FRIEND guidance console is activated when i915 transcoding is disabled)
# 2025.01.06 v1.1.0.0 
# Added features for distribution of xTCRP (Tinycore Linux stripped down version)
# 2025.01.12 v1.1.0.1 
# When using a single m.2 NVMe volume, the DDSML error issue has occurred, 
# so menu usage has been excluded and related support has been strengthened.
# 2025.01.29 v1.2.0.0 
# Added new platforms purley, broadwellnkv2, broadwellntbap and started supporting all models for each platform
# 2025.02.02 v1.2.1.0 
# Create tinycore-mshell and xTCRP together in grub boot. Merge Re-install boot entries without USB/SATA distinction and fix KP bug.
# 2025.02.06 v1.2.1.1 
# Renewal of SynoDisk bootloader injection function
# 2025.02.07 v1.2.1.2 
# SynoDisk with Bootloader Injection Supports NVMe DISK
# 2025.02.09 v1.2.1.3 
# SynoDisk with Bootloader Injection Supports Single SHR DISK
# 2025.02.10 v1.2.1.4 
# SynoDisk with bootloader injection feature discontinues support for BASIC or JBOD DISK
# 2025.02.11 v1.2.1.5 
# SynoDisk with bootloader injection uses UUID 8765-4321 instead of 6234-C863
    
function showlastupdate() {
    cat <<EOF

# 2023.12.18 v1.0.1.0
# Update : Upgrade from Tinycore version 12.0 (kernel 5.10.3) to 14.0 (kernel 6.1.2) to improve compatibility with the latest devices.

# 2024.03.18
# Added RedPill bootloader hard disk porting function supporting All SHR & RAID Type DISK        

# 2024.03.22 v1.0.2.4 
# Added NVMe bootloader support

# 2024.05.13
# Menu configuration for adding nvmesystem addon

# 2024.05.26 v1.0.3.0
# Integrate my, rploader.sh, myfunc.h into functions.sh, optimize distribution

# 2024.06.01 v1.0.3.1, 1.0.3.2
# Added loader file packing menu for remote update, Added dom_szmax for jot mode

# 2024.06.04 v1.0.3.3 
# Boot entry order for jot mode synchronized with Friend's order

# 2024.06.08 v1.0.3.4
# Maintain boot-wait addon when using satadom in SA6400

# 2024.06.09 v1.0.3.5 
# Remove getstaticmodule() and undefined PROXY variables (cause of lkm download failure in final release)

# 2024.06.10 v1.0.3.6 
# Use intel_iommu on the command line

# 2024.06.11 v1.0.3.7 
#Add command line native satadom support option change menu

# 2024.06.17 v1.0.3.8
# Sort netif order by bus-id order (Synology netif sorting method)

# 2024.07.06 v1.0.3.9 
# NVMe-related function supplementation and error correction
# Discontinue use of sortnetif addon, discontinue use of sortnetif if there is only 1 NIC

# 2024.07.07 v1.0.4.0 
# Added sata_remap processing menu for SataPort reordering.

# 2024.08.23 v1.0.4.1 
# Added a feature to check whether the pre-counted number of disks matches when booting Friend
    
# 2024.08.26 v1.0.4.2
# Update : Add Support DSM 7.2.2-72803 Official Version

# 2024.08.31 v1.0.4.3 
# No separation between USB/SATA menus in Jot Mod (boot menu merge)

# 2024.09.05 v1.0.4.4 
# Loader building is blocked when using Apollolake + proxmox(kvm)/qemu(kvm) (KP occurs in versions after lkm 24.8.29)

# 2024.09.08 v1.0.4.5 
# Solved the KP occurrence issue when using SATA-type bootloader in proxmox(kvm), 
# SA6400(epyc7002) integration from lkm5 (lkm 24.9.8)

# 2024.09.09 v1.0.4.6 
# Rearrange menu order, automatically enter Gen value when S/N or mac is not selected

# 2024.09.12 v1.0.4.7 
# Fix from DSM 7.2.2-72803 to DSM 7.2.2-72806

# 2024.10.14 v1.0.4.8 
# Enable mmc (SD Card) bus type recognition for the bootloader

# 2024.10.15 v1.0.4.9 
# When mmc bus type is used, module processing method is applied with priority given to eudev instead of ddsml.

# 2024.10.26 v1.0.5.0 
# Improved internet check function in menu.sh

# 2024.11.04 v1.0.5.1 
# Added manual update feature to friend specified version, added disable/enable friend automatic update feature
# ( usage : ./functions.sh update v0.1.1j | ./functions.sh autoupdate off | ./functions.sh autoupdate on )

# 2024.11.05 v1.0.5.2 
# Upgraded grub version from 2.06 to 2.12 ( improved uefi, legacy boot compatibility [especially in jot mode] )

# 2024.11.14 v1.0.6.0 
# Added the ability to choose between the integrated modules all-modules (tcrp) and rr-modules

# 2024.11.16 v1.0.6.1 
# Improved bootloader boot partition detection method

# 2024.11.19 v1.0.6.2 
# Changed to use only the first one when multiple bootloaders exist

# 2024.11.27 v1.0.6.3
# Added ability to force loading mmc and sd modules when loading Tinycore Linux

# 2024.12.17 v1.0.6.4 
# Expanded MAC address support from 4 to 8.

# 2024.12.20 v1.0.6.5 
# Includes tinycore linux scsi module for scsi type bootloader support.

# 2024.12.22 v1.0.6.6 
# Discontinuing support for DS3615xs.

# 2024.12.23 v1.0.6.7
# Applying REDPILL background image to grub boot

# 2025.01.01 v1.0.6.8
# i915.modeset=0 menu processing improvement (FRIEND guidance console is activated when i915 transcoding is disabled)

# 2025.01.06 v1.1.0.0 
# Added features for distribution of xTCRP (Tinycore Linux stripped down version)

# 2025.01.12 v1.1.0.1 
# When using a single m.2 NVMe volume, the DDSML error issue has occurred, 
# so menu usage has been excluded and related support has been strengthened.

# 2025.01.29 v1.2.0.0 
# Added new platforms purley, broadwellnkv2, broadwellntbap and started supporting all models for each platform

# 2025.02.02 v1.2.1.0 
# Create tinycore-mshell and xTCRP together in grub boot. Merge Re-install boot entries without USB/SATA distinction and fix KP bug.

# 2025.02.06 v1.2.1.1 
# Renewal of SynoDisk bootloader injection function

# 2025.02.07 v1.2.1.2 
# SynoDisk with Bootloader Injection Supports NVMe DISK

# 2025.02.09 v1.2.1.3 
# SynoDisk with Bootloader Injection Supports Single SHR DISK

# 2025.02.10 v1.2.1.4 
# SynoDisk with bootloader injection feature discontinues support for BASIC or JBOD DISK

# 2025.02.11 v1.2.1.5 
# SynoDisk with bootloader injection uses UUID 8765-4321 instead of 6234-C863

EOF
}

function showhelp() {
    cat <<EOF
$(basename ${0})

----------------------------------------------------------------------------------------
Usage: ${0} <Synology Model Name> <Options>

Options: update, postupdate, noconfig, noclean, manual, realmac, userdts

- update : Option to handle updates to the m shell.

- postupdate : Option to patch the restore loop after applying DSM 7.1.0-42661 after Update 2, no additional build required.

- noconfig: SKIP automatic detection change processing such as SN/Mac/Vid/Pid/SataPortMap of user_config.json file.

- noclean: SKIP the 💊   RedPill LKM/LOAD directory without clearing it with the Clean command. 
           However, delete the Cache directory and loader.img.

- manual: Options for manual extension processing and manual dtc processing in build action (skipping extension auto detection).

- realmac : Option to use the NIC's real mac address instead of creating a virtual one.

- userdts : Option to use the user-defined platform.dts file instead of auto-discovery mapping with dtcpatch.


Please type Synology Model Name after ./$(basename ${0})

- for friend mode

./$(basename ${0}) DS918+-7.2.1-69057
./$(basename ${0}) DS3617xs-7.2.1-69057
./$(basename ${0}) DS3622xs+-7.2.1-69057
./$(basename ${0}) DVA3221-7.2.1-69057
./$(basename ${0}) DS920+-7.2.1-69057
./$(basename ${0}) DS1621+-7.2.1-69057
./$(basename ${0}) DS2422+-7.2.1-69057
./$(basename ${0}) DVA1622-7.2.1-69057
./$(basename ${0}) DS1520+-7.2.1-69057
./$(basename ${0}) FS2500-7.2.1-69057
./$(basename ${0}) DS1621xs+-7.2.1-69057
./$(basename ${0}) RS4021xs+-7.2.1-69057 
./$(basename ${0}) DVA3219-7.2.1-69057
./$(basename ${0}) RS3618xs-7.2.1-69057
./$(basename ${0}) DS1019+-7.2.1-69057
./$(basename ${0}) DS923+-7.2.1-69057
./$(basename ${0}) DS723+-7.2.1-69057
./$(basename ${0}) SA6400-7.2.1-69057
./$(basename ${0}) DS720+-7.2.1-69057
./$(basename ${0}) RS1221+-7.2.1-69057
./$(basename ${0}) RS2423+-7.2.1-69057
./$(basename ${0}) RS1619xs+-7.2.1-69057
./$(basename ${0}) RS3621xs+-7.2.1-69057
./$(basename ${0}) SA6400-7.2.1-69057
./$(basename ${0}) DS916+-7.2.1-69057
./$(basename ${0}) DS1821+-7.2.1-69057
./$(basename ${0}) DS1819+-7.2.1-69057
./$(basename ${0}) DS1823xs+-7.2.1-69057
./$(basename ${0}) DS620slim+-7.2.1-69057

ex) Except for postupdate and userdts that must be used alone, the rest of the options can be used in combination. 

- When you want to build the loader while maintaining the already set SN/Mac/Vid/Pid/SataPortMap
./my DS3622xs+H noconfig

- When you want to build the loader while maintaining the already set SN/Mac/Vid/Pid/SataPortMap and without deleting the downloaded DSM pat file.
./my DS3622xs+H noconfig noclean

- When you want to build the loader while using the real MAC address of the NIC, with extended auto-detection disabled
./my DS3622xs+H realmac manual

EOF

}

function getloaderdisk() {
    loaderdisk=""
    while read -r edisk; do
        if [ $(sudo /sbin/fdisk -l "$edisk" | grep -c "83 Linux") -eq 3 ]; then
            loaderdisk=$(/sbin/blkid | grep "6234-C863" | cut -d ':' -f1 | sed 's/p\?3//g' | awk -F/ '{print $NF}' | head -n 1)
            if [ -n "$loaderdisk" ]; then
                break
            else
                # check for the other type
                loaderdisk="$(echo ${edisk} | cut -c 1-12 | awk -F\/ '{print $3}')"
                [ -n "$loaderdisk" ] && break
            fi
        fi
    done < <(lsblk -ndo NAME | grep -v '^loop' | grep -v '^zram' | sed 's/^/\/dev\//')

    echo "LOADER DISK: $loaderdisk"
}

# ==============================================================================          
# Color Function                                                                          
# ==============================================================================          
function cecho () {                                                                                
#    if [ -n "$3" ]                                                                                                            
#    then                                                                                  
#        case "$3" in                                                                                 
#            black  | bk) bgcolor="40";;                                                              
#            red    |  r) bgcolor="41";;                                                              
#            green  |  g) bgcolor="42";;                                                                 
#            yellow |  y) bgcolor="43";;                                             
#            blue   |  b) bgcolor="44";;                                             
#            purple |  p) bgcolor="45";;                                                   
#            cyan   |  c) bgcolor="46";;                                             
#            gray   | gr) bgcolor="47";;                                             
#        esac                                                                        
#    else                                                                            
        bgcolor="0"                                                                 
#    fi                                                                              
    code="\033["                                                                    
    case "$1" in                                                                    
        black  | bk) color="${code}${bgcolor};30m";;                                
        red    |  r) color="${code}${bgcolor};31m";;                                
        green  |  g) color="${code}${bgcolor};32m";;                                
        yellow |  y) color="${code}${bgcolor};33m";;                                
        blue   |  b) color="${code}${bgcolor};34m";;                                
        purple |  p) color="${code}${bgcolor};35m";;                                
        cyan   |  c) color="${code}${bgcolor};36m";;                                
        gray   | gr) color="${code}${bgcolor};37m";;                                
    esac                                                                            
                                                                                                                                                                    
    text="$color$2${code}0m"                                                                                                                                        
    echo -e "$text"                                                                                                                                                 
}   

function getvarsmshell()
{

    # Set the path for the models.json file
    MODELS_JSON="/home/tc/models.json"

    # Define platform groups
    platforms="epyc7002 broadwellnk broadwell bromolow broadwellnkv2 broadwellntbap purley denverton apollolake r1000 v1000 geminilake"

    # Initialize MODELS array
    MODELS=()

    # Extract models for each platform and add them to the mdl file
    for platform in $platforms; do
      models=$(jq -r ".$platform.models[]" "$MODELS_JSON" 2>/dev/null)
      if [ -n "$models" ]; then
        MODELS+=($models)
      fi
    done
    
    SUVP=""
    ORIGIN_PLATFORM=""

    tem="${1}"

    MODEL="$(echo ${tem} |cut -d '-' -f 1)"
    TARGET_REVISION="$(echo ${tem} |cut -d '-' -f 3)"    
    if [ "$TARGET_REVISION" == "64570" ]; then
      TARGET_VERSION="$(echo ${tem} |cut -d '-' -f 2 | cut -c 1-3)"
    else
      TARGET_VERSION="$(echo ${tem} |cut -d '-' -f 2)"
    fi

    #echo "MODEL is $MODEL"
    TARGET_PLATFORM=$(echo "$MODEL" | sed 's/DS/ds/' | sed 's/RS/rs/' | sed 's/+/p/' | sed 's/DVA/dva/' | sed 's/FS/fs/' | sed 's/SA/sa/' )
    SYNOMODEL="${TARGET_PLATFORM}_${TARGET_REVISION}"
    
    if [ $(echo ${MODELS[@]} | grep ${MODEL} | wc -l ) -eq 0 ]; then
        echo "This synology model not supported by TCRP."
        exit 99
    fi
    
    if [ "$TARGET_REVISION" == "42218" ]; then
        KVER="4.4.180"
        SUVP=""
    elif [ "$TARGET_REVISION" == "42962" ]; then
        KVER="4.4.180"
        MODELS6="DS423+ DS723+ DS923+ DS1823xs+ RS3621xs+ RS4021xs+ RS3618xs SA6400"
        if [ $(echo ${MODELS6} | grep ${MODEL} | wc -l ) -gt 0 ]; then
           SUVP="-6"
        else
           SUVP="-1"
        fi
    elif [ "$TARGET_REVISION" == "64570" ]; then
        KVER="4.4.302"
        SUVP="-1" 
    elif [ "$TARGET_REVISION" == "69057" ]; then
        KVER="4.4.302"
        SUVP="-1"
    elif [ "$TARGET_REVISION" == "72806" ]; then
        KVER="4.4.302"
        SUVP="" 
    else
        echo "Synology model revision not supported by TCRP."
        exit 0
    fi

    #SFVAL=${SUVP:--0}

    # Extract models for each platform and add them to the mdl file
    for platform in $platforms; do
      # Initialize MODELS array
      MODELS=()
      models=$(jq -r ".$platform.models[]" "$MODELS_JSON" 2>/dev/null)
      if [ -n "$models" ]; then
        MODELS=($models)
      fi
      if [ $(echo ${MODELS[@]} | grep ${MODEL} | wc -l ) -gt 0 ]; then
        ORIGIN_PLATFORM="${platform}"
        case ${platform} in
        bromolow) KVER="3.10.108";;
        epyc7002) KVER="5.10.55";; 
        esac
        break
      fi
    done    
    
    case ${MODEL} in
    DS224+)
        permanent="WBR"
        serialstart="2350"
        suffix="alpha"
        ;;
    DS423+)
        permanent="VKR"
        serialstart="22A0"
        suffix="alpha"
        ;;
    DS718+)
        permanent="PEN"
        serialstart="1930"
        suffix="numeric"
        ;;
    DS720+)
        permanent="QWR"
        serialstart="2010 2110"
        suffix="alpha"
        ;;
    DS918+)
        permanent="PDN"
        serialstart="1910"
        suffix="numeric"
        ;;
    DS920+)
        permanent="SBR"
        serialstart="2030 2040 20C0 2150"
        suffix="alpha"
        ;;
    DS923+)
        permanent="TQR"
        serialstart="2270"
        suffix="alpha"
        ;;
    DS1019+)
        permanent="QXR"
        serialstart="1850 1880"
        suffix="numeric"
        ;;
    DS1520+)
        permanent="RYR"
        serialstart="2060"
        suffix="alpha"
        ;;
    DS1522+)
        permanent="TRR"
        serialstart="2270"
        suffix="alpha"
        ;;
    DS1621+)
        permanent="S7R"
        serialstart="2080"
        suffix="alpha"
        ;;
    DS1621xs+)
        permanent="RVR"
        serialstart="2070"
        suffix="alpha"
        ;;
    DS1819+)
        permanent="R5R"
        serialstart="1890"
        suffix="alpha"
        ;;
    DS1821+)
        permanent="SKR"
        serialstart="2110"
        suffix="alpha"
        ;;
    DS1823xs+)
        permanent="V5R"
        serialstart="2280"
        suffix="alpha"
        ;;
    DS2419+)
        permanent="QZA"
        serialstart="1880"
        suffix="alpha"
        ;;
    DS2422+)
        permanent="SLR"
        serialstart="2140 2180"
        suffix="alpha"
        ;;
    DS3617xs)
        permanent="ODN"
        serialstart="1130 1230 1330 1430"
        suffix="numeric"
        ;;
    DS3622xs+)
        permanent="SQR"
        serialstart="2150"
        suffix="alpha"
        ;;
    DVA1622)
        permanent="UBR"
        serialstart="2030 2040 20C0 2150"
        suffix="alpha"
        ;;
    DVA3219)
        permanent="RFR"
        serialstart="1930 1940"
        suffix="alpha"
        ;;
    DVA3221)
        permanent="SJR"
        serialstart="2030 2040 20C0 2150"
        suffix="alpha"
        ;;
    FS2500)
        permanent="PSN"
        serialstart="1960"
        suffix="numeric"
        ;;
    FS6400)
        permanent="XXX"
        serialstart="0000"
        suffix="alpha"
        ;;
    HD6500)
        permanent="RUR"
        serialstart="20A0 21C0"
        suffix="alpha"
        ;;
    RS1221+)
        permanent="RWR"
        serialstart="20B0"
        suffix="alpha"
        ;;
    RS1619xs+)
        permanent="QPR"
        serialstart="1920"
        suffix="alpha"
        ;;
    RS2423RP+)
        permanent="V3R"
        serialstart="22B0"
        suffix="alpha"
        ;;
    RS3621xs+)
        permanent="SZR"
        serialstart="20A0"
        suffix="alpha"
        ;;
    RS4021xs+)
        permanent="T2R"
        serialstart="2160"
        suffix="alpha"
        ;;
    SA3200D)
        permanent="S4R"
        serialstart="19A0"
        suffix="alpha"
        ;;
    SA3400)
        permanent="RJR"
        serialstart="1970"
        suffix="alpha"
        ;;
    SA6400)
        permanent="W8R"
        serialstart="2350"
        suffix="alpha"
        ;;
    SA3410)
        permanent="UMR"
        serialstart="2270"
        suffix="alpha"
        ;;
    *)
        permanent="XXX"
        serialstart="0000"
        suffix="alpha"
        ;;
    esac


}

# Function READ_YN, cecho                                                                                        
# Made by FOXBI
# 2022.04.14                                                                                                                  
#                                                                                                                             
# ==============================================================================                                              
# Y or N Function                                                                                                             
# ==============================================================================                                              
function READ_YN () { # ${1}:question ${2}:default                                                                                         
    while true; do
        read -n1 -p "${1}" Y_N                                                                                                       
        case "$Y_N" in                                                                                                            
            [Yy]* ) Y_N="y"                                                                                                                
                 echo -e "\n"; break ;;                                                                                                      
            [Nn]* ) Y_N="n"                                                                                                                
                 echo -e "\n"; break ;;                                                                                                      
            *) echo -e "Please answer in Y / y or N / n.\n" ;;                                                                                                        
        esac                                                                                                                      
    done        
}                                                                                         

function st() {
echo -e "[$(date '+%T.%3N')]:-------------------------------------------------------------" >> /home/tc/buildstatus
echo -e "\e[35m$1\e[0m	\e[36m$2\e[0m	$3" >> /home/tc/buildstatus
}

function getlatestmshell() {

    echo -n "Checking if a newer mshell version exists on the repo -> "

    if [ ! -f $mshellgz ]; then
        curl -ksL "$mshtarfile" -o $mshellgz
    fi

    curl -ksL "$mshtarfile" -o latest.mshell.gz

    CURRENTSHA="$(sha256sum $mshellgz | awk '{print $1}')"
    REPOSHA="$(sha256sum latest.mshell.gz | awk '{print $1}')"

    if [ "${CURRENTSHA}" != "${REPOSHA}" ]; then
    
        if [ "${1}" = "noask" ]; then
            confirmation="y"
        else
            echo -n "There is a newer version of m shell script on the repo should we use that ? [yY/nN]"
            read confirmation
        fi
    
        if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
            echo "OK, updating, please re-run after updating"
            cp -f /home/tc/latest.mshell.gz /home/tc/$mshellgz
            rm -f /home/tc/latest.mshell.gz
            tar -zxvf $mshellgz
            echo "Updating m shell with latest updates"
            . /home/tc/functions.sh
            showlastupdate
            echo "y"|rploader backup
            echo "press any key to continue..."                                                                                                   
            read answer            
        else
            rm -f /home/tc/latest.mshell.gz
        fi
    else
        echo "Version is current"
        rm -f /home/tc/latest.mshell.gz
    fi

}

function macgen() {
echo

    if [ "$realmac" == 'Y' ] ; then
        mac2=$(/sbin/ifconfig eth1 | head -1 | awk '{print $NF}')
        echo "Real Mac2 Address : $mac2"
        echo "Notice : realmac option is requested, real mac2 will be used"
    else
        mac2="$(generateMacAddress ${1})"
    fi

    cecho y "Mac2 Address for Model ${1} : $mac2 "

    macaddress2=$(echo $mac2 | sed -s 's/://g')

    if [ $(cat user_config.json | grep "mac2" | wc -l) -gt 0 ]; then
        bf_mac2="$(cat user_config.json | grep "mac2" | cut -d ':' -f 2 | cut -d '"' -f 2)"
        cecho y "The Mac2 address : $bf_mac2 already exists. Change an existing value."
        json="$(jq --arg var "$macaddress2" '.extra_cmdline.mac2 = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
#        sed -i "/mac2/s/'$bf_mac2'/'$macaddress2'/g" user_config.json
    else
        sed -i "/\"extra_cmdline\": {/c\  \"extra_cmdline\": {\"mac2\": \"$macaddress2\",\"netif_num\": \"2\", "  user_config.json
    fi

    echo "After changing user_config.json"      
    cat user_config.json

}

function generateMacAddress() {
    printf '00:11:32:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))

}
function random() {
        printf "%06d" $(($RANDOM % 30000 + 1))
}
function randomhex() {
        val=$(($RANDOM % 255 + 1))
        echo "obase=16; $val" | bc
}
function generateRandomLetter() {
        for i in a b c d e f g h j k l m n p q r s t v w x y z; do
            echo $i
        done | sort -R | tail -1
}
function generateRandomValue() {
        for i in 0 1 2 3 4 5 6 7 8 9 a b c d e f g h j k l m n p q r s t v w x y z; do
            echo $i
        done | sort -R | tail -1
}
function toupper() {
       echo $1 | tr '[:lower:]' '[:upper:]'
}
function generateSerial() {
    case ${suffix} in
    numeric)
        serialnum="$(echo "$serialstart" | tr ' ' '\n' | sort -R | tail -1)$permanent"$(random)
        ;;
    alpha)
        serialnum=$(toupper "$(echo "$serialstart" | tr ' ' '\n' | sort -R | tail -1)$permanent"$(generateRandomLetter)$(generateRandomValue)$(generateRandomValue)$(generateRandomValue)$(generateRandomValue)$(generateRandomLetter))
        ;;
    *)    
        serialnum="$(echo "$serialstart" | tr ' ' '\n' | sort -R | tail -1)$permanent"$(random)
        ;;  
    esac
    echo $serialnum
}

function msgalert() {
    echo -e "\033[1;31m$1\033[0m"
}
function msgwarning() {
    echo -e "\033[1;33m$1\033[0m"
}
function msgnormal() {
    echo -e "\033[1;32m$1\033[0m"
} 

function readanswer() {
    while true; do
        read answ
        case $answ in
            [Yy]* ) answer="$answ"; break;;
            [Nn]* ) answer="$answ"; break;;
            * ) msgwarning "Please answer yY/nN.";;
        esac
    done
}        

###############################################################################
# Write to json config file
function writeConfigKey() {

    block="$1"
    field="$2"
    value="$3"

    if [ -n "$1 " ] && [ -n "$2" ]; then
        jsonfile=$(jq ".$block+={\"$field\":\"$value\"}" $userconfigfile)
        echo $jsonfile | jq . >$userconfigfile
    else
        echo "No values to update"
    fi

}

###############################################################################
# Delete field from json config file
function DeleteConfigKey() {

    block="$1"
    field="$2"

    if [ -n "$1 " ] && [ -n "$2" ]; then
        jsonfile=$(jq "del(.$block.$field)" $userconfigfile)
        echo $jsonfile | jq . >$userconfigfile
    else
        echo "No values to remove"
    fi

}
    
function checkmachine() {

    if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
        MACHINE="VIRTUAL"
        HYPERVISOR=$(dmesg | grep -i "Hypervisor detected" | awk '{print $5}')
        echo "Machine is $MACHINE Hypervisor=$HYPERVISOR"
    else
        MACHINE="NON-VIRTUAL"
    fi

    if [ $(lspci -nn | grep -ie "\[0107\]" | wc -l) -gt 0 ]; then
        echo "Found SAS HBAs, Restrict use of DT Models."
        HBADETECT="ON"
    else
        HBADETECT="OFF"    
    fi   
    
}

function checkinternet() {

    echo -n "Checking Internet Access -> "
#    nslookup $gitdomain 2>&1 >/dev/null
    curl --insecure -L -s https://raw.githubusercontent.com/about.html -O 2>&1 >/dev/null

    if [ $? -eq 0 ]; then
        echo "OK"
    else
        cecho g "Error: No internet found, or $gitdomain is not accessible"
        
        gitdomain="giteas.duckdns.org"
        cecho p "Try to connect to $gitdomain......"
        nslookup $gitdomain 2>&1 >/dev/null
        if [ $? -eq 0 ]; then
            echo "OK"
        else
            cecho g "Error: No internet found, or $gitdomain is not accessible"
            exit 99
        fi
    fi

}

###############################################################################
# check for Sas module
function checkforsas() {

    sasmods="mpt3sas hpsa mvsas"
    for sasmodule in $sasmods
    do
        echo "Checking existense of $sasmodule"
        for sas in `depmod -n 2>/dev/null |grep -i $sasmodule |grep pci|cut -d":" -f 2 | cut -c 6-9,15-18`
    do
        if [ `grep -i $sas /proc/bus/pci/devices |wc -l` -gt 0 ] ; then
            echo "  => $sasmodule, device found, block eudev mode" 
            BLOCK_EUDEV="Y"
        fi
    done
    done 
}

###############################################################################
# check Intel or AMD
function checkcpu() {

    if [ $(lscpu |grep Intel |wc -l) -gt 0 ]; then
        CPU="INTEL"
    else
        if [ $(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//' | grep -e N36L -e N40L -e N54L | wc -l) -gt 0 ]; then
            CPU="HP"
            LDRMODE="JOT"
            writeConfigKey "general" "loadermode" "${LDRMODE}"
        else
            CPU="AMD"
        fi        
    fi
    
    if [ $(lscpu |grep movbe |wc -l) -gt 0 ]; then    
        AFTERHASWELL="ON"
    else
        AFTERHASWELL="OFF"
    fi
    
    if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
        AFTERHASWELL="ON"    
    fi

}

###############################################################################
# Get fastest url in list
# @ - url list
function _get_fastest() {
  local speedlist=""
  for I in $@; do
    speed=$(ping -c 1 -W 5 ${I} 2>/dev/null | awk '/time=/ {print $7}' | cut -d '=' -f 2)
    speedlist+="${I} ${speed:-999}\n"
  done
  fastest="$(echo -e "${speedlist}" | tr -s '\n' | sort -k2n | head -1 | awk '{print $1}')"
  echo "${fastest}"
}

function chkavail() {

    if [ $(df -h /mnt/${tcrppart} | grep mnt | awk '{print $4}' | grep G | wc -l) -gt 0 ]; then
        avail_str=$(df -h /mnt/${tcrppart} | grep mnt | awk '{print $4}' | sed -e 's/G//g' | cut -c 1-3)
        avail=$(echo "$avail_str 1000" | awk '{print $1 * $2}')
    else
        avail=$(df -h /mnt/${tcrppart} | grep mnt | awk '{print $4}' | sed -e 's/M//g' | cut -c 1-3)
    fi

    avail_num=$(($avail))
    
    echo "Avail space ${avail_num}M on /mnt/${tcrppart}"
}    

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  BUS=""
  # usb/ata(sata/ide)/scsi
  [ -z "${BUS}" ] && BUS=$(udevadm info --query property --name "${1}" 2>/dev/null | grep ID_BUS | cut -d= -f2 | sed 's/ata/sata/')
  # usb/sata(sata/ide)/nvme
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${1} " | awk '{print $2}') #Spaces are intentional
  # usb/scsi(sata/ide)/virtio(scsi/virtio)/mmc/nvme/loop block
  [ -z "${BUS}" ] && BUS=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${1} " | awk '{print $2}' | awk -F':' '{print (NF>1) ? $2 : $0}') #Spaces are intentional
  # empty is block
  [ -z "${BUS}" ] && BUS="block"
  echo "${BUS}"

  [ "${BUS}" = "nvme" ] && [[ "${loaderdisk}" != *p ]] && loaderdisk="${loaderdisk}p"
  [ "${BUS}" = "mmc"  ] && [[ "${loaderdisk}" != *p ]] && loaderdisk="${loaderdisk}p"
  [ "${BUS}" = "block" ] && [[ "${loaderdisk}" != *p ]] && loaderdisk="${loaderdisk}p"

}

###############################################################################
# git clone redpill-load
function gitdownload() {

    git config --global http.sslVerify false   

    if [ -d "/home/tc/redpill-load" ]; then
        cecho y "Loader sources already downloaded, pulling latest !!!"
        cd /home/tc/redpill-load
        git pull
        if [ $? -ne 0 ]; then
           cd /home/tc    
           rploader clean 
           git clone -b master --single-branch https://github.com/PeterSuh-Q3/redpill-load.git
           #git clone -b master --single-branch https://giteas.duckdns.org/PeterSuh-Q3/redpill-load.git
        fi   
        cd /home/tc
    else
        git clone -b master --single-branch https://github.com/PeterSuh-Q3/redpill-load.git
        #git clone -b master --single-branch https://giteas.duckdns.org/PeterSuh-Q3/redpill-load.git
    fi

}

function _pat_process() {

  PATURL="${URL}"
  PAT_FILE="${SYNOMODEL}.pat"
  PAT_PATH="${patfile}"
  #mirrors=("global.synologydownload.com" "global.download.synology.com" "cndl.synology.cn")
  mirrors=("global.synologydownload.com" "global.download.synology.com")

  fastest=$(_get_fastest "${mirrors[@]}")
  echo "fastest = " "${fastest}"
  mirror="$(echo ${PATURL} | sed 's|^http[s]*://\([^/]*\).*|\1|')"
  echo "mirror = " "${mirror}"
  if echo "${mirrors[@]}" | grep -wq "${mirror}" && [ "${mirror}" != "${fastest}" ]; then
      echo "Based on the current network situation, switch to ${fastest} mirror to downloading."
      PATURL="$(echo ${PATURL} | sed "s/${mirror}/${fastest}/")"
  fi

  # Discover remote file size
  echo "BUS type = ${BUS} (Discover remote file size)"
  if [ "${BUS}" != "block"  ]; then
      SPACELEFT=$(df --block-size=1 | awk '/'${loaderdisk}'3/{print $4}') # Check disk space left
      FILESIZE=$(curl -k -sLI "${PATURL}" | grep -i Content-Length | awk '{print$2}')

      FILESIZE=$(echo "${FILESIZE}" | tr -d '\r')
      SPACELEFT=$(echo "${SPACELEFT}" | tr -d '\r')

      FILESIZE_FORMATTED=$(printf "%'d" "${FILESIZE}")
      SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
      FILESIZE_MB=$((FILESIZE / 1024 / 1024))
      SPACELEFT_MB=$((SPACELEFT / 1024 / 1024))    
    
      echo "FILESIZE  = ${FILESIZE_FORMATTED} bytes (${FILESIZE_MB} MB)"
      echo "SPACELEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"
    
      if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
          # No disk space to download, change it to RAMDISK
          echo "No adequate space on ${local_cache} to download file into cache folder, clean up PAT file now ....."
          sudo sh -c "sudo rm -vf $(ls -t ${local_cache}/*.pat | head -n 1)"
      fi
  fi
  
  echo "PATURL = " "${PATURL}"
  STATUS=$(sudo curl -k -w "%{http_code}" -L "${PATURL}" -o "${PAT_PATH}" --progress-bar)
  if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      sudo rm -f "${PAT_PATH}"
      echo "Check internet or cache disk space.\nError: ${STATUS}"
      exit 99
  fi

}

function setnetwork() {

    if [ -f /opt/eth*.sh ] && [ "$(grep dhcp /opt/eth*.sh | wc -l)" -eq 0 ]; then

        ipset="static"
        ipgw="$(route | grep default | head -1 | awk '{print $2}')"
        ipprefix="$(grep /sbin/ifconfig /opt/eth*.sh | head -1 | awk '{print "ipcalc -p " $3 " " $5 }' | sh - | awk -F= '{print $2}')"
        myip="$(grep /sbin/ifconfig /opt/eth*.sh | head -1 | awk '{print $3 }')"
        ipaddr="${myip}/${ipprefix}"
        ipgw="$(grep route /opt/eth*.sh | head -1 | awk '{print  $5 }')"
        ipdns="$(grep nameserver /opt/eth*.sh | head -1 | awk '{print  $3 }')"
        ipproxy="$(env | grep -i http | awk -F= '{print $2}' | uniq)"

        for field in ipset ipaddr ipgw ipdns ipproxy; do
            jsonfile=$(jq ".ipsettings+={\"$field\":\"${!field}\"}" $userconfigfile)
            echo $jsonfile | jq . >$userconfigfile
        done

    fi

}

function getip() {
    ethdevs=$(ls /sys/class/net/ | grep eth || true)
    for eth in $ethdevs; do 
        DRIVER=$(ls -ld /sys/class/net/${eth}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
        if [ $(ls -l /sys/class/net/${eth}/device | grep "0000:" | wc -l) -gt 0 ]; then
            BUSID=$(ls -ld /sys/class/net/${eth}/device 2>/dev/null | awk -F '0000:' '{print $NF}')
        else
            BUSID=""
        fi
        IP="$(/sbin/ifconfig ${eth} | grep inet | awk '{print $2}' | awk -F \: '{print $2}')"
        HWADDR="$(/sbin/ifconfig ${eth} | grep HWaddr | awk '{print $5}')"
        if [ -f /sys/class/net/${eth}/device/vendor ] && [ -f /sys/class/net/${eth}/device/device ]; then
            VENDOR=$(cat /sys/class/net/${eth}/device/vendor | sed 's/0x//')
            DEVICE=$(cat /sys/class/net/${eth}/device/device | sed 's/0x//')
            if [ ! -z "${VENDOR}" ] && [ ! -z "${DEVICE}" ]; then
                MATCHDRIVER=$(echo "$(matchpciidmodule ${VENDOR} ${DEVICE})")
                if [ ! -z "${MATCHDRIVER}" ]; then
                    if [ "${MATCHDRIVER}" != "${DRIVER}" ]; then
                        DRIVER=${MATCHDRIVER}
                    fi
                fi
            fi    
        fi    
        echo "IP Addr : $(msgnormal "${IP}"), ${HWADDR}, ${BUSID}, ${eth} (${DRIVER})"
    done
}

function listpci() {

    lspci -n | while read line; do

        bus="$(echo $line | cut -c 1-7)"
        class="$(echo $line | cut -c 9-12)"
        vendor="$(echo $line | cut -c 15-18)"
        device="$(echo $line | cut -c 20-23)"

        #echo "PCI : $bus Class : $class Vendor: $vendor Device: $device"
        case $class in
#        0100)
#            echo "Found SCSI Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0106)
#            echo "Found SATA Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0101)
#            echo "Found IDE Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
        0104)
            msgnormal "RAID bus Controller : Required Extension : $(matchpciidmodule ${vendor} ${device})"
            echo `lspci -nn |grep ${vendor}:${device}|awk 'match($0,/0104/) {print substr($0,RSTART+7,100)}'`| sed 's/\['"$vendor:$device"'\]//' | sed 's/(rev 05)//'
            ;;
        0107)
            msgnormal "SAS Controller : Required Extension : $(matchpciidmodule ${vendor} ${device})"
            echo `lspci -nn |grep ${vendor}:${device}|awk 'match($0,/0107/) {print substr($0,RSTART+7,100)}'`| sed 's/\['"$vendor:$device"'\]//' | sed 's/(rev 03)//'
            ;;
#        0200)
#            msgnormal "Ethernet Interface : Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0680)
#            msgnormal "Ethernet Interface : Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0300)
#            echo "Found VGA Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
#        0c04)
#            echo "Found Fibre Channel Controller : pciid ${vendor}d0000${device}  Required Extension : $(matchpciidmodule ${vendor} ${device})"
#            ;;
        esac
    done

}

function monitor() {

    getloaderdisk
    if [ -z "${loaderdisk}" ]; then
        echo "Not Supported Loader BUS Type, program Exit!!!"
        exit 99
    fi

    getBus "${loaderdisk}" 

    [ "$(mount | grep /dev/${loaderdisk}1 | wc -l)" -eq 0 ] && mount /dev/${loaderdisk}1
    [ "$(mount | grep /dev/${loaderdisk}2 | wc -l)" -eq 0 ] && mount /dev/${loaderdisk}2

    HYPERVISOR=$(dmesg | grep -i "Hypervisor detected" | awk '{print $5}')

    while true; do
        clear
        echo -e "-------------------------------System Information----------------------------"
        echo -e "Hostname:\t\t"$(hostname) 
        echo -e "uptime:\t\t\t"$(uptime | awk '{print $3}' | sed 's/,//')" min"
        echo -e "Manufacturer:\t\t"$(cat /sys/class/dmi/id/chassis_vendor) 
        echo -e "Product Name:\t\t"$(cat /sys/class/dmi/id/product_name)
        echo -e "Version:\t\t"$(cat /sys/class/dmi/id/product_version)
        echo -e "Serial Number:\t\t"$(sudo cat /sys/class/dmi/id/product_serial)
        echo -e "Operating System:\t"$(grep PRETTY_NAME /etc/os-release | awk -F \= '{print $2}')
        echo -e "Kernel:\t\t\t"$(uname -r)
        echo -e "Processor Name:\t\t"$(awk -F':' '/^model name/ {print $2}' /proc/cpuinfo | uniq | sed -e 's/^[ \t]*//')
        echo -e "Machine Type:\t\t"$(
            vserver=$(lscpu | grep Hypervisor | wc -l)
            if [ $vserver -gt 0 ]; then echo "VM (${HYPERVISOR})"; else echo "Physical"; fi
        ) 
        msgnormal "CPU Threads:\t\t"$(nproc)
        echo -e "Current Date Time:\t"$(date)
        #msgnormal "System Main IP:\t\t"$(/sbin/ifconfig | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | awk -F \: '{print $2}' | tr '\n' ',' | sed 's#,$##')
        getip
        listpci
        echo -e "-------------------------------Loader boot entries---------------------------"
        grep -i menuentry /mnt/${loaderdisk}1/boot/grub/grub.cfg | awk -F \' '{print $2}'
        echo -e "-------------------------------CPU / Memory----------------------------------"
        msgnormal "Total Memory (MB):\t"$(cat /proc/meminfo |grep MemTotal | awk '{printf("%.2f%"), $2/1000}')
        echo -e "Swap Usage:\t\t"$(free | awk '/Swap/{printf("%.2f%"), $3/$2*100}')
        echo -e "CPU Usage:\t\t"$(cat /proc/stat | awk '/cpu/{printf("%.2f%\n"), ($2+$4)*100/($2+$4+$5)}' | awk '{print $0}' | head -1)
        echo -e "-------------------------------Disk Usage >80%-------------------------------"
        df -Ph /mnt/${loaderdisk}1 /mnt/${loaderdisk}2 /mnt/${loaderdisk}3

        echo "Press ctrl-c to exit"
        sleep 10
    done

}

function savesession() {

    lastsessiondir="/mnt/${tcrppart}/lastsession"

    echo -n "Saving user session for future use. "

    [ ! -d ${lastsessiondir} ] && sudo mkdir ${lastsessiondir}

    echo -n "Saving current extensions "

    if [ "$FRKRNL" = "NO" ]; then
        cat /home/tc/redpill-load/custom/extensions/*/*json | jq '.url' >${lastsessiondir}/extensions.list
    else
        echo
    fi

    [ -f ${lastsessiondir}/extensions.list ] && echo " -> OK !"

    echo -n "Saving current user_config.json "

    if [ "$FRKRNL" = "NO" ]; then
        cp /home/tc/user_config.json ${lastsessiondir}/user_config.json
    else
        sudo cp /home/tc/user_config.json ${lastsessiondir}/user_config.json
    fi

    [ -f ${lastsessiondir}/user_config.json ] && echo " -> OK !"

}

function copyextractor() {
#m shell mofified
    local_cache="/mnt/${tcrppart}/auxfiles"

    echo "making directory ${local_cache}"
    [ ! -d ${local_cache} ] && mkdir ${local_cache}

    echo "making directory ${local_cache}/extractor"
    [ ! -d ${local_cache}/extractor ] && sudo mkdir ${local_cache}/extractor
    [ ! -f /home/tc/extractor.gz ] && sudo curl -kL -# "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/extractor.gz" -o /home/tc/extractor.gz
    sudo tar -zxvf /home/tc/extractor.gz -C ${local_cache}/extractor

    if [ "${BUS}" = "block"  ]; then
      git clone https://github.com/technorabilia/syno-extract-system-patch.git
      cd syno-extract-system-patch
      sudo docker build --tag syno-extract-system-patch .
      sudo mkdir -p ~/data/in
      sudo mkdir -p ~/data/out
    fi

    echo "Copying required libraries to local lib directory"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/lib* /lib/
    echo "Linking lib to lib64"
    [ ! -h /lib64 ] && sudo ln -s /lib /lib64
    echo "Copying executable"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/scemd /bin/syno_extract_system_patch
    echo "pigz copy for multithreaded compression"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/pigz /usr/bin/pigz

}

function downloadextractor() {

st "extractor" "Extraction tools" "Extraction Tools downloaded"        
#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    local_cache="/mnt/${tcrppart}/auxfiles"
    temp_folder="/tmp/synoesp"

#m shell mofified
    copyextractor

    if [ -d ${local_cache/extractor /} ] && [ -f ${local_cache}/extractor/scemd ]; then

        msgnormal "Found extractor locally cached"

    else

        echo "Getting required extraction tool"
        echo "------------------------------------------------------------------"
        echo "Checking tinycore cache folder"

        [ -d $local_cache ] && echo "Found tinycore cache folder, linking to home/tc/custom-module" && [ ! -h /home/tc/custom-module ] && sudo ln -s $local_cache /home/tc/custom-module

        echo "Creating temp folder /tmp/synoesp"

        mkdir ${temp_folder}

        if [ -d /home/tc/custom-module ] && [ -f /home/tc/custom-module/*42218*.pat ]; then

            patfile=$(ls /home/tc/custom-module/*42218*.pat | head -1)
            echo "Found custom pat file ${patfile}"
            echo "Processing old pat file to extract required files for extraction"
            tar -C${temp_folder} -xf /${patfile} rd.gz
        else
            curl -kL https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat -o /home/tc/oldpat.tar.gz
            [ -f /home/tc/oldpat.tar.gz ] && tar -C${temp_folder} -xf /home/tc/oldpat.tar.gz rd.gz
        fi

        echo "Entering synoesp"
        cd ${temp_folder}

        xz -dc <rd.gz >rd 2>/dev/null || echo "extract rd.gz"
        echo "finish"
        cpio -idm <rd 2>&1 || echo "extract rd"
        mkdir extract

        mkdir /mnt/${tcrppart}/auxfiles && cd /mnt/${tcrppart}/auxfiles

        echo "Copying required files to local cache folder for future use"

        mkdir /mnt/${tcrppart}/auxfiles/extractor

        for file in usr/lib/libcurl.so.4 usr/lib/libmbedcrypto.so.5 usr/lib/libmbedtls.so.13 usr/lib/libmbedx509.so.1 usr/lib/libmsgpackc.so.2 usr/lib/libsodium.so usr/lib/libsynocodesign-ng-virtual-junior-wins.so.7 usr/syno/bin/scemd; do
            echo "Copying $file to /mnt/${tcrppart}/auxfiles"
            cp $file /mnt/${tcrppart}/auxfiles/extractor
        done

    fi

    echo "Removing temp folder /tmp/synoesp"
    rm -rf $temp_folder

    if [ "${BUS}" != "block" ]; then
        msgnormal "Checking if tool is accessible"
        if [ -d ${local_cache/extractor /} ] && [ -f ${local_cache}/extractor/scemd ]; then    
            /bin/syno_extract_system_patch 2>&1 >/dev/null
        else
            /bin/syno_extract_system_patch
        fi
        if [ $? -eq 255 ]; then echo "Executed succesfully"; else echo "Cound not execute"; fi    
    fi
}

function testarchive() {

    archive="$1"
    if [ "${BUS}" != "block" ]; then
        archiveheader="$(od -bc ${archive} | awk 'NR==1 {print $3; exit}')"
    
        case ${archiveheader} in
        105)
            echo "${archive}, is a Tar file"
            isencrypted="no"
            return 0
            ;;
        255)
            echo "File ${archive}, is  encrypted"
            isencrypted="yes"
            return 1
            ;;
        213)
            echo "File ${archive}, is a compressed tar"
            isencrypted="no"
            ;;
        057)
            echo "File ${archive}, is a compressed tar (from GNU friend kernel)"
            isencrypted="no"
            ;;
        *)
            echo "Could not determine if file ${archive} is encrypted or not, maybe corrupted"
            ls -ltr ${archive}
            echo ${archiveheader}
            exit 99
            ;;
        esac
    else
        if [ ${TARGET_REVISION} -gt 42218 ]; then
            echo "Found build request for revision greater than 42218"
            echo "File ${archive}, is  encrypted"
            isencrypted="yes"
            return 1
        else
            echo "Found build request for revision less equal than 42218"
            echo "${archive}, is a Tar file"
            isencrypted="no"
            return 0
        fi
    fi

}

function processpat() {

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    local_cache="/mnt/${tcrppart}/auxfiles"
    temp_pat_folder="/tmp/pat"
    temp_dsmpat_folder="/tmp/dsmpat"

    setplatform

    if [ ! -d "${temp_pat_folder}" ]; then
        msgnormal "Creating temp folder ${temp_pat_folder} "
        mkdir ${temp_pat_folder} && sudo mount -t tmpfs -o size=512M tmpfs ${temp_pat_folder} && cd ${temp_pat_folder}
        mkdir ${temp_dsmpat_folder} && sudo mount -t tmpfs -o size=512M tmpfs ${temp_dsmpat_folder}
    fi

    echo "Checking for cached pat file"
    [ -d $local_cache ] && msgnormal "Found tinycore cache folder, linking to home/tc/custom-module" && [ ! -h /home/tc/custom-module ] && sudo ln -s $local_cache /home/tc/custom-module

    if [ -d ${local_cache} ] && [ -f ${local_cache}/*${SYNOMODEL}*.pat ] || [ -f ${local_cache}/*${MODEL}*${TARGET_REVISION}*.pat ]; then

        [ -f /home/tc/custom-module/*${SYNOMODEL}*.pat ] && patfile=$(ls /home/tc/custom-module/*${SYNOMODEL}*.pat | head -1)
        [ -f ${local_cache}/*${MODEL}*${TARGET_REVISION}*.pat ] && patfile=$(ls /home/tc/custom-module/*${MODEL}*${TARGET_REVISION}*.pat | head -1)

        msgnormal "Found locally cached pat file ${patfile}"
st "iscached" "Caching pat file" "Patfile ${SYNOMODEL}.pat is cached"
        testarchive "${patfile}"
        if [ ${isencrypted} = "no" ]; then
            echo "File ${patfile} is already decrypted"
            msgnormal "Copying file to /home/tc/redpill-load/cache folder"
            sudo mv -f ${patfile} /home/tc/redpill-load/cache/
        elif [ ${isencrypted} = "yes" ]; then
            [ -f /home/tc/redpill-load/cache/${SYNOMODEL}.pat ] && testarchive /home/tc/redpill-load/cache/${SYNOMODEL}.pat
            if [ -f /home/tc/redpill-load/cache/${SYNOMODEL}.pat ] && [ ${isencrypted} = "no" ]; then
                echo "Decrypted file is already cached in :  /home/tc/redpill-load/cache/${SYNOMODEL}.pat"
            else
                if [ "${BUS}" = "block"  ]; then            
                  echo "Copying encrypted pat file : ${patfile} to ~/data/in"
                  sudo mv -f ${patfile} ~/data/in/${SYNOMODEL}.pat
                  echo "Extracting encrypted pat file : ~/data/in/${SYNOMODEL}.pat to ~/data/out"
                  sudo docker run --rm -v ~/data:/data syno-extract-system-patch /data/in/${SYNOMODEL}.pat /data/out/. || echo "extract latest pat"
                  rsync -a --remove-source-files ~/data/out/ ${temp_pat_folder}/
                else
                  echo "Copying encrypted pat file : ${patfile} to ${temp_dsmpat_folder}"
                  sudo mv -f ${patfile} ${temp_dsmpat_folder}/${SYNOMODEL}.pat
                  echo "Extracting encrypted pat file : ${temp_dsmpat_folder}/${SYNOMODEL}.pat to ${temp_pat_folder}"
                  sudo /bin/syno_extract_system_patch ${temp_dsmpat_folder}/${SYNOMODEL}.pat ${temp_pat_folder} || echo "extract latest pat"
                fi
                echo "Decrypted pat file tar compression in progress ${SYNOMODEL}.pat to /home/tc/redpill-load/cache folder (multithreaded comporession)"
                mkdir -p /home/tc/redpill-load/cache/
                echo "threads = ${threads}"
                if [ "${BUS}" = "block"  ]; then
                  cd ${temp_pat_folder} && tar -cf ${temp_dsmpat_folder}/${SYNOMODEL}.pat ./ && cp -f ${temp_dsmpat_folder}/${SYNOMODEL}.pat /home/tc/redpill-load/cache/${SYNOMODEL}.pat
                else
                  if [ "$FRKRNL" = "NO" ]; then
                      cd ${temp_pat_folder} && sudo sh -c "tar -cf - ./ | pigz -p ${threads} > ${temp_dsmpat_folder}/${SYNOMODEL}.pat" && sudo cp -f ${temp_dsmpat_folder}/${SYNOMODEL}.pat /home/tc/redpill-load/cache/${SYNOMODEL}.pat
                  else    
                      cd ${temp_pat_folder} && sudo sh -c "tar -cf ${temp_dsmpat_folder}/${SYNOMODEL}.pat ./" && sudo cp -f ${temp_dsmpat_folder}/${SYNOMODEL}.pat /home/tc/redpill-load/cache/${SYNOMODEL}.pat
                  fi    
                fi
            fi
            patfile="/home/tc/redpill-load/cache/${SYNOMODEL}.pat"            

        else
            echo "Something went wrong, please check cache files"
            exit 99
        fi

        cd /home/tc/redpill-load/cache
st "patextraction" "Pat file extracted" "VERSION:${TARGET_VERSION}-${TARGET_REVISION}"        
        sudo tar xvf /home/tc/redpill-load/cache/${SYNOMODEL}.pat ./VERSION && . ./VERSION && cat ./VERSION && rm ./VERSION
        os_md5=$(md5sum /home/tc/redpill-load/cache/${SYNOMODEL}.pat | awk '{print $1}')
        msgnormal "Pat file md5sum is : $os_md5"

        echo -n "Checking config file existence -> "
        if [ -f "/home/tc/redpill-load/config/pats.json" ]; then
            echo "OK"
        else
            echo "No config file(pats.json) found, The download may be corrupted or may not be run the original repo. Please re-download from original repo."
            exit 99
        fi

        msgnormal "Editing config file !!!!!"
       
        echo -n "Verifying config file -> "
        verifyid=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.sum) | .[0]" "${configfile}")
        sed -i "s/${verifyid}/$os_md5/" ${configfile}
        verifyid="$os_md5"

        if [ "$os_md5" == "$verifyid" ]; then
            echo "OK ! "
        else
            echo "config file, os md5 verify FAILED, check ${configfile} "
            exit 99
        fi

        msgnormal "Clearing temp folders"
        sudo umount ${temp_pat_folder} && sudo rm -rf ${temp_pat_folder}
        sudo umount ${temp_dsmpat_folder} && sudo rm -rf ${temp_dsmpat_folder}        

        return

    else

        echo "Could not find pat file locally cached"
        
        pat_url=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.url) | .[0]" "${configfile}")
        echo -e "Configfile: $configfile \nPat URL : $pat_url"
        echo "Downloading pat file from URL : ${pat_url} "

        chkavail
        if [ $avail_num -le 370 ]; then
            echo "No adequate space on ${local_cache} to download file into cache folder, clean up the space and restart"
            exit 99
        fi

        [ -n $pat_url ] && curl -kL ${pat_url} -o "/${local_cache}/${SYNOMODEL}.pat"
        patfile="/${local_cache}/${SYNOMODEL}.pat"
        if [ -f ${patfile} ]; then
            testarchive ${patfile}
        else
            echo "Failed to download PAT file $patfile from ${pat_url} "
            exit 99
        fi

        if [ "${isencrypted}" = "yes" ]; then
            echo "File ${patfile}, has been cached but its encrypted, re-running decrypting process"
            processpat
        else
            return
        fi

    fi

}

function addrequiredexts() {

    echo "Processing add_extensions entries found on models.json file : ${EXTENSIONS}"
    for extension in ${EXTENSIONS_SOURCE_URL}; do
        echo "Adding extension ${extension} "
        cd /home/tc/redpill-load/ && ./ext-manager.sh add "$(echo $extension | sed -s 's/"//g' | sed -s 's/,//g')"
        if [ $? -ne 0 ]; then
            echo "FAILED : Processing add_extensions failed check the output for any errors"
            rploader clean
            exit 99
        fi
    done

    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then
        vkersion=${major}${minor}_${KVER}
    else
        vkersion=${KVER}
    fi

    for extension in ${EXTENSIONS}; do
        echo "Updating extension : ${extension} contents for platform, kernel : ${ORIGIN_PLATFORM}, ${vkersion}  "
        platkver="$(echo ${ORIGIN_PLATFORM}_${vkersion} | sed 's/\.//g')"
        echo "platkver = ${platkver}"
        cd /home/tc/redpill-load/ && ./ext-manager.sh _update_platform_exts ${platkver} ${extension}
        if [ $? -ne 0 ]; then
            echo "FAILED : Processing add_extensions failed check the output for any errors"
            rploader clean
            exit 99
        fi
    done

#m shell only
 #Use user define dts file instaed of dtbpatch ext now
    if [ ${ORIGIN_PLATFORM} = "geminilake" ] || [ ${ORIGIN_PLATFORM} = "v1000" ] || [ ${ORIGIN_PLATFORM} = "r1000" ]; then
        echo "For user define dts file instaed of dtbpatch ext"
        patchdtc
        echo "Patch dtc is superseded by fbelavenuto dtbpatch"
    fi
    
}

function updateuserconfig() {

    echo "Checking user config for general block"
    generalblock="$(jq -r -e '.general' $userconfigfile)"
    if [ "$generalblock" = "null" ] || [ -n "$generalblock" ]; then
        echo "Result=${generalblock}, File does not contain general block, adding block"

        for field in model version smallfixnumber redpillmake zimghash rdhash usb_line sata_line; do
            jsonfile=$(jq ".general+={\"$field\":\"\"}" $userconfigfile)
            echo $jsonfile | jq . >$userconfigfile
        done
    fi

}
function updateuserconfigfield() {

    block="$1"
    field="$2"
    value="$3"

    if [ -n "$1 " ] && [ -n "$2" ]; then
        jsonfile=$(jq ".$block+={\"$field\":\"$value\"}" $userconfigfile)
        echo $jsonfile | jq . >$userconfigfile
    else
        echo "No values to update specified"
    fi
}

function postupdate() {

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"

    cd /home/tc

    updateuserconfig
    setnetwork

    updateuserconfigfield "general" "model" "$MODEL"
    updateuserconfigfield "general" "version" "${TARGET_VERSION}-${TARGET_REVISION}"
    updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
    updateuserconfigfield "general" "redpillmake" "${redpillmake}-${TAG}"
    echo "Creating temp ramdisk space" && mkdir /home/tc/ramdisk

    echo "Mounting partition ${loaderdisk}1" && sudo mount /dev/${loaderdisk}1
    echo "Mounting partition ${loaderdisk}2" && sudo mount /dev/${loaderdisk}2

    zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
    updateuserconfigfield "general" "zimghash" "$zimghash"
    rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
    updateuserconfigfield "general" "rdhash" "$rdhash"

    zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
    updateuserconfigfield "general" "zimghash" "$zimghash"
    rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
    updateuserconfigfield "general" "rdhash" "$rdhash"
    echo "Backing up $userconfigfile "
    cp $userconfigfile /mnt/${loaderdisk}3

    cd /home/tc/ramdisk

    echo "Extracting update ramdisk"

    if [ $(od /mnt/${loaderdisk}2/rd.gz | head -1 | awk '{print $2}') == "000135" ]; then
        sudo unlzma -c /mnt/${loaderdisk}2/rd.gz | cpio -idm 2>&1 >/dev/null
    else
        sudo cat /mnt/${loaderdisk}2/rd.gz | cpio -idm 2>&1 >/dev/null
    fi

    . ./etc.defaults/VERSION && echo "Found Version : ${productversion}-${buildnumber}-${smallfixnumber}"

#    echo -n "Do you want to use this for the loader ? [yY/nN] : "
#    readanswer

#    if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then

        echo "Extracting redpill ramdisk"

        if [ $(od /mnt/${loaderdisk}3/rd.gz | head -1 | awk '{print $2}') == "000135" ]; then
            sudo unlzma -c /mnt/${loaderdisk}3/rd.gz | cpio -idm
            RD_COMPRESSED="yes"
        else
            sudo cat /mnt/${loaderdisk}3/rd.gz | cpio -idm
        fi

        . ./etc.defaults/VERSION && echo "The new smallupdate version will be  : ${productversion}-${buildnumber}-${smallfixnumber}"

#        echo -n "Do you want to use this for the loader ? [yY/nN] : "
#        readanswer

#        if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then

            echo "Recreating ramdisk "

            if [ "$RD_COMPRESSED" = "yes" ]; then
                sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root | xz -9 --format=lzma >../rd.gz
            else
                sudo find . 2>/dev/null | sudo cpio -o -H newc -R root:root >../rd.gz
            fi

            cd ..

            echo "Adding fake sign" && sudo dd if=/dev/zero of=rd.gz bs=68 count=1 conv=notrunc oflag=append

            echo "Putting ramdisk back to the loader partition ${loaderdisk}1" && sudo cp -f rd.gz /mnt/${loaderdisk}3/rd.gz

            echo "Removing temp ramdisk space " && rm -rf ramdisk

            echo "Done"
#        else
#            echo "Removing temp ramdisk space " && rm -rf ramdisk
#            exit 0
#        fi

#m shell only
        checkmachine

        if [ "$MACHINE" = "VIRTUAL" ]; then
            echo "Setting default boot entry to SATA"
            sudo sed -i "/set default=/cset default=\"1\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg
        else
            echo "Setting default boot entry to USB"
            sudo sed -i "/set default=/cset default=\"0\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg
        fi

#    fi

}

function getgrubbkg() {

    curl -kLO# "https://github.com/PeterSuh-Q3/tinycore-redpill/raw/main/grub/grubbkg.cfg"
    if [ ! -f /home/tc/grubbkg.png ]; then
        curl -kLO# "https://github.com/PeterSuh-Q3/tinycore-redpill/raw/main/grub/grubbkg.png"
        sudo cp -vf /home/tc/grubbkg.png /mnt/${loaderdisk}3/grubbkg.png
    fi
}

function getbspatch() {

    chmod 777 /home/tc/tools/bspatch
    if [ "$FRKRNL" = "YES" ]; then
        if [ ! -f /usr/bin/bspatch ]; then
            echo "bspatch does not exist, copy from tools"
            sudo cp -vf ~/tools/bspatch /usr/bin/
        fi
    else
        if [ ! -f /usr/local/bspatch ]; then
            echo "bspatch does not exist, copy from tools"
            sudo cp -vf ~/tools/bspatch /usr/local/bin/
        fi
    fi

}

function removemodelexts() {                                                                             
                                                                                        
    echo "Entering redpill-load directory to remove exts"                                                            
    cd /home/tc/redpill-load/
    echo "Removing all exts directories..."
    sudo rm -rf /home/tc/redpill-load/custom/extensions/*
                                                                                                                              
    #echo "Removing model exts directories..."
    #for modelextdir in ${EXTENSIONS}; do
    #    if [ -d /home/tc/redpill-load/custom/extensions/${modelextdir} ]; then                                                         
    #        echo "Removing : ${modelextdir}"
    #        sudo rm -rf /home/tc/redpill-load/custom/extensions/${modelextdir}            
    #    fi                                                                                            
    #done                                                           

} 

function getPlatforms() {

    platform_versions=$(jq -s '.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]'  custom_config.json | jq -r '.build_configs[].id')
    echo "platform_versions=$platform_versions"

}

function selectPlatform() {

    platform_selected=$(jq -r ".${1}" models.json)
    echo "platform_selected=${platform_selected}"

}
function getValueByJsonPath() {

    local JSONPATH=${1}
    local CONFIG=${2}
    jq -c -r "${JSONPATH}" <<<${CONFIG}

}
function readConfig() {

    if [ ! -e custom_config.json ]; then
        cat global_config.json
    else
        jq -s '.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]'  custom_config.json
    fi

}

function setplatform() {

    SYNOMODEL=${TARGET_PLATFORM}_${TARGET_REVISION}
    #MODEL=$(echo "${TARGET_PLATFORM}" | sed 's/ds/DS/' | sed 's/rs/RS/' | sed 's/p/+/' | sed 's/dva/DVA/' | sed 's/fs/FS/' | sed 's/sa/SA/' )
    #ORIGIN_PLATFORM="$(echo $platform_selected | jq -r -e '.platform_name')"

}

function getvars() {

    KVER="$(jq -r -e '.general.kver' $userconfigfile)"

    CONFIG=$(readConfig)
    selectPlatform $1

    GETTIME=$(curl -k -v -s https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
    INTERNETDATE=$(date +"%d%m%Y" -d "$GETTIME")
    LOCALDATE=$(date +"%d%m%Y")

    #EXTENSIONS="$(echo $platform_selected | jq -r -e '.add_extensions[]')"
    EXTENSIONS="$(echo $platform_selected | jq -r -e '.add_extensions[]' | grep json | awk -F: '{print $1}' | sed -s 's/"//g')"
    #EXTENSIONS_SOURCE_URL="$(echo $platform_selected | jq '.add_extensions[] .url')"
    EXTENSIONS_SOURCE_URL="$(echo $platform_selected | jq '.add_extensions[]' | grep json | awk '{print $2}')"
    #TARGET_PLATFORM="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[0])"
    #TARGET_VERSION="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[1])"
    #TARGET_REVISION="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[2])"

    tcrppart="${tcrpdisk}3"
    local_cache="/mnt/${tcrppart}/auxfiles"
    usbpart1uuid=$(/sbin/blkid /dev/${tcrpdisk}1 | awk '{print $3}' | sed -e "s/\"//g" -e "s/UUID=//g")
    usbpart3uuid="6234-C863"

    [ ! -h /lib64 ] && sudo ln -s /lib /lib64

    sudo chown -R tc:staff /home/tc

    getgrubbkg
    getbspatch

    if [ "${offline}" = "NO" ]; then
        echo "Redownload the latest module.alias.4.json file ..."    
        echo
        curl -ksL "$modalias4" -o modules.alias.4.json.gz
        [ -f modules.alias.4.json.gz ] && gunzip -f modules.alias.4.json.gz    
    fi    

    [ ! -d ${local_cache} ] && sudo mkdir -p ${local_cache}
    [ -h /home/tc/custom-module ] && unlink /home/tc/custom-module
    [ ! -h /home/tc/custom-module ] && sudo ln -s $local_cache /home/tc/custom-module

    if [ -z "$TARGET_PLATFORM" ] || [ -z "$TARGET_VERSION" ] || [ -z "$TARGET_REVISION" ]; then
        echo "Error : Platform not found "
        showhelp
        exit 99
    fi

    case $ORIGIN_PLATFORM in

    bromolow | braswell)
        KERNEL_MAJOR="3"
        MODULE_ALIAS_FILE="modules.alias.3.json"
        ;;
    apollolake | broadwell | broadwellnk | v1000 | denverton | geminilake | broadwellnkv2 | broadwellntbap | purley | *)
        KERNEL_MAJOR="4"
        MODULE_ALIAS_FILE="modules.alias.4.json"
        ;;
    esac

    setplatform

    threads="$(nproc)"
    [ -z "$threads" ] && threads="1"

    #echo "Platform : $platform_selected"
    echo "Rploader Version  : ${rploaderver}"
    echo "Extensions        : $EXTENSIONS "
    echo "Extensions URL    : $EXTENSIONS_SOURCE_URL"
    echo "TARGET_PLATFORM   : $TARGET_PLATFORM"
    echo "TARGET_VERSION    : $TARGET_VERSION"
    echo "TARGET_REVISION   : $TARGET_REVISION"
    echo "KERNEL_MAJOR      : $KERNEL_MAJOR"
    echo "MODULE_ALIAS_FILE : $MODULE_ALIAS_FILE"
    echo "SYNOMODEL         : $SYNOMODEL"
    echo "MODEL             : $MODEL"
    echo "KERNEL VERSION    : $KVER"
    echo "Local Cache Folder : $local_cache"
    echo "CPU THREADS       : $threads"
    echo "DATE Internet     : $INTERNETDATE Local : $LOCALDATE"

  if [ "${offline}" = "NO" ]; then
    if [ "$INTERNETDATE" != "$LOCALDATE" ]; then
        echo "ERROR ! System DATE is not correct"
        synctime
        echo "Current time after communicating with NTP server ${ntpserver} :  $(date) "
    fi

    LOCALDATE=$(date +"%d%m%Y")
    if [ "$INTERNETDATE" != "$LOCALDATE" ]; then
        echo "Sync with NTP server ${ntpserver} :  $(date) Fail !!!"
        echo "ERROR !!! The system date is incorrect."
        exit 99        
    fi
  fi
    #getvarsmshell "$MODEL"

}

function cleanloader() {

    echo "Clearing local redpill files"
    sudo rm -rf /home/tc/redpill*
    sudo rm -rf /home/tc/*tgz

}

function backuploader() {

  thread=$(nproc)
  if [ "${BUS}" != "block"  ]; then
#Apply pigz for fast backup  
    if [ ! -n "$(which pigz)" ]; then
        echo "pigz does not exist, bringing over from repo"
        curl -s -k -L "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/tools/pigz" -O
        chmod 777 pigz
        sudo mv pigz /usr/bin/
    fi

    # backup xtcrp together
    sudo sh -c "tar -cf - ./ | pigz -p ${thread} > /mnt/${loaderdisk}3/xtcrp.tgz"
    if [ $? -ne 0 ]; then
        cecho r "An error occurred while backing up the loader!!!"
    else
        cecho y "Successfully backed up the loader!!!"
    fi

    if [ "$FRKRNL" = "YES" ]; then
        TGZ_FILE="/mnt/${tcrppart}/mydata.tgz"
        TAR_UNZIPPED="/mnt/${tcrppart}/mydata.tar"
        SOURCE_FILE="/home/tc/user_config.json"
        # Check if the compressed file exists
        if [ -f "$TGZ_FILE" ]; then
            echo "Adding ${SOURCE_FILE} to ${TGZ_FILE} !!!"
            # Decompress the existing archive
            sudo gunzip "$TGZ_FILE"
            # Add the file to the archive
            sudo tar --append -C / --file="$TAR_UNZIPPED" "home/tc/user_config.json"
            # Compress the archive again and save with the original name
            sudo sh -c "gzip -c $TAR_UNZIPPED > $TGZ_FILE"
            # Remove the decompressed temporary file
            sudo rm "$TAR_UNZIPPED"
        fi
        return
    fi
    
    if [ $(cat /usr/bin/filetool.sh | grep pigz | wc -l ) -eq 0 ]; then
        sudo sed -i "s/\-czvf/\-cvf \- \| pigz -p "${thread}" \>/g" /usr/bin/filetool.sh
        sudo sed -i "s/\-czf/\-cf \- \| pigz -p "${thread}" \>/g" /usr/bin/filetool.sh
    fi
  fi  
#    loaderdisk=$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)
    homesize=$(du -sh /home/tc | awk '{print $1}')

    echo "Please make sure you are using the latest 1GB img before using backup option"
    echo "Current /home/tc size is $homesize , try to keep it less than 1GB as it might not fit into your image"

    echo "Should i update the $loaderdisk with your current files [Yy/Nn]"
    readanswer
    if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
        echo -n "Backing up home files to $loaderdisk : "
        if filetool.sh -b ${loaderdisk}3; then
            echo ""
        else
            echo "Error: Couldn't backup files"
        fi
    else
        echo "OK, keeping last status"
    fi

}

function checkfilechecksum() {

    local FILE="${1}"
    local EXPECTED_SHA256="${2}"
    local SHA256_RESULT=$(sha256sum ${FILE})
    if [ "${SHA256_RESULT%% *}" != "${EXPECTED_SHA256}" ]; then
        echo "The ${FILE} is corrupted, expected sha256 checksum ${EXPECTED_SHA256}, got ${SHA256_RESULT%% *}"
        #rm -f "${FILE}"
        #echo "Deleted corrupted file ${FILE}. Please re-run your action!"
        echo "Please delete the file ${FILE} manualy and re-run your command!"
        exit 99
    fi

}

function tinyentry() {
    cat <<EOF
menuentry 'Tiny Core Image Build' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /vmlinuz64 loglevel=3 cde waitusb=5 vga=791
        echo Loading initramfs...
        initrd /corepure64.gz
        echo Booting TinyCore for loader creation
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function tcrpfriendentry() {
    cat <<EOF
menuentry 'Tiny Core Friend $MODEL ${TARGET_VERSION}-${TARGET_REVISION} Update ${smallfixnumber} ${DMPM}' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8
        echo Loading initramfs...
        initrd /initrd-friend
        echo Booting TinyCore Friend
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function xtcrpconfigureentry() {
    cat <<EOF
menuentry 'xTCRP Configure Boot Loader (Loader Build)' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8 IWANTTOCONFIGURE
        echo Loading initramfs to configure loader...
        initrd /initrd-friend
        echo Loding RAMDISK to configure loader...
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function tcrpentry_junior() {
    cat <<EOF
menuentry 'Re-Install DSM of $MODEL ${TARGET_VERSION}-${TARGET_REVISION} Update 0 ${DMPM}' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        set kernel_cmdline="${USB_LINE} force_junior"
        set bus_type="${BUS}"
        if [ "\${bus_type}" != "usb" ]; then
            set kernel_cmdline="\${kernel_cmdline} synoboot_satadom=1"
        fi
        linux /zImage-dsm \${kernel_cmdline}
        echo Loading initramfs...
        initrd /initrd-dsm
        echo Entering Force Junior (For Re-install DSM)
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function postupdateentry() {
    cat <<EOF
menuentry 'Tiny Core PostUpdate (RamDisk Update) $MODEL ${TARGET_VERSION}-${TARGET_REVISION} Update ${smallfixnumber} ${DMPM}' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 
        echo Loading initramfs...
        initrd /initrd-friend
        echo Booting TinyCore Friend
        set gfxpayload=1024x768x16,1024x768
}
EOF
}

function tinyjotfunc() {
    cat <<EOF
function savedefault {
    saved_entry="\${chosen}"
    save_env --file \$prefix/grubenv saved_entry
    echo -e "----------={ M Shell for TinyCore RedPill JOT }=----------"
    echo "TCRP JOT Version : ${rploaderver}"
    echo -e "Running on $(cat /proc/cpuinfo | grep "model name" | awk -F: '{print $2}' | wc -l) Processor $(cat /proc/cpuinfo | grep "model name" | awk -F: '{print $2}' | uniq)"
    echo -e "$(cat /tmp/tempentry.txt | grep earlyprintk | head -1 | sed 's/linux \/zImage/cmdline :/' )"
}    
EOF
}

function showsyntax() {
    cat <<EOF
$(basename ${0})

Version : $rploaderver
----------------------------------------------------------------------------------------

Usage: ${0} <action> <platform version> <static or compile module> [extension manager arguments]

Actions: build, ext, download, clean, listmod, serialgen, identifyusb, patchdtc, 
satamap, backup, backuploader, restoreloader, restoresession, mountdsmroot, postupdate,
mountshare, version, monitor, getgrubconf, help

----------------------------------------------------------------------------------------
Available platform versions:
----------------------------------------------------------------------------------------
$(getPlatforms)
----------------------------------------------------------------------------------------
Check custom_config.json for platform settings.
EOF
}

function showhelp() {
    cat <<EOF
$(basename ${0})

Version : $rploaderver
----------------------------------------------------------------------------------------
Usage: ${0} <action> <platform version> <static or compile module> [extension manager arguments]

Actions: build, ext, download, clean, listmod, serialgen, identifyusb, patchdtc, 
satamap, backup, backuploader, restoreloader, restoresession, mountdsmroot, postupdate, 
mountshare, version, monitor, bringfriend, downloadupgradepat, help 

- build <platform> <option> : 
  Build the 💊 RedPill LKM and update the loader image for the specified platform version and update
  current loader.

  Valid Options:     static/compile/manual/junmod/withfriend

  ** withfriend add the TCRP friend and a boot option for auto patching 
  
- ext <platform> <option> <URL> 
  Manage extensions using redpill extension manager. 

  Valid Options:  add/force_add/info/remove/update/cleanup/auto . Options after platform 
  
  Example: 
  rploader ext apollolake-7.0.1-42218 add https://raw.githubusercontent.com/PeterSuh-Q3/rp-ext/master/e1000/rpext-index.json
  or for auto detect use 
  rploader ext apollolake-7.0.1-42218 auto 
  
- download <platform> :
  Download redpill sources only
  
- clean :
  Removes all cached and downloaded files and starts over clean
 
- listmods <platform>:
  Tries to figure out any required extensions. This usually are device modules
  
- serialgen <synomodel> <option> :
  Generates a serial number and mac address for the following platforms 
  DS3615xs DS3617xs DS916+ DS918+ DS920+ DS3622xs+ FS6400 DVA3219 DVA3221 DS1621+ DVA1622 DS2422+ RS4021xs+ DS923+
  
  Valid Options :  realmac , keeps the real mac of interface eth0
  
- identifyusb :    
  Tries to identify your loader usb stick VID:PID and updates the user_config.json file 
  
- patchdtc :       
  Tries to identify and patch your dtc model for your disk and nvme devices. If you want to have 
  your manually edited dts file used convert it to dtb and place it under /home/tc/custom-modules
  
- satamap :
  Tries to identify your SataPortMap and DiskIdxMap values and updates the user_config.json file 
  
- backup :
  Backup and make changes /home/tc changed permanent to your loader disk. Next time you boot,
  your /home will be restored to the current state.
  
- backuploader :
  Backup current loader partitions to your TCRP partition
  
- restoreloader :
  Restore current loader partitions from your TCRP partition
  
- restoresession :
  Restore last user session files. (extensions and user_config.json)
  
- mountdsmroot :
  Mount DSM root for manual intervention on DSM root partition
  
- postupdate :
  Runs a postupdate process to recreate your rd.gz, zImage and custom.gz for junior to match root
  
- mountshare :
  Mounts a remote CIFS working directory

- version <option>:
  Prints rploader version and if the history option is passed then the version history is listed.

  Valid Options : history, shows rploader release history.

- monitor :
  Prints system statistics related to TCRP loader 

- getgrubconf :
  Checks your user_config.json file variables against current grub.cfg variables and updates your
  user_config.json accordingly

- bringfriend
  Downloads TCRP friend and makes it the default boot option. TCRP Friend is here to assist with
  automated patching after an upgrade. No postupgrade actions will be required anymore, if TCRP
  friend is left as the default boot option.

- downloadupgradepat
  Downloads a specific upgade pat that can be used for various troubleshooting purposes

- removefriend
  Reverse bringfriend actions and remove TCRP from your loader 

- help:           Show this page

----------------------------------------------------------------------------------------
Version : $rploaderver
EOF

}

function checkUserConfig() {

  SN=$(jq -r -e '.extra_cmdline.sn' "$userconfigfile")
  MACADDR1=$(jq -r -e '.extra_cmdline.mac1' "$userconfigfile")
  netif_num=$(jq -r -e '.extra_cmdline.netif_num' $userconfigfile)
  netif_num_cnt=$(cat $userconfigfile | grep \"mac | wc -l)
  
  tz="US"

  if [ "${BUS}" = "block"  ]; then
    [ ! -n "${SN}" ] && SN=$(echo $(generateSerial ${MODEL})) && writeConfigKey "extra_cmdline" "sn" "${SN}"
    [ ! -n "${MACADDR1}" ] && MACADDR1=`./macgen.sh "randommac" "eth0" ${MODEL}` && writeConfigKey "extra_cmdline" "mac1" "${MACADDR1}"
  fi

  if [ ! -n "${SN}" ]; then
    eval "echo \${MSG${tz}36}"
    msgalert "Synology serial number not set. Check user_config.json again. Abort the loader build !!!!!!"
    exit 99
  fi
  
  if [ ! -n "${MACADDR1}" ]; then
    eval "echo \${MSG${tz}37}"
    msgalert "The first MAC address is not set. Check user_config.json again. Abort the loader build !!!!!!"
    exit 99
  fi

  if [ "${BUS}" != "block"  ]; then
      if [ $netif_num != $netif_num_cnt ]; then
        echo "netif_num = ${netif_num}"
        echo "number of mac addresses = ${netif_num_cnt}"       
        eval "echo \${MSG${tz}38}"
        msgalert "The netif_num and the number of mac addresses do not match. Check user_config.json again. Abort the loader build !!!!!!"
        exit 99
      fi  
  fi
}

function buildloader() {

#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    local_cache="/mnt/${tcrppart}/auxfiles"

checkmachine

    [ "$1" == "junmod" ] && JUNLOADER="YES" || JUNLOADER="NO"

    [ -d $local_cache ] && echo "Found tinycore cache folder, linking to home/tc/custom-module" && [ ! -d /home/tc/custom-module ] && ln -s $local_cache /home/tc/custom-module

    DMPM="$(jq -r -e '.general.devmod' $userconfigfile)"
    msgnormal "Device Module Processing Method is ${DMPM}"

    cd /home/tc

    echo -n "Checking user_config.json : "
    if jq -s . user_config.json >/dev/null; then
        echo "Done"
    else
        echo "Error : Problem found in user_config.json"
        exit 99
    fi

    echo "Clean up extension files before building!!!"
    removemodelexts    

    [ ! -d /lib64 ] &&  sudo ln -s /lib /lib64
    [ ! -f /lib64/libbz2.so.1 ] && sudo ln -s /usr/local/lib/libbz2.so.1.0.8 /lib64/libbz2.so.1
    [ ! -f /home/tc/redpill-load/user_config.json ] && ln -s /home/tc/user_config.json /home/tc/redpill-load/user_config.json
    [ ! -d cache ] && mkdir -p /home/tc/redpill-load/cache
    cd /home/tc/redpill-load

    if [ ${TARGET_REVISION} -gt 42218 ]; then
        echo "Found build request for revision greater than 42218"
        downloadextractor
        processpat
    else
        [ -d /home/tc/custom-module ] && sudo cp -adp /home/tc/custom-module/*${TARGET_REVISION}*.pat /home/tc/redpill-load/cache/
    fi

    [ -d /home/tc/redpill-load ] && cd /home/tc/redpill-load

    [ ! -d /home/tc/redpill-load/custom/extensions ] && mkdir -p /home/tc/redpill-load/custom/extensions
st "extensions" "Extensions collection" "Extensions collection..."
    addrequiredexts
st "make loader" "Creation boot loader" "Compile n make boot file."
st "copyfiles" "Copying files to P1,P2" "Copied boot files to the loader"
    UPPER_ORIGIN_PLATFORM=$(echo ${ORIGIN_PLATFORM} | tr '[:lower:]' '[:upper:]')

    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then
        vkersion=${major}${minor}_${KVER}
    else
        vkersion=${KVER}
    fi

    #if [ "$WITHFRIEND" != "YES" ]; then
    #    jsonfile=$(jq "del(.[\"localrss\"])" /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
    #fi 
    
    if [ "$JUNLOADER" == "YES" ]; then
        echo "jun build option has been specified, so JUN MOD loader will be created"
        # jun's mod must patch using custom.gz from the first partition, so you need to fix the partition.
        sed -i "s/BRP_OUT_P2}\/\${BRP_CUSTOM_RD_NAME/BRP_OUT_P1}\/\${BRP_CUSTOM_RD_NAME/g" /home/tc/redpill-load/build-loader.sh
        if [ "$FRKRNL" = "NO" ]; then
            sudo BRP_JUN_MOD=1 BRP_DEBUG=0 BRP_USER_CFG=user_config.json ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${vkersion} ${SYNOMODEL}
        else
            BRP_JUN_MOD=1 BRP_DEBUG=0 BRP_USER_CFG=user_config.json ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${vkersion} ${SYNOMODEL}
        fi
    else
        if [ "$FRKRNL" = "NO" ]; then
            sudo ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${vkersion} ${SYNOMODEL}
        else
            ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${vkersion} ${SYNOMODEL}
        fi    
    fi

    [ $? -ne 0 ] && echo "FAILED : Loader creation failed check the output for any errors" && exit 99
    msgnormal "Chkeck Result of build-loader"
    ls -l /mnt/${loaderdisk}1/
    ls -l /mnt/${loaderdisk}2/
    ls -l /mnt/${loaderdisk}3/

    msgnormal "Modify Jot Menu entry"
    # backup Jot menuentry to tempentry
    # Get Only USB Part from line 61 to 80
    tempentry=$(cat /tmp/grub.cfg | head -n 80 | tail -n 20)
    #if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
    #    sudo sed -i '61,80d' /tmp/grub.cfg
    #else
        sudo sed -i '43,80d' /tmp/grub.cfg
    #fi
    echo "$tempentry" > /tmp/tempentry.txt
    # Append background to grub.cfg
    #if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "KVM" ]; then
    #    echo
    #else
        sudo tee -a /tmp/grub.cfg < /home/tc/grubbkg.cfg
    #fi
    
    if [ "$WITHFRIEND" = "YES" ]; then
        echo
    else
        sudo sed -i '31,34d' /tmp/grub.cfg
        # Check dom size and set max size accordingly for jot
        if [ "${BUS}" = "sata" ]; then
            DOM_PARA="dom_szmax=$(sudo /sbin/fdisk -l /dev/${loaderdisk} | head -1 | awk -F: '{print $2}' | awk '{ print $1*1024}')"
            sed -i "s/earlyprintk/${DOM_PARA} earlyprintk/" /tmp/tempentry.txt
        fi
        sed -i "s/${ORIGIN_PLATFORM}/${MODEL}/" /tmp/tempentry.txt
        sed -i "s/earlyprintk/syno_hw_version=${MODEL} earlyprintk/" /tmp/tempentry.txt
        tinyjotfunc | sudo tee --append /tmp/grub.cfg
    fi

    msgnormal "Replacing set root with filesystem UUID instead"
    sudo sed -i "s/set root=(hd0,msdos1)/search --set=root --fs-uuid $usbpart1uuid --hint hd0,msdos1/" /tmp/tempentry.txt
    sudo sed -i "s/Verbose/Verbose, ${DMPM}/" /tmp/tempentry.txt
    sudo sed -i "s/Linux.../Linux... ${DMPM}/" /tmp/tempentry.txt

    # Share RD of friend kernel with JOT 2023.05.01
    if [ ! -f /home/tc/friend/initrd-friend ] && [ ! -f /home/tc/friend/bzImage-friend ]; then
st "frienddownload" "Friend downloading" "TCRP friend copied to /mnt/${loaderdisk}3"        
        bringoverfriend
    fi

    if [ -f /home/tc/friend/initrd-friend ] && [ -f /home/tc/friend/bzImage-friend ]; then
        sudo cp /home/tc/friend/initrd-friend /mnt/${loaderdisk}3/
        sudo cp /home/tc/friend/bzImage-friend /mnt/${loaderdisk}3/
    fi

    USB_LINE="$(grep -A 5 "USB," /tmp/tempentry.txt | grep linux | cut -c 16-999)"
    SATA_LINE="$(grep -A 5 "SATA," /tmp/tempentry.txt | grep linux | cut -c 16-999)"

    if echo "apollolake geminilake purley" | grep -wq "${ORIGIN_PLATFORM}"; then
        USB_LINE="${USB_LINE} nox2apic"
        SATA_LINE="${SATA_LINE} nox2apic"    
    fi

    if echo "geminilake v1000 r1000" | grep -wq "${ORIGIN_PLATFORM}"; then
        echo "add modprobe.blacklist=mpt3sas for Device-tree based platforms"
        USB_LINE="${USB_LINE} modprobe.blacklist=mpt3sas"
        SATA_LINE="${SATA_LINE} modprobe.blacklist=mpt3sas"
    fi

    if [ -v CPU ]; then
        if [ "${CPU}" == "AMD" ]; then
            echo "Add configuration disable_mtrr_trim for AMD"
            USB_LINE="${USB_LINE} disable_mtrr_trim=1"
            SATA_LINE="${SATA_LINE} disable_mtrr_trim=1"
        else
            #if echo "epyc7002 apollolake geminilake" | grep -wq "${ORIGIN_PLATFORM}"; then
            #    if [ "$MACHINE" = "VIRTUAL" ]; then
            #        USB_LINE="${USB_LINE} intel_iommu=igfx_off "
            #        SATA_LINE="${SATA_LINE} intel_iommu=igfx_off "
            #    fi   
            #fi    
    
            if [ -d "/home/tc/redpill-load/custom/extensions/nvmesystem" ]; then
                echo "Add configuration pci=nommconf for nvmesystem addon"
                USB_LINE="${USB_LINE} pci=nommconf"
                SATA_LINE="${SATA_LINE} pci=nommconf"
            fi
        fi
    fi

    if [ "$WITHFRIEND" = "YES" ]; then
        USB_LINE="${USB_LINE} syno_hw_version=${MODEL} "
        SATA_LINE="${SATA_LINE} syno_hw_version=${MODEL} "
    fi    

    if [ "$WITHFRIEND" = "YES" ]; then
        echo "Creating tinycore friend entry"
        tcrpfriendentry | sudo tee --append /tmp/grub.cfg
    else
        echo "Creating tinycore Jot postupdate entry"
        postupdateentry | sudo tee --append /tmp/grub.cfg
    fi

    if [ -f /mnt/${tcrppart}/corepure64.gz ] && [ -f /mnt/${tcrppart}/vmlinuz64 ] && [ -d /mnt/${tcrppart}/cde ]; then
        echo "Creating tinycore configure loader entry"
        tinyentry | sudo tee --append /tmp/grub.cfg
    fi
    
    echo "Creating xTCRP configure loader entry"
    xtcrpconfigureentry | sudo tee --append /tmp/grub.cfg

    if [ "$WITHFRIEND" = "YES" ]; then
        tcrpentry_junior | sudo tee --append /tmp/grub.cfg 
    else
        echo "Creating tinycore Jot entry"
        echo "$(head -n 10 /tmp/tempentry.txt | sed 's/USB/USB\/SATA/g')" | sudo tee --append /tmp/grub.cfg
    fi

    cd /home/tc/redpill-load

    msgnormal "Entries in Localdisk bootloader : "
    echo "======================================================================="
    grep menuentry /tmp/grub.cfg

    ### Updating user_config.json
    updateuserconfigfield "general" "model" "$MODEL"
    updateuserconfigfield "general" "version" "${TARGET_VERSION}-${TARGET_REVISION}"
    updateuserconfigfield "general" "redpillmake" "${redpillmake}-${TAG}"
    updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
    zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
    updateuserconfigfield "general" "zimghash" "$zimghash"
    rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
    updateuserconfigfield "general" "rdhash" "$rdhash"
    
    msgwarning "Updated user_config with USB Command Line : $USB_LINE"
    json=$(jq --arg var "${USB_LINE}" '.general.usb_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile
    msgwarning "Updated user_config with SATA Command Line : $SATA_LINE"
    json=$(jq --arg var "${SATA_LINE}" '.general.sata_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile

    sudo cp $userconfigfile /mnt/${loaderdisk}3/

    # Share RD of friend kernel with JOT 2023.05.01
    sudo cp /mnt/${loaderdisk}1/zImage /mnt/${loaderdisk}3/zImage-dsm

    # Repack custom.gz including /usr/lib/modules and /usr/lib/firmware in all_modules 2024.02.18
    # Compining rd.gz and custom.gz
    
    [ ! -d /home/tc/rd.temp ] && mkdir /home/tc/rd.temp
    [ -d /home/tc/rd.temp ] && cd /home/tc/rd.temp
    RD_COMPRESSED=$(cat /home/tc/redpill-load/config/${ORIGIN_PLATFORM}/${TARGET_VERSION}-${TARGET_REVISION}/config.json | jq -r -e ' .extra .compress_rd')

    if [ "$RD_COMPRESSED" = "false" ]; then
        echo "Ramdisk in not compressed "    
        cat /mnt/${loaderdisk}3/rd.gz | sudo cpio -idm
    else    
        echo "Ramdisk in compressed " 
        unlzma -dc /mnt/${loaderdisk}3/rd.gz | sudo cpio -idm
    fi

    # 1.0.2.2 Recycle initrd-dsm instead of custom.gz (extract /exts), The priority starts from custom.gz
    if [ -f /mnt/${loaderdisk}3/custom.gz ]; then
        echo "Found custom.gz, so extract from custom.gz " 
        cat /mnt/${loaderdisk}3/custom.gz | sudo cpio -idm  >/dev/null 2>&1
    else
        echo "Not found custom.gz, extract /exts from initrd-dsm" 
        cat /mnt/${loaderdisk}3/initrd-dsm | sudo cpio -idm "*exts*"  >/dev/null 2>&1
        cat /mnt/${loaderdisk}3/initrd-dsm | sudo cpio -idm "*modprobe*"  >/dev/null 2>&1
        cat /mnt/${loaderdisk}3/initrd-dsm | sudo cpio -idm "*rp.ko*"  >/dev/null 2>&1
    fi

    # Network card configuration file
    for N in $(seq 0 7); do
      echo -e "DEVICE=eth${N}\nBOOTPROTO=dhcp\nONBOOT=yes\nIPV6INIT=dhcp\nIPV6_ACCEPT_RA=1" >"/home/tc/ifcfg-eth${N}"
    done
    sudo cp -vf /home/tc/ifcfg-eth* /home/tc/rd.temp/etc/sysconfig/network-scripts/

    # SA6400 patches for JOT Mode
    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then
        echo -e "Apply Epyc7002 Fixes"
        sudo sed -i 's#/dev/console#/var/log/lrc#g' /home/tc/rd.temp/usr/bin/busybox
        sudo sed -i '/^echo "START/a \\nmknod -m 0666 /dev/console c 1 3' /home/tc/rd.temp/linuxrc.syno     

        #[ ! -d /home/tc/rd.temp/usr/lib/firmware ] && sudo mkdir /home/tc/rd.temp/usr/lib/firmware
        #sudo curl -kL https://github.com/PeterSuh-Q3/tinycore-redpill/releases/download/v1.0.1.0/usr.tgz -o /tmp/usr.tgz
        #sudo tar xvfz /tmp/usr.tgz -C /home/tc/rd.temp

        #sudo tar xvfz /home/tc/rd.temp/exts/all-modules/${ORIGIN_PLATFORM}*${KVER}.tgz -C /home/tc/rd.temp/usr/lib/modules/        
        #sudo tar xvfz /home/tc/rd.temp/exts/all-modules/firmware.tgz -C /home/tc/rd.temp/usr/lib/firmware        
        #sudo curl -kL https://github.com/PeterSuh-Q3/tinycore-redpill/raw/main/rr/addons.tgz -o /tmp/addons.tgz
        #sudo tar xvfz /tmp/addons.tgz -C /home/tc/rd.temp
        #sudo curl -kL https://github.com/PeterSuh-Q3/tinycore-redpill/raw/main/rr/modules.tgz -o /tmp/modules.tgz
        #sudo tar xvfz /tmp/modules.tgz -C /home/tc/rd.temp/usr/lib/modules/
        #sudo tar xvfz /home/tc/rd.temp/exts/all-modules/sbin.tgz -C /home/tc/rd.temp
        #sudo cp -vf /home/tc/tools/dtc /home/tc/rd.temp/usr/bin
        #sudo curl -kL https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/main/rr/linuxrc.syno.impl -o /home/tc/rd.temp/linuxrc.syno.impl        
    fi
    if [ "${ORIGIN_PLATFORM}" = "broadwellntbap" ]; then
        sudo sed -i 's/IsUCOrXA="yes"/XIsUCOrXA="yes"/g; s/IsUCOrXA=yes/XIsUCOrXA=yes/g' "/home/tc/rd.temp/usr/syno/share/environments.sh"
    fi
    sudo chmod +x /home/tc/rd.temp/usr/sbin/modprobe    

    # add dummy loop0 test
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tcrpfriend/main/buildroot/board/tcrpfriend/rootfs-overlay/root/boot-image-dummy-sda.img.gz -o /home/tc/rd.temp/root/boot-image-dummy-sda.img.gz
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tcrpfriend/main/buildroot/board/tcrpfriend/rootfs-overlay/root/load-sda-first.sh -o /home/tc/rd.temp/root/load-sda-first.sh
    #sudo chmod +x /home/tc/rd.temp/root/load-sda-first.sh 
    #sudo mkdir -p /home/tc/rd.temp/etc/udev/rules.d
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tcrpfriend/main/buildroot/board/tcrpfriend/rootfs-overlay/etc/udev/rules.d/99-custom.rules -o /home/tc/rd.temp/etc/udev/rules.d/99-custom.rules
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/losetup/master/sbin/libsmartcols.so.1 -o /home/tc/rd.temp/usr/lib/libsmartcols.so.1
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/losetup/master/sbin/losetup -o /home/tc/rd.temp/usr/sbin/losetup
    #sudo chmod +x /home/tc/rd.temp/usr/sbin/losetup

    # Reassembly ramdisk
    if [ "$RD_COMPRESSED" = "false" ]; then
        echo "Ramdisk in not compressed "
        if [ "$FRKRNL" = "NO" ]; then
            (cd /home/tc/rd.temp && sudo find . | sudo cpio -o -H newc -R root:root >/mnt/${loaderdisk}3/initrd-dsm) >/dev/null
        else
            (cd /home/tc/rd.temp && sudo find . | sudo cpio -o -H newc -R root:root > /tmp/initrd-dsm)
            sudo cp -v /tmp/initrd-dsm /mnt/${loaderdisk}3/initrd-dsm
        fi
    else
        echo "Ramdisk in compressed "
        if [ "$FRKRNL" = "NO" ]; then
            (cd /home/tc/rd.temp && sudo find . | sudo cpio -o -H newc -R root:root | xz -9 --format=lzma >/mnt/${loaderdisk}3/initrd-dsm) >/dev/null
        else
            (cd /home/tc/rd.temp && find . | sudo cpio -o -H newc -R root:root | xz -9 --format=lzma >/mnt/${loaderdisk}3/initrd-dsm) >/dev/null
        fi
    fi

    if [ "$WITHFRIEND" = "YES" ]; then
        msgnormal "Setting default boot entry to TCRP Friend"
        sudo sed -i "/set default=\"*\"/cset default=\"0\"" /tmp/grub.cfg
    else
        echo
        msgnormal "Setting default boot entry to JOT ${BUS}"
        #if [ "${BUS}" = "usb" ]; then
            sudo sed -i "/set default=\"*\"/cset default=\"3\"" /tmp/grub.cfg
        #else
        #    sudo sed -i "/set default=\"*\"/cset default=\"3\"" /tmp/grub.cfg
        #fi
    fi
    sudo cp -vf /tmp/grub.cfg /mnt/${loaderdisk}1/boot/grub/grub.cfg
st "gen grub     " "Gen GRUB entries" "Finished Gen GRUB entries : ${MODEL}"

    [ -f /mnt/${loaderdisk}3/loader72.img ] && rm /mnt/${loaderdisk}3/loader72.img
    [ -f /mnt/${loaderdisk}3/grub72.cfg ] && rm /mnt/${loaderdisk}3/grub72.cfg
    [ -f /mnt/${loaderdisk}3/initrd-dsm72 ] && rm /mnt/${loaderdisk}3/initrd-dsm72

    sudo rm -rf /home/tc/rd.temp /home/tc/friend /home/tc/cache/*.pat

    if [ "${BUS}" != "block" ]; then
        msgnormal "Caching files for future use"
        [ ! -d ${local_cache} ] && mkdir ${local_cache}
    
        # Discover remote file size
        patfile=$(ls /home/tc/redpill-load/cache/*${TARGET_REVISION}*.pat | head -1)    
        FILESIZE=$(stat -c%s "${patfile}")
        SPACELEFT=$(df --block-size=1 | awk '/'${loaderdisk}'3/{print $4}') # Check disk space left    
    
        FILESIZE_FORMATTED=$(printf "%'d" "${FILESIZE}")
        SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
        FILESIZE_MB=$((FILESIZE / 1024 / 1024))
        SPACELEFT_MB=$((SPACELEFT / 1024 / 1024))    
    
        echo "FILESIZE  = ${FILESIZE_FORMATTED} bytes (${FILESIZE_MB} MB)"
        echo "SPACELEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"
    
        if [ 0${FILESIZE} -ge 0${SPACELEFT} ]; then
            # No disk space to download, change it to RAMDISK
            echo "No adequate space on ${local_cache} to backup cache pat file, clean up PAT file now ....."
            sudo sh -c "rm -vf $(ls -t ${local_cache}/*.pat | head -n 1)"
        fi
    
        if [ -f ${patfile} ]; then
            echo "Found ${patfile}, moving to cache directory : ${local_cache} "
            if [ "$FRKRNL" = "NO" ]; then
                cp -vf ${patfile} ${local_cache} && rm -vf /home/tc/redpill-load/cache/*.pat
            else
                sudo cp -vf ${patfile} ${local_cache} && sudo rm -vf /home/tc/redpill-load/cache/*.pat 
            fi
        fi
st "cachingpat" "Caching pat file" "Cached file to: ${local_cache}"
    fi    
}

function curlfriend() {

    LATESTURL="`curl --connect-timeout 5 -skL -w %{url_effective} -o /dev/null "https://github.com/PeterSuh-Q3/tcrpfriend/releases/latest"`"
    FRTAG="${LATESTURL##*/}"
    echo "FRIEND TAG is ${FRTAG}"        
    curl -kLO# "https://github.com/PeterSuh-Q3/tcrpfriend/releases/download/${FRTAG}/chksum" \
    -O "https://github.com/PeterSuh-Q3/tcrpfriend/releases/download/${FRTAG}/bzImage-friend" \
    -O "https://github.com/PeterSuh-Q3/tcrpfriend/releases/download/${FRTAG}/initrd-friend"

    if [ $? -ne 0 ]; then
        msgalert "Download failed from github.com friend... !!!!!!!!"
    else
        msgnormal "Bringing over my friend from github.com Done!!!!!!!!!!!!!!"            
    fi

}

function bringoverfriend() {

  [ ! -d /home/tc/friend ] && mkdir /home/tc/friend/ && cd /home/tc/friend

  echo -n "Checking for latest friend -> "
  # for test
  #curl -kLO# https://github.com/PeterSuh-Q3/tcrpfriend/releases/download/v0.1.0o/chksum -O https://github.com/PeterSuh-Q3/tcrpfriend/releases/download/v0.1.0o/bzImage-friend -O https://github.com/PeterSuh-Q3/tcrpfriend/releases/download/v0.1.0o/initrd-friend
  #return
  
  URL="https://github.com/PeterSuh-Q3/tcrpfriend/releases/latest/download/chksum"
  [ -n "$URL" ] && curl --connect-timeout 5 -s -k -L $URL -O

  if [ -f chksum ]; then
    FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
    BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
    INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
    if [ "$(sha256sum /mnt/${tcrppart}/bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum /mnt/${tcrppart}/initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ]; then
        msgnormal "OK, latest \n"
    else
        msgwarning "Found new version, bringing over new friend version : $FRIENDVERSION \n"
        curlfriend

        if [ -f bzImage-friend ] && [ -f initrd-friend ] && [ -f chksum ]; then
            FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
            BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
            INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
            cat chksum |grep VERSION
            echo
            [ "$(sha256sum bzImage-friend | awk '{print $1}')" == "$BZIMAGESHA256" ] && msgnormal "bzImage-friend checksum OK !" || msgalert "bzImage-friend checksum ERROR !" || exit 99
            [ "$(sha256sum initrd-friend | awk '{print $1}')" == "$INITRDSHA256" ] && msgnormal "initrd-friend checksum OK !" || msgalert "initrd-friend checksum ERROR !" || exit 99
        else
            msgalert "Could not find friend files !!!!!!!!!!!!!!!!!!!!!!!"
        fi
    fi
  else
    msgalert "No IP yet to check for latest friend \n"
  fi

}

function synctime() {

    if [ "$FRKRNL" = "NO" ]; then
        #Get Timezone
        tz=$(curl -s ipinfo.io | grep timezone | awk '{print $2}' | sed 's/,//')
        if [ $(echo $tz | grep Seoul | wc -l ) -gt 0 ]; then
            ntpserver="asia.pool.ntp.org"
        else
            ntpserver="pool.ntp.org"
        fi
    
        if [ "$(which ntpclient)_" == "_" ]; then
            tce-load -iw ntpclient 2>&1 >/dev/null
        fi    
        export TZ="${timezone}"
        echo "Synchronizing dateTime with ntp server $ntpserver ......"
        sudo ntpclient -s -h ${ntpserver} 2>&1 >/dev/null
    else
        GOOGLETIME=$(curl -k -v -s https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
        sudo date -u -s "$(date -d "$GOOGLETIME" "+%Y-%m-%d %H:%M:%S")"
    fi
    echo
    echo "DateTime synchronization complete!!!"

}

function matchpciidmodule() {

    MODULE_ALIAS_FILE="modules.alias.4.json"

    vendor="$(echo $1 | sed 's/[a-z]/\U&/g')"
    device="$(echo $2 | sed 's/[a-z]/\U&/g')"

    pciid="${vendor}d0000${device}"

    #jq -e -r ".modules[] | select(.alias | test(\"(?i)${1}\")?) |   .name " modules.alias.json
    # Correction to work with tinycore jq
    matchedmodule=$(jq -e -r ".modules[] | select(.alias | contains(\"${pciid}\")?) | .name " $MODULE_ALIAS_FILE)

    # Call listextensions for extention matching

    echo "$matchedmodule"

    #listextension $matchedmodule

}

function getmodaliasfile() {

    echo "{"
    echo "\"modules\" : ["

    grep -ie pci -ie usb /lib/modules/$(uname -r)/modules.alias | while read line; do

        read alias pciid module <<<"$line"
        echo "{"
        echo "\"name\" :  \"${module}\"",
        echo "\"alias\" :  \"${pciid}\""
        echo "}",
        #       echo "},"

    done | sed '$ s/,//'

    echo "]"
    echo "}"

}

function listmodules() {

    if [ ! -f $MODULE_ALIAS_FILE ]; then
        echo "Creating module alias json file"
        getmodaliasfile >modules.alias.4.json
    fi

    echo -n "Testing $MODULE_ALIAS_FILE -> "
    if $(jq '.' $MODULE_ALIAS_FILE >/dev/null); then
        echo "File OK"
        echo "------------------------------------------------------------------------------------------------"
        echo -e "It looks that you will need the following modules : \n\n"

        if [ "$WITHFRIEND" = "YES" ]; then
            echo "Block listpci for using all-modules. 2022.11.09"
        else    
            listpci
        fi

        echo "------------------------------------------------------------------------------------------------"
    else
        echo "Error : File $MODULE_ALIAS_FILE could not be parsed"
    fi

}

function ext_manager() {

    local _SCRIPTNAME="${0}"
    local _ACTION="${1}"
    local _PLATFORM_VERSION="${2}"
    shift 2
    local _REDPILL_LOAD_SRC="/home/tc/redpill-load"
    export MRP_SRC_NAME="${_SCRIPTNAME} ${_ACTION} ${_PLATFORM_VERSION}"
    ${_REDPILL_LOAD_SRC}/ext-manager.sh $@
    exit $?

}

function getredpillko() {

    DSMVER=$(echo ${TARGET_VERSION} | cut -c 1-3 )
    echo "KERNEL VERSION of getredpillko() is ${KVER}, DSMVER is ${DSMVER}"
    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then
        v=""
    else
        v=""
    fi

    TAG=""
    if [ "${offline}" = "NO" ]; then
        echo "Downloading ${ORIGIN_PLATFORM} ${KVER}+ redpill.ko ..."    
        LATESTURL="`curl --connect-timeout 5 -skL -w %{url_effective} -o /dev/null "https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/latest"`"
        #echo "? = $?"
        #if [ $? -ne 0 ]; then
        #    echo "Error downloading last version of ${ORIGIN_PLATFORM} ${KVER}+ rp-lkms.zip tring other path..."
        #    curl -skL https://raw.githubusercontent.com/PeterSuh-Q3/redpill-lkm${v}/master/rp-lkms.zip -o /mnt/${tcrppart}/rp-lkms${v}.zip
        #    if [ $? -ne 0 ]; then
        #        echo "Error downloading https://raw.githubusercontent.com/PeterSuh-Q3/redpill-lkm${v}/master/rp-lkms${v}.zip"
        #        exit 99
        #    fi    
        #else
        #    if [ "${ORIGIN_PLATFORM}" = "apollolake" ]; then
                TAG="${LATESTURL##*/}"
                #[ "${ORIGIN_PLATFORM}" = "bromolow" ] && TAG="23.12.0"
        #    elif [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then
        #        TAG="${LATESTURL##*/}"
        #    else
        #        TAG="24.4.11"
        #    fi
            echo "TAG is ${TAG}"
            STATUS=`sudo curl --connect-timeout 5 -skL -w "%{http_code}" "https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/download/${TAG}/rp-lkms.zip" -o "/mnt/${tcrppart}/rp-lkms${v}.zip"`
        #fi
    else
        echo "Unzipping ${ORIGIN_PLATFORM} ${KVER}+ redpill.ko ..."        
    fi    

    sudo rm -f /home/tc/custom-module/*.gz
    sudo rm -f /home/tc/custom-module/*.ko
    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then    
        unzip /mnt/${tcrppart}/rp-lkms${v}.zip        rp-${ORIGIN_PLATFORM}-${DSMVER}-${KVER}-${redpillmake}.ko.gz -d /tmp >/dev/null 2>&1
        gunzip -f /tmp/rp-${ORIGIN_PLATFORM}-${DSMVER}-${KVER}-${redpillmake}.ko.gz >/dev/null 2>&1
        sudo cp -vf /tmp/rp-${ORIGIN_PLATFORM}-${DSMVER}-${KVER}-${redpillmake}.ko /home/tc/custom-module/redpill.ko
    elif [ "${ORIGIN_PLATFORM}" = "bromolow" ]; then
        STATUS=`sudo curl --connect-timeout 5 -skL -w "%{http_code}" "https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/download/${TAG}/rp-bromolow-3.10.108-prod.ko.gz" -o "/mnt/${tcrppart}/rp-bromolow-3.10.108-prod.ko.gz"`
        sudo cp -vf /mnt/${tcrppart}/rp-bromolow-3.10.108-prod.ko.gz /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-${redpillmake}.ko.gz >/dev/null 2>&1
        gunzip -f /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-${redpillmake}.ko.gz >/dev/null 2>&1
        sudo cp -vf /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-${redpillmake}.ko /home/tc/custom-module/redpill.ko
    else    
        unzip /mnt/${tcrppart}/rp-lkms${v}.zip        rp-${ORIGIN_PLATFORM}-${KVER}-${redpillmake}.ko.gz -d /tmp >/dev/null 2>&1
        gunzip -f /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-${redpillmake}.ko.gz >/dev/null 2>&1
        sudo cp -vf /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-${redpillmake}.ko /home/tc/custom-module/redpill.ko
    fi

    if [ -z "${TAG}" ]; then
        unzip /mnt/${tcrppart}/rp-lkms${v}.zip        VERSION -d /tmp >/dev/null 2>&1
        TAG=$(cat /tmp/VERSION )
        echo "TAG of VERSION is ${TAG}"
    fi

    #REDPILL_MOD_NAME="redpill-linux-v$(modinfo /home/tc/custom-module/redpill.ko | grep vermagic | awk '{print $2}').ko"
    if [ "${ORIGIN_PLATFORM}" = "bromolow" ]; then
        REDPILL_MOD_NAME="redpill-linux-v${KVER}.ko"
    else
        REDPILL_MOD_NAME="redpill-linux-v${KVER}+.ko"
    fi    
    sudo cp -vf /home/tc/custom-module/redpill.ko /home/tc/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME}
    sudo strip --strip-debug /home/tc/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME}

}

function changeautoupdate {
    if [ -z "$1" ]; then
      echo -en "\r$(msgalert "There is no on or off parameter.!!!")\n"
      exit 99
    elif [ "$1" != "on" ] && [ "$1" != "off" ]; then
      echo -en "\r$(msgalert "There is no on or off parameter.!!!")\n"
      exit 99
    fi

    getloaderdisk
    tcrppart="${loaderdisk}3"

    jsonfile=$(jq . $userconfigfile)
    
    echo -n "friendautoupd on User config file needs update, updating -> "
    if [ "$1" = "on" ]; then
        jsonfile=$(echo $jsonfile | jq '.general |= . + { "friendautoupd":"true" }' || echo $jsonfile | jq .)
    else
        jsonfile=$(echo $jsonfile | jq '.general |= . + { "friendautoupd":"false" }' || echo $jsonfile | jq .)
    fi
    cp $userconfigfile /mnt/${tcrppart}/
    echo $jsonfile | jq . >$userconfigfile && echo "Done" || echo "Failed"
    
    cat $userconfigfile | grep friendautoupd
}

function upgrademan() {
    if [ -z "$1" ]; then
      echo -en "\r$(msgalert "There is no TCRP Friend version.!!!")\n"
      exit 99
    fi

    getloaderdisk
    tcrppart="${loaderdisk}3"

    [ ! -d /home/tc/friend ] && mkdir /home/tc/friend/ && cd /home/tc/friend
    
    friendautoupd="$(jq -r -e '.general .friendautoupd' $userconfigfile)"
    if [ "${friendautoupd}" = "false" ]; then
        echo -en "\r$(msgwarning "TCRP Friend auto update disabled")\n"
    else
        echo -en "\r$(msgwarning "TCRP Friend auto update enabled")\n"	
    fi
    FRIENDVERSION="$1"
    msgwarning "Found target version, bringing over new friend version : $FRIENDVERSION \n"
    echo -n "Checking for version $FRIENDVERSION friend -> "
    URL=$(curl --connect-timeout 15 -s --insecure -L https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/tags/"${FRIENDVERSION}" | jq -r -e .assets[].browser_download_url | grep chksum)
    if [ $? -ne 0 ]; then
        msgalert "Error downloading version of $FRIENDVERSION friend...\n"
        exit 99
    fi

    # download file chksum
    [ -n "$URL" ] && curl -s --insecure -L $URL -O
    if [ $? -ne 0 ]; then
        msgalert "Error downloading version of $FRIENDVERSION friend...\n"
        exit 99
    fi
    URLS=$(curl --insecure -s https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/tags/"${FRIENDVERSION}" | jq -r ".assets[].browser_download_url")
    for file in $URLS; do curl --insecure --location --progress-bar "$file" -O; done
    FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
    BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
    INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
    [ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f bzImage-friend /mnt/${tcrppart}/ && msgnormal "bzImage OK! \n"
    [ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f initrd-friend /mnt/${tcrppart}/ && msgnormal "initrd-friend OK! \n"
    echo -e "$(msgnormal "TCRP FRIEND HAS BEEN UPDATED!!!")"
    changeautoupdate "off"

    if [ -f /home/tc/friend/initrd-friend ] && [ -f /home/tc/friend/bzImage-friend ]; then
        cp /home/tc/friend/initrd-friend /mnt/${tcrppart}/
        cp /home/tc/friend/bzImage-friend /mnt/${tcrppart}/
        sudo rm -rf /home/tc/friend
    fi

}

function returnto() {
    echo "${1}"
    read answer
    cd ~
}

function spacechk() {
  # Discover file size
  SPACEUSED=$(df --block-size=1 | awk '/'${1}'/{print $3}') # Check disk space used
  SPACELEFT=$(df --block-size=1 | awk '/'${2}'/{print $4}') # Check disk space left

  SPACEUSED_FORMATTED=$(printf "%'d" "${SPACEUSED}")
  SPACELEFT_FORMATTED=$(printf "%'d" "${SPACELEFT}")
  SPACEUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${SPACEUSED} / 1024 / 1024}")
  SPACELEFT_MB=$(awk "BEGIN {printf \"%.1f\", ${SPACELEFT} / 1024 / 1024}")      

  msgwarning "SOURCE SPACE USED = ${SPACEUSED_FORMATTED} bytes (${SPACEUSED_MB} MB)"
  msgwarning "TARGET SPACE LEFT = ${SPACELEFT_FORMATTED} bytes (${SPACELEFT_MB} MB)"
}

function get_partition() {
    local disk=$1
    local num=$2
    if [[ "$disk" =~ ^/dev/nv ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

function tcrpfriendentry_hdd() {
    
    cat <<EOF
menuentry 'Tiny Core Friend ${MODEL} ${BUILD} Update 0 ${DMPM}' {
        savedefault
        search --set=root --fs-uuid "1234-5678" --hint hd0,msdos${1}
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8
        echo Loading initramfs...
        initrd /initrd-friend
        echo Booting TinyCore Friend
}
EOF

}

function xtcrpconfigureentry_hdd() {
    cat <<EOF
menuentry 'xTCRP Configure Boot Loader (Loader Build)' {
        savedefault
        search --set=root --fs-uuid "1234-5678" --hint hd0,msdos${1}
        echo Loading Linux...
        linux /bzImage-friend loglevel=3 waitusb=5 vga=791 net.ifnames=0 biosdevname=0 console=ttyS0,115200n8 IWANTTOCONFIGURE
        echo Loading initramfs to configure loader...
        initrd /initrd-friend
        echo Loding xTCRP RAMDISK to configure loader...
}
EOF
}

function wr_part1() {

    fediskpart="$(get_partition "${edisk}" ${1})"
    mdiskpart=$(echo "${fediskpart}" | sed 's/dev/mnt/')
    
    [ ! -d "${mdiskpart}" ] && sudo mkdir "${mdiskpart}"
      while true; do
        sleep 1
        echo "Mounting ${fediskpart} ..."
        sudo mount "${fediskpart}" "${mdiskpart}"
        [ $( mount | grep "${fediskpart}" | wc -l ) -gt 0 ] && break
    done
    sudo rm -rf "${mdiskpart}"/*

    diskid=$(echo "${fediskpart}" | sed 's#/dev/##')
    spacechk "${loaderdisk}1" "${diskid}"
    FILESIZE1=$(ls -l /mnt/${loaderdisk}3/bzImage-friend | awk '{print$5}')
    FILESIZE2=$(ls -l /mnt/${loaderdisk}3/initrd-friend | awk '{print$5}')
    
    a_num=$(echo $FILESIZE1 | bc)
    b_num=$(echo $FILESIZE2 | bc)
    c_num=$(echo $SPACEUSED | bc)
    t_num=$(($a_num + $b_num + $c_num))
    
    TOTALUSED=$(echo $t_num)
    TOTALUSED_FORMATTED=$(printf "%'d" "${TOTALUSED}")
    TOTALUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${TOTALUSED} / 1024 / 1024}")
    msgwarning "TARGET TOTAL USED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"

    ZIMAGESIZE=""
    if [ 0${TOTALUSED} -ge 0${SPACELEFT} ]; then
        ZIMAGESIZE=$(ls -l /mnt/${loaderdisk}1/zImage | awk '{print$5}')
        z_num=$(echo $ZIMAGESIZE | bc)
        t_num=$(($t_num - $z_num))

        TOTALUSED=$(echo $t_num)
        TOTALUSED_FORMATTED=$(printf "%'d" "${TOTALUSED}")
        TOTALUSED_MB=$((TOTALUSED / 1024 / 1024))
        echo "FIXED TOTALUSED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"

        if [ 0${TOTALUSED} -ge 0${SPACELEFT} ]; then
            mountpoint -q "${mdiskpart}" && sudo umount "${mdiskpart}"
            returnto "Source Partition is too big ${TOTALUSED}, Space left ${SPACELEFT} !!!. Stop processing!!! " 
            false
        fi   
    fi

    if [ -z ${ZIMAGESIZE} ]; then
        cd /mnt/${loaderdisk}1 && sudo find . | sudo cpio -pdm "${mdiskpart}" 2>/dev/null
    else
        cd /mnt/${loaderdisk}1 && sudo find . -not -name "zImage" | sudo cpio -pdm "${mdiskpart}" 2>/dev/null
    fi

    echo "Modifying grub.cfg for new loader boot..."
    sudo sed -i '61,$d' "${mdiskpart}"/boot/grub/grub.cfg
    tcrpfriendentry_hdd ${1} | sudo tee --append "${mdiskpart}"/boot/grub/grub.cfg
    xtcrpconfigureentry_hdd ${1} | sudo tee --append "${mdiskpart}"/boot/grub/grub.cfg

    sudo cp -vf /mnt/${loaderdisk}3/bzImage-friend  "${mdiskpart}"
    sudo cp -vf /mnt/${loaderdisk}3/initrd-friend  "${mdiskpart}"

    sudo mkdir -p /usr/local/share/locale
    sudo grub-install --target=x86_64-efi --boot-directory="${mdiskpart}"/boot --efi-directory="${mdiskpart}" --removable > /dev/null 2>&1
    [ $? -ne 0 ] && returnto "excute grub-install ${mdiskpart} failed. Stop processing!!! " && false
    sudo grub-install --target=i386-pc --boot-directory="${mdiskpart}"/boot "${edisk}" > /dev/null 2>&1
    [ $? -ne 0 ] && returnto "excute grub-install ${mdiskpart} failed. Stop processing!!! " && false
    true
}

function wr_part2() {

    fediskpart="$(get_partition "${edisk}" ${1})"
    mdiskpart=$(echo "${fediskpart}" | sed 's/dev/mnt/')
    
    [ ! -d "${mdiskpart}" ] && sudo mkdir "${mdiskpart}"
    while true; do
        sleep 1
        echo "Mounting ${fediskpart} ..."
        sudo mount "${fediskpart}" "${mdiskpart}"
        [ $( mount | grep "${fediskpart}" | wc -l ) -gt 0 ] && break
    done
    sudo rm -rf "${mdiskpart}"/*

    diskid=$(echo "${fediskpart}" | sed 's#/dev/##')        
    spacechk "${loaderdisk}2" "${diskid}"

    TOTALUSED_FORMATTED=$(printf "%'d" "${SPACEUSED}")
    TOTALUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${SPACEUSED} / 1024 / 1024}")
    msgwarning "TARGET TOTAL USED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"

    if [ 0${SPACEUSED} -ge 0${SPACELEFT} ]; then
        mountpoint -q "${mdiskpart}" && sudo umount "${mdiskpart}"
        returnto "Source Partition is too big ${SPACEUSED}, Space left ${SPACELEFT} !!!. Stop processing!!! " 
        false
    fi   
  
    cd /mnt/${loaderdisk}2 && sudo find . | sudo cpio -pdm "${mdiskpart}" 2>/dev/null
    true
}

function wr_part3() {

    fediskpart="$(get_partition "${edisk}" ${1})"
    mdiskpart=$(echo "${fediskpart}" | sed 's/dev/mnt/')
    
    [ ! -d "${mdiskpart}" ] && sudo mkdir "${mdiskpart}"
    while true; do
        sleep 1
        echo "Mounting ${fediskpart} ..."
        sudo mount "${fediskpart}" "${mdiskpart}"
        [ $( mount | grep "${fediskpart}" | wc -l ) -gt 0 ] && break
    done
    sudo rm -rf "${mdiskpart}"/*

    diskid=$(echo "${fediskpart}" | sed 's#/dev/##')
    spacechk "${loaderdisk}3" "${diskid}"
    FILESIZE1=$(ls -l /mnt/${loaderdisk}3/zImage-dsm | awk '{print$5}')
    FILESIZE2=$(ls -l /mnt/${loaderdisk}3/initrd-dsm | awk '{print$5}')
    
    a_num=$(echo $FILESIZE1 | bc)
    b_num=$(echo $FILESIZE2 | bc)
    t_num=$(($a_num + $b_num + 2000 ))
    TOTALUSED=$(echo $t_num)

    TOTALUSED_FORMATTED=$(printf "%'d" "${TOTALUSED}")
    TOTALUSED_MB=$(awk "BEGIN {printf \"%.1f\", ${TOTALUSED} / 1024 / 1024}")
    msgwarning "TARGET TOTAL USED = ${TOTALUSED_FORMATTED} bytes (${TOTALUSED_MB} MB)"
    
    if [ 0${TOTALUSED} -ge 0${SPACELEFT} ]; then
        mountpoint -q "${mdiskpart}" && sudo umount "${mdiskpart}"
        returnto "Source Partition is too big ${TOTALUSED}, Space left ${SPACELEFT} !!!. Stop processing!!! " 
        false
    fi   

    cd /mnt/${loaderdisk}3 && find . -name "*dsm*" -o -name "user_config.json" | sudo cpio -pdm "${mdiskpart}" 2>/dev/null
    #sudo curl -kL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/refs/heads/main/xtcrp.tgz -o "${mdiskpart}"/xtcrp.tgz
    true
}

function prepare_grub() {

    tce-load -i grub2-multi 
    if [ $? -eq 0 ]; then
        echo "Install grub2-multi OK !!!"
    else
        tce-load -iw grub2-multi
        [ $? -ne 0 ] && returnto "Install grub2-multi failed. Stop processing!!! " && false
    fi
    #sudo echo "grub2-multi.tcz" >> /mnt/${tcrppart}/cde/onboot.lst

    true
}

function prepare_img() {

    echo "Downloading tempelete disk image to ${imgpath}..."
    imgpath="/dev/shm/boot-image-to-hdd.img"  
    if [ -f ${imgpath} ]; then
        echo "Image file ${imgpath} Already Exist..."
     else
        sudo curl -kL# https://github.com/PeterSuh-Q3/rp-ext/releases/download/temp/boot-image-to-hdd.img.gz -o "${imgpath}.gz"
        [ $? -ne 0 ] && returnto "Download failed. Stop processing!!! ${imgpath}" && false
        echo "Unpacking image ${imgpath}..."
        sudo gunzip -f "${imgpath}.gz"
    fi

     if [ -z "$(losetup | grep -i ${imgpath})" ]; then
        if [ ! -n "$(losetup -j ${imgpath} | awk '{print $1}' | sed -e 's/://')" ]; then
            echo -n "Setting up ${imgpath} loop -> "
            sudo losetup -fP ${imgpath}
            [ $? -ne 0 ] && returnto "Mount loop device for ${imgpath} failed. Stop processing!!! " && false
        else
            echo -n "Loop device exists..."
        fi
    fi
    loopdev=$(losetup -j ${imgpath} | awk '{print $1}' | sed -e 's/://')
    echo "$loopdev"
 
    true
}

function get_disk_type_cnt() {

    RAID_CNT="$(sudo /sbin/fdisk -l | grep "fd Linux raid autodetect" | grep ${1} | wc -l )"
    DOS_CNT="$(sudo /sbin/fdisk -l | grep "83 Linux" | grep ${1} | wc -l )"
    W95_CNT="$(sudo /sbin/fdisk -l | grep "95 Ext" | grep ${1} | wc -l )" 
    EXT_CNT="$(sudo /sbin/fdisk -l | grep "Extended" | grep ${1} | wc -l )" 
    if [ "${2}" = "Y" ]; then
        echo "RAID_CNT=$RAID_CNT"
        echo "DOS_CNT=$DOS_CNT"
        echo "W95_CNT=$W95_CNT"
        echo "EXT_CNT=$EXT_CNT"
    fi    
}

function inject_loader() {

  if [ ! -f /mnt/${loaderdisk}3/bzImage-friend ] || [ ! -f /mnt/${loaderdisk}3/initrd-friend ] || [ ! -f /mnt/${loaderdisk}3/zImage-dsm ] || [ ! -f /mnt/${loaderdisk}3/initrd-dsm ] || [ ! -f /mnt/${loaderdisk}3/user_config.json ] || [ ! $(grep -i "Tiny Core Friend" /mnt/${loaderdisk}1/boot/grub/grub.cfg | wc -l) -eq 1 ]; then
    returnto "The loader has not been built yet. Start with the build.... Stop processing!!! " && return
  fi

  plat=$(cat /mnt/${loaderdisk}1/GRUB_VER | grep PLATFORM | cut -d "=" -f2 | tr '[:upper:]' '[:lower:]' | sed 's/"//g')
  [ "${plat}" = "epyc7002" ] &&    returnto "Epyc7002 like SA6400 is not supported... Stop processing!!! " && return

  #[ "$MACHINE" = "VIRTUAL" ] &&    returnto "Virtual system environment is not supported. Two or more BASIC type hard disks are required on bare metal. (SSD not possible)... Stop processing!!! " && return

  BASIC=0
  SHR=0  
  BASIC_EX=0  
  SHR_EX=0
  FIRST_SHR=""
  while read -r edisk; do
      get_disk_type_cnt "${edisk}" "N"
      
      if [ $RAID_CNT -eq 3 ]; then
          case "$DOS_CNT $W95_CNT" in
              #"0 0")
              #    echo "This is BASIC or JBOD Type Hard Disk. $edisk"
              #    ((BASIC++))
              #    ;;
              "0 1")
                  echo "This is SHR Type Hard Disk. $edisk"
                  ((SHR++))
                  if [ -z "$FIRST_SHR" ]; then
                      FIRST_SHR="$edisk"
                  fi                  
                  ;;
              "2 0")
                  echo "This is BASIC Type Hard Disk and Has synoboot1 and synoboot2 Boot Partition $edisk"
                  ((BASIC_EX++))
                  ;;
              "1 0")
                  if [ $(sudo /sbin/blkid | grep ${edisk} | grep -c "8765-4321") -eq 1 ]; then
                      echo "This is BASIC Type Hard Disk and Has synoboot3 Boot Partition $edisk"
                      ((BASIC_EX++))
                  fi
                  ;;
              "3 1")
                  echo "This is SHR Type Hard Disk and Has synoboot1, synoboot2 and synoboot3 Boot Partition $edisk"
                  ((SHR_EX++))
                  if [ -z "$FIRST_SHR" ]; then
                      FIRST_SHR="$edisk"
                  fi                  
                  ;;
          esac
      fi
  done < <(sudo /sbin/fdisk -l | grep -e "Disk /dev/sd" -e "Disk /dev/nv" | awk '{print $2}' | sed 's/://' | sort -k1.6 -r )

  echo "SHR = $SHR, BASIC_EX = $BASIC_EX, SHR_EX = $SHR_EX"
  [ -n "$FIRST_SHR" ] && echo "First SHR disk: $FIRST_SHR"

  do_ex_first=""
  if [ $BASIC_EX -ge 1 ]; then
    #echo "There is at least one BASIC type disk each with an injected bootloader...OK"
    #do_ex_first="Y"
    returnto "BASIC or JBOD Type Disk is no longer supported. It is possible by converting to SHR.. Function Exit now!!! Press any key to continue..." && return  
  elif [ $SHR_EX -eq 1 ]; then
    echo "There is at least one SHR type disk each with an injected bootloader...OK"
    do_ex_first="Y"
  elif [ $SHR -ge 1 ]; then
    echo "There is at least one disk of type SHR...OK"
    if [ -z "${do_ex_first}" ]; then
      do_ex_first="N"
    fi
  #elif [ $BASIC_EX -eq 0 ] && [ $SHR_EX -gt 1 ]; then 
  else
      returnto "There is not enough Type Disk. Function Exit now!!! Press any key to continue..." && return  
  fi

  echo "do_ex_first = ${do_ex_first}"
  
echo -n "(Warning) Do you want to port the bootloader to Syno disk? [yY/nN] : "
readanswer
if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then
    if [ ! -f /tmp/tce/optional/inject-tool.tgz ]; then
        curl -kL# https://github.com/PeterSuh-Q3/tinycore-redpill/releases/download/v1.2.0.0/inject-tool.tgz -o /tmp/tce/optional/inject-tool.tgz
        tar -zxvf /tmp/tce/optional/inject-tool.tgz -C /tmp/tce/optional/    
    fi    

    tce-load -i bc
    if [ $? -eq 0 ]; then
        echo "Install bc OK !!!"
    else
        tce-load -iw bc
        [ $? -ne 0 ] && returnto "Install grub2-multi failed. Stop processing!!! " && return
    fi
    tce-load -i dosfstools
    if [ $? -eq 0 ]; then
        echo "Install dosfstools OK !!!"
    else
        tce-load -iw dosfstools
        [ $? -ne 0 ] && returnto "Install dosfstools failed. Stop processing!!! " && false
    fi

    if [ "${do_ex_first}" = "N" ]; then
        if [ $SHR -ge 1 ]; then
            echo "New bootloader injection (including /sbin/fdisk partition creation)..."

            BOOTMAKE=""
            SYNOP3MAKE=""

            # If there is a SHR disk, only process that disk.
            if [ -n "$FIRST_SHR" ]; then
                disk_list="$FIRST_SHR"
            else
                # descending sort from /dev/sd            
                disk_list=$(sudo /sbin/fdisk -l | grep -e "Disk /dev/sd" -e "Disk /dev/nv" | awk '{print $2}' | sed 's/://' | sort -k1.6 -r)
            fi
            
            for edisk in $disk_list; do
         
                model=$(lsblk -o PATH,MODEL | grep $edisk | head -1)
                get_disk_type_cnt "${edisk}" "Y"
                
                if [ $RAID_CNT -eq 0 ] && [ $DOS_CNT -eq 3 ] && [ $W95_CNT -eq 0 ] && [ $EXT_CNT -eq 0 ]; then
                    echo "Skip this disk as it is a loader disk. $model"
                    continue
                elif [ -z "${BOOTMAKE}" ] && [ $RAID_CNT -eq 3 ] && [ $DOS_CNT -eq 0 ]; then

                    prepare_grub
                    [ $? -ne 0 ] && return

                    if [ $W95_CNT -eq 1 ]; then
                        # SHR OR RAID can make primary partition
                        # make 1st partition
                        echo "Create primary and logical partitions on 1st disk. ${model}"
                        last_sector="20979712"
                    
                        # +127M
                        echo "Create primary partition on SHR disks... $edisk"
                        echo -e "n\np\n$last_sector\n+127M\nw\n" | sudo /sbin/fdisk "${edisk}" > /dev/null 2>&1
                        [ $? -ne 0 ] && returnto "make primary partition on ${edisk} failed. Stop processing!!! " && remove_loader && return
                        sleep 2
      
                        echo -e "a\n4\nw" | sudo /sbin/fdisk "${edisk}" > /dev/null 2>&1
                        [ $? -ne 0 ] && returnto "activate partition on ${edisk} failed. Stop processing!!! " && remove_loader && return
                        sleep 2

                        # make 2rd partition
                        last_sector="$(fdisk -l "${edisk}" | grep "$(get_partition "${edisk}" 5)" | awk '{print $3}')"
                        # skip 96 sectors
                        last_sector=$((${last_sector} + 96))
                        #echo "part 6's start sector is $last_sector"
                        
                        # +12.8M
                        echo -e "n\n$last_sector\n+13M\nw\n" | sudo /sbin/fdisk "${edisk}" > /dev/null 2>&1
                        [ $? -ne 0 ] && returnto "make primary partition on ${edisk} failed. Stop processing!!! " && remove_loader && return
                        sleep 2

                        if [ $(/sbin/blkid | grep "8765-4321" | wc -l) -eq 0 ]; then
                            # make 3rd partition
                            last_sector="$(fdisk -l "${edisk}" | grep "$(get_partition "${edisk}" 6)" | awk '{print $3}')"
                            # skip 96 sectors
                            last_sector=$((${last_sector} + 96))
                            #echo "part 7's start sector is $last_sector"
                            
                            # +79M
                            echo -e "n\n$last_sector\n\n\nw\n" | sudo /sbin/fdisk "${edisk}" > /dev/null 2>&1
                            [ $? -ne 0 ] && returnto "make primary partition on ${edisk} failed. Stop processing!!! " && remove_loader && return
                            sleep 2
                        else
                            echo "The synoboot3 was already made!!!"
                        fi

                        sudo mkfs.vfat -i 12345678 -F16 "$(get_partition "${edisk}" 4)" > /dev/null 2>&1
                        synop1=$(get_partition "${edisk}" 4)
                        wr_part1 "4"
                        [ $? -ne 0 ] && remove_loader && return

                        sudo mkfs.vfat -F16 "$(get_partition "${edisk}" 6)" > /dev/null 2>&1
                        synop2=$(get_partition "${edisk}" 6)
                        wr_part2 "6"
                        [ $? -ne 0 ] && remove_loader && return

                        #prepare_img
                        sudo mkfs.vfat -i 87654321 -F16 "$(get_partition "${edisk}" 7)" > /dev/null 2>&1
                        synop3=$(get_partition "${edisk}" 7)
                        wr_part3 "7"
                        [ $? -ne 0 ] && remove_loader && return
                        
                        SYNOP3MAKE="YES"
                        break
                    fi    
           
                else
                    echo "The conditions for adding a fat partition are not met (3 rd, 0 83). $model"
                    continue
                fi
            done
        fi
    elif [ "${do_ex_first}" = "Y" ]; then
        if [ $SHR_EX -eq 1 ]; then
            echo "Reinject bootloader (into existing partition)..."

            # If there is a SHR disk, only process that disk.
            if [ -n "$FIRST_SHR" ]; then
                disk_list="$FIRST_SHR"
            else
                # descending sort from /dev/sd            
                disk_list=$(sudo /sbin/fdisk -l | grep -e "Disk /dev/sd" -e "Disk /dev/nv" | awk '{print $2}' | sed 's/://' | sort -k1.6 -r)
            fi
            
            for edisk in $disk_list; do
         
                model=$(lsblk -o PATH,MODEL | grep $edisk | head -1)
                get_disk_type_cnt "${edisk}" "Y"
                
                echo
                if [ $RAID_CNT -eq 0 ] && [ $DOS_CNT -eq 3 ] && [ $W95_CNT -eq 0 ] && [ $EXT_CNT -eq 0 ]; then
                    echo "Skip this disk as it is a loader disk. $model"
                    continue
                elif [ $RAID_CNT -eq 3 ] && [ $DOS_CNT -eq 3 ] && [ $W95_CNT -eq 1 ] && [ $EXT_CNT -eq 0 ]; then
                    # single SHR 
                    prepare_grub
                    [ $? -ne 0 ] && remove_loader && return

                    synop1=$(get_partition "${edisk}" 4)                    
                    wr_part1 "4"
                    [ $? -ne 0 ] && remove_loader && return                    

                    synop2=$(get_partition "${edisk}" 6)                 
                    wr_part2 "6"
                    [ $? -ne 0 ] && remove_loader && return

                    synop3=$(get_partition "${edisk}" 7)
                    wr_part3 "7"
                    [ $? -ne 0 ] && remove_loader && return
                    
                    break
              
                fi
            done
        fi
    fi 
    #sudo losetup -d ${loopdev}
    #[ -z "$(losetup | grep -i ${imgpath})" ] && echo "boot-image-to-hdd.img losetup OK !!!"
    sync
    echo "unmount synoboot partitions...${synop1}, ${synop2}, ${synop3}"
    synop1=$(echo "${synop1}" | sed 's/dev/mnt/')
    synop2=$(echo "${synop2}" | sed 's/dev/mnt/')
    synop3=$(echo "${synop3}" | sed 's/dev/mnt/')
    mountpoint -q "${synop1}" && sudo umount ${synop1} 
    mountpoint -q "${synop2}" && sudo umount ${synop2} 
    mountpoint -q "${synop3}" && sudo umount ${synop3}
    returnto "The entire process of injecting the boot loader into the disk has been completed! Press any key to continue..." && return
fi

}

function debug_msg() {
    echo "[DEBUG] $1" >&2
}

function remove_loader() {

  echo -n "(Warning) Do you want to remove partitions from Syno disk? [yY/nN] : "
  readanswer
  if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then

      LC_ALL=C sudo fdisk -l | awk '$NF=="Linux" && $(NF-1)==83 {print $1}' | while read -r dev; do
          part_num="${dev##*[!0-9]}"
          if [[ $part_num -ge 4 ]]; then
              base_dev=$(lsblk -no pkname "$dev" | xargs -I{} echo "/dev/{}")
              echo "$base_dev $part_num"
          fi
      done | sort -u | awk '{arr[$1]=arr[$1]" "$2} END{for (i in arr) print i, arr[i]}' | while read -r dev parts; do
          cmd=""
          for p in $(echo "$parts" | tr ' ' '\n' | sort -nr); do
              cmd+="d\n$p\n"
          done
          echo -e "${cmd}w\n" | sudo fdisk "$dev"
      done
  
  fi
  returnto "The entire process of removing the partition is completed! Press any key to continue..." && return

}

function rploader() {

    echo "LOADER DISK = ${loaderdisk}"
    [ -z "${loaderdisk}" ] && getloaderdisk
    if [ -z "${loaderdisk}" ]; then
        echo "Not Supported Loader BUS Type, program Exit!!!"
        exit 99
    fi
    
    #getBus "${loaderdisk}" 
    echo -ne "Loader BUS: $(msgnormal "${BUS}")\n"

    tcrppart="${loaderdisk}3"
    tcrpdisk=$loaderdisk

    case $1 in

    build)

        getvars $ORIGIN_PLATFORM
        if [ -d /mnt/${tcrppart}/redpill-load/ ]; then
            offline="YES"
        else
            offline="NO"
            checkinternet
        fi    
#        getlatestrploader
#        gitdownload     # When called from the parent my.sh, -d flag authority check is not possible, pre-downloaded in advance 
        checkUserConfig
        getredpillko
#for test getredpillko
#exit 0
echo "$3"

        [ "$3" = "withfriend" ] && WITHFRIEND="YES" || WITHFRIEND="NO"

        case $3 in

        manual)

            echo "Using static compiled redpill extension"
            echo "Got $REDPILL_MOD_NAME "
            echo "Manual extension handling,skipping extension auto detection "
            echo "Starting loader creation "
            buildloader "manual"
            [ $? -eq 0 ] && savesession
            ;;

        jun)
            echo "Using static compiled redpill extension"
            echo "Got $REDPILL_MOD_NAME "
            listmodules
            echo "Starting loader creation "
            buildloader "junmod"
            [ $? -eq 0 ] && savesession
            ;;

        static | *)
            echo "No extra build option or static specified, using default <static> "
            echo "Using static compiled redpill extension"
            echo "Got $REDPILL_MOD_NAME "
            listmodules 
            echo "Starting loader creation "
            buildloader "static"
            [ $? -eq 0 ] && savesession
            ;;

        esac
        ;;

    clean)
        cleanloader
        ;;

    backup)
        backuploader
        ;;

    postupdate)
        getvars $ORIGIN_PLATFORM
        checkinternet
        gitdownload
        postupdate
        [ $? -eq 0 ] && savesession
        ;;
    help)
        showhelp
        exit 99
        ;;
    monitor)
        monitor
        exit 0
        ;;    
    *)
        showsyntax
        exit 99
        ;;

    esac
}

function add-addons() {
    jsonfile=$(jq ". |= .+ {\"${1}\": \"https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/master/${1}/rpext-index.json\"}" /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json    
}

function my() {

  echo "$1"
  echo "$2"
  echo "$3"

  echo "LOADER DISK = ${loaderdisk}"
  [ -z "${loaderdisk}" ] && getloaderdisk
  if [ -z "${loaderdisk}" ]; then
      echo "Not Supported Loader BUS Type, program Exit!!!"
      exit 99
  fi

  echo "${loaderdisk}" > /tmp/loaderdisk
  
  #getBus "${loaderdisk}" 
    
  tcrppart="${loaderdisk}3"

  if [ "${BUS}" = "block" ]; then
    git clone --depth=1 "https://github.com/PeterSuh-Q3/tcrp-addons.git"
    mkdir -p /dev/shm/tcrp-addons
    rm -rf ./tcrp-addons/.git/
    mv -f ./tcrp-addons/* /dev/shm/tcrp-addons/
  fi
  
  if [ -d /mnt/${tcrppart}/redpill-load/ ]; then
      offline="YES"
  else
      offline="NO"
      checkinternet
      if [ "$gitdomain" = "raw.githubusercontent.com" ]; then
          if [ $# -lt 1 ]; then
              getlatestmshell "ask"
          else
              if [ "$1" = "update" ]; then 
                  getlatestmshell "noask"
                  exit 0
              else
                  getlatestmshell "noask"
              fi
          fi
      fi
      gitdownload
  fi
  
  if [ $# -lt 1 ]; then
      showhelp 
      exit 99
  fi
  
  getvarsmshell "$1"
  
  #echo "$TARGET_REVISION"                                                      
  #echo "$TARGET_PLATFORM"                                            
  #echo "$SYNOMODEL"                                      
  
  postupdate="N"
  userdts="N"
  noconfig="N"
  jot="N"
  prevent_init="N"
  
  shift
      while [[ "$#" > 0 ]] ; do
  
          case $1 in
          postupdate)
              postupdate="Y"
              ;;
              
          userdts)
              userdts="Y"
              ;;
  
          noconfig)
              noconfig="Y"
              ;;
           
          jot)
              jot="Y"
              ;;
  
          fri)
              jot="N"
              ;;
  
          prevent_init)
              prevent_init="Y"
              ;;
  
          *)
              echo "Syntax error, not valid arguments or not enough options"
              exit 0
              ;;
  
          esac
          shift
      done
  
  #echo $postupdate
  #echo $userdts
  #echo $noconfig
  
  echo
  
  if [ "$tcrppart" = "mmc3" ]; then
      tcrppart="mmcblk0p3"
  fi
  
  echo
  echo "loaderdisk is" "${loaderdisk}"
  echo
  
  if [ ! -d "/mnt/${tcrppart}/auxfiles" ]; then
      cecho g "making directory  /mnt/${tcrppart}/auxfiles"  
      mkdir -p /mnt/${tcrppart}/auxfiles 
  fi
  if [ ! -h /home/tc/custom-module ]; then
      cecho y "making link /home/tc/custom-module"  
      sudo ln -s /mnt/${tcrppart}/auxfiles /home/tc/custom-module 
  fi
  
  local_cache="/mnt/${tcrppart}/auxfiles"
  
  #if [ -d ${local_cache/extractor /} ] && [ -f ${local_cache}/extractor/scemd ]; then
  #    echo "Found extractor locally cached"
  #else
  #    cecho g "making directory  /mnt/${tcrppart}/auxfiles/extractor"  
  #    mkdir /mnt/${tcrppart}/auxfiles/extractor
  #    sudo curl --insecure -L --progress-bar "https://$gitdomain/PeterSuh-Q3/tinycore-redpill/master/extractor.gz" --output /mnt/${tcrppart}/auxfiles/extractor/extractor.gz
  #    sudo tar -zxvf /mnt/${tcrppart}/auxfiles/extractor/extractor.gz -C /mnt/${tcrppart}/auxfiles/extractor
  #fi
  
  echo
  cecho y "TARGET_PLATFORM is $TARGET_PLATFORM"
  cecho r "ORIGIN_PLATFORM is $ORIGIN_PLATFORM"
  cecho c "TARGET_VERSION is $TARGET_VERSION"
  cecho p "TARGET_REVISION is $TARGET_REVISION"
  cecho y "SUVP is $SUVP"
  cecho g "SYNOMODEL is $SYNOMODEL"  
  cecho c "KERNEL VERSION is $KVER"  

  [[ -d /sys/firmware/efi && "${ORIGIN_PLATFORM}" = "bromolow" ]] && msgalert "${ORIGIN_PLATFORM} does not working in UEFI boot mode, Aborting the loader build!!!\n" && readanswer && exit 0
  
  st "buildstatus" "Building started" "Model :$MODEL-$TARGET_VERSION-$TARGET_REVISION"
  
  #fullupgrade="Y"
  
  cecho y "If fullupgrade is required, please handle it separately."
  
  cecho g "Downloading Peter Suh's custom configuration files.................."
  
  writeConfigKey "general" "kver" "${KVER}"
  
  DMPM="$(jq -r -e '.general.devmod' $userconfigfile)"
  if [ "${DMPM}" = "null" ]; then
      DMPM="DDSML"
      writeConfigKey "general" "devmod" "${DMPM}"
  fi
  cecho y "Device Module Processing Method is ${DMPM}"

  MDLNAME="$(jq -r -e '.general.modulename' $userconfigfile)"
  if [ "${MDLNAME}" = "null" ]; then
      MDLNAME="all-modules"
      writeConfigKey "general" "modulename" "${MDLNAME}"
  fi
  cecho y "The selected integrated module pack is ${MDLNAME}"
  
  [ $(cat /home/tc/redpill-load/bundled-exts.json | jq 'has("mac-spoof")') = true ] && spoof=true || spoof=false
  [ $(cat /home/tc/redpill-load/bundled-exts.json | jq 'has("nvmesystem")') = true ] && nvmes=true || nvmes=false
  [ $(cat /home/tc/redpill-load/bundled-exts.json | jq 'has("dbgutils")') = true ] && dbgutils=true || dbgutils=false
  [ $(cat /home/tc/redpill-load/bundled-exts.json | jq 'has("sortnetif")') = true ] && sortnetif=true || sortnetif=false
  
  echo  "download original bundled-exts.json file..."
  curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/bundled-exts.json -o /home/tc/redpill-load/bundled-exts.json
  
  if [ "${DMPM}" = "DDSML" ]; then
      jsonfile=$(jq 'del(.eudev)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  elif [ "${DMPM}" = "EUDEV" ]; then
      jsonfile=$(jq 'del(.ddsml)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  elif [ "${DMPM}" = "DDSML+EUDEV" ]; then
      cecho p "It uses both ddsml and eudev from /home/tc/redpill-load/bundled-exts.json file"
  else
      cecho p "Device Module Processing Method is Undefined, Program Exit!!!!!!!!"
      exit 0
  fi

  #if [ "$MACHINE" = "VIRTUAL" ]; then
  #    jsonfile=$(jq 'del(.acpid)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  #fi
  
  [ "$spoof" = true ] && add-addons "mac-spoof" 
  [ "$nvmes" = true ] && add-addons "nvmesystem" 
  [ "$dbgutils" = true ] && add-addons "dbgutils" 
  [ "$sortnetif" = true ] && add-addons "sortnetif" 

  [ "${offline}" = "NO" ] && curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/models.json

  if [ "${MDLNAME}" = "all-modules" ]; then
      sed -i "s/rr-modules/all-modules/g" models.json
  elif [ "${MDLNAME}" = "rr-modules" ]; then
      sed -i "s/all-modules/rr-modules/g" models.json
  fi  
  
  echo
  if [ "$jot" = "N" ]; then    
  cecho y "This is TCRP friend mode"
  else    
  cecho y "This is TCRP original jot mode"
  fi
  
  if [ -f /home/tc/custom-module/${TARGET_PLATFORM}.dts ]; then
      sed -i "s/dtbpatch/redpill-dtb-static/g" models.json
  fi
  
  if [ "$postupdate" = "Y" ]; then
      cecho y "Postupdate in progress..."  
      sudo rploader postupdate ${TARGET_PLATFORM}-7.1.1-${TARGET_REVISION}
  
      echo                                                                                                                                        
      cecho y "Backup in progress..."
      echo                                                                                                                                        
      echo "y"|rploader backup    
      exit 0
  fi
  
  if [ "$userdts" = "Y" ]; then
      
      cecho y "user-define dts file make in progress..."  
      echo
      
      cecho g "copy and paste user dts contents here, press any key to continue..."      
      read answer
      sudo vi /home/tc/custom-module/${TARGET_PLATFORM}.dts
  
      cecho p "press any key to continue..."
      read answer
  
      echo                                                                                                                                        
      cecho y "Backup in progress..."
      echo                                                                                                                                        
      echo "y"|rploader backup    
      exit 0
  fi
  
  echo
  
  if [ "$noconfig" = "Y" ]; then                            
      cecho r "SN Gen/Mac Gen/Vid/Pid/SataPortMap detection skipped!!"
      checkmachine
      if [ "$MACHINE" = "VIRTUAL" ] && [ "${prevent_init}" = "N" ]; then
          cecho p "Sataportmap,DiskIdxMap to blank for VIRTUAL MACHINE"
          json="$(jq --arg var "" '.extra_cmdline.SataPortMap = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
          json="$(jq --arg var "" '.extra_cmdline.DiskIdxMap = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json        
          cat user_config.json
      fi
  else 
      cecho c "Before changing user_config.json" 
      cat user_config.json
      echo "y"|rploader identifyusb
  
      if [ "$ORIGIN_PLATFORM" = "v1000" ]||[ "$ORIGIN_PLATFORM" = "r1000" ]||[ "$ORIGIN_PLATFORM" = "geminilake" ]; then
          cecho p "Device Tree based model does not need SataPortMap setting...."     
      else    
          rploader satamap    
      fi    
      cecho y "After changing user_config.json"     
      cat user_config.json        
  fi
  
  echo
  echo
  DN_MODEL="$(echo $MODEL | sed 's/+/%2B/g')"
  echo "DN_MODEL is $DN_MODEL"
  
  cecho p "DSM PAT file pre-downloading in progress..."
  URL=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.url) | .[0]" "${configfile}")
  cecho y "$URL"
  patfile="/mnt/${tcrppart}/auxfiles/${SYNOMODEL}.pat"                                         
  
  if [ "$TARGET_VERSION" = "7.2" ]; then
      TARGET_VERSION="7.2.0"
  fi
  
  #if [ "$ORIGIN_PLATFORM" = "apollolake" ]||[ "$ORIGIN_PLATFORM" = "geminilake" ]; then
  #   jsonfile=$(jq 'del(.drivedatabase)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  #   sudo rm -rf /home/tc/redpill-load/custom/extensions/drivedatabase
  #   jsonfile=$(jq 'del(.reboottotcrp)' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
  #   sudo rm -rf /home/tc/redpill-load/custom/extensions/reboottotcrp
  #fi   
          
  if [ -f ${patfile} ]; then
      cecho r "Found locally cached pat file ${SYNOMODEL}.pat in /mnt/${tcrppart}/auxfiles"
      cecho b "Downloadng Skipped!!!"
  st "download pat" "Found pat    " "Found ${SYNOMODEL}.pat"
  else
  
  st "download pat" "Downloading pat  " "${SYNOMODEL}.pat"        
  
      #if [ 1 = 0 ]; then
      #  STATUS=`curl --insecure -w "%{http_code}" -L "${URL}" -o ${patfile} --progress-bar`
      #  if [ $? -ne 0 -o ${STATUS} -ne 200 ]; then
      #    echo  "Check internet or cache disk space"
      #    exit 99
      #  fi
      #else
      echo  "download original pats.json file..."
      curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/redpill-load/master/config/pats.json -o /home/tc/redpill-load/config/pats.json
      echo "offline = ${offline}"
        [ "${offline}" = "NO" ] && _pat_process    
      #fi
  
      os_md5=$(md5sum ${patfile} | awk '{print $1}')                                
      cecho y "Pat file md5sum is : $os_md5"                                       
       
      verifyid=$(jq -e -r ".\"${MODEL}\" | to_entries | map(select(.key | startswith(\"${BUILD}\"))) | map(.value.sum) | .[0]" "${configfile}")
      cecho p "verifyid md5sum is : $verifyid"                                        
  
      if [ "$os_md5" = "$verifyid" ]; then                                            
          cecho y "pat file md5sum is OK ! "                                           
      else                                                                                
          cecho y "os md5sum verify FAILED, check ${patfile} "
          exit 99                                                                         
      fi
  fi
  
  echo
  cecho g "Loader Building in progress..."
  echo
  
  if [ "$MODEL" = "SA6400" ] && [ "${BUS}" = "usb" ]; then
      cecho g "Remove Exts for SA6400 (thethorgroup.boot-wait) ..."
      jsonfile=$(jq 'del(.["thethorgroup.boot-wait"])' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
      sudo rm -rf /home/tc/redpill-load/custom/extensions/thethorgroup.boot-wait
  
      cecho g "Remove Exts for SA6400 (automount) ..."
      jsonfile=$(jq 'del(.["automount"])' /home/tc/redpill-load/bundled-exts.json) && echo $jsonfile | jq . > /home/tc/redpill-load/bundled-exts.json
      sudo rm -rf /home/tc/redpill-load/custom/extensions/automount
  fi
  
  if [ "$jot" = "N" ]; then
      echo "n"|rploader build ${TARGET_PLATFORM}-${TARGET_VERSION}-${TARGET_REVISION} withfriend
  else
      echo "n"|rploader build ${TARGET_PLATFORM}-${TARGET_VERSION}-${TARGET_REVISION} static
  fi
echo "errorcode = $?"
  if [ $? -ne 0 ]; then
      cecho r "An error occurred while building the loader!!! Clean the redpill-load directory!!! "
      readanswer
      echo "OK, keep going..."
      rploader clean
  else
      [ "${BUS}" = "block" ] && exit 0
      [ "$MACHINE" != "VIRTUAL" ] && sleep 2
      echo "y"|rploader backup
  fi
#[ "$FRKRNL" = "YES" ] && readanswer  
}

if [ $# -gt 1 ]; then
    case $1 in
    
    my) 
        my "$2" "$3" "$4"
        ;;
    update)
        upgrademan "$2"
        ;;
    autoupdate)
        changeautoupdate "$2"
        ;;
    *)
        ;;
    esac    
fi
