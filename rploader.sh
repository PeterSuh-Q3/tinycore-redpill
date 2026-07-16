#!/bin/bash
#
# Author : pocopico 
# Date : 221115
# Version : 0.9.4.0-1
#
#
##### INCLUDES ######################################################################################
source /home/tc/functions.h
#####################################################################################################

rploaderver="1.0.2.9"
build="alpine-redpill"
redpillmake="prod"

rploaderfile="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/rploader.sh"
rploaderrepo="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/"

redpillextension="https://raw.githubusercontent.com/PeterSuh-Q3/rp-ext/master/redpill${redpillmake}/rpext-index.json"
modextention="https://raw.githubusercontent.com/PeterSuh-Q3/rp-ext/master/rpext-index.json"
modalias4="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/modules.alias.4.json.gz"
modalias3="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/modules.alias.3.json.gz"
dtcbin="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/tools/dtc"
dtsfiles="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build"
timezone="UTC"
ntpserver="pool.ntp.org"
userconfigfile="/home/tc/user_config.json"

fullupdatefiles="custom_config.json custom_config_jun.json global_config.json modules.alias.3.json.gz modules.alias.4.json.gz rpext-index.json user_config.json rploader.sh"

HOMEPATH="/home/tc"
TOOLSPATH="https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/tools/"
TOOLS="bspatch bzImage-template-v4.gz bzImage-template-v5.gz bzImage-to-vmlinux.sh calc_run_size.sh crc32 dtc kexec ramdisk-patch.sh vmlinux-to-bzImage.sh xxd zimage-patch.sh kpatch grub-editenv pigz modprobe"

# END Do not modify after this line
######################################################################################################

# extract nano  LD_LIBRARY_PATH=/home/tc/archive/lib /home/tc/archive/synoarchive.nano -xvf ../synology_geminilake_dva1622.pat

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
    --------------------------------------------------------------------------------------
EOF

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
function st() {
echo -e "[$(date '+%T.%3N')]:-------------------------------------------------------------" >> /home/tc/buildstatus
echo -e "\e[35m$1\e[0m	\e[36m$2\e[0m	$3" >> /home/tc/buildstatus
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

function setnetwork() {

    if [ -f /opt/eth*.sh ] && [ "$(grep dhcp /opt/eth*.sh | wc -l)" -eq 0 ]; then

        ipset="static"
        ipgw="$(route | grep default | head -1 | awk '{print $2}')"
        ipprefix="$(grep ifconfig /opt/eth*.sh | head -1 | awk '{print "ipcalc -p " $3 " " $5 }' | sh - | awk -F= '{print $2}')"
        myip="$(grep ifconfig /opt/eth*.sh | head -1 | awk '{print $3 }')"
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

function httpconf() {

    tce-load -iw lighttpd 2>&1 >/dev/null

    cat >/home/tc/lighttpd.conf <<EOF
server.document-root = "/home/tc/html"
server.modules  = ( "mod_cgi" , "mod_alias" )
server.errorlog             = "/home/tc/html/error.log"
server.pid-file             = "/home/tc/html/lighttpd.pid"
server.username             = "tc"
server.groupname            = "staff"
server.port                 = 80
alias.url       = ( "/rploader/" => "/home/tc/html/" )
cgi.assign = ( ".sh" => "/usr/local/bin/bash" )
index-file.names           = ( "index.html","index.htm", "index.sh" )

EOF

    sudo lighttpd -f /home/tc/lighttpd.conf

    [ $(sudo netstat -an 2>/dev/null | grep LISTEN | grep ":80" 2>/dev/null | wc -l) -eq 1 ] && echo "Server started succesfully"

    # Add entry to bootlocal and backup
    # cat /opt/bootlocal.sh

}

function getgrubconf() {

#    tcrpdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
    grubdisk="${tcrpdisk}1"

    echo "Mounting bootloader disk to get grub contents"
    sudo mount /dev/$grubdisk

    if [ $(df | grep -i $grubdisk | wc -l) -gt 0 ]; then
        echo -n "Mounted succesfully : $(df -h | grep $grubdisk)"
        [ -f /mnt/$grubdisk/boot/grub/grub.cfg ] && [ $(cat /mnt/$grubdisk/boot/grub/grub.cfg | wc -l) -gt 0 ] && echo "  -> Grub cfg is accessible and readable"
    else
        echo "Couldnt mount device : $grubdisk "
        exit 99
    fi

    echo "Getting known loader grub variables"

    grep pid /mnt/$grubdisk/boot/grub/grub.cfg >/tmp/grub.vars

    while IFS=" " read -r -a line; do
        printf "%s\n" "${line[@]}"
    done </tmp/grub.vars | egrep -i "sataportmap|sn|pid|vid|mac|hddhotplug|diskidxmap|netif_num" | sort | uniq >/tmp/known.vars

    if [ -f /tmp/known.vars ]; then
        echo "Sourcing vars, found in grub : "
        . /tmp/known.vars
        rows="%-15s| %-15s | %-10s | %-10s | %-10s | %-15s | %-15s %c\n"
        printf "$rows" Serial Mac Netif_num PID VID SataPortMap DiskIdxMap
        printf "$rows" $sn $mac1 $netif_num $pid $vid $SataPortMap $DiskIdxMap

        echo "Checking user config against grub vars"

        for var in pid vid sn mac1 SataPortMap DiskIdxMap; do
            if [ $(jq -r .extra_cmdline.$var user_config.json) == "${!var}" ]; then
                echo "Grub var $var = ${!var} Matches your user_config.json"
            else
                echo "Grub var $var = ${!var} does not match your user_config.json variable which is set to : $(jq -r .extra_cmdline.$var user_config.json) "
                echo "Should we populate user_config.json with these variables ? [Yy/Nn] "
                readanswer
                if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
                    json="$(jq --arg newvar "${!var}" '.extra_cmdline.'$var'= $newvar' user_config.json)" && echo -E "${json}" | jq . >user_config.json
                else
                    echo "OK, you can edit yourself later"
                fi
            fi
        done

    else

        echo "Could not read variables"
    fi

}

function getip() {
    ethdevs=$(ls /sys/class/net/ | grep eth || true)
    for eth in $ethdevs; do 
        DRIVER=$(ls -ld /sys/class/net/${eth}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
        IP="$(ifconfig ${eth} | grep inet | awk '{print $2}' | awk -F \: '{print $2}')"
        HWADDR="$(ifconfig ${eth} | grep HWaddr | awk '{print $5}')"
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
        echo "IP Address : $(msgnormal "${IP}"), ${HWADDR} : ${eth} (${DRIVER})"        
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

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
    mount /dev/${loaderdisk}1
    mount /dev/${loaderdisk}2

    while [ -z "$GATEWAY_INTERFACE" ]; do
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
            if [ $vserver -gt 0 ]; then echo "VM"; else echo "Physical"; fi
        ) 
        msgnormal "CPU Threads:\t\t"$(lscpu |grep CPU\(s\): | awk '{print $2}')
        echo -e "Current Date Time:\t"$(date)
        #msgnormal "System Main IP:\t\t"$(ifconfig | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | awk -F \: '{print $2}' | tr '\n' ',' | sed 's#,$##')
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

function syntaxcheck() {

    if [ $# -lt 2 ] && [ "$1" == "download" ] || [ "$1" == "build" ] || [ "$1" == "ext" ] || [ "$1" == "restoresession" ] || [ "$1" == "listmods" ] || [ "$1" == "serialgen" ] || [ "$1" == "patchdtc" ] || [ "$1" == "postupdate" ]; then

        echo "Error : Number of arguments : $#, options $@ "
        case $1 in

        download)
            echo "Syntax error, You have to specify one of the existing platforms" && getPlatforms
            ;;

        build)
            echo "Syntax error, You have to specify one of the existing platforms" && getPlatforms
            ;;

        ext)
            echo "Syntax error, You have to specify one of the existing platforms, the action and the extension URL"
            echo "example:"
            echo "rploader.sh ext apollolake-7.0.1-42218 add https://github.com/PeterSuh-Q3/rp-ext/raw/master/e1000/rpext-index.json"
            echo "or for auto detect use"
            echo "rploader.sh ext apollolake-7.0.1-42218 auto"
            ;;

        restoresession)
            echo "Syntax error, You have to specify one of the existing platforms" && getPlatforms
            ;;

        listmods)
            echo "Syntax error, You have to specify one of the existing platforms" && getPlatforms
            ;;

        serialgen)
            echo "Syntax error, You have to specify one of the existing models"
            echo "DS3615xs DS3617xs DS916+ DS918+ DS1019+ DS920+ DS3622xs+ FS6400 DVA3219 DVA3221 DS1621+ DS1621xs+ DS2422+ DS1520+ FS2500 RS4021xs+ RS3618xs RS3413xs+ DS923+"
            ;;

        patchdtc)
            echo "Syntax error, You have to specify one of the existing platforms" && getPlatforms
            ;;

        postupdate)
            echo "Syntax error, You have to specify one of the existing platforms" && getPlatforms
            ;;

        *)
            echo "Syntax error, not valid arguments or not enough options"
            showhelp
            ;;

        esac

        exit 99

    else
        return
    fi

}

function version() {

    shift 1
    echo $rploaderver

    [ "$1" == "history" ] && history

}

function checkmachine() {

    if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
        MACHINE="VIRTUAL"
        HYPERVISOR=$(dmesg | grep -i "Hypervisor detected" | awk '{print $5}')
        echo "Machine is $MACHINE Hypervisor=$HYPERVISOR"
    fi

    if [ $(lscpu |grep Intel |wc -l) -gt 0 ]; then
        CPU="INTEL"
    else	
        CPU="AMD"    
    fi

}

