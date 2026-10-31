#!/usr/bin/env bash
set -eu
base=$(cd "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/nondt-inventory.XXXXXXXX")
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/sys/bus/pci/devices/0000:00:17.0" "$test_dir/sys/bus/pci/devices/0000:03:00.0" \
  "$test_dir/sys/devices/0000:00:17.0/ata1/host0/target0:0:0/0:0:0:0/block/sda/device" "$test_dir/sys/class/block/sda1" "$test_dir/sys/class/block/nvme0n1/device" \
  "$test_dir/sys/class/ata_port/ata1" "$test_dir/sys/class/ata_port/ata2" "$test_dir/sys/class/ata_port/ata3" "$test_dir/sys/class/scsi_host/host0"
printf 'ahci\n' > "$test_dir/sys/class/scsi_host/host0/proc_name"
printf '0x010601\n' > "$test_dir/sys/bus/pci/devices/0000:00:17.0/class"
printf '0x8086\n' > "$test_dir/sys/bus/pci/devices/0000:00:17.0/vendor"
printf '0x1234\n' > "$test_dir/sys/bus/pci/devices/0000:00:17.0/device"
printf '0x010700\n' > "$test_dir/sys/bus/pci/devices/0000:03:00.0/class"
ln -s /drivers/ahci "$test_dir/sys/bus/pci/devices/0000:00:17.0/driver"
ln -s "$test_dir/sys/devices/0000:00:17.0/ata1/host0/target0:0:0/0:0:0:0/block/sda" "$test_dir/sys/class/block/sda"
printf 'Disk A\n' > "$test_dir/sys/class/block/sda/device/model"
printf 'serial-a\n' > "$test_dir/sys/class/block/sda/device/serial"
printf '4096\n' > "$test_dir/sys/class/block/sda/size"
printf '1\n' > "$test_dir/sys/class/block/sda1/partition"
printf '8192\n' > "$test_dir/sys/class/block/nvme0n1/size"
printf '%s\n' '{"extra_cmdline":{"SataPortMap":"42","DiskIdxMap":"0004","SasIdxMap":"0","other":"keep"},"synoinfo":{"maxdisks":"12","usbportcfg":"0x40"}}' > "$test_dir/config.json"
printf '%s\n' '[ 1.0] ata1: SATA link down' '[ 2.0] ata1: SATA link up 6.0 Gbps' '[ 3.0] ata2: SATA link down' > "$test_dir/dmesg"
result=$(MSHELL_INVENTORY_SYS_ROOT="$test_dir/sys" MSHELL_INVENTORY_DMESG_FILE="$test_dir/dmesg" bash "$base/tools/nondt-mapping-inventory.sh" "$test_dir/config.json" /dev/sda)
jq -e '.schema == 1 and .mapping_verified == false and (.controllers|length)==2 and (.disks|length)==2 and .ata_ports[0].dummy_state == "unknown" and .scsi_hosts[0].driver == "ahci" and .settings.extra_cmdline.SasIdxMap == "0" and (.settings.extra_cmdline|has("other")|not) and ([.disks[].name]|index("sda1")|not) and ([.controllers[]|select(.pci == "0000:00:17.0" and .driver == "ahci")]|length)==1 and ([.disks[]|select(.name == "sda" and .serial == "serial-a" and .boot_role == "loader" and .mapping_eligible == false and .controller_pci == "0000:00:17.0" and .ata_path == "ata1" and .dsm_slot == null)]|length)==1' <<<"$result" >/dev/null
jq -e '([.ata_ports[]|select(.name == "ata1" and .link_state == "up")]|length)==1 and ([.ata_ports[]|select(.name == "ata2" and .link_state == "down")]|length)==1 and ([.ata_ports[]|select(.name == "ata3" and .link_state == "unknown")]|length)==1' <<<"$result" >/dev/null
result_without_loader=$(MSHELL_INVENTORY_SYS_ROOT="$test_dir/sys" bash "$base/tools/nondt-mapping-inventory.sh" "$test_dir/config.json")
jq -e '[.disks[]|select(.name == "sda" and .boot_role == "unknown" and .mapping_eligible == true)]|length == 1' <<<"$result_without_loader" >/dev/null
if MSHELL_INVENTORY_SYS_ROOT="$test_dir/sys" bash "$base/tools/nondt-mapping-inventory.sh" "$test_dir/missing.json" >/dev/null 2>&1; then
  echo 'Missing config unexpectedly accepted' >&2
  exit 1
fi
if MSHELL_INVENTORY_SYS_ROOT="$test_dir/missing-sys" bash "$base/tools/nondt-mapping-inventory.sh" "$test_dir/config.json" >/dev/null 2>&1; then
  echo 'Missing sysfs unexpectedly accepted' >&2
  exit 1
fi
echo 'Non-DT inventory fixture tests passed.'
