#!/bin/bash

set -u # Unbound variable errors are not allowed

##### INCLUDES ######################################################################################
. /home/tc/functions.sh
#####################################################################################################

function check_internet() {
  ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1
  return $?
}

function gitclone() {
    git clone -b master --single-branch --depth=1 https://github.com/PeterSuh-Q3/redpill-load.git
}

function gitdownload() {

    cd /home/tc
    git config --global http.sslVerify false    
    if [ -d /home/tc/redpill-load ]; then
        echo "Loader sources already downloaded, pulling latest"
        cd /home/tc/redpill-load
        git pull
        if [ $? -ne 0 ]; then
           cd /home/tc
           rploader clean
           gitclone    
        fi   
        cd /home/tc
    else
        gitclone
    fi
    
}

function mmc_modprobe() {
  echo "excute modprobe for mmc(include sd)..."
  sudo /sbin/modprobe mmc_block
  sudo /sbin/modprobe mmc_core
  sudo /sbin/modprobe rtsx_pci
  sudo /sbin/modprobe rtsx_pci_sdmmc
  sudo /sbin/modprobe sdhci
  sudo /sbin/modprobe sdhci_pci
  sleep 1
  if [ `/sbin/lsmod |grep -i mmc|wc -l` -gt 0 ] ; then
      echo "Module mmc loaded succesfully!!!"
  else
      echo "Module mmc failed to load successfully!!!"
  fi
}

if [ $(/sbin/blkid | grep "6234-C863" | wc -l) -ge 2 ]; then
    echo "There is two more bootloder exists, program Exit!!!"
    read answer
    exit 99
fi

mmc_modprobe

getloaderdisk

if [ -z "${loaderdisk}" ]; then
    echo "Not Supported Loader BUS Type, program Exit!!!"
    read answer
    exit 99
fi

getBus "${loaderdisk}" 

tcrppart="${loaderdisk}3"

if [ -d /mnt/${tcrppart}/redpill-load/ ] && [ -d /mnt/${tcrppart}/tcrp-addons/ ] && [ -d /mnt/${tcrppart}/tcrp-modules/ ]; then
    echo "Repositories for offline loader building have been confirmed. Copy the repositories to the required location..."
    echo "Press any key to continue..."    
    read answer
    cp -rf /mnt/${tcrppart}/redpill-load/ ~/
    mv -f /mnt/${tcrppart}/tcrp-addons/ /dev/shm/
    mv -f /mnt/${tcrppart}/tcrp-modules/ /dev/shm/
    echo "Go directly to the menu. Press any key to continue..."
    read answer
else
    while true; do
      if check_internet; then
        getlatestmshell "noask"
        break
      fi
      sleep 5
      echo "Waiting for internet connection in menu.sh..."
    done
    gitdownload
fi

if [ -z "${1-}" ]; then
  [ -f /tmp/test_mode ] && rm /tmp/test_mode
else
  touch /tmp/test_mode
fi

if [ -d /mnt/${tcrppart}/redpill-load/ ]; then
    offline="YES"
else
    offline="NO"
fi  

if [ "${offline}" = "NO" ]; then
    curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/models.json
    if [ -f /tmp/test_mode ]; then
      cecho g "###############################  This is Test Mode  ############################"
      curl -skL# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/functions_t.sh -o functions.sh
      chmod +x /home/tc/redpill-load/*.sh
      /bin/cp -vf /home/tc/redpill-load/build-loader_t.sh /home/tc/redpill-load/build-loader.sh
    else
      curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/functions.sh
    fi
fi

/home/tc/menu_m.sh
exit 0
