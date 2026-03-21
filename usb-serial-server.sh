#!/bin/sh

REAL_DEV=/dev/ttyUSB0
ALIAS_DEV=/dev/ttyS0
BAUD=115200

case $1 in
    start)
        # 1) 커널 모듈 로드
        insmod /lib/modules/usbserial.ko  2>/dev/null
        insmod /lib/modules/cp210x.ko     2>/dev/null  # 또는 ch341.ko
        sleep 3

        # 2) ttyUSB0 인식 확인
        if [ ! -e ${REAL_DEV} ]; then
            echo "ERROR: ${REAL_DEV} not found" > /dev/kmsg
            exit 1
        fi
        chmod 666 ${REAL_DEV}

        # 3) ttyS0 점유 여부 확인 후 처리
        if fuser ${ALIAS_DEV} > /dev/null 2>&1; then
            # 점유 중 → socat PTY 브릿지로 우회
            echo "ttyS0 busy, using socat PTY bridge" > /dev/kmsg
            mv ${ALIAS_DEV} ${ALIAS_DEV}.orig 2>/dev/null
            socat PTY,link=${ALIAS_DEV},raw,echo=0,mode=666 \
                  ${REAL_DEV},b${BAUD},raw,echo=0 &
            echo $! > /var/run/socat-serial.pid
        else
            # 비어있음 → 직접 심볼릭 링크
            echo "ttyS0 free, creating symlink" > /dev/kmsg
            rm -f ${ALIAS_DEV}
            ln -sf ${REAL_DEV} ${ALIAS_DEV}
        fi

        # 4) stty 파라미터 적용
        stty -F ${REAL_DEV} ${BAUD} cs8 -cstopb -parenb -crtscts raw 2>/dev/null

        echo "Serial bridge ready: ${ALIAS_DEV} -> ${REAL_DEV}" > /dev/kmsg
        ;;

    stop)
        # socat 종료
        if [ -f /var/run/socat-serial.pid ]; then
            kill $(cat /var/run/socat-serial.pid) 2>/dev/null
            rm /var/run/socat-serial.pid
        fi
        # ttyS0 복원
        rm -f ${ALIAS_DEV}
        mv ${ALIAS_DEV}.orig ${ALIAS_DEV} 2>/dev/null
        # 모듈 언로드
        rmmod cp210x usbserial 2>/dev/null
        ;;
esac
