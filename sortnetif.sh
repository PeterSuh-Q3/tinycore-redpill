#!/usr/bin/env ash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

#tce-load -wi ethtool iproute2

echo "this is sortnetif..."
#  echo "extract usr.tgz to /usr/ "
#  tar xvfz /exts/sortnetif/usr.tgz -C /
#  chmod +x /usr/bin/awk /usr/bin/tr /usr/bin/sort /usr/bin/sed /usr/bin/ethtool

ETHLIST=""
ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) # real network cards list
for ETH in ${ETHX}; do
  MAC="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
  BUS=$(ethtool -i ${ETH} 2>/dev/null | grep bus-info | awk '{print $2}')
  ETHLIST="${ETHLIST}${BUS} ${MAC} ${ETH}\n"
done

ETHLIST="$(echo -e "${ETHLIST}" | sort)"
ETHLIST="$(echo -e "${ETHLIST}" | grep -v '^$')"

echo -e "${ETHLIST}" >/tmp/ethlist
cat /tmp/ethlist

# sort
IDX=0
while true; do
  cat /tmp/ethlist
  [ ${IDX} -ge $(wc -l </tmp/ethlist) ] && break
  ETH=$(cat /tmp/ethlist | sed -n "$((${IDX} + 1))p" | awk '{print $3}')
  echo "ETH: ${ETH}"
  if [ -n "${ETH}" ] && [ ! "${ETH}" = "eth${IDX}" ]; then
    echo "change ${ETH} <=> eth${IDX}"
      ip link set dev eth${IDX} down
      ip link set dev ${ETH} down
      sleep 1
      ip link set dev eth${IDX} name tmp
      ip link set dev ${ETH} name eth${IDX}
      ip link set dev tmp name ${ETH}
      sleep 1
      ip link set dev eth${IDX} up
      ip link set dev ${ETH} up
      sleep 1
      sed -i "s/eth${IDX}/tmp/" /tmp/ethlist
      sed -i "s/${ETH}/eth${IDX}/" /tmp/ethlist
      sed -i "s/tmp/${ETH}/" /tmp/ethlist
      sleep 1
      udhcpc -i ${ETH}
  fi
  IDX=$((${IDX} + 1))
done

rm -f /tmp/ethlist

exit 0
