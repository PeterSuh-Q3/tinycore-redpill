#!/bin/bash

set -u # Unbound variable errors are not allowed

##### INCLUDES ######################################################################################
. /home/tc/functions.sh
#####################################################################################################


# lock
#exec 304>"/tmp/menu.lock"
#flock -n 304 || {
#  MSG="The menu.sh instance is already running in another terminal. To avoid conflicts, please operate in one instance only."
#  dialog --colors --aspect 50 --title "$(TEXT "Error")" --msgbox "${MSG}" 0 0
#  exit 1
#}
#trap 'flock -u 304; rm -f "/tmp/menu.lock"' EXIT INT TERM HUP


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
    if [ $(/sbin/blkid | grep "1234-5678" | wc -l) -eq 1 ]; then
        echo "There is Synodisk Injected Bootloader..."
    else
        echo "There is two more bootloder exists, program Exit!!!"
        read answer
        exit 99
    fi    
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

if [ -d /mnt/${tcrppart}/tcrp-addons/ ] && [ -d /mnt/${tcrppart}/tcrp-modules/ ]; then
    echo "Repositories for offline loader building have been confirmed. Copy the repositories to the required location..."
    echo "Press any key to continue..."    
    read answer
    cp -rf /mnt/${tcrppart}/redpill-load/ ~/
    mv -f /mnt/${tcrppart}/tcrp-addons/ /dev/shm/
    mv -f /mnt/${tcrppart}/tcrp-modules/ /dev/shm/
    echo "Go directly to the menu. Press any key to continue..."
    read answer
else
    # Record the start time.
    start_time=$(date +%s)
    while true; do
      if check_internet; then
        getlatestmshell "noask"
        break
      fi
      # Calculate the elapsed time and exit the loop if it exceeds 15 seconds.
      current_time=$(date +%s)
      elapsed=$(( current_time - start_time ))
      if [ $elapsed -ge 30 ]; then
        echo "Internet connection wait time exceeded 30 seconds"
        break
      fi
      sleep 2
      echo "Waiting for internet connection by checking 8.8.8.8 (Google DNS)..."
    done
    echo -n "Checking GitHub Access -> "
    curl --insecure -L -s https://raw.githubusercontent.com/about.html -O 2>&1 >/dev/null
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "Error: GitHub is unavailable. Please try again later."
        read answer
        exit 99
    fi
    gitdownload
fi

if [ -z "${1-}" ]; then
  [ -f /tmp/test_mode ] && rm /tmp/test_mode
else
  touch /tmp/test_mode
fi

if [ -d /dev/shm/tcrp-modules/ ]; then
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
      /bin/cp -vf /home/tc/redpill-load/config/pats_t.json /home/tc/redpill-load/config/pats.json
    else
      curl -skLO# https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/master/functions.sh
    fi
fi

/home/tc/menu_m.sh
exit 0