function savesession() {

    lastsessiondir="/mnt/${tcrppart}/lastsession"

    echo -n "Saving user session for future use. "

    [ ! -d ${lastsessiondir} ] && sudo mkdir ${lastsessiondir}

    echo -n "Saving current extensions "

    cat /home/tc/redpill-load/custom/extensions/*/*json | jq '.url' >${lastsessiondir}/extensions.list

    [ -f ${lastsessiondir}/extensions.list ] && echo " -> OK !"

    echo -n "Saving current user_config.json "

    cp /home/tc/user_config.json ${lastsessiondir}/user_config.json

    [ -f ${lastsessiondir}/user_config.json ] && echo " -> OK !"

}

function restoresession() {

    lastsessiondir="/mnt/${tcrppart}/lastsession"

    if [ -d $lastsessiondir ]; then

        echo -n "Found last user session :  , restore session ? [yY/nN] : "
        readanswer

        if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then

            if [ -d $lastsessiondir ] && [ -f ${lastsessiondir}/extensions.list ]; then
                for extension in $(cat ${lastsessiondir}/extensions.list); do
                    echo "Adding extension ${extension} "
                    cd /home/tc/redpill-load/ && ./ext-manager.sh add "$(echo $extension | sed -s 's/"//g' | sed -s 's/,//g')"
                done
            fi
            if [ -d $lastsessiondir ] && [ -f ${lastsessiondir}/user_config.json ]; then
                echo "Copying last user_config.json"
                cp ${lastsessiondir}/user_config.json /home/tc
            fi

        fi
    else
        echo "OK, we will not restore last session"
    fi
}

function downloadtools() {

  echo "Downloading Kernel Patch tools"

  [ ! -d ${HOMEPATH}/tools ] && mkdir -p ${HOMEPATH}/tools
  cd ${HOMEPATH}/tools
  for FILE in $TOOLS; do
    curl -skLO "$TOOLSPATH/${FILE}"
    chmod +x $FILE
  done

st "Patch Tools" "Download tools  " "Kernel Patch Tools downloaded"
  cd ${HOMEPATH}

}

function copyextractor() {
#m shell mofified
    local_cache="/mnt/${tcrppart}/auxfiles"

    echo "making directory ${local_cache}"
    [ ! -d ${local_cache} ] && mkdir ${local_cache}

    echo "making directory ${local_cache}/extractor"
    [ ! -d ${local_cache}/extractor ] && mkdir ${local_cache}/extractor
    [ ! -f /home/tc/extractor.gz ] && sudo curl -kL -# "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/extractor.gz" -o /home/tc/extractor.gz
    sudo tar -zxvf /home/tc/extractor.gz -C ${local_cache}/extractor

    echo "Copying required libraries to local lib directory"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/lib* /lib/
    echo "Linking lib to lib64"
    [ ! -h /lib64 ] && sudo ln -s /lib /lib64
    echo "Copying executable"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/scemd /bin/syno_extract_system_patch
    echo "pigz copy for multithreaded compression"
    sudo cp /mnt/${tcrppart}/auxfiles/extractor/pigz /usr/local/bin/pigz

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

    msgnormal "Checking if tool is accessible"
    if [ -d ${local_cache/extractor /} ] && [ -f ${local_cache}/extractor/scemd ]; then    
        /bin/syno_extract_system_patch 2>&1 >/dev/null
    else
        /bin/syno_extract_system_patch
    fi
    if [ $? -eq 255 ]; then echo "Executed succesfully"; else echo "Cound not execute"; fi    

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
            mv -f ${patfile} /home/tc/redpill-load/cache/
        elif [ ${isencrypted} = "yes" ]; then
            [ -f /home/tc/redpill-load/cache/${SYNOMODEL}.pat ] && testarchive /home/tc/redpill-load/cache/${SYNOMODEL}.pat
            if [ -f /home/tc/redpill-load/cache/${SYNOMODEL}.pat ] && [ ${isencrypted} = "no" ]; then
                echo "Decrypted file is already cached in :  /home/tc/redpill-load/cache/${SYNOMODEL}.pat"
            else
                echo "Copying encrypted pat file : ${patfile} to ${temp_dsmpat_folder}"
                mv -f ${patfile} ${temp_dsmpat_folder}/${SYNOMODEL}.pat
                echo "Extracting encrypted pat file : ${temp_dsmpat_folder}/${SYNOMODEL}.pat to ${temp_pat_folder}"
                sudo /bin/syno_extract_system_patch ${temp_dsmpat_folder}/${SYNOMODEL}.pat ${temp_pat_folder} || echo "extract latest pat"
                echo "Decrypting pat file ${SYNOMODEL}.pat to /home/tc/redpill-load/cache folder (multithreaded comporession)"
                mkdir -p /home/tc/redpill-load/cache/
                thread=$(lscpu |grep CPU\(s\): | awk '{print $2}')
                cd ${temp_pat_folder} && tar -cf - ./ | pigz -p $thread > ${temp_dsmpat_folder}/${SYNOMODEL}.pat && cp -f ${temp_dsmpat_folder}/${SYNOMODEL}.pat /home/tc/redpill-load/cache/${SYNOMODEL}.pat                
            fi
            patfile="/home/tc/redpill-load/cache/${SYNOMODEL}.pat"            

        else
            echo "Something went wrong, please check cache files"
            exit 99
        fi

        cd /home/tc/redpill-load/cache
st "patextraction" "Pat file extracted" "VERSION:${TARGET_VERSION}-${TARGET_REVISION}"        
        tar xvf /home/tc/redpill-load/cache/${SYNOMODEL}.pat ./VERSION && . ./VERSION && cat ./VERSION && rm ./VERSION
        os_sha256=$(sha256sum /home/tc/redpill-load/cache/${SYNOMODEL}.pat | awk '{print $1}')
        msgnormal "Pat file  sha256sum is : $os_sha256"

        echo -n "Checking config file existence -> "
        if [ -f "/home/tc/redpill-load/config/$MODEL/${major}.${minor}.${micro}-${buildnumber}/config.json" ]; then
            echo "OK"
            configfile="/home/tc/redpill-load/config/$MODEL/${major}.${minor}.${micro}-${buildnumber}/config.json"
        else
            echo "No config file found, The download may be corrupted or may not be run the original repo. Please re-download from original repo."
            exit 99
        fi

        msgnormal "Editing config file !!!!!"
        sed -i "/\"os\": {/!b;n;n;n;c\"sha256\": \"$os_sha256\"" ${configfile}
        echo -n "Verifying config file -> "
        verifyid="$(cat ${configfile} | jq -r -e '.os .sha256')"

        if [ "$os_sha256" == "$verifyid" ]; then
            echo "OK ! "
        else
            echo "config file, os sha256 verify FAILED, check ${configfile} "
            exit 99
        fi

        msgnormal "Clearing temp folders"
        sudo umount ${temp_pat_folder} && sudo rm -rf ${temp_pat_folder}
        sudo umount ${temp_dsmpat_folder} && sudo rm -rf ${temp_dsmpat_folder}        

        return

    else

        echo "Could not find pat file locally cached"
        configdir="/home/tc/redpill-load/config/${MODEL}/${TARGET_VERSION}-${TARGET_REVISION}"
        configfile="${configdir}/config.json"
        pat_url=$(cat ${configfile} | jq '.os .pat_url' | sed -s 's/"//g')
        echo -e "Configdir : $configdir \nConfigfile: $configfile \nPat URL : $pat_url"
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

function testarchive() {

    archive="$1"
    archiveheader="$(od -bc ${archive} | head -1 | awk '{print $3}')"

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
    *)
        echo "Could not determine if file ${archive} is encrypted or not, maybe corrupted"
        ls -ltr ${archive}
        echo ${archiveheader}
        exit 99
        ;;
    esac

}

function addrequiredexts() {

    echo "Processing add_extensions entries found on custom_config.json file : ${EXTENSIONS}"
    for extension in ${EXTENSIONS_SOURCE_URL}; do
        echo "Adding extension ${extension} "
        cd /home/tc/redpill-load/ && ./ext-manager.sh add "$(echo $extension | sed -s 's/"//g' | sed -s 's/,//g')"
        if [ $? -ne 0 ]; then
            echo "FAILED : Processing add_extensions failed check the output for any errors"
            ./rploader.sh clean
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
            ./rploader.sh clean
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

function installapache() {

    echo "Installing apache2 and php module"

    tce-load -iw apache2.4.tcz
    tce-load -iw apache2.4-doc.tcz
    tce-load -iw php-8.0-mod.tcz
    tce-load -iw libnghttp2.tcz
    #cd /usr/local/
    #sudo tar xvf /home/tc/tcrphtml/tc.apache.tar.gz etc/httpd/
    #apachectl start

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

function removefriend() {

    clear
#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"

    echo "------------------------------------------------------------------------------------------------------------"
    echo "You are not satisfied with TCRP friend."
    echo "Understandable, but you will not be able to perform automatic patching after updates."
    echo "you can still though use the postupdate process instead or just set the default option to SATA or USB as usual"
    echo "------------------------------------------------------------------------------------------------------------"

    echo -n "Do you still want to remove TCRP Friend, please answer [Yy/Nn]"
    readanswer

    if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then

        mount /dev/${loaderdisk}1 2>/dev/null
        mount /dev/${loaderdisk}2 2>/dev/null
        mount /dev/${loaderdisk}3 2>/dev/null

        echo "Removing TCRP Friend from ${loaderdisk}3 "
        [ -f /mnt/${loaderdisk}3/initrd-friend ] && sudo rm -rf /mnt/${loaderdisk}3/initrd-friend
        [ -f /mnt/${loaderdisk}3/bzImage-friend ] && sudo rm -rf /mnt/${loaderdisk}3/bzImage-friend
        echo "Removing initrd-dsm and zimage-dsm from ${loaderdisk}3 "
        [ ! "$(sha256sum /mnt/${loaderdisk}3/initrd-dsm | awk '{print $2}')" = "$(sha256sum /mnt/${loaderdisk}3/rd.gz | awk '{print $2}')" ] && cp /mnt/${loaderdisk}3/initrd-dsm /mnt/${loaderdisk}3/rd.gz
        [ -f /mnt/${loaderdisk}3/initrd-dsm ] && sudo rm -rf /mnt/${loaderdisk}3/initrd-dsm
        [ ! "$(sha256sum /mnt/${loaderdisk}3/zImage-dsm | awk '{print $2}')" = "$(sha256sum /mnt/${loaderdisk}1/zImage | awk '{print $2}')" ] && cp /mnt/${loaderdisk}3/zImage-dsm /mnt/${loaderdisk}1/zImage
        [ -f /mnt/${loaderdisk}3/zimage-dsm ] && sudo rm -rf /mnt/${loaderdisk}3/zimage-dsm
        echo "Removing TCRP Friend Grub entry "
        [ $(grep -i "Tiny Core Friend" /mnt/${loaderdisk}1/boot/grub/grub.cfg | wc -l) -eq 1 ] && sed -i "/Tiny Core Friend/,+9d" /mnt/${loaderdisk}1/boot/grub/grub.cfg

        if [ "$MACHINE" = "VIRTUAL" ]; then
            echo "Setting default boot entry to SATA"
            cd /home/tc/redpill-load/ && sudo sed -i "/set default=\"*\"/cset default=\"1\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg
        else
            echo "Setting default boot entry to USB"
            cd /home/tc/redpill-load/ && sudo sed -i "/set default=\"*\"/cset default=\"0\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg
        fi
    else
        echo "OK ! Wise choice !!! "
    fi

}

function bringfriend() {

    clear

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
    mount /dev/${loaderdisk}1 2>/dev/null
    mount /dev/${loaderdisk}2 2>/dev/null
    mount /dev/${loaderdisk}3 2>/dev/null

    if [ -f /mnt/${loaderdisk}3/lastsession/user_config.json ]; then
        cp /mnt/${loaderdisk}3/lastsession/user_config.json /home/tc/user_config.json
        getgrubconf
    else
        getgrubconf
    fi

    if [ -f /mnt/${loaderdisk}3/bzImage-friend ] && [ -f /mnt/${loaderdisk}3/initrd-friend ] && [ -f /mnt/${loaderdisk}3/zImage-dsm ] && [ -f /mnt/${loaderdisk}3/initrd-dsm ] && [ -f /mnt/${loaderdisk}3/user_config.json ] && [ $(grep -i "Tiny Core Friend" /mnt/${loaderdisk}1/boot/grub/grub.cfg | wc -l) -eq 1 ]; then
        echo "Your TCRP friend seems in place, do you want to re-run the process ?"
        readanswer
        if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then
            echo "OK re-running the TCRP Friend bring over process"
        else
            echo "Wise choice"
            exit 0
        fi
    fi

    echo "You are upgrading your system with TCRP friend."
    echo "Your system will still be able to boot using the USB/SATA options."
    echo "After bringing over TCRP Friend, The default boot option will be set TCRP Friend."
    echo "You will still have the option to move to SATA/USB but for automatic patching after an update,"
    echo "please leave the default to TCRR Friend"

    echo -n "If you agree with the above, please answer [Yy/Nn]"
    readanswer

    if [ "${answer}" = "Y" ] || [ "${answer}" = "y" ]; then

        if [ ! -f /mnt/${loaderdisk}3/initrd-friend ] || [ ! -f /mnt/${loaderdisk}3/bzImage-friend ]; then

            [ ! -f /home/tc/friend/initrd-friend ] && [ ! -f /home/tc/friend/bzImage-friend ] && bringoverfriend

            if [ -f /home/tc/friend/initrd-friend ] && [ -f /home/tc/friend/bzImage-friend ]; then

                cp /home/tc/friend/initrd-friend /mnt/${loaderdisk}3/
                cp /home/tc/friend/bzImage-friend /mnt/${loaderdisk}3/

            fi

        fi

        if [ -f /mnt/${loaderdisk}3/initrd-friend ] || [ -f /mnt/${loaderdisk}3/bzImage-friend ]; then

            [ $(grep -i "Tiny Core Friend" /mnt/${loaderdisk}1/boot/grub/grub.cfg | wc -l) -eq 1 ] || tcrpfriendentry | sudo tee --append /mnt/${loaderdisk}1/boot/grub/grub.cfg

            # Compining rd.gz and custom.gz

            echo "Compining rd.gz and custom.gz and copying zimage to ${loaderdisk}3 "

            [ ! -d /home/tc/rd.temp ] && mkdir /home/tc/rd.temp
            [ -d /home/tc/rd.temp ] && cd /home/tc/rd.temp
            if [ "$(od /mnt/${loaderdisk}3/rd.gz | head -1 | awk '{print $2}')" = "000135" ]; then
                RD_COMPRESSED="true"
            else
                RD_COMPRESSED="false"
            fi

            if [ "$RD_COMPRESSED" = "false" ]; then
                echo "Ramdisk in not compressed "
                cat /mnt/${loaderdisk}3/rd.gz | sudo cpio -idm 2>/dev/null >/dev/null
                cat /mnt/${loaderdisk}3/custom.gz | sudo cpio -idm 2>/dev/null >/dev/null
                sudo chmod +x /home/tc/rd.temp/usr/sbin/modprobe
                (cd /home/tc/rd.temp && sudo find . | sudo cpio -o -H newc -R root:root >/mnt/${loaderdisk}3/initrd-dsm) 2>&1 >/dev/null
            else
                unlzma -dc /mnt/${loaderdisk}3/rd.gz | sudo cpio -idm 2>/dev/null >/dev/null
                cat /mnt/${loaderdisk}3/custom.gz | sudo cpio -idm 2>/dev/null >/dev/null
                sudo chmod +x /home/tc/rd.temp/usr/sbin/modprobe
                (cd /home/tc/rd.temp && sudo find . | sudo cpio -o -H newc -R root:root | xz -9 --format=lzma >/mnt/${loaderdisk}3/initrd-dsm) 2>&1 >/dev/null
            fi

            . /home/tc/rd.temp/etc/VERSION

            MODEL="$(grep upnpmodelname /home/tc/rd.temp/etc/synoinfo.conf | awk -F= '{print $2}' | sed -e 's/"//g')"
            VERSION="${productversion}-${buildnumber}"

            cp -f /mnt/${loaderdisk}1/zImage /mnt/${loaderdisk}3/zImage-dsm

            updateuserconfig
            setnetwork

            updateuserconfigfield "general" "model" "$MODEL"
            updateuserconfigfield "general" "version" "${VERSION}"
            updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
            updateuserconfigfield "general" "redpillmake" "${redpillmake}"
            zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
            updateuserconfigfield "general" "zimghash" "$zimghash"
            rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
            updateuserconfigfield "general" "rdhash" "$rdhash"

            USB_LINE="$(grep -A 5 "USB," /mnt/${loaderdisk}1/boot/grub/grub.cfg | grep linux | cut -c 16-999)"
            SATA_LINE="$(grep -A 5 "SATA," /mnt/${loaderdisk}1/boot/grub/grub.cfg | grep linux | cut -c 16-999)"

            echo "Updated user_config with USB Command Line : $USB_LINE"
            json=$(jq --arg var "${USB_LINE}" '.general.usb_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile
            echo "Updated user_config with SATA Command Line : $SATA_LINE"
            json=$(jq --arg var "${SATA_LINE}" '.general.sata_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile

            cp $userconfigfile /mnt/${loaderdisk}3/

#m shell only start
            if [ "$WITHFRIEND" = "YES" ]; then
                sudo sed -i '61,80d' /mnt/${loaderdisk}1/boot/grub/grub.cfg
            fi    
#m shell only end

            echo "Setting default boot entry to TCRP Friend"
            sudo sed -i "/set default=\"*\"/cset default=\"1\"" /mnt/${loaderdisk}1/boot/grub/grub.cfg

            if [ ! -f /mnt/${loaderdisk}3/bzImage-friend ] || [ ! -f /mnt/${loaderdisk}3/initrd-friend ] || [ ! -f /mnt/${loaderdisk}3/zImage-dsm ] || [ ! -f /mnt/${loaderdisk}3/initrd-dsm ] || [ ! -f /mnt/${loaderdisk}3/user_config.json ] || [ ! $(grep -i "Tiny Core Friend" /mnt/${loaderdisk}1/boot/grub/grub.cfg | wc -l) -eq 1 ]; then
                echo "ERROR !!! Something went wrong, please re-run the process"
            fi
            echo "Cleaning up temp files"
            cd /home/tc
            sudo rm -rf /home/tc/friend
            sudo rm -rf /home/tc/rd.temp
            echo "Unmounting file systems"
            sudo umount /dev/${loaderdisk}1
            sudo umount /dev/${loaderdisk}2

        fi

    else

        echo "OK ! its your choice"
        sudo umount /dev/${loaderdisk}1
        sudo umount /dev/${loaderdisk}2
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
    updateuserconfigfield "general" "redpillmake" "${redpillmake}"
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

function getbspatch() {
    if [ ! -f /usr/local/bspatch ]; then

        #echo "bspatch does not exist, bringing over from repo"
        #curl -kL "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/tools/bspatch" -O
         
        echo "bspatch does not exist, copy from tools"
        chmod 777 ~/tools/bspatch
        sudo cp -vf ~/tools/bspatch /usr/local/bin/
    fi
}    

function postupdatev1() {

    echo "Mounting root to get the latest dsmroot patch in /.syno/patch "

    if [ ! -f /home/tc/redpill-load/user_config.json ]; then
        [ ! -h /home/tc/redpill-load/user_config.json ] && ln -s /home/tc/user_config.json /home/tc/redpill-load/user_config.json
    fi

    if [ $(mount | grep -i dsmroot | wc -l) -le 0 ]; then
        mountdsmroot
        [ $(mount | grep -i dsmroot | wc -l) -le 0 ] && echo "Failed to mount DSM root, cannot continue the postupdate process, returning" && return
    else
        echo "Already mounted"
    fi

    echo "Clearing last created loader "
    rm -f redpill-load/loader.img

    if [ ! -d "/lib64" ]; then
        echo "/lib64 does not exist, bringing linking /lib"
        [ ! -h /lib64 ] && ln -s /lib /lib64
    fi

    getbspatch

    echo "Checking available patch"

    if [ -d "/mnt/dsmroot/.syno/patch/" ]; then
        cd /mnt/dsmroot/.syno/patch/
        . ./VERSION
        . ./GRUB_VER
    else
        echo "Patch directory not found, please remember that you have to run update usign DSM manual upgrade first"
        echo "Postupdate is not possible, returning"
        return
    fi

    echo "Found Platform : ${PLATFORM}  Model : $MODEL Version : ${major}.${minor}.${micro}-${buildnumber} "

    echo -n "Do you want to use this for the loader ? [yY/nN] : "
    readanswer

    if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
        patfile="$(echo ${MODEL}_${buildnumber} | sed -e 's/\+/p/' | tr '[:upper:]' '[:lower:]').pat"
        echo "Creating pat file ${patfile} using contents of : $(pwd) "
        [ ! -d "/home/tc/redpill-load/cache" ] && mkdir /home/tc/redpill-load/cache/
        tar cfz /home/tc/redpill-load/cache/${patfile} *
        os_sha256=$(sha256sum /home/tc/redpill-load/cache/${patfile} | awk '{print $1}')
        echo "Created pat file with sha256sum : $os_sha256"
        cd /home/tc
    else
        echo "OK, see you later"
        return
    fi

    echo -n "Checking config file existence -> "
    if [ -f "/home/tc/redpill-load/config/$MODEL/${major}.${minor}.${micro}-${buildnumber}/config.json" ]; then
        echo "OK"
        configfile="/home/tc/redpill-load/config/$MODEL/${major}.${minor}.${micro}-${buildnumber}/config.json"
    else
        echo "No config file found, The download may be corrupted or may not be run the original repo. Please re-download from original repo."
        exit 99
    fi

    echo -n "Editing config file -> "
    sed -i "/\"os\": {/!b;n;n;n;c\"sha256\": \"$os_sha256\"" ${configfile}
    echo -n "Verifying config file -> "
    verifyid="$(cat ${configfile} | jq -r -e '.os .sha256')"

    if [ "$os_sha256" == "$verifyid" ]; then
        echo "OK ! "
    else
        echo "config file, os sha256 verify FAILED, check ${configfile} "
        exit 99
    fi

    removebundledexts

    cd /home/tc/redpill-load/

    addrequiredexts

    echo "Creating loader ${MODEL} ${major}.${minor}.${micro}-${buildnumber} ... "

    sudo ./build-loader.sh ${MODEL} ${major}.${minor}.${micro}-${buildnumber}

    loadername="redpill-${MODEL}_${major}.${minor}.${micro}-${buildnumber}"
    loaderimg=$(ls -ltr /home/tc/redpill-load/images/${loadername}* | tail -1 | awk '{print $9}')

    echo "Moving loader ${loaderimg} to loader.img "
    if [ -f "${loaderimg}" ]; then
        mv -f $loaderimg loader.img
    else
        echo "Failed to find loader ${loaderimg}, exiting"
        exit 99
    fi

    if [ ! -n "$(losetup -j loader.img | awk '{print $1}' | sed -e 's/://')" ]; then
        echo -n "Setting up loader img loop -> "
        sudo losetup -fP ./loader.img
        loopdev=$(losetup -j loader.img | awk '{print $1}' | sed -e 's/://')
        echo "$loopdev"
    else
        echo -n "Loop device exists, removing "
        losetup -d $(losetup -j loader.img | awk '{print $1}' | sed -e 's/://')
        echo -n "Setting up loader img loop -> "
        sudo losetup -fP ./loader.img
        loopdev=$(losetup -j loader.img | awk '{print $1}' | sed -e 's/://')
    fi

    echo -n "Mounting loop disks -> "

    [ ! -d /home/tc/redpill-load/localdiskp1 ] && mkdir /home/tc/redpill-load/localdiskp1
    [ ! -d /home/tc/redpill-load/localdiskp2 ] && mkdir /home/tc/redpill-load/localdiskp2

    [ ! -n "$(mount | grep -i localdiskp1)" ] && sudo mount ${loopdev}p1 localdiskp1
    [ ! -n "$(mount | grep -i localdiskp2)" ] && sudo mount ${loopdev}p2 localdiskp2

    [ -n "mount |grep -i localdiskp1" ] && [ -n "mount |grep -i localdiskp2" ] && echo "mounted succesfully"

    echo -n "Mounting loader disk -> "
#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"

    sudo mount /dev/${loaderdisk}1
    sudo mount /dev/${loaderdisk}2

    [ -n "mount |grep -i ${loaderdisk}1" ] && [ -n "mount |grep -i ${loaderdisk}2" ] && echo "mounted succesfully"

    echo -n "Copying loader files -> "
    echo -n "rd.gz : "
    cp -f /home/tc/redpill-load/localdiskp3/rd.gz /mnt/${loaderdisk}3/rd.gz
    cp -f /home/tc/redpill-load/localdiskp2/rd.gz /mnt/${loaderdisk}2/rd.gz
    [ "$(sha256sum /home/tc/redpill-load/localdiskp3/rd.gz | awk '{print $1}')" == "$(sha256sum /mnt/${loaderdisk}3/rd.gz | awk '{print $1}')" ] && [ "$(sha256sum /home/tc/redpill-load/localdiskp2/rd.gz | awk '{print $1}')" == "$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')" ] && echo -n "OK !!!"
    echo -n " zImage : "
    cp -f /home/tc/redpill-load/localdiskp1/zImage /mnt/${loaderdisk}1/zImage
    cp -f /home/tc/redpill-load/localdiskp2/zImage /mnt/${loaderdisk}2/zImage
    [ "$(sha256sum /home/tc/redpill-load/localdiskp1/zImage | awk '{print $1}')" == "$(sha256sum /mnt/${loaderdisk}1/zImage | awk '{print $1}')" ] && [ "$(sha256sum /home/tc/redpill-load/localdiskp2/zImage | awk '{print $1}')" == "$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')" ] && echo -n "OK !!!"
    echo -n " grub.cfg : "
    cp -f /home/tc/redpill-load/localdiskp1/boot/grub/grub.cfg /mnt/${loaderdisk}1/boot/grub/grub.cfg
    [ "$(sha256sum /home/tc/redpill-load/localdiskp1/boot/grub/grub.cfg | awk '{print $1}')" == "$(sha256sum /mnt/${loaderdisk}1/boot/grub/grub.cfg | awk '{print $1}')" ] && echo "OK !!!"
    echo "Creating tinycore entry"
    tinyentry | sudo tee --append /mnt/${loaderdisk}1/boot/grub/grub.cfg

    echo "Do you want to overwrite your custom.gz as well ? [yY/nN] : "
    readanswer

    if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
        echo "Copying custom.gz"
        cp -f /home/tc/redpill-load/localdiskp1/custom.gz /mnt/${loaderdisk}3/custom.gz
        [ "$(sha256sum /home/tc/redpill-load/localdiskp1/custom.gz | awk '{print $1}')" == "$(sha256sum /mnt/${loaderdisk}3/custom.gz | awk '{print $1}')" ] && echo "OK !!!"
    else
        echo "OK, you should be fine keeping your existing custom.gz"
    fi

    echo "Cleaning up... "
    echo -n "Unmounting loaderdisk ${loaderdisk} -> "
    sudo umount /dev/${loaderdisk}1 && sudo umount /dev/${loaderdisk}2
    [ -z $(mount | grep -i ${loaderdisk}1) ] && [ -z $(mount | grep -i ${loaderdisk}2) ] && echo "OK !!!"

    echo -n "Unmounting loader image ${loopdev} -> "
    sudo umount ${loopdev}p1 && sudo umount ${loopdev}p2
    [ -z $(mount | grep -i ${loopdev}p1) ] && [ -z $(mount | grep -i ${loopdev}p2) ] && echo "OK !!!"
    echo -n "Detaching loop loader image -> "
    sudo losetup -d ${loopdev}
    [ -z $(losetup | grep -i loader.img) ] && echo "OK !!!"

    if [ -f /home/tc/redpill-load/loader.img ]; then
        echo -n "Removing loader.img -> "
        sudo rm -rf /home/tc/redpill-load/loader.img
        [ ! -f /home/tc/redpill-load/loader.img ] && echo "OK !!!"
    fi

    echo "Unmounting dsmroot -> "
    [ ! -z "$(mount | grep -i dsmroot)" ] && sudo umount /mnt/dsmroot
    [ -z "$(mount | grep -i dsmroot)" ] && echo "OK !!! "

    echo "Done, closing"

}

function removebundledexts() {

    echo "Entering redpill-load directory to remove bundled exts"
    cd /home/tc/redpill-load/

    echo "Removing bundled exts directories"
    for bundledextdir in $(cat bundled-exts.json | jq 'keys[]' | sed -e 's/"//g'); do
        if [ -d /home/tc/redpill-load/custom/extensions/${bundledextdir} ]; then
            echo "Removing : ${bundledextdir}"
            sudo rm -rf /home/tc/redpill-load/custom/extensions/${bundledextdir}
        fi
    done

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

function downloadextractorv2() {

    [ ! -d /home/tc/patch-extractor/ ] && mkdir /home/tc/patch-extractor/

    cd /home/tc/patch-extractor/

    [ -f /home/tc/oldpat.tar.gz ] || curl -kL https://global.download.synology.com/download/DSM/release/7.0.1/42218/DSM_DS3622xs%2B_42218.pat -o /home/tc/oldpat.tar.gz

    tar xf ../oldpat.tar.gz hda1.tgz
    tar xf hda1.tgz usr/lib
    tar xf hda1.tgz usr/syno/sbin

    [ ! -d /home/tc/patch-extractor/lib/ ] && mkdir /home/tc/patch-extractor/lib/

    cp usr/lib/libicudata.so* /home/tc/patch-extractor/lib
    cp usr/lib/libicui18n.so* /home/tc/patch-extractor/lib
    cp usr/lib/libicuuc.so* /home/tc/patch-extractor/lib
    cp usr/lib/libjson.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_program_options.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_locale.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_filesystem.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_thread.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_coroutine.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_regex.so* /home/tc/patch-extractor/lib
    cp usr/lib/libapparmor.so* /home/tc/patch-extractor/lib
    cp usr/lib/libjson-c.so* /home/tc/patch-extractor/lib
    cp usr/lib/libsodium.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_context.so* /home/tc/patch-extractor/lib
    cp usr/lib/libsynocrypto.so* /home/tc/patch-extractor/lib
    cp usr/lib/libsynocredentials.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_iostreams.so* /home/tc/patch-extractor/lib
    cp usr/lib/libsynocore.so* /home/tc/patch-extractor/lib
    cp usr/lib/libicuio.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_chrono.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_date_time.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_system.so* /home/tc/patch-extractor/lib
    cp usr/lib/libsynocodesign.so.7* /home/tc/patch-extractor/lib
    cp usr/lib/libsynocredential.so* /home/tc/patch-extractor/lib
    cp usr/lib/libjson-glib-1.0.so* /home/tc/patch-extractor/lib
    cp usr/lib/libboost_serialization.so* /home/tc/patch-extractor/lib
    cp usr/lib/libmsgpackc.so* /home/tc/patch-extractor/lib

    cp -r usr/syno/sbin/synoarchive /home/tc/patch-extractor/

    sudo rm -rf usr
    sudo rm -rf ../oldpat.tar.gz
    sudo rm -rf hda1.tgz

    curl -k -s -L https://github.com/PeterSuh-Q3/tinycore-redpill/blob/main/tools/xxd?raw=true -o xxd

    chmod +x xxd

    ./xxd synoarchive | sed -s 's/000039f0: 0300/000039f0: 0100/' | ./xxd -r >synoarchive.nano
    ./xxd synoarchive | sed -s 's/000039f0: 0300/000039f0: 0a00/' | ./xxd -r >synoarchive.smallpatch
    ./xxd synoarchive | sed -s 's/000039f0: 0300/000039f0: 0000/' | ./xxd -r >synoarchive.system

    chmod +x synoarchive.*

    [ ! -d /mnt/${tcrppart}/auxfiles/patch-extractor ] && mkdir /mnt/${tcrppart}/auxfiles/patch-extractor

    cp -rf /home/tc/patch-extractor/lib /mnt/${tcrppart}/auxfiles/patch-extractor/
    cp -rf /home/tc/patch-extractor/synoarchive* /mnt/${tcrppart}/auxfiles/patch-extractor/

    sudo cp -rf /home/tc/patch-extractor/lib /lib
    sudo cp -rf /home/tc/patch-extractor/synoarchive.* /bin

}

function downloadupgradepat() {

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"

    if [ ! -d /mnt/${tcrppart}/auxfiles/patch-extractor ] || [ ! -f /mnt/${tcrppart}/auxfiles/patch-extractor/synoarchive.nano ]; then
        downloadextractorv2
    else
        echo "Found locally cached extractor"
        [ ! -h /lib64 ] && sudo ln -s /lib /lib64
        sudo cp -f /mnt/${tcrppart}/auxfiles/patch-extractor/lib/* /lib/
        sudo cp -f /mnt/${tcrppart}/auxfiles/patch-extractor/synoarchive* /bin
    fi

    cd /home/tc

    PS3="Select Model : "

    select model in $(ls /home/tc/redpill-load/config | grep -v common); do

        echo "Selected model : ${model} "

        PS3="Select update version : "
        select version in $(curl -k -s https://archive.synology.com/download/Os/DSM/ | grep "/download/Os/DSM/7" | awk '{print $2}' | awk -F\/ '{print $5}' | sed -s 's/"//g'); do
            echo "Selected version : $version"
            selectedmodel=$(echo $model | sed -e 's/DS//g' | sed -e 's/RS//g' | sed -e 's/DVA//g' | sed -e 's/+//g')
            PS3="Select pat file URL : "
            select patfile in $(curl -k -s "https://archive.synology.com/download/Os/DSM/${version}" | grep href | grep -i $selectedmodel | awk '{print $2}' | sed -e 's/href=//g'); do

                patfile="$(echo $patfile | sed -e 's/"//g')"
                echo "Selected patfile :  $patfile "
                patfilever="$(echo $patfile | awk -F\/ '{print $8}')"
                updatepat="/home/tc/${model}_${patfilever}.pat"

                echo "Downloading PAT file "
                curl -k -# -L "$patfile" -o $updatepat

                [ -f $updatepat ] && echo "Downloaded Patfile $updatepat "

                extractdownloadpat "$version" && return

            done

        done

    done

}

function extractdownloadpat() {

    upgradepatdir="/home/tc/upgradepat"
    temppat="/home/tc/temppat"

    rm -rf $upgradepatdir
    rm -rf $temppat

    echo "Extracting pat file to find your files..."
    [ ! -d $temppat ] && mkdir $temppat
    cd $temppat

    echo "Upgrade patfile $updatepat will be extracted to $temppat"

    issystempat="$(echo $version | grep -i nano | wc -l)"

    if [ $issystempat -eq 1 ]; then
        echo "PAT file is a system nanopacked file "
        synoarchive.system -xf ${updatepat}
    else
        echo "PAT file is a smallupdate file "
        synoarchive.nano -xf ${updatepat}
        tarfile="$(ls flash*update* | head -1 2>/dev/null)"
        if [ ! -z $tarfile ]; then
            tar xf $tarfile
            tar xf content.txz
        else
            echo "update does not contain a flashupdate"
        fi

    fi

    [ ! -d $upgradepatdir ] && mkdir $upgradepatdir

    [ -f rd.gz ] && echo "Copying rd.gz to $upgradepatdir" && cp rd.gz $upgradepatdir
    [ -f zImage ] && echo "Copying zImage to $upgradepatdir" && cp zImage $upgradepatdir

    if [ -f $upgradepatdir/rd.gz ] && [ -f $upgradepatdir/zImage ]; then
        cd /home/tc
        echo "Cleaning up "
        rm -rf $temppat
        rm -rf $updatepat
        echo "The initrd you need is -> $(ls $upgradepatdir/rd.gz) "
    else
        echo "Something went wrong or the update file does not contain rd.gz or zImage"
    fi

}

function fullupgrade() {

    backupdate="$(date +%Y-%b-%d-%H-%M)"

    echo "Performing a full TCRP upgrade"
    echo "Warning some of your local files will be moved to /home/tc/old/xxxx.${backupdate}"

    mkdir -p /home/tc/old

    for updatefile in ${fullupdatefiles}; do

        echo "Updating ${updatefile}"

        [ -f ${updatefile} ] && sudo mv $updatefile old/${updatefile}.${backupdate}
        sudo curl -k -s -L "${rploaderrepo}/${updatefile}" -O
        [ ! -f ${updatefile} ] && mv old/${updatefile}.${backupdate} $updatefile

    done

    sudo chown tc:staff $fullupdatefiles
    gunzip -f modules.alias.*.gz
    sudo chmod 700 rploader.sh

    backup

}

function backuploader() {

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    homesize=$(du -sh /home/tc | awk '{print $1}')
    backupdate="$(date +%Y-%b-%d-%H-%M)"

    if [ ! -n "$loaderdisk" ] || [ ! -n "$tcrppart" ]; then
        echo "No Loader disk or no TCRP partition found, return"
        return
    fi

    if [ $avail_num -le 50 ]; then
        echo "No adequate space on TCRP loader partition  /mnt/${tcrppart} for backup"
        return
    fi

    echo "Backing up current loader"
    echo "Checking backup folder existence"
    [ ! -d /mnt/${tcrppart}/backup ] && mkdir /mnt/${tcrppart}/backup
    echo "The backup folder holds the following backups"
    ls -ltr /mnt/${tcrppart}/backup
    echo "Creating backup folder $backupdate"
    [ ! -d /mnt/${tcrppart}/backup/${backupdate} ] && mkdir /mnt/${tcrppart}/backup/${backupdate}
    echo "Mounting partition 1"
    mount /dev/${loaderdisk}1
    cd /mnt/${loaderdisk}1
    tar cfz /mnt/${tcrppart}/backup/${backupdate}/partition1.tgz *

    echo "Mounting partition 2"
    mount /dev/${loaderdisk}2
    cd /mnt/${loaderdisk}2
    tar cfz /mnt/${tcrppart}/backup/${backupdate}/partition2.tgz *

    cd
    echo "Listing backup files : "

    ls -ltr /mnt/${tcrppart}/backup/${backupdate}/

    echo "Partition 1 : $(tar tfz /mnt/${tcrppart}/backup/${backupdate}/partition1.tgz | wc -l) files and directories "
    echo "Partition 2 : $(tar tfz /mnt/${tcrppart}/backup/${backupdate}/partition2.tgz | wc -l) files and directories "

    echo "DONE"

}

function restoreloader() {

#    loaderdisk="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)"
#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    homesize=$(du -sh /home/tc | awk '{print $1}')
    PS3="Select backup folder to restore : "
    options=""

    if [ ! -n "$loaderdisk" ] || [ ! -n "$tcrppart" ]; then
        echo "No Loader disk or no TCRP partition found, return"
        return
    fi

    echo "Restoring loader from backup"
    echo "The backup folder holds the following backups"

    for folder in $(ls /mnt/${tcrppart}/backup | sed -e 's/\///g'); do
        options=" $options ${folder}"
        echo -n $folder
        echo -n "Partition 1 : $(tar tfz /mnt/${tcrppart}/backup/${folder}/partition1.tgz | wc -l) files and directories "
        echo "Partition 2 : $(tar tfz /mnt/${tcrppart}/backup/${folder}/partition2.tgz | wc -l) files and directories "
    done

    select restorefolder in ${options[@]}; do
        if [ "$REPLY" == "quit" ]; then
            return
        fi
        if [ -f "/mnt/${tcrppart}/backup/$restorefolder/partition1.tgz" ]; then
            echo " Restore folder : $restorefolder"
            echo -n "You have chosen ${restorefolder} : "
            echo "Folder contains : "
            ls -ltr /mnt/${tcrppart}/backup/$restorefolder

            echo -n "Do you want to restore [yY/nN] : "
            readanswer

            if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
                echo restoring $restorefolder
                echo "Mounting partition 1"
                mount /dev/${loaderdisk}1
                echo "Restoring partition1 "
                cd /mnt/${loaderdisk}1
                tar xfz /mnt/${tcrppart}/backup/${restorefolder}/partition1.tgz *
                ls -ltr /mnt/${loaderdisk}1
                echo "Mounting partition 2"
                mount /dev/${loaderdisk}2
                echo "Restoring partition2 "
                cd /mnt/${loaderdisk}2
                tar xfz /mnt/${tcrppart}/backup/${restorefolder}/partition2.tgz *
                ls -ltr /mnt/${loaderdisk}2
                return
            else
                echo "OK, retry "
                return
            fi
        fi
        echo "Invalid choice : $REPLY"
    done

}

function checkforscsi() {

    # Make sure we load SCSI modules if SCSI/RAID/SAS HBAs exist on the system
    #
    if [ $(lspci -nn | grep -ie "\[0100\]" -ie "\[0104\]" -ie "\[0107\]" | wc -l) -gt 0 ]; then
        echo "Found SCSI HBAs, We need to install the SCSI modules"
        tce-load -iw scsi-5.10.3-tinycore64.tcz
        [ $(losetup | grep -i "scsi-" | wc -l) -gt 0 ] && echo "Succesfully installed SCSI modules"
    fi

}

function mountdsmroot() {

    # DSM Disks will be linux_raid_member and will  have the
    # same DSM PARTUUID with the addition of the partition number e.g :
    #/dev/sdb1: UUID="629ae3df-7eef-54e3-05d9-49f7b0bbaec7" TYPE="linux_raid_member" PARTUUID="d5ff7cea-01"
    #/dev/sdb2: UUID="260b3a01-ff65-a527-05d9-49f7b0bbaec7" TYPE="linux_raid_member" PARTUUID="d5ff7cea-02"
    # So a command like the below will list the first partition of a DSM disk
    #blkid /dev/sd* |grep -i raid  | awk '{print $1 " " $4}' |grep UUID | grep "\-01" | awk -F ":" '{print $1}'

    checkforscsi

    dsmrootdisk="$(blkid /dev/sd* | grep -i raid | awk '{print $1 " " $4}' | grep UUID | grep sd[a-z]1 | head -1 | awk -F ":" '{print $1}')"
    # OLD DSM
    #dsmrootdisk="$(blkid /dev/sd* | grep -i raid | awk '{print $1 " " $4}' | grep UUID | grep "\-01" | awk -F ":" '{print $1}' | head -1)"

    [[ ! -d /mnt/dsmroot ]] && mkdir /mnt/dsmroot

    [ ! $(mount | grep -i dsmroot | wc -l) -gt 0 ] && sudo mount -t ext4 $dsmrootdisk /mnt/dsmroot

    if [ $(mount | grep -i dsmroot | wc -l) -gt 0 ]; then
        echo "Succesfully mounted under /mnt/dsmroot"
    else
        echo "Failed to mount"
        return
    fi

    echo "Checking if patch version exists"

    if [ -d /mnt/dsmroot/.syno/patch ]; then
        echo "Patch directory exists"
        sudo cp /mnt/dsmroot/.syno/patch/VERSION /tmp/VERSION
        sudo chmod 666 /tmp/VERSION
        . /tmp/VERSION
        echo "DSM Root holds a patch version $productversion-$base-$nano "
    else
        echo "No DSM patch directory exists"
        return
    fi

}

function mountdatadisk() {

    echo "Assembling MD ..."
    sudo mdadm -Asf

    for mdarray in "$(ls /dev/md* | awk -F "\/" '{print $3}')"; do
        echo "Mounting $mdarray"
        echo "Getting md devices for array $mdarray"

        # Keep for LVM root disks recovery in future release
        if [ "$(fstype /dev/${mdarray})" == "LVM2_member" ]; then
            echo "Found LVM array, downloading LVM"
            tce-load -iw lvm2
            sudo vgchange -a y
            for volume in $(sudo lvs | grep -i vol | awk '{print $2"-"$1}'); do

                if [ "$(fstype /dev/mapper/$volume)" == "btrfs" ]; then
                    echo "BTRFS Mounting is not supported in tinycore"
                    return
                fi
                mkdir /mnt/$volume
                sudo mount /dev/mapper/$volume
            done
        else
            echo "Mounting $mdarray "
            sudo mkdir /mnt/$mdarray
            sudo mount /dev/$mdarray /mnt/$mdarray
        fi
    done

}

function patchdtc() {

    checkmachine
#    loaderdisk=$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)
    localdisks=$(lsblk | grep -i disk | grep -i sd | awk '{print $1}' | grep -v $loaderdisk)
    localnvme=$(lsblk | grep -i nvme | awk '{print $1}')
    usbpid=$(cat user_config.json | jq '.extra_cmdline .pid' | sed -e 's/"//g' | sed -e 's/0x//g')
    usbvid=$(cat user_config.json | jq '.extra_cmdline .vid' | sed -e 's/"//g' | sed -e 's/0x//g')
    loaderusb=$(lsusb | grep "${usbvid}:${usbpid}" | awk '{print $2 "-"  $4 }' | sed -e 's/://g' | sed -s 's/00//g')

    curl -skL "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/${TARGET_PLATFORM}.dts" -o /home/tc/redpill-load/${TARGET_PLATFORM}.dts

    if [ ! -d /lib64 ]; then
        [ ! -h /lib64 ] && sudo ln -s /lib /lib64
    fi

    # Download dtc
    if [ "$(which dtc)_" == "_" ]; then
        echo "dtc dos not exist, Downloading dtc binary"
        curl -skLO "$dtcbin"
        chmod 700 dtc
        sudo mv -vf dtc /usr/local/bin/
    fi 

    if [ -f /home/tc/custom-module/${TARGET_PLATFORM}.dts ] && [ ! -f /home/tc/custom-module/${TARGET_PLATFORM}.dtb ]; then
        echo "Found locally cached dts file ${TARGET_PLATFORM}.dts and dtb file does not exist in cache, converting dts to dtb"
        ./dtc -q -I dts -O dtb /home/tc/custom-module/${TARGET_PLATFORM}.dts >/home/tc/custom-module/${TARGET_PLATFORM}.dtb
    fi

    if [ -f /home/tc/custom-module/${TARGET_PLATFORM}.dtb ]; then

        echo "Fould locally cached dtb file"
#        read -p "Should i use that file ? [Yy/Nn]" answer
#        if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
            echo "OK copying over the cached dtb file"

            dtbextfile="$(find /home/tc/redpill-load/custom -name model_${TARGET_PLATFORM}.dtb)"
            if [ ! -z ${dtbextfile} ] && [ -f ${dtbextfile} ]; then
                echo -n "Copying patched dtb file ${TARGET_PLATFORM}.dtb to ${dtbextfile} -> "
                sudo cp /home/tc/custom-module/${TARGET_PLATFORM}.dtb ${dtbextfile}
                if [ $(sha256sum /home/tc/custom-module/${TARGET_PLATFORM}.dtb | awk '{print $1}') = $(sha256sum ${dtbextfile} | awk '{print $1}') ]; then
                    echo -e "OK ! File copied and verified !"
                    return
                else
                    echo -e "ERROR !\nFile has not been copied succesfully, you will need to copy it yourself"
                    return
                fi
            else
                [ -z ${dtbextfile} ] && echo "dtb extension is not loaded and its required for DSM to find disks on ${SYNOMODEL}"
                echo "Copy of the DTB file ${TARGET_PLATFORM}.dtb to ${dtbextfile} was not succesfull."
                echo "Please remember to replace the dtb extension model file ..."
                echo "execute manually : cp ${TARGET_PLATFORM}.dtb ${dtbextfile} and re-run"
                exit 99
            fi
#        else
#            echo "OK lets continue patching"
#        fi
    else
        echo "No cached dtb file found in /home/tc/custom-module/${TARGET_PLATFORM}.dtb"
    fi

}

function dont_use_patchdtc() {

    if [ ! -f ${dtbfile}.dts ]; then
        echo "dts file for ${dtbfile} not found, trying to download"
        curl -kL -# -O "${dtsfiles}/${dtbfile}.dts"
    fi

    echo "Found $(echo $localdisks | wc -w) disks and $(echo $localnvme | wc -w) nvme"
    let diskslot=1
    echo "Collecting disk paths"

    for disk in $localdisks; do
        diskdepth=$(udevadm info --query path --name $disk | awk -F"/" '{print NF-1}')
        if [[ $diskdepth = 9 ]]; then
            diskpath=$(udevadm info --query path --name $disk | awk -F "/" '{print $4 ":" $5 }' | awk -F ":" '{print $2 ":" $3 }')
        elif [[ $diskdepth = 11 ]]; then
            diskpath=$(udevadm info --query path --name $disk | awk -F "/" '{print $4 ":" $5 ":" $6 }' | awk -F ":" '{print $2 ":" $3 "," $6 "," $9 }')
        else
            diskpath=$(udevadm info --query path --name $disk | awk -F "/" '{print $4 ":" $5 }' | awk -F ":" '{print $2 ":" $3 "," $6}')
        fi
        #diskpath=$(udevadm info --query path --name $disk | awk -F "\/" '{print $4 ":" $5 }' | awk -F ":" '{print $2 ":" $3 "," $6}' | sed 's/,*$//')
        if [ "$HYPERVISOR" == "VMware" ]; then
            diskport=$(udevadm info --query path --name $disk | sed -n '/target/{s/.*target//;p;}' | awk -F: '{print $1}')
            diskport=$(($diskport - 30)) && diskport=$(printf "%x" $diskport)
        else
            diskport=$(udevadm info --query path --name $disk | sed -n '/target/{s/.*target//;p;}' | awk -F: '{print $1}')
            diskport=$(printf "%x" $diskport)
        fi

        echo "Found local disk $disk with path $diskpath, adding into internal_slot $diskslot with portnumber $diskport"
        if [ "${dtbfile}" == "ds920p" ] || [ "${dtbfile}" == "dva1622" ]; then
            sed -i "/internal_slot\@${diskslot} {/!b;n;n;n;n;n;n;n;cpcie_root = \"$diskpath\";" ${dtbfile}.dts
            sed -i "/internal_slot\@${diskslot} {/!b;n;n;n;n;n;n;n;n;cata_port = <0x$diskport>;" ${dtbfile}.dts
            let diskslot=$diskslot+1
        else
            sed -i "/internal_slot\@${diskslot} {/!b;n;n;n;n;n;cpcie_root = \"$diskpath\";" ${dtbfile}.dts
            sed -i "/internal_slot\@${diskslot} {/!b;n;n;n;n;n;n;cata_port = <0x$diskport>;" ${dtbfile}.dts
            let diskslot=$diskslot+1
        fi

    done

    if [ $(echo $localnvme | wc -w) -gt 0 ]; then
        let nvmeslot=1
        echo "Collecting nvme paths"

        for nvme in $localnvme; do
            nvmepath=$(udevadm info --query path --name $nvme | awk -F "\/" '{print $4 ":" $5 }' | awk -F ":" '{print $2 ":" $3 "," $6}' | sed 's/,*$//')
            echo "Found local nvme $nvme with path $nvmepath, adding into m2_card $nvmeslot"
            if [ "${dtbfile}" == "ds920p" ]; then
                sed -i "/nvme_slot\@${nvmeslot} {/!b;n;cpcie_root = \"$nvmepath\";" ${dtbfile}.dts
                let diskslot=$diskslot+1
            else
                sed -i "/m2_card\@${nvmeslot} {/!b;n;n;n;cpcie_root = \"$nvmepath\";" ${dtbfile}.dts
                let nvmeslot=$diskslot+1
            fi
        done

    else
        echo "NO NVME disks found, returning"
    fi

    if
        [ ! -z $loaderusb ] && [ -n $loaderusb ]
    then
        echo "Patching USB to include your loader. Loader found in ${loaderusb} port"
        sed -i "/usb_slot\@1 {/!b;n;n;n;n;n;n;n;cusb_port = \"${loaderusb}\";" ${dtbfile}.dts
    else
        echo "Your loader is not in USB, i will not try to patch dtb for USB"
    fi

    echo "Converting dts file : ${dtbfile}.dts to dtb file : >${dtbfile}.dtb "
    ./dtc -q -I dts -O dtb ${dtbfile}.dts >${dtbfile}.dtb

    dtbextfile="$(find /home/tc/redpill-load/custom -name model_${dtbfile}.dtb)"
    if [ ! -z ${dtbextfile} ] && [ -f ${dtbextfile} ]; then
        echo -n "Copying patched dtb file ${dtbfile}.dtb to ${dtbextfile} -> "
        sudo cp ${dtbfile}.dtb ${dtbextfile}
        if [ $(sha256sum ${dtbfile}.dtb | awk '{print $1}') = $(sha256sum ${dtbextfile} | awk '{print $1}') ]; then
            echo -e "OK ! File copied and verified !"
        else
            echo -e "ERROR !\nFile has not been copied succesfully, you will need to copy it yourself"
        fi
    else
        [ -z ${dtbextfile} ] && echo "dtb extension is not loaded and its required for DSM to find disks on ${SYNOMODEL}"
        echo "Copy of the DTB file ${dtbfile}.dtb to ${dtbextfile} was not succesfull."
        echo "Please remember to replace the dtb extension model file ..."
        echo "execute manually : cp ${dtbfile}.dtb ${dtbextfile} and re-run"
        exit 99
    fi
}

function mountshare() {

    echo "smb user of the share, leave empty when you do not want to use one"
    read -r user

    echo "smb password of the share, leave empty when you do not want to use one"
    read -r password

    if [ -n "$user" ] && [ -z "$password" ]; then
        echo "u used a username, so we need a password too"
        echo "smb password of the share"
        read -r password
    fi

    echo "smb host ip or hostname"
    read -r server

    echo "smb shared folder. Start always with /"
    read -r share

    echo "local mount folder. Use foldername for the mount. This folder is created in /home/tc (default:/home/tc/mount)"
    read -r mountpoint

    if [ -z "$mountpoint" ]; then
        echo "use /home/tc/mount folder, nothing was entered to use so we use the default folder"
        mountpoint="/home/tc/mount"

        if [ ! -d "$mountpoint" ]; then
            sudo mkdir -p "$mountpoint"
        fi
    else
        sudo mkdir -p "$mountpoint"
    fi

    if [ -n "$user" ] && [ -n "$password" ]; then
        sudo mount.cifs "//$server$share" "$mountpoint" -o user="$user",pass="$password"
    else
        echo "No user/password given, mount without. Press enter"
        sudo mount.cifs "//$server$share" "$mountpoint"
    fi
}

function backup() {

#Apply pigz for fast backup  
    if [ ! -n "$(which pigz)" ]; then
        echo "pigz does not exist, bringing over from repo"
        curl -s -k -L "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/tools/pigz" -O
        chmod 777 pigz
        sudo mv pigz /usr/local/bin/
    fi

    thread=$(lscpu |grep CPU\(s\): | awk '{print $2}')
    if [ $(cat /usr/bin/filetool.sh | grep pigz | wc -l ) -eq 0 ]; then
        sudo sed -i "s/\-czvf/\-cvf \- \| pigz -p "${thread}" \>/g" /usr/bin/filetool.sh
        sudo sed -i "s/\-czf/\-cf \- \| pigz -p "${thread}" \>/g" /usr/bin/filetool.sh
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

function satamap() {

    # This function identifies all SATA controllers and create a plausible sataportmap and diskidxmap.
    #
    # In the case of SATABOOT: While TinyCore suppresses the /dev/sd device servicing synoboot, the
    # controller still takes up a sataportmap entry. ThorGroup advised not to map the controller ports
    # beyond the MaxDisks limit, but there is no harm in doing so - unless additional devices are
    # connected along with SATABOOT. This will create a gap/empty first slot.
    #
    # By mapping the SATABOOT controller ports beyond MaxDisks like Jun loader, it forces data disks
    # onto a secondary controller, and it's clear what the SATABOOT controller and device are being
    # used for. The KVM q35 bogus controller is mapped in the same manner.
    #
    # DUMMY ports (flagged by kernel as empty/non-functional, usually because hotplug is supported and
    # not enabled, and no disk is attached are detected and alerted. Any DUMMY port visible to the
    # DSM installer will result in a "SATA port disabled" message.
    #
    # SCSI/SAS and non-AHCI compliant SATA are unaffected by sataportmap and diskidxmap but a summary
    # controller and drive report is provided in order to avoid user distress.
    #
    # This code was written with the intention of reusing the detection strategy for device tree
    # creation, and the two functions could easily be integrated if desired.

    checkmachine
    checkforscsi

    let diskidxmapidx=0
    badportfail=false
    sataportmap=""
    diskidxmap=""

    maxdisks=$(jq -r ".synoinfo.maxdisks" user_config.json)

    # look for dummy SATA flagged by kernel (bad ports)
    dmys=$(dmesg | grep ": DUMMY$" | awk -F"] ata" '{print $2}' | awk -F: '{print $1}' | sort -n)

    # if we cannot find usb disk, the boot disk must be intended for SATABOOT
    if [ $(ls -la /sys/block/sd* | fgrep "/usb" | wc -l) -eq 0 ]; then
#        loaderdisk=$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)
        sbpci=$(ls -la /sys/block/$loaderdisk | awk -F"/ata" '{print $1}' | awk -F"/" '{print $NF}' | cut --complement -f1 -d:)
    fi

    # get all SATA controllers PCI class 106
    # 100 = SCSI, 104 = RAIDHBA, 107 = SAS - none of these appear to honor sataportmap/diskidxmap
    pcis=$(lspci -d ::106 | awk '{print $1}')

    # loop through controllers in correct order
    for pci in $pcis; do
        # get attached block devices (exclude CD-ROMs)
        ports=$(ls -la /sys/class/ata_device | fgrep "$pci" | wc -l)
        drives=$(ls -la /sys/block | fgrep "$pci" | grep -v "sr.$" | wc -l)
        echo -e "\nFound \"$(lspci -s $pci | sed "s/\ .*://")\""
        echo -n "Detected $ports ports/$drives drives. "

        # look for bad ports on this controller
        badports=""
        for dmy in $dmys; do
            badpci=$(ls -la /sys/class/ata_port/ata$dmy | awk -F"/ata$dmy/ata_port/" '{print $1}' | awk -F"/" '{print $NF}' | cut --complement -f1 -d:)
            [ "$pci" = "$badpci" ] && badports=$(echo $badports$dmy" ")
        done
        # display the bad ports, referenced to controller port numbering
        if [ ! -z "$badports" ]; then
            # minmap is invalid with bad ports!
            [ "$1" = "minmap" ] && badportfail=true
            # get first port of PCI adapter with bad ports
            badportbase=$(ls -la /sys/class/ata_port | fgrep "$badpci" | awk -F"/ata_port/ata" '{print $2}' | sort -n | head -1)
            echo -n "Bad ports:"
            for badport in $badports; do
                let badport=$badport-$badportbase+1
                echo -n " "$badport
            done
            echo -n ". "
        fi
        # SATABOOT controller? (if so, it has to be mapped as first controller, we think)
        if [ "$pci" = "$sbpci" ]; then
            echo "Mapping SATABOOT drive after maxdisks"
            [ ${drives} -gt 1 ] && echo "WARNING: Other drives are connected that will not be accessible!"
            sataportmap=$sataportmap"1"
            diskidxmap=$diskidxmap$(printf "%02X" $maxdisks)
        else
            if [ "$pci" = "00:1f.2" ] && [ "$HYPERVISOR" = "KVM" ]; then
                # KVM q35 bogus controller?
                echo "Mapping KVM q35 bogus controller after maxdisks"
                sataportmap=$sataportmap"1"
                diskidxmap=$diskidxmap$(printf "%02X" $maxdisks)
            else
                # handle VMware virtual SATA controller insane port count
                if [ "$HYPERVISOR" = "VMware" ] && [ $ports -eq 30 ]; then
                    echo "Defaulting 8 virtual ports for typical system compatibility"
                    ports=8
                else
                    # if minmap and not vmware virtual sata, don't update sataportmap/diskidxmap
                    if [ "$1" = "minmap" ]; then
                        echo
                        continue
                    fi
                fi
                # ask interactively if not minmap
                if [ "$1" != "minmap" ]; then
                    echo -n "Override # of ports or ENTER to accept <$ports> "
                    read newports
                    if [ ! -z "$newports" ]; then
                        ports=$newports
                        if ! [ "$ports" -eq "$ports" ] 2>/dev/null; then
                            echo "Non-numeric, overridden to 0"
                            ports=0
                        fi
                    fi
                else
                    echo
                fi
                # if badports are in the port range, set the fail flag
                if [ ! -z "$badports" ]; then
                    for badport in $badports; do
                        let badport=$badport-$badportbase+1
                        [ $ports -ge $badport ] && badportfail=true
                    done
                fi
                if [ $ports -gt 9 ]; then
                    echo "WARNING: SataPortMap values >9 are experimental and may affect stability"
                    let ports=$ports+48
                    portchar=$(printf \\$(printf "%o" $ports))
                else
                    portchar=$ports
                fi
                sataportmap=$sataportmap$portchar
                diskidxmap=$diskidxmap$(printf "%02x" $diskidxmapidx)
                let diskidxmapidx=$diskidxmapidx+$ports
            fi
        fi
    done

    # ports > maxdisks?
    [ $diskidxmapidx -gt $maxdisks ] && echo "WARNING: mapped SATA port count exceeds maxdisks"

    # fix kernel panic if 1st position is set to 0 ports (from no SATA mappings or deliberate user selection)
    [ -z "$sataportmap" -o "${sataportmap:0:1}" = "0" ] && sataportmap=1${sataportmap:1}

    # handle no assigned SATA ports affecting SCSI mapping problem
    [ -z "$diskidxmap" ] && diskidxmap="00"

    # now advise on SCSI drives for user peace of mind
    # 100 = SCSI, 104 = RAIDHBA, 107 = SAS - none of these honor sataportmap/diskidxmap
    pcis=$(
        lspci -d ::100
        lspci -d ::104
        lspci -d ::107 | awk '{print $1}'
    )
    [ ! -z "$pcis" ] && echo
    # loop through non-SATA controllers
    for pci in $pcis; do
        # get attached block devices (exclude CD-ROMs)
        drives=$(ls -la /sys/block | fgrep "$pci" | grep -v "sr.$" | wc -l)
        echo "Found SCSI/HBA \""$(lspci -s $pci | sed "s/\ .*://")"\" ($drives drives)"
    done

    echo -e "\nComputed settings:"
    echo "SataPortMap=$sataportmap"
    echo "DiskIdxMap=$diskidxmap"
    [ "$badportfail" = true ] && echo -e "\nWARNING: Bad ports are mapped. The DSM installation will fail!"

    echo -en "\nShould i update the user_config.json with these values ? [Yy/Nn] "
    readanswer
    if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
        json="$(jq --arg var "$sataportmap" '.extra_cmdline.SataPortMap = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
        json="$(jq --arg var "$diskidxmap" '.extra_cmdline.DiskIdxMap = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
        echo "Done."
    else
        echo "OK remember to update manually by editing user_config.json file"
    fi
}

function usbidentify() {

    checkmachine

    if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "VMware" ]; then
        echo "Running on VMware, no need to set USB VID and PID, you should SATA shim instead"
        exit 0
    fi

    if [ "$MACHINE" = "VIRTUAL" ] && [ "$HYPERVISOR" = "QEMU" ]; then
        echo "Running on QEMU, If you are using USB shim, VID 0x46f4 and PID 0x0001 should work for you"
        vendorid="0x46f4"
        productid="0x0001"
        echo "Vendor ID : $vendorid Product ID : $productid"

        echo "Should i update the user_config.json with these values ? [Yy/Nn]"
        readanswer
        if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
            sed -i "/\"pid\": \"/c\    \"pid\": \"$productid\"," user_config.json
            sed -i "/\"vid\": \"/c\    \"vid\": \"$vendorid\"," user_config.json
        else
            echo "OK remember to update manually by editing user_config.json file"
        fi
        exit 0
    fi

#    loaderdisk=$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)

    lsusb -v 2>&1 | grep -B 33 -A 1 SCSI >/tmp/lsusb.out

    usblist=$(grep -B 33 -A 1 SCSI /tmp/lsusb.out)
    vendorid=$(grep -B 33 -A 1 SCSI /tmp/lsusb.out | grep -i idVendor | awk '{print $2}')
    productid=$(grep -B 33 -A 1 SCSI /tmp/lsusb.out | grep -i idProduct | awk '{print $2}')

    if [ $(echo $vendorid | wc -w) -gt 1 ]; then
        echo "Found more than one USB disk devices, please select which one is your loader on"
        usbvendor=$(for item in $vendorid; do grep $item /tmp/lsusb.out | awk '{print $3}'; done)
        select usbdev in $usbvendor; do
            vendorid=$(grep -B 10 -A 10 $usbdev /tmp/lsusb.out | grep idVendor | grep $usbdev | awk '{print $2}')
            productid=$(grep -B 10 -A 10 $usbdev /tmp/lsusb.out | grep -A 1 idVendor | grep idProduct | awk '{print $2}')
            echo "Selected Device : $usbdev , with VendorID: $vendorid and ProductID: $productid"
            break
        done
    else
        usbdevice="$(grep iManufacturer /tmp/lsusb.out | awk '{print $3}') $(grep iProduct /tmp/lsusb.out | awk '{print $3}') SerialNumber: $(grep iSerial /tmp/lsusb.out | awk '{print $3}')"
    fi

    if [ -n "$usbdevice" ] && [ -n "$vendorid" ] && [ -n "$productid" ]; then
        echo "Found $usbdevice"
        echo "Vendor ID : $vendorid Product ID : $productid"

        echo "Should i update the user_config.json with these values ? [Yy/Nn]"
        readanswer
        if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
            #  sed -i "/\"pid\": \"/c\    \"pid\": \"$productid\"," user_config.json
            json="$(jq --arg var "$productid" '.extra_cmdline.pid = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
            #  sed -i "/\"vid\": \"/c\    \"vid\": \"$vendorid\"," user_config.json
            json="$(jq --arg var "$vendorid" '.extra_cmdline.vid = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
        else
            echo "OK remember to update manually by editing user_config.json file"
        fi
    else
        echo "Sorry, no usb disk could be identified"
        rm /tmp/lsusb.out
    fi
}

function serialgen() {

    [ ! -z "$GATEWAY_INTERFACE" ] && shift 0 || shift 1

    [ "$2" == "realmac" ] && let keepmac=1 || let keepmac=0

        serial=`./sngen.sh $1`
#        serial="$(generateSerial $1)"
        
        mac=`./macgen.sh "randommac" "eth0" $1`
        realmac=`./macgen.sh "realmac" "eth0" $1`        
#        mac="$(generateMacAddress $1)"
#        realmac=$(ifconfig eth0 | head -1 | awk '{print $NF}')

        echo "Serial Number for Model = $serial"
        echo "Mac Address for Model $1 = $mac "
        [ $keepmac -eq 1 ] && echo "Real Mac Address : $realmac"
        [ $keepmac -eq 1 ] && echo "Notice : realmac option is requested, real mac will be used"

        if [ -z "$GATEWAY_INTERFACE" ]; then

            echo "Should i update the user_config.json with these values ? [Yy/Nn]"
            readanswer
        else
            answer="y"
        fi

        if [ -n "$answer" ] && [ "$answer" = "Y" ] || [ "$answer" = "y" ]; then
            # sed -i "/\"sn\": \"/c\    \"sn\": \"$serial\"," user_config.json
            json="$(jq --arg var "$serial" '.extra_cmdline.sn = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json

            if [ $keepmac -eq 1 ]; then
                macaddress=$(echo $realmac | sed -s 's/://g')
            else
                macaddress=$(echo $mac | sed -s 's/://g')
            fi

            json="$(jq --arg var "$macaddress" '.extra_cmdline.mac1 = $var' user_config.json)" && echo -E "${json}" | jq . >user_config.json
            # sed -i "/\"mac1\": \"/c\    \"mac1\": \"$macaddress\"," user_config.json
        else
            echo "OK remember to update manually by editing user_config.json file"
        fi

}

function prepareforcompile() {

    echo "Downloading required build software "
    tce-load -wi git compiletc coreutils bc perl5 openssl-1.1.1-dev

    if [ ! -d /lib64 ]; then
        [ ! -h /lib64 ] && sudo ln -s /lib /lib64
    fi
    if [ ! -f /lib64/libbz2.so.1 ]; then
        [ ! -h /lib64/libbz2.so.1 ] && sudo ln -s /usr/local/lib/libbz2.so.1.0.8 /lib64/libbz2.so.1
    fi

}

function getPlatforms() {

    platform_versions=$(jq -s '.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]' custom_config_jun.json custom_config.json | jq -r '.build_configs[].id')
    echo "platform_versions=$platform_versions"

}

function selectPlatform() {

    platform_selected=$(jq -s '.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]' custom_config_jun.json custom_config.json | jq ".build_configs[] | select(.id==\"${1}\")")
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
        jq -s '.[0].build_configs=(.[1].build_configs + .[0].build_configs | unique_by(.id)) | .[0]' custom_config_jun.json custom_config.json
    fi

}

function setplatform() {

    SYNOMODEL=${TARGET_PLATFORM}_${TARGET_REVISION}
    MODEL=$(echo "${TARGET_PLATFORM}" | sed 's/ds/DS/' | sed 's/rs/RS/' | sed 's/p/+/' | sed 's/dva/DVA/' | sed 's/fs/FS/' | sed 's/sa/SA/' )
    ORIGIN_PLATFORM="$(echo $platform_selected | jq -r -e '.platform_name')"

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
    TARGET_PLATFORM="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[0])"
    TARGET_VERSION="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[1])"
    TARGET_REVISION="$(echo $platform_selected | jq -r -e '.id | split("-")' | jq -r -e .[2])"

    tcrppart="${tcrpdisk}3"
    local_cache="/mnt/${tcrppart}/auxfiles"
    usbpart1uuid=$(blkid /dev/${tcrpdisk}1 | awk '{print $3}' | sed -e "s/\"//g" -e "s/UUID=//g")
    usbpart3uuid="6234-C863"

    [ ! -h /lib64 ] && sudo ln -s /lib /lib64

    sudo chown -R tc:staff /home/tc

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

    case $ORIGINAL_PLATFORM in

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
    sudo rm -rf /home/tc/latestrploader.sh

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
}
EOF

}

function tcrpentry_juniorusb() {
    
    cat <<EOF
menuentry 'Re-Install DSM of $MODEL ${TARGET_VERSION}-${TARGET_REVISION} Update 0 ${DMPM}, USB' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /zImage-dsm ${USB_LINE} force_junior
        echo Loading initramfs...
        initrd /initrd-dsm
        echo Entering Force Junior (For Re-install DSM, USB)
}
EOF

}

function tcrpentry_juniorsata() {
    
    cat <<EOF
menuentry 'Re-Install DSM of $MODEL ${TARGET_VERSION}-${TARGET_REVISION} Update 0 ${DMPM}, SATA' {
        savedefault
        search --set=root --fs-uuid $usbpart3uuid --hint hd0,msdos3
        echo Loading Linux...
        linux /zImage-dsm ${SATA_LINE} force_junior
        echo Loading initramfs...
        initrd /initrd-dsm
        echo Entering Force Junior (For Re-install DSM, SATA)
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
  rploader.sh ext apollolake-7.0.1-42218 add https://raw.githubusercontent.com/PeterSuh-Q3/rp-ext/master/e1000/rpext-index.json
  or for auto detect use 
  rploader.sh ext apollolake-7.0.1-42218 auto 
  
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

function checkinternet() {

    echo -n "Checking Internet Access -> "
    nslookup github.com 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "Error: No internet found, or github is not accessible"
        exit 99
    fi

}

function gitdownload() {

    git config --global http.sslVerify false   

    if [ -d "/home/tc/redpill-load" ]; then
        echo "Loader sources already downloaded, pulling latest"
        cd /home/tc/redpill-load
        git pull
        cd /home/tc
    else
        git clone -b master "https://github.com/PeterSuh-Q3/redpill-load.git"        
    fi

}

function getstaticmodule() {

    cd /home/tc

    if [ -d /home/tc/custom-module ] && [ -f /home/tc/custom-module/redpill.ko ]; then
        #echo "Found custom redpill module, do you want to use this instead ? [yY/nN] : "
        #readanswer

        #if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
            REDPILL_MOD_NAME="redpill-linux-v$(modinfo /home/tc/custom-module/redpill.ko | grep vermagic | awk '{print $2}').ko"
            cp -vf /home/tc/custom-module/redpill.ko /home/tc/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME}
            strip --strip-debug /home/tc/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME}
            return
        #fi

    fi

    echo "Removing any old redpill.ko modules"
    [ -f /home/tc/redpill.ko ] && rm -f /home/tc/redpill.ko

    extension=$(curl -k -s -L "$redpillextension")

    setplatform

    echo "Looking for redpill for : $SYNOMODEL "

    #release=`echo $extension |  jq -r '.releases .${SYNOMODEL}_{$TARGET_REVISION}'`
    release=$(echo $extension | jq -r -e --arg SYNOMODEL $SYNOMODEL '.releases[$SYNOMODEL]')
    files=$(curl -k -s -L "$release" | jq -r '.files[] .url')

    for file in $files; do
        echo "Getting file $file"
        curl -k -s -O $file
        if [ -f redpill*.tgz ]; then
            echo "Extracting module"
            tar xf redpill*.tgz
            rm redpill*.tgz
            strip --strip-debug redpill.ko
        fi
    done

    if [ -f redpill.ko ] && [ -n $(strings redpill.ko | grep $SYNOMODEL) ]; then
        REDPILL_MOD_NAME="redpill-linux-v$(modinfo redpill.ko | grep vermagic | awk '{print $2}').ko"
        mv /home/tc/redpill.ko /home/tc/redpill-load/ext/rp-lkm/${REDPILL_MOD_NAME}
    else
        echo "Module does not contain platorm information for ${SYNOMODEL}"
        exit 99
    fi

}

function tinyjotfunc() {
    cat <<EOF
function savedefault {
    saved_entry="\${chosen}"
    save_env --file \$prefix/grubenv saved_entry
    echo -e "----------={ M Shell for TinyCore RedPill JOT }=----------"
    echo "TCRP JOT Version : 1.0.2.0"
    echo -e "Running on $(cat /proc/cpuinfo | grep "model name" | awk -F: '{print $2}' | wc -l) Processor $(cat /proc/cpuinfo | grep "model name" | awk -F: '{print $2}' | uniq)"
    echo -e "$(cat /tmp/tempentry.txt | grep earlyprintk | head -1 | sed 's/linux \/zImage/cmdline :/' )"
}    
EOF
}

function checkUserConfig() {

  SN=$(jq -r -e '.extra_cmdline.sn' "$userconfigfile")
  MACADDR1=$(jq -r -e '.extra_cmdline.mac1' "$userconfigfile")
  netif_num=$(jq -r -e '.extra_cmdline.netif_num' $userconfigfile)
  netif_num_cnt=$(cat $userconfigfile | grep \"mac | wc -l)
  
  tz="US"

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
                    
  if [ $netif_num != $netif_num_cnt ]; then
    echo "netif_num = ${netif_num}"
    echo "number of mac addresses = ${netif_num_cnt}"       
    eval "echo \${MSG${tz}38}"
    msgalert "The netif_num and the number of mac addresses do not match. Check user_config.json again. Abort the loader build !!!!!!"
    exit 99
  fi  

}

function buildloader() {

#    tcrppart="$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)3"
    local_cache="/mnt/${tcrppart}/auxfiles"

checkmachine

    [ "$1" == "junmod" ] && JUNLOADER="YES"

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

    if [ "$FROMMYV" = "YES" ]; then
        echo "skip removebundledexts() for called from myv.sh"
    else
        echo "Clean up extension files before building!!!"
        removemodelexts    
    fi    

    [ ! -d /lib64 ] &&  sudo ln -s /lib /lib64
    [ ! -f /lib64/libbz2.so.1 ] && sudo ln -s /usr/local/lib/libbz2.so.1.0.8 /lib64/libbz2.so.1
    [ ! -f /home/tc/redpill-load/user_config.json ] && ln -s /home/tc/user_config.json /home/tc/redpill-load/user_config.json
    [ ! -d cache ] && mkdir -p /home/tc/redpill-load/cache
    cd /home/tc/redpill-load

    #downloadtools
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
    
    if [ "$JUNLOADER" == "YES" ]; then
        echo "jun build option has been specified, so JUN MOD loader will be created"
        # jun's mod must patch using custom.gz from the first partition, so you need to fix the partition.
        sed -i "s/BRP_OUT_P2}\/\${BRP_CUSTOM_RD_NAME/BRP_OUT_P1}\/\${BRP_CUSTOM_RD_NAME/g" /home/tc/redpill-load/build-loader.sh        
        sudo BRP_JUN_MOD=1 BRP_DEBUG=0 BRP_USER_CFG=user_config.json ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${vkersion}
    else
        sudo ./build-loader.sh $MODEL $TARGET_VERSION-$TARGET_REVISION loader.img ${UPPER_ORIGIN_PLATFORM} ${vkersion}
    fi

    [ $? -ne 0 ] && echo "FAILED : Loader creation failed check the output for any errors" && exit 99

    msgnormal "Modify Jot Menu entry"
    tempentry=$(cat /tmp/grub.cfg | head -n 80 | tail -n 20)
    sudo sed -i '61,80d' /tmp/grub.cfg
    echo "$tempentry" > /tmp/tempentry.txt
    
    if [ "$WITHFRIEND" = "YES" ]; then
        echo
    else
        sudo sed -i '31,34d' /tmp/grub.cfg
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
        cp /home/tc/friend/initrd-friend /mnt/${loaderdisk}3/
        cp /home/tc/friend/bzImage-friend /mnt/${loaderdisk}3/
    fi

    USB_LINE="$(grep -A 5 "USB," /tmp/tempentry.txt | grep linux | cut -c 16-999)"
    SATA_LINE="$(grep -A 5 "SATA," /tmp/tempentry.txt | grep linux | cut -c 16-999)"

    if [ "$WITHFRIEND" = "YES" ]; then
        echo "Creating tinycore friend entry"
        tcrpfriendentry | sudo tee --append /tmp/grub.cfg
    else
        echo "Creating tinycore Jot entry"
        echo "$(cat /tmp/tempentry.txt)" | sudo tee --append /tmp/grub.cfg
        echo "Creating tinycore Jot postupdate entry"            
        postupdateentry | sudo tee --append /tmp/grub.cfg
    fi

    echo "Creating tinycore entry"
    tinyentry | sudo tee --append /tmp/grub.cfg

    [ "$WITHFRIEND" = "YES" ] && tcrpentry_juniorusb | sudo tee --append /tmp/grub.cfg && tcrpentry_juniorsata | sudo tee --append /tmp/grub.cfg

    cd /home/tc/redpill-load

    msgnormal "Entries in Localdisk bootloader : "
    echo "======================================================================="
    grep menuentry /tmp/grub.cfg

    ### Updating user_config.json
    updateuserconfigfield "general" "model" "$MODEL"
    updateuserconfigfield "general" "version" "${TARGET_VERSION}-${TARGET_REVISION}"
    updateuserconfigfield "general" "redpillmake" "${redpillmake}"
    updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
    zimghash=$(sha256sum /mnt/${loaderdisk}2/zImage | awk '{print $1}')
    updateuserconfigfield "general" "zimghash" "$zimghash"
    rdhash=$(sha256sum /mnt/${loaderdisk}2/rd.gz | awk '{print $1}')
    updateuserconfigfield "general" "rdhash" "$rdhash"

    if [ ${ORIGIN_PLATFORM} = "geminilake" ] || [ ${ORIGIN_PLATFORM} = "v1000" ] || [ ${ORIGIN_PLATFORM} = "r1000" ]; then
        echo "add modprobe.blacklist=mpt3sas for Device-tree based platforms"
        USB_LINE="${USB_LINE} modprobe.blacklist=mpt3sas "
        SATA_LINE="${SATA_LINE} modprobe.blacklist=mpt3sas "
    fi

    if [ "${CPU}" == "AMD" ]; then
        echo "Add configuration disable_mtrr_trim for AMD"
        USB_LINE="${USB_LINE} disable_mtrr_trim=1 "
        SATA_LINE="${SATA_LINE} disable_mtrr_trim=1 "
    else
        if [ ${ORIGIN_PLATFORM} = "geminilake" ] || [ ${ORIGIN_PLATFORM} = "epyc7002" ] || [ ${ORIGIN_PLATFORM} = "apollolake" ]; then
            if [ "$MACHINE" != "VIRTUAL" ]; then
                DISABLEI915=$(jq -r -e '.general.disablei915' "$userconfigfile")
                if [ "${DISABLEI915}" = "ON" ]; then
                    echo "Add configuration i915.modeset=0 for INTEL i915"
                    USB_LINE="${USB_LINE} i915.modeset=0 "
                    SATA_LINE="${SATA_LINE} i915.modeset=0 "
                fi
            fi  
        fi    

        if [ -d "/home/tc/redpill-load/custom/extensions/nvmesystem" ]; then
            echo "Add configuration pci=nommconf for nvmesystem addon"
            USB_LINE="${USB_LINE} pci=nommconf "
            SATA_LINE="${SATA_LINE} pci=nommconf "
        fi
    fi
    
    msgwarning "Updated user_config with USB Command Line : $USB_LINE"
    json=$(jq --arg var "${USB_LINE}" '.general.usb_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile
    msgwarning "Updated user_config with SATA Command Line : $SATA_LINE"
    json=$(jq --arg var "${SATA_LINE}" '.general.sata_line = $var' $userconfigfile) && echo -E "${json}" | jq . >$userconfigfile

    cp $userconfigfile /mnt/${loaderdisk}3/

    # Share RD of friend kernel with JOT 2023.05.01
    cp /mnt/${loaderdisk}1/zImage /mnt/${loaderdisk}3/zImage-dsm

    # Repack custom.gz including /usr/lib/modules and /usr/lib/firmware in all_modules 2024.02.18
    # Compining rd.gz and custom.gz
    
    [ ! -d /home/tc/rd.temp ] && mkdir /home/tc/rd.temp
    [ -d /home/tc/rd.temp ] && cd /home/tc/rd.temp
    RD_COMPRESSED=$(cat /home/tc/redpill-load/config/$MODEL/${TARGET_VERSION}-${TARGET_REVISION}/config.json | jq -r -e ' .extra .compress_rd')

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
    
    if [ "$RD_COMPRESSED" = "false" ]; then
        echo "Ramdisk in not compressed "
        (cd /home/tc/rd.temp && sudo find . | sudo cpio -o -H newc -R root:root >/mnt/${loaderdisk}3/initrd-dsm) >/dev/null
    else
        echo "Ramdisk in compressed "            
        (cd /home/tc/rd.temp && sudo find . | sudo cpio -o -H newc -R root:root | xz -9 --format=lzma >/mnt/${loaderdisk}3/initrd-dsm) >/dev/null
    fi

    if [ "$WITHFRIEND" = "YES" ]; then
        msgnormal "Setting default boot entry to TCRP Friend"
        sudo sed -i "/set default=\"*\"/cset default=\"0\"" /tmp/grub.cfg
    else
        echo
        if [ "$MACHINE" = "VIRTUAL" ]; then
            msgnormal "Setting default boot entry to JOT SATA"
            sudo sed -i "/set default=\"*\"/cset default=\"1\"" /tmp/grub.cfg
        fi
    fi
    sudo cp -vf /tmp/grub.cfg /mnt/${loaderdisk}1/boot/grub/grub.cfg
st "gen grub     " "Gen GRUB entries" "Finished Gen GRUB entries : ${MODEL}"

    [ -f /mnt/${loaderdisk}3/loader72.img ] && rm /mnt/${loaderdisk}3/loader72.img
    [ -f /mnt/${loaderdisk}3/grub72.cfg ] && rm /mnt/${loaderdisk}3/grub72.cfg
    [ -f /mnt/${loaderdisk}3/initrd-dsm72 ] && rm /mnt/${loaderdisk}3/initrd-dsm72

    sudo rm -rf /home/tc/rd.temp /home/tc/friend /home/tc/cache/*.pat
    
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
        cp -vf ${patfile} ${local_cache} && rm -vf /home/tc/redpill-load/cache/*.pat
    fi
st "cachingpat" "Caching pat file" "Cached file to: ${local_cache}"

}

function curlfriend() {

    msgwarning "Download failed from ${domain}..."
    curl -kLO# "https://${domain}/PeterSuh-Q3/tcrpfriend/main/chksum" \
    -O "https://${domain}/PeterSuh-Q3/tcrpfriend/main/bzImage-friend" \
    -O "https://${domain}/PeterSuh-Q3/tcrpfriend/main/initrd-friend"
    if [ $? -ne 0 ]; then
        msgalert "Download failed from ${domain}... !!!!!!!!"
    else
        msgnormal "Bringing over my friend from ${domain} Done!!!!!!!!!!!!!!"            
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
  if [ ! -f chksum ]; then
    URL="https://raw.githubusercontent.com/PeterSuh-Q3/tcrpfriend/main/chksum"
    [ -n "$URL" ] && curl --connect-timeout 5 -s -k -L $URL -O
  fi

  if [ -f chksum ]; then
    FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
    BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
    INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
    if [ "$(sha256sum /mnt/${tcrppart}/bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum /mnt/${tcrppart}/initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ]; then
        msgnormal "OK, latest \n"
    else
        msgwarning "Found new version, bringing over new friend version : $FRIENDVERSION \n"

        domain="raw.githubusercontent.com"
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

function kernelprepare() {

    export ARCH=x86_64

    cd /home/tc/linux-kernel
    cp synoconfigs/${TARGET_PLATFORM} .config
    if [ ${TARGET_PLATFORM} = "apollolake" ] || [ ${TARGET_PLATFORM} = "ds918p" ]; then
        echo '+' >.scmversion
    fi

    if [ ${TARGET_PLATFORM} = "bromolow" ] || [ ${TARGET_PLATFORM} = "ds3615xs" ]; then

        cat <<EOF >patch-reloc
--- arch/x86/tools/relocs.c
+++ arch/x86/tools/relocs.b
@@ -692,7 +692,7 @@
*
*/
static int per_cpu_shndx       = -1;
-Elf_Addr per_cpu_load_addr;
+static Elf_Addr per_cpu_load_addr;

static void percpu_init(void)
{
EOF

        if ! patch -R -p0 -s -f --dry-run <patch-reloc; then
            patch -p0 <patch-reloc
        fi

    fi

    make oldconfig
    make headers_install
    make modules_prepare

}

function getlatestrploader() {

    echo -n "Checking if a newer version exists on the $build repo -> "

    curl -ksL "$rploaderfile" -o latestrploader.sh
    curl -ksL "$modalias3" -o modules.alias.3.json.gz
    [ -f modules.alias.3.json.gz ] && gunzip -f modules.alias.3.json.gz
    curl -ksL "$modalias4" -o modules.alias.4.json.gz
    [ -f modules.alias.4.json.gz ] && gunzip -f modules.alias.4.json.gz

    CURRENTSHA="$(sha256sum rploader.sh | awk '{print $1}')"
    REPOSHA="$(sha256sum latestrploader.sh | awk '{print $1}')"

    if [ -f latestrploader.sh ] && [ "${CURRENTSHA}" != "${REPOSHA}" ]; then
        echo "Found newversion : $(bash ./latestrploader.sh version now)"
        echo "Current version : $(bash ./rploader.sh version now)"
        echo -n "There is a newer version of the script on the repo should we use that ? [yY/nN]"
        read confirmation
        if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
            echo "OK, updating, please re-run after updating"
            cp -f /home/tc/latestrploader.sh /home/tc/rploader.sh
            rm -f /home/tc/latestrploader.sh
#            loaderdisk=$(mount | grep -i optional | grep cde | awk -F / '{print $3}' | uniq | cut -c 1-3)
            echo "Updating tinycore loader with latest updates"
            #cleanloader
            filetool.sh -b ${loaderdisk}3
            exit
        else
            rm -f /home/tc/latestrploader.sh
            return
        fi
    else
        echo "Version is current"
        rm -f /home/tc/latestrploader.sh
    fi

}

function synctime() {

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

function getmodulealiasjson() {

    echo "{"
    echo "\"modules\" : ["

    for module in $(ls *.ko); do
        if [ $(modinfo ./$module --field alias | grep -ie pci -ie usb | wc -l) -ge 1 ]; then
            for alias in $(modinfo ./$module --field alias | grep -ie pci -ie usb); do
                echo "{"
                echo "\"name\" :  \"${module}\"",
                echo "\"alias\" :  \"${alias}\""
                echo "}",
            done
        fi
        #       echo "},"
    done | sed '$ s/,//'

    echo "]"
    echo "}"

    #
    # To query alias for module run #cat n | jq '.modules[] | select(.alias | test ("8086d00001000")?) .name'
    # or cat modules.alias.json | jq '.modules[] | select(.alias | test("(?i)1000d00000030")?) |  .name'
    #
    #

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

function listextension() {

    if [ ! -f rpext-index.json ]; then
        curl -k -# -L "${modextention}" -o rpext-index.json
    fi

    ## Get extension author rpext-index.json and then parse for extension download with :
    #       jq '. | select(.id | contains("vxge")) .url  ' rpext-index.json

    if [ ! -z $1 ]; then
        echo "Searching for matching extension for $1"
        matchingextension=($(jq ". | select(.id | endswith(\"${1}\")) .url  " rpext-index.json))

        if [ ! -z $matchingextension ]; then
            echo "Found matching extension : "
            echo $matchingextension
            ./redpill-load/ext-manager.sh add "${matchingextension//\"/}"
        fi

        extensionslist+="${matchingextension} "
        echo $extensionslist

#m shell only
        #def
        if [ 1 = 0 ]; then
        echo "Target Platform : ${TARGET_PLATFORM}"
        if [ "${TARGET_PLATFORM}" = "broadwellnk" ] || [ "${TARGET_PLATFORM}" = "rs4021xsp" ] || [ "${TARGET_PLATFORM}" = "ds1621xsp" ]; then
            if [ -d /home/tc/redpill-load/custom/extensions/PeterSuh-Q3.ixgbe ]; then
                echo "Removing : PeterSuh-Q3.ixgbe"
                echo "Reason : The Broadwellnk platform has a vanilla.ixgbe ext driver built into the DSM, so they conflict with each other if ixgbe is added separately."
                sudo rm -rf /home/tc/redpill-load/custom/extensions/PeterSuh-Q3.ixgbe
            fi
        fi
        #def
        fi
        
    else
        echo "No matching extension"
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
        v="5"
    else
        v=""
    fi

    if [ "${offline}" = "NO" ]; then
        echo "Downloading ${ORIGIN_PLATFORM} ${KVER}+ redpill.ko ..."    
        LATESTURL="`curl --connect-timeout 5 -skL -w %{url_effective} -o /dev/null "${PROXY}https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/latest"`"
        if [ $? -ne 0 ]; then
            echo "Error downloading last version of ${ORIGIN_PLATFORM} ${KVER}+ rp-lkms.zip tring other path..."
            curl -skL https://raw.githubusercontent.com/PeterSuh-Q3/redpill-lkm${v}/master/rp-lkms.zip -o /mnt/${tcrppart}/rp-lkms${v}.zip
            if [ $? -ne 0 ]; then
                echo "Error downloading https://raw.githubusercontent.com/PeterSuh-Q3/redpill-lkm${v}/master/rp-lkms${v}.zip"
                exit 99
            fi    
        else
            TAG="${LATESTURL##*/}"
            echo "TAG is ${TAG}"        
            STATUS=`curl --connect-timeout 5 -skL -w "%{http_code}" "${PROXY}https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/download/${TAG}/rp-lkms.zip" -o "/mnt/${tcrppart}/rp-lkms${v}.zip"`
        fi
    else
        echo "Unzipping ${ORIGIN_PLATFORM} ${KVER}+ redpill.ko ..."        
    fi    

    sudo rm -f /home/tc/custom-module/*.gz
    sudo rm -f /home/tc/custom-module/*.ko
    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then    
        unzip /mnt/${tcrppart}/rp-lkms${v}.zip        rp-${ORIGIN_PLATFORM}-${DSMVER}-${KVER}-prod.ko.gz -d /tmp >/dev/null 2>&1
        gunzip -f /tmp/rp-${ORIGIN_PLATFORM}-${DSMVER}-${KVER}-prod.ko.gz >/dev/null 2>&1
        cp -vf /tmp/rp-${ORIGIN_PLATFORM}-${DSMVER}-${KVER}-prod.ko /home/tc/custom-module/redpill.ko
    else    
        unzip /mnt/${tcrppart}/rp-lkms${v}.zip        rp-${ORIGIN_PLATFORM}-${KVER}-prod.ko.gz -d /tmp >/dev/null 2>&1
        gunzip -f /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-prod.ko.gz >/dev/null 2>&1
        cp -vf /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-prod.ko /home/tc/custom-module/redpill.ko
    fi

}

if [ $# -lt 2 ]; then
    syntaxcheck $@
fi

if [ -z "$GATEWAY_INTERFACE" ]; then

    loaderdisk=""
    for edisk in $(sudo fdisk -l | grep "Disk /dev/sd" | awk '{print $2}' | sed 's/://' ); do
        if [ $(sudo fdisk -l | grep "83 Linux" | grep ${edisk} | wc -l ) -eq 3 ]; then
            loaderdisk="$(blkid | grep ${edisk} | grep "6234-C863" | cut -c 1-8 | awk -F\/ '{print $3}')"    
        fi    
    done
    if [ -z "${loaderdisk}" ]; then
        for edisk in $(sudo fdisk -l | grep -e "Disk /dev/nvme" -e "Disk /dev/mmc" | awk '{print $2}' | sed 's/://' ); do
            if [ $(sudo fdisk -l | grep "83 Linux" | grep ${edisk} | wc -l ) -eq 3 ]; then
                loaderdisk="$(blkid | grep ${edisk} | grep "6234-C863" | cut -c 1-12 | awk -F\/ '{print $3}')"
            fi    
        done
    fi

    if [ -z "${loaderdisk}" ]; then
        echo "Not Supported Loader BUS Type, program Exit!!!"
        exit 99
    fi
    
    getBus "${loaderdisk}" 
    echo -ne "Loader BUS: $(msgnormal "${BUS}")\n"

    [ "${BUS}" = "nvme" ] && loaderdisk="${loaderdisk}p"
    [ "${BUS}" = "mmc"  ] && loaderdisk="${loaderdisk}p"

    tcrppart="${loaderdisk}3"
    tcrpdisk=$loaderdisk

    case $1 in

    download)
        getvars $2
        checkinternet
        gitdownload
        ;;

    build)

        getvars $2
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

echo "$3"
echo "$4"
        [ "$3" = "withfriend" ] && echo "withfriend option set, My friend will be added" && WITHFRIEND="YES"

        [ "$4" = "frmyv" ] && echo "called from myv.sh option set, From Myv will be added" && FROMMYV="YES"

        [ "$4" = "makeimg" ] && echo "makeimg option set, keep loader.img for 7.2" && MAKEIMG="YES"

        case $3 in

        manual)

            echo "Using static compiled redpill extension"
            getstaticmodule
            echo "Got $REDPILL_MOD_NAME "
            echo "Manual extension handling,skipping extension auto detection "
            echo "Starting loader creation "
            buildloader
            [ $? -eq 0 ] && savesession
            ;;

        jun)
            echo "Using static compiled redpill extension"
            getstaticmodule
            echo "Got $REDPILL_MOD_NAME "
            listmodules
            echo "Starting loader creation "
            buildloader junmod
            [ $? -eq 0 ] && savesession
            ;;

        static | *)
            echo "No extra build option or static specified, using default <static> "
            echo "Using static compiled redpill extension"
            getstaticmodule
            echo "Got $REDPILL_MOD_NAME "
            listmodules
            echo "Starting loader creation "
            buildloader
            [ $? -eq 0 ] && savesession
            ;;

        esac

        ;;

    \
        ext)
        getvars $2
        checkinternet
        gitdownload

        if [ "$3" = "auto" ]; then
            listmodules
        else
            ext_manager $@ # instead of listmodules
        fi
        ;;

    restoresession)
        getvars $2
        checkinternet
        gitdownload
        restoresession
        ;;

    clean)
        cleanloader
        ;;

#    update)
#        checkinternet
#        getlatestrploader
#        ;;

    listmods)
        getvars $2
        checkinternet
        gitdownload
        listmodules
        echo "$extensionslist"
        ;;

    serialgen)
        serialgen $@
        ;;

    interactive)
        if [ -f interactive.sh ]; then
            . ./interactive.sh
        else
            curl -kL -# "https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/$build/interactive.sh" -o interactive.sh
            . ./interactive.sh
            exit 99
        fi
        ;;

    identifyusb)
        usbidentify
        ;;

    patchdtc)
        getvars $2
        checkinternet
        patchdtc
        ;;

    satamap)
        satamap $2
        ;;

    backup)
        backup
        ;;

    backuploader)
        backuploader
        ;;

    restoreloader)
        restoreloader
        ;;
    postupdate)
        getvars $2
        checkinternet
        gitdownload
        getstaticmodule
        postupdate
        [ $? -eq 0 ] && savesession
        ;;

    mountdsmroot)
        mountdsmroot
        ;;
#    fullupgrade)
#        fullupgrade
#        ;;

    mountshare)
        mountshare
        ;;
    installapache)
        installapache
        ;;
    version)
        version $@
        ;;
    help)
        showhelp
        exit 99
        ;;
    monitor)
        monitor
        exit 0
        ;;
    getgrubconf)
        getgrubconf
        exit 0
        ;;
    bringfriend)
        bringfriend
        exit 0
        ;;
    removefriend)
        removefriend
        exit 0
        ;;
    downloadupgradepat)
        downloadupgradepat
        exit 0
        ;;
    *)
        showsyntax
        exit 99
        ;;

    esac

else

    htmlstart

fi
