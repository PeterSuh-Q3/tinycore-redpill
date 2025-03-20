#!/bin/bash

os-detect() {
    os=$(uname -s)
    if [ "$os" == "Linux" ]; then
        distro=$(awk -F= '$1=="ID" { print $2 }' /etc/os-release)
        if [ "$distro" == "arch" ]; then
            echo "Arch Linux detected"
            pacman -S smartmontools
        elif [ "$distro" == "centos" ]; then
            echo "CentOS detected"
            yum install smartmontools
        elif [ "$distro" == "debian" ] || [ "$distro" == "ubuntu" ]; then
            echo "debian/ubuntu detected"
            apt install smartmontools
        elif [ "$distro" == "gentoo" ]; then
            echo "gentoo detected"
            emerge smartmontools
	elif [ "$distro" == "tinycore" ]; then
            echo "tinycore detected"
	    tce-load -wi smartmontools
        else
            echo "Unknown Linux distribution detected"
        fi
    elif [ "$os" == "Darwin" ]; then
        echo "MacOS detected"
        brew install smartmontools
    else
        echo "Unsupported OS detected"
    fi
}

init() {
    for devtree in /dev/disk[0-9]
    do
        if [ "$(uname -s)" == "Darwin" ]; then
            diskutil list | grep -E '/dev/disk[0-9]' | grep physical | awk '{ print $1 }' | while read device; do
                smartctl --smart=on ${device} > /dev/null 2>&1
            done
        else
            smartctl --smart=on ${devtree} > /dev/null 2>&1
        fi
    done
}

run() {
    if [ "$(uname -s)" == "Darwin" ]; then
        diskutil list | grep -E '/dev/disk[0-9]' | grep physical | awk '{ print $1 }' | while read device; do
          protocol=$(diskutil info ${device} | grep "Protocol:" | awk '{ print $2 }')

          if [ "$protocol" == "PCI-Express" ]; then
 	    echo -e "\r\n${device} NVMe 디스크 S.M.A.R.T 정보"
            smartctl -a ${device} | grep "Model Number" | awk -F : '{ print "NVMe 모델 : "$2 }'
            smartctl -a ${device} | grep "Serial Number" | awk -F : '{ print "NVMe 시리얼넘버 : "$2}'
            smartctl -a ${device} | grep "Firmware Version:" | awk -F [ '{ print "NVMe 펌웨어 버전 : "$2}'
            smartctl -a ${device} | grep "Total NVM Capacity" | awk -F [ '{ print "NVMe 용량 :               ["$2}'
            smartctl -a ${device} | grep "Temperature:" | awk '{ print "NVMe 온도 :                  ("$2" 도)"}'
	    smartctl -a ${device} | grep "Power Cycles:" | awk -F : '{ print "NVMe 사용 횟수 : "$2" 회"}'
	    smartctl -a ${device} | grep "Power On Hours:" | awk -F : '{ print "NVMe 사용 시간 : "$2" 시간"}'
	    smartctl -a ${device} | grep "Unsafe Shutdowns:" | awk -F : '{ print "NVMe 불안정 종료횟수 : "$2" 회"}'
          elif [ "$protocol" == "SATA" ]; then
            echo -e "\r\n${device} SATA 디스크 S.M.A.R.T 정보"
            smartctl -a ${device} | grep "Device Model" | awk -F : '{ print "디스크 모델 : "$2 }'
            smartctl -a ${device} | grep "Serial Number" | awk -F : '{ print "디스크 시리얼넘버 : "$2}'
            smartctl -a ${device} | grep "User Capacity" | awk -F [ '{ print "디스크 용량 : ["$2}'
            smartctl -a ${device} | grep Reallocated_Sector_Ct | awk '{ print "디스크섹터 문제("$2") : "$10 }'
            smartctl -a ${device} | grep Current_Pending_Sector | awk '{ print "불안정한 색터 수("$2") : "$10 }'
	    smartctl -a ${device} | grep "Power_Cycle_Count" | awk '{ print "사용 횟수("$2") : "$10 }'
	    smartctl -a ${device} | grep "Power_On_Hours" | awk '{ print "사용 시간("$2") : "$10 }'
	    smartctl -a ${device} | grep "174 Unsafe_Shutdown_Count" | awk '{ print "불안정 종료횟수("$2") : "$10 }'
          fi
        done
    else

        for device in /dev/nvme[0-9]n[0-9]
        do
            echo -e "\r\n${device} NVMe 디스크 S.M.A.R.T 정보"
            smartctl -a ${device} | grep "Model Number" | awk -F : '{ print "NVMe 모델 : "$2 }'
            smartctl -a ${device} | grep "Serial Number" | awk -F : '{ print "NVMe 시리얼넘버 : "$2}'
            smartctl -a ${device} | grep "Firmware Version:" | awk -F [ '{ print "NVMe 펌웨어 버전 : "$2}'
            smartctl -a ${device} | grep "Total NVM Capacity" | awk -F [ '{ print "NVMe 용량 :                 ["$2}'
            smartctl -a ${device} | grep "Temperature:" | awk '{ print "NVMe 온도 :                  ("$2" 도)"}'
	    smartctl -a ${device} | grep "Power Cycles:" | awk -F : '{ print "NVMe 사용 횟수 : "$2" 회"}'
	    smartctl -a ${device} | grep "Power On Hours:" | awk -F : '{ print "NVMe 사용 시간 : "$2" 시간"}'
	    smartctl -a ${device} | grep "Unsafe Shutdowns:" | awk -F : '{ print "NVMe 불안정 종료횟수 : "$2" 회"}'
        done

        for device in /dev/sd[a-z]
        do
            echo -e "\r\n${device} 하드디스크 S.M.A.R.T 정보"
            smartctl -a ${device} | grep "Device Model" | awk -F : '{ print "하드디스크 모델 : "$2 }'
            smartctl -a ${device} | grep "Serial Number" | awk -F : '{ print "하드디스크 시리얼넘버 : "$2}'
            smartctl -a ${device} | grep "User Capacity" | awk -F [ '{ print "하드디스크 용량 : ["$2}'
            smartctl -a ${device} | grep Temperature_Celsius | awk '{ print "하드디스크 온도("$2") : "$10 }'
            smartctl -a ${device} | grep Raw_Read_Error_Rate | awk '{ print "물리적인 충격 수("$2") : "$10 }'
            smartctl -a ${device} | grep Reallocated_Sector_Ct | awk '{ print "섹터 문제("$2") : "$10 }'
            smartctl -a ${device} | grep Seek_Error_Rate | awk '{ print "탐색 오류("$2") : "$10 }'
            smartctl -a ${device} | grep Spin_Retry_Count | awk '{ print "최대 RPM까지 회전 시도 수("$2") : "$10 }'
            smartctl -a ${device} | grep Current_Pending_Sector | awk '{ print "불안정한 색터 수("$2") : "$10 }'
            smartctl -a ${device} | grep Offline_Uncorrectable | awk '{ print "배드섹터 수("$2") : "$10 }'
            smartctl -a ${device} | grep UDMA_CRC_Error_Count | awk '{ print "전송과정 문제, 케이블, 포트 문제 등 ("$2") : "$10 }'
        done
    fi
}

if [ "$(whereis smartctl | awk '{ print $2}')" == "" ] 
then
    os-detect
else
    init
    run
fi
