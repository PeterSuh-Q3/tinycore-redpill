#!/bin/sh

REAL_DEV=/dev/ttyUSB0
ALIAS_DEV=/dev/ttyS0
BAUD=115200

case $1 in
    start)
        # 1) 커널 모듈 로드 (FTDI는 DSM 네이티브 내장)
        # insmod 불필요한 경우가 많으나 명시적으로 로드
        insmod /lib/modules/usbserial.ko  2>/dev/null
        insmod /lib/modules/ftdi_sio.ko   2>/dev/null
        # pl2303.ko / cp210x.ko / ch341.ko 불필요
        sleep 2  # FTDI는 인식 빠르므로 3→2초로 단축

        # 2) ttyUSB0 인식 확인
        if [ ! -e ${REAL_DEV} ]; then
            echo "ERROR: ${REAL_DEV} not found" > /dev/kmsg
            exit 1
        fi
        chmod 666 ${REAL_DEV}

        # 3) ttyS0 점유 여부 확인 후 처리
        if fuser ${ALIAS_DEV} > /dev/null 2>&1; then
            echo "ttyS0 busy, using socat PTY bridge" > /dev/kmsg
            mv ${ALIAS_DEV} ${ALIAS_DEV}.orig 2>/dev/null
            socat PTY,link=${ALIAS_DEV},raw,echo=0,mode=666 \
                  ${REAL_DEV},b${BAUD},raw,echo=0 &
            echo $! > /var/run/socat-serial.pid
        else
            echo "ttyS0 free, creating symlink" > /dev/kmsg
            rm -f ${ALIAS_DEV}
            ln -sf ${REAL_DEV} ${ALIAS_DEV}
        fi

        # 4) stty 파라미터 적용 (FTDI는 stty 정상 동작)
        stty -F ${REAL_DEV} ${BAUD} cs8 -cstopb -parenb -crtscts raw 2>/dev/null

        echo "Serial bridge ready: ${ALIAS_DEV} -> ${REAL_DEV}" > /dev/kmsg

        # 5) 상태 출력
        echo "=== Module ===" && lsmod | grep -E 'usbserial|ftdi_sio'
        echo "=== Device ===" && ls -la /dev/ttyUSB0 /dev/ttyS0 2>/dev/null
        echo "=== Kernel log ===" && dmesg | grep -E 'ftdi|ttyUSB|Serial bridge' | tail -5
        echo "=== socat ===" && ps | grep socat | grep -v grep
        ;;

    stop)
        if [ -f /var/run/socat-serial.pid ]; then
            kill $(cat /var/run/socat-serial.pid) 2>/dev/null
            rm /var/run/socat-serial.pid
        fi
        rm -f ${ALIAS_DEV}
        mv ${ALIAS_DEV}.orig ${ALIAS_DEV} 2>/dev/null
        # FTDI 모듈 언로드
        rmmod ftdi_sio usbserial 2>/dev/null
        ;;
esac
