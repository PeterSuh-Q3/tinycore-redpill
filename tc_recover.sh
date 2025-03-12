#!/bin/bash

loaderdisk=$(/sbin/blkid | grep "6234-C863" | cut -d ':' -f1 | sed 's/p\?3//g' | awk -F/ '{print $NF}' | head -n 1)
echo "LOADER DISK: $loaderdisk"
tcrppart="${loaderdisk}3"

sudo curl -kL https://github.com/PeterSuh-Q3/tinycore-redpill/raw/refs/heads/main/mydata.tgz -o /mnt/${tcrppart}/mydata.tgz

echo "A reboot is required. Press any key to reboot..."
read -n 1 -s  # Wait for a key press
    
sudo reboot
