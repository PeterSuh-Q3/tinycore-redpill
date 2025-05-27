#!/bin/bash

for edisk in $(fdisk -l | grep -e "Disk /dev/sd" -e "Disk /dev/nv" | awk '{print $2}' | sed 's/://' ); do
    model=$(lsblk -o PATH,MODEL | grep $edisk | head -1)
    echo
    echo
    if [ $(fdisk -l | grep "83 Linux" | grep ${edisk} | wc -l ) -gt 0 ]; then
        echo "Skip this disk as it is a loader disk. $model"
        continue
    else
        echo "Erase Disk. $model"
        while true; do
            read -r -p "Can I really erase this disk $edisk? (yY/nN) : " answer
            case $answer in
                [Yy]* ) dd if=/dev/zero of=${edisk} bs=1k count=1; blockdev --rereadpt ${edisk}; echo "Disk Erase Complete. $edisk"; break;;
                [Nn]* ) echo "Cancel Erase Disk. $edisk"; break;;
                * ) echo "Please answer y or Y or n or N";;
            esac
        done
    fi    
done
