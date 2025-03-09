#!/bin/bash

[ -f /home/tc/buildstatus ] && rm -f /home/tc/buildstatus

while [ -z "$GATEWAY_INTERFACE" ]; do
    clear
    if [ -f /home/tc/buildstatus ]; then
      echo -e "\e[33m-------------------M-Shell for TCRP Loader Build Staus---------------------\e[0m"
      echo -e "\e[33mStage\e[0m		\e[32mStatus\e[0m			Message"
      cat /home/tc/buildstatus
    else
      echo -e "\e[33m----------------------user_config.json extra_cmdline-----------------------\e[0m"
      jq '.extra_cmdline' /home/tc/user_config.json
      echo -e "\e[33m----------------------user_config.json synoinfo----------------------------\e[0m"
      jq '.synoinfo' /home/tc/user_config.json
      echo -e "\e[33m----------------------added addons-----------------------------------------\e[0m"
      [ -d /home/tc/redpill-load/custom/extensions ] && ls /home/tc/redpill-load/custom/extensions || echo "No Addons added. (Loader build required)"
    fi
    echo "Press ctrl-c to exit"
    sleep 1
done
