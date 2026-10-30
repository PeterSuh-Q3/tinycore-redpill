#!/usr/bin/env bash
# Read-only Non-DT storage inventory. No mapping is inferred or applied.
set -eu
sys_root="${MSHELL_INVENTORY_SYS_ROOT:-/sys}"
config="${1:-/home/tc/user_config.json}"
loader_disk="${2:-}"
loader_disk="${loader_disk#/dev/}"
if [ ! -d "$sys_root/class/block" ] || [ ! -d "$sys_root/bus/pci/devices" ]; then
  echo 'Storage or PCI sysfs inventory is unavailable' >&2
  exit 1
fi
if [ ! -r "$config" ] || ! jq -e 'type == "object"' "$config" >/dev/null 2>&1; then
  echo 'Cannot read a valid user_config.json' >&2
  exit 1
fi

read_value() {
  local value
  # Some sysfs attributes exist and are readable but fail at read time (e.g.
  # ENXIO on devices without a serial). Treat them as unknown, not fatal.
  if [ -r "$1" ] && value=$(tr -d '\n\r' < "$1" 2>/dev/null); then
    printf '%s' "$value"
  fi
}

controllers='[]'
for entry in "$sys_root"/bus/pci/devices/*; do
  [ -e "$entry" ] || continue
  class=$(read_value "$entry/class")
  case "$class" in 0x0100*|0x0104*|0x0106*|0x0107*|0x0108*) ;; *) continue ;; esac
  pci=${entry##*/}
  vendor=$(read_value "$entry/vendor")
  device=$(read_value "$entry/device")
  driver_path=$(readlink "$entry/driver" 2>/dev/null || true)
  driver=${driver_path##*/}
  controllers=$(jq -c --arg pci "$pci" --arg class "$class" --arg vendor "$vendor" \
    --arg device "$device" --arg driver "$driver" \
    '. + [{pci:$pci,class:$class,vendor:$vendor,device:$device,driver:(if $driver == "" then null else $driver end)}]' <<<"$controllers")
done

if [ -n "${MSHELL_INVENTORY_DMESG_FILE:-}" ]; then
  kernel_log=$(cat "$MSHELL_INVENTORY_DMESG_FILE" 2>/dev/null || true)
else
  kernel_log=$(dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null || true)
fi
ports='[]'
for entry in "$sys_root"/class/ata_port/ata*; do
  [ -e "$entry" ] || continue
  name=${entry##*/}
  target=$(readlink -f "$entry" 2>/dev/null || true)
  # A missing link message is not evidence of an empty port. Use the most
  # recent explicit kernel observation; logs may have wrapped or be denied.
  state=$(printf '%s\n' "$kernel_log" | awk -v port="$name:" '
    index($0, port) && /SATA link down/ { state="down" }
    index($0, port) && /SATA link up/ { state="up" }
    END { if (state == "") state="unknown"; print state }')
  ports=$(jq -c --arg name "$name" --arg path "$target" \
    --arg state "$state" \
    '. + [{name:$name,sysfs_path:$path,link_state:$state,dummy_state:"unknown",dsm_slot:null}]' <<<"$ports")
done

hosts='[]'
for entry in "$sys_root"/class/scsi_host/host*; do
  [ -e "$entry" ] || continue
  name=${entry##*/}
  target=$(readlink -f "$entry" 2>/dev/null || true)
  driver=$(read_value "$entry/proc_name")
  hosts=$(jq -c --arg name "$name" --arg path "$target" --arg driver "$driver" \
    '. + [{name:$name,sysfs_path:$path,driver:(if $driver == "" then null else $driver end)}]' <<<"$hosts")
done

disks='[]'
for entry in "$sys_root"/class/block/*; do
  [ -e "$entry" ] || continue
  name=${entry##*/}
  case "$name" in sd[a-z]*|sata[0-9]*|nvme[0-9]*n[0-9]*) ;; *) continue ;; esac
  [ ! -e "$entry/partition" ] || continue
  target=$(readlink -f "$entry" 2>/dev/null || true)
  model=$(read_value "$entry/device/model")
  serial=$(read_value "$entry/device/serial")
  wwid=$(read_value "$entry/device/wwid")
  sectors=$(read_value "$entry/size")
  boot_role=unknown
  [ -z "$loader_disk" ] || [ "$name" != "$loader_disk" ] || boot_role=loader
  disks=$(jq -c --arg name "$name" --arg path "$target" --arg model "$model" \
    --arg serial "$serial" --arg wwid "$wwid" --arg sectors "$sectors" --arg boot_role "$boot_role" \
    '. + [{name:$name,sysfs_path:$path,model:$model,serial:$serial,wwid:$wwid,sectors:$sectors,boot_role:$boot_role,mapping_eligible:($boot_role != "loader"),dsm_slot:null}]' <<<"$disks")
done

jq -n --slurpfile config "$config" --argjson controllers "$controllers" --argjson disks "$disks" --argjson ports "$ports" --argjson hosts "$hosts" '
  {schema:1, scope:"loader-observation", mapping_verified:false,
   settings: {extra_cmdline: (($config[0].extra_cmdline // {}) | with_entries(select(.key == "SataPortMap" or .key == "DiskIdxMap" or .key == "SasIdxMap" or .key == "sata_remap"))),
              synoinfo: (($config[0].synoinfo // {}) | with_entries(select(.key == "maxdisks" or .key == "internalportcfg" or .key == "esataportcfg" or .key == "usbportcfg")))},
   controllers:$controllers, ata_ports:$ports, scsi_hosts:$hosts, disks:$disks,
   warnings:["Loader enumeration does not establish DSM controller order, physical bay, or boot disk."]}'
