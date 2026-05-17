#!/bin/sh

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

cecho yellow "Proceed with remote upgrade of the loader of TCRP-mshell..."
echo
cecho green "Mounting synoboot partitions..."
echo
[ ! -d /mnt/p1 ] &&  mkdir /mnt/p1
[ ! -d /mnt/p2 ] &&  mkdir /mnt/p2
[ ! -d /mnt/p3 ] &&  mkdir /mnt/p3

cd /dev/
mount -o loop /dev/synoboot1 /mnt/p1
mount -o loop /dev/synoboot2 /mnt/p2
mount -o loop /dev/synoboot3 /mnt/p3
#mount -t vfat synoboot1 /mnt/p1
#mount -t vfat synoboot2 /mnt/p2
#mount -t vfat synoboot3 /mnt/p3

cecho yellow "Unzip the updatepack and upgrade the synoboot loader partition..."
echo
tar --no-same-owner --touch -zxvf /volume*/homes/admin/remote.updatepack.*.tgz -C /mnt

cd /mnt
umount /mnt/p1
umount /mnt/p2
umount /mnt/p3

cecho green "Unmounting of the synoboot partition was successful. Please reboot to apply the upgraded loader..."
echo
