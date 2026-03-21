#!/bin/sh

REAL_DEV=/dev/ttyUSB0
CONSOLE_DEV=/dev/ttyS0
BAUD=115200

case $1 in
    start)
        # 1) 커널 모듈 로드 (FTDI 자동로드 확인 후 필요시만)
        if ! lsmod | grep -q ftdi_sio; then
            insmod /lib/modules/usbserial.ko 2>/dev/null
            insmod /lib/modules/ftdi_sio.ko  2>/dev/null
            sleep 2
        else
            echo "ftdi_sio already loaded" > /dev/kmsg
        fi
        sleep 2

        # 2) ttyUSB0 인식 확인
        if [ ! -e ${REAL_DEV} ]; then
            echo "ERROR: ${REAL_DEV} not found" > /dev/kmsg
            exit 1
        fi
        chmod 666 ${REAL_DEV}

        # 3) 기존 socat 중복 실행 방지
        if [ -f /var/run/socat-serial.pid ]; then
            kill $(cat /var/run/socat-serial.pid) 2>/dev/null
            rm -f /var/run/socat-serial.pid
        fi

        # 4) ttyS0 → ttyUSB0 socat 브릿지 실행
        socat ${CONSOLE_DEV},b${BAUD},raw,echo=0 \
              ${REAL_DEV},b${BAUD},raw,echo=0 &
        echo $! > /var/run/socat-serial.pid
        echo "socat bridge started: ${CONSOLE_DEV}(${BAUD}) -> ${REAL_DEV}(${BAUD}) PID:$(cat /var/run/socat-serial.pid)" > /dev/kmsg

        # 5) 상태 출력
        echo "=== Module ===" && lsmod | grep -E 'usbserial|ftdi_sio'
        echo "=== Device ===" && ls -la ${REAL_DEV} ${CONSOLE_DEV} 2>/dev/null
        echo "=== Kernel log ===" && dmesg | grep -E 'ftdi|ttyUSB|socat' | tail -5
        echo "=== socat ===" && ps | grep socat | grep -v grep
        ;;

    stop)
        # socat 종료
        if [ -f /var/run/socat-serial.pid ]; then
            kill $(cat /var/run/socat-serial.pid) 2>/dev/null
            rm -f /var/run/socat-serial.pid
        else
            # PID 파일 없을 때 강제 탐색
            kill $(ps | grep socat | grep -v grep | awk '{print $1}') 2>/dev/null
        fi

        # ttyUSB0 점유 프로세스 전체 정리
        kill $(fuser ${REAL_DEV} 2>/dev/null) 2>/dev/null

        # FTDI 모듈 언로드
        rmmod ftdi_sio usbserial 2>/dev/null

        echo "Serial bridge stopped" > /dev/kmsg
        echo "=== socat ===" && ps | grep socat | grep -v grep
        ;;

    status)
        echo "=== Module ===" && lsmod | grep -E 'usbserial|ftdi_sio'
        echo "=== Device ===" && ls -la ${REAL_DEV} ${CONSOLE_DEV} 2>/dev/null
        echo "=== socat PID ===" && cat /var/run/socat-serial.pid 2>/dev/null
        echo "=== socat process ===" && ps | grep socat | grep -v grep
        echo "=== ttyUSB0 users ===" && fuser ${REAL_DEV} 2>/dev/null
        ;;
esac
