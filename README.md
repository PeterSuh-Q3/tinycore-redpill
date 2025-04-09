# M Shell for tinycore-redpill

<a href="https://github.com/PeterSuh-Q3/tinycore-redpill/releases"><img src="https://img.shields.io/github/release/PeterSuh-Q3/tinycore-redpill.svg"></a>
<a href="https://hits.seeyoufarm.com"><img src="https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FPeterSuh-Q3%2Ftinycore-redpill&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false"/></a>
[![](https://img.shields.io/static/v1?label=Sponsor&message=%E2%9D%A4&logo=GitHub&color=%23fe8e86)](https://github.com/sponsors/PeterSuh-Q3)
<!-- [![committers.top badge](https://user-badge.committers.top/south_korea/PeterSuh-Q3.svg)](https://user-badge.committers.top/south_korea/PeterSuh-Q3) -->

https://paypal.me/PeterSuhQ3

-------------------------------------------------------------------------------

 - GitHub ACTIONS-COOL Loader Auto Build Feature Distribution (Using Issues)

1. You must have a GitHub account.

https://github.com/

Create an account with Sign Up and then log in with Sign In.

2. If you write an issue in this issue, the loader will be automatically built based on the model in the content you wrote.

https://github.com/PeterSuh-Q3/tinycore-redpill/issues

This is using the GitHub ACTIONS-COOL build bot.

![21e6b8bb01a0f49b976a6f175173a8b1](https://github.com/user-attachments/assets/f0385210-792f-4a82-b118-254926dbe0b3)

3. The title of the issue (the word custom must be included in the title.)

custom DS920+

The content of the main text is

{"model":"DS920+","version":"7.2.2-72806"}

Or

If you have a full-size serial and Mac address, please enter it in the following format. (Mac addresses are supported up to 4, mac4 only.)

{"model":"DS920+","version":"7.2.2-72806","mac1":"112233445566","mac2":"77889900aabb","sn":"1111222233333"}

If the Mac address and serial are omitted, they will be randomly generated.

You must write it in the form of a JSON body like this.

You can change the model and version, but if you make even the slightest mistake in spelling, the build will not be done properly.

![a09f1c3d82f63c2cf7dfd917c0b694b4](https://github.com/user-attachments/assets/64f09a2f-2c57-4e3a-bd19-5e3dbfae3fe9)

![dc286e5ddbfb72f5fb42345de1c99ea3](https://github.com/user-attachments/assets/c53d2c1c-1329-42d1-bcd4-1d4f787a2d1f)

![40931b574eb514bb95cc73b8b573a282](https://github.com/user-attachments/assets/c9a1fd02-16b6-47ff-8efb-82e9a61f5db0)


4. Save the issue

If you go to the Actions side, you will see an orange icon and the loader build will proceed.

https://github.com/PeterSuh-Q3/tinycore-redpill/actions

Workflow runs · PeterSuh-Q3/tinycore-redpill
github.com
Contribute to PeterSuh-Q3/tinycore-redpill development by creating an

If you want to see the details, you can click on the workflow in progress.

If the loader build is successful, the workflow will turn green.

If you select Summary,

The artifact result, which is the loader file generated at the very bottom, is saved in the form of a zip file.

![913c47b901d2e77763781e122247ccf3](https://github.com/user-attachments/assets/476896a6-7216-4972-9166-94eedb8b4b1b)

In this MshellImage-*.zip, the img file and vmdk file are each recompressed in tgz format.

The core content of this function is

Originally, you burn the official img of the TCRP-mshell loader to USB,

Enter ./menu.sh, select the model, version, serial, MAC address, etc., and go through manual build to complete the loader,

but this function is a function that allows you to receive an already completed loader from GitHub, bake it, and use it.

Since the Grub boot menu is created in the same way as when you manually build,

you can also build the loader created in this way by entering the manual build menu again.

--------------------------------------------------------------------


![스크린샷 2023-10-28 오전 9 13 45](https://github.com/PeterSuh-Q3/tinycore-redpill/assets/85427533/f0a293de-0765-43d1-b75c-89271b417124)


### Please note that minimum recommended memory size for configuring the loader is 4GB


# Instructions 

A typical build process starts with:

1. Burn images

    A. To burn physical gunzip and img files to a USB stick
    
    B. For virtual gunzip use the provided vmdk file
    
2. Boot Tinycore

3. Loader Building

<img width="1021" alt="스크린샷 2023-03-01 오후 8 29 11" src="https://user-images.githubusercontent.com/85427533/222127202-64d8ec9b-118d-42d7-b2a7-048098836c1d.png">


        A. Choose one of the Synology models.


<img width="507" alt="스크린샷 2023-02-24 오후 6 32 42" src="https://user-images.githubusercontent.com/85427533/221143853-02cd5136-98be-422a-94f2-44a8d39cd8d7.png">


        B. Create a virtual serial number or enter a prepared serial number.


<img width="480" alt="스크린샷 2023-02-24 오후 6 58 31" src="https://user-images.githubusercontent.com/85427533/221150226-bb4af0cd-068e-4fca-b726-475016a0183e.png">


        C. Select the real mac address of the nic or create a virtual mac address or 
           input the prepared mac address. 
           (If there are 2 nics, you can enter up to the 2nd mac address)
    
    
<img width="492" alt="스크린샷 2023-02-24 오후 7 02 21" src="https://user-images.githubusercontent.com/85427533/221150320-2421f744-d5b5-4fe8-8e99-247919afa8e7.png">
    
    
        D. Build the loader.

6. Reboot

< Version History >

    1.0.1.1 Fix monitor fuction about ethernet infomation
    1.0.1.2 Fix for SA6400
    1.0.2.0 Remove restrictions on use of DT-based models when using HBA (apply mpt3sas blacklist instead)
    1.0.2.1 Changed extension file organization method
    1.0.2.2 Recycle initrd-dsm instead of custom.gz (extract /exts), The priority starts from custom.gz
    1.0.2.3 Added RedPill bootloader hard disk porting function
    1.0.2.4 Added NVMe bootloader support
    ...
    1.0.5.0 Improved internet check function in menu.sh
    ...
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
    1.2.1.6 DS3615xs(bromolow) support again, LEGACY boot mode must be used!
    1.2.1.7 SynoDisk with Bootloader Injection Supports 2.4GB /dev/md0 size (before dsm 7.1.1)
    1.2.1.8 Modify the method of checking Internet connection in menu.sh
    1.2.1.9 Fixed to keep graphic console screen even in Jot Mode/Legacy Boot environment (use gfxpayload=keep)
    1.2.2.0 Activate Tinycore TTYD web console (port 7681, login use tc/P@ssw0rd)
    1.2.2.1 TTYD web console baremetal headless support fix
    1.2.2.2 Added to change the default value of the Grub boot entry (in the submenu)
    1.2.2.3 Added a feature to immediately reflect changes to user_config.json (no need for loader build)

