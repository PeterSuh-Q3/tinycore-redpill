#!/usr/bin/env bash
# Build an Alpine based BTRFS recovery rootfs/initramfs.
set -Eeuo pipefail

ALPINE_VERSION="${ALPINE_VERSION:-v3.8}"
ARCH="${ARCH:-x86_64}"
ROOTFS_URL="${ROOTFS_URL:-https://dl-3.alpinelinux.org/alpine/${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION#v}.0-${ARCH}.tar.gz}"
WORK_DIR="${WORK_DIR:-$PWD/btr-work}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOTFS_DIR="${WORK_DIR}/rootfs"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/alpine_3.8}"
KERNEL_IMAGE="${KERNEL_IMAGE:-}"
KERNEL_MODULES="${KERNEL_MODULES:-}"
INITRAMFS_NAME="${INITRAMFS_NAME:-btr-recovery-${ARCH}.initramfs}"
KERNEL_RELEASE="${KERNEL_RELEASE:-$(basename "${KERNEL_MODULES}")}"
BTR_ROOT_PASSWORD="${BTR_ROOT_PASSWORD:-}"
BTR_TC_PASSWORD="${BTR_TC_PASSWORD:-}"

die() { echo "btr.sh: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

[ "$(id -u)" -eq 0 ] || die "run as root inside the build VM"
need curl; need tar; need chroot; need apk
[ -n "${KERNEL_IMAGE}" ] || die "set KERNEL_IMAGE to the Linux 4.14 kernel image"
[ -f "${KERNEL_IMAGE}" ] || die "kernel image not found: ${KERNEL_IMAGE}"
[ -n "${KERNEL_MODULES}" ] || die "set KERNEL_MODULES to matching 4.14 modules directory"
[ -d "${KERNEL_MODULES}" ] || die "kernel modules directory not found: ${KERNEL_MODULES}"
[ -n "${BTR_ROOT_PASSWORD}" ] || die "set BTR_ROOT_PASSWORD for the recovery root account"
[ -n "${BTR_TC_PASSWORD}" ] || die "set BTR_TC_PASSWORD for the recovery tc account"

mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"
echo "[btr] downloading Alpine rootfs: ${ROOTFS_URL}"
curl -fL --retry 3 "${ROOTFS_URL}" | tar -xz -C "${ROOTFS_DIR}"

cp -L /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
mount --bind /dev "${ROOTFS_DIR}/dev"
mount --bind /dev/shm "${ROOTFS_DIR}/dev/shm"
mount --bind /proc "${ROOTFS_DIR}/proc"
mount --bind /sys "${ROOTFS_DIR}/sys"
cleanup() {
  umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
  umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
  umount -l "${ROOTFS_DIR}/dev/shm" 2>/dev/null || true
  umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
}
trap cleanup EXIT

cat > "${ROOTFS_DIR}/etc/apk/repositories" <<EOF
https://dl-3.alpinelinux.org/alpine/${ALPINE_VERSION}/main
https://dl-3.alpinelinux.org/alpine/${ALPINE_VERSION}/community
EOF

chroot "${ROOTFS_DIR}" /sbin/apk update
chroot "${ROOTFS_DIR}" /sbin/apk add --no-cache alpine-base alpine-conf mkinitfs btrfs-progs mdadm lvm2 device-mapper util-linux e2fsprogs dosfstools kmod openssh shadow sudo dialog bash

chroot "${ROOTFS_DIR}" /usr/sbin/adduser -D -s /bin/sh tc
mkdir -p "${ROOTFS_DIR}/home/tc"
chroot "${ROOTFS_DIR}" /bin/chown tc:tc /home/tc
printf 'root:%s\ntc:%s\n' "${BTR_ROOT_PASSWORD}" "${BTR_TC_PASSWORD}" | \
  chroot "${ROOTFS_DIR}" /usr/sbin/chpasswd
chroot "${ROOTFS_DIR}" /usr/sbin/addgroup tc wheel
printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' > "${ROOTFS_DIR}/etc/sudoers.d/tc"
chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d/tc"
# This recovery image exposes only the serial and primary virtual console.
# Alpine's default inittab also starts agetty on tty2-tty6, which do not exist
# on serial-only/VM boots and otherwise produces an endless error loop.
sed -i -E '/^[^#]*tty[2-6][[:space:]]*::/d' "${ROOTFS_DIR}/etc/inittab"
printf '%s\n' 'ttyS0::askfirst:-/sbin/agetty -L 115200 ttyS0 vt100' >> "${ROOTFS_DIR}/etc/inittab"
# BusyBox init must create device nodes before agetty starts.
sed -i '/^::sysinit:/i::sysinit:/bin/mount -t devtmpfs devtmpfs /dev' "${ROOTFS_DIR}/etc/inittab"
rm -rf "${ROOTFS_DIR}/dev/fd" "${ROOTFS_DIR}/dev/stdin" \
  "${ROOTFS_DIR}/dev/stdout" "${ROOTFS_DIR}/dev/stderr"
ln -s /proc/self/fd "${ROOTFS_DIR}/dev/fd"
ln -s /proc/self/fd/0 "${ROOTFS_DIR}/dev/stdin"
ln -s /proc/self/fd/1 "${ROOTFS_DIR}/dev/stdout"
ln -s /proc/self/fd/2 "${ROOTFS_DIR}/dev/stderr"

# The recovery menu is intentionally kept as a separate script so it can be
# updated without rebuilding the menu logic.  Start it on the local console
# immediately after Alpine reaches the default runlevel.
install -D -m 0755 "${SCRIPT_DIR}/mountvol.sh" "${ROOTFS_DIR}/home/tc/mountvol.sh"
mkdir -p "${ROOTFS_DIR}/etc/local.d"
cat > "${ROOTFS_DIR}/etc/local.d/mountvol.start" <<'EOF'
#!/bin/sh
# Run the interactive BTRFS/LVM recovery menu on the first local console.
[ -c /dev/tty1 ] || exit 0
sleep 5
udevadm settle 2>/dev/null || true
exec setsid /home/tc/mountvol.sh </dev/tty1 >/dev/tty1 2>&1
EOF
chmod 0755 "${ROOTFS_DIR}/etc/local.d/mountvol.start"
chroot "${ROOTFS_DIR}" /sbin/rc-update add local default >/dev/null 2>&1 || true

cat > "${ROOTFS_DIR}/etc/motd" <<'EOF'
Alpine 3.8 BTRFS Recovery Environment

This is a rescue system. Prefer read-only degraded mounts.
Available tools: mdadm, lvm2, btrfs-progs and util-linux.
Do not run filesystem repair commands until the source disks are backed up.
EOF

mkdir -p "${ROOTFS_DIR}/etc/ssh"
cat > "${ROOTFS_DIR}/etc/ssh/sshd_config" <<'EOF'
Port 22
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
PrintMotd yes
Subsystem sftp /usr/lib/ssh/sftp-server
EOF
chroot "${ROOTFS_DIR}" /usr/bin/ssh-keygen -A
chroot "${ROOTFS_DIR}" /sbin/rc-update add sshd default >/dev/null 2>&1 || true

mkdir -p "${ROOTFS_DIR}/etc/modules-load.d"
cat > "${ROOTFS_DIR}/etc/modules-load.d/btr-recovery.conf" <<'EOF'
md_mod
dm_mod
btrfs
raid6_pq
zstd
zlib_deflate
lzo
# SATA/SCSI/NVMe storage stack
scsi_mod
sd_mod
sg
sr_mod
libata
ahci
nvme_core
nvme
usb_storage
uas
# VM/USB console input stack
hid
usbhid
hid_generic
evdev
i8042
atkbd
psmouse
virtio
virtio_pci
virtio_ring
virtio_input
xhci_hcd
ehci_hcd
uhci_hcd
# Common wired NIC drivers for recovery SSH/DHCP
igc
e1000e
e1000
igb
ixgbe
r8169
r8152
tg3
bnx2
atlantic
alx
sky2
skge
EOF

mkdir -p "${ROOTFS_DIR}/lib/modules/${KERNEL_RELEASE}"
cp -a "${KERNEL_MODULES}"/. "${ROOTFS_DIR}/lib/modules/${KERNEL_RELEASE}/"
chroot "${ROOTFS_DIR}" /sbin/depmod -a "${KERNEL_RELEASE}" || true

# mkinitfs runs inside the chroot, so make the configured output directory
# visible there as well as on the host.
mkdir -p "${ROOTFS_DIR}${OUTPUT_DIR}"
# This is a self-contained recovery image.  mkinitfs alone creates Alpine's
# early boot ramdisk and expects a separate rootfs/modloop; it does not pack
# the installed ROOTFS_DIR.  Pack the complete Alpine rootfs so /sbin/init,
# userspace tools, mountvol.sh and the matching modules are available at boot.
ln -sf /sbin/init "${ROOTFS_DIR}/init"
umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
umount -l "${ROOTFS_DIR}/dev/shm" 2>/dev/null || true
umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
# The build VM may run with umask 077.  The cpio entry for '.' becomes the
# runtime root directory, so it must remain traversable by the recovery user.
chmod 0755 "${ROOTFS_DIR}"
(
  cd "${ROOTFS_DIR}"
  find . -print | cpio -o -H newc 2>/dev/null | gzip -9 \
    > "${OUTPUT_DIR}/${INITRAMFS_NAME}"
)
install -m 0644 "${KERNEL_IMAGE}" "${OUTPUT_DIR}/vmlinuz-4.14"
printf '%s\n' "${ROOTFS_URL}" > "${OUTPUT_DIR}/rootfs-source.txt"
printf '%s\n' "${KERNEL_IMAGE}" > "${OUTPUT_DIR}/kernel-source.txt"
echo "[btr] recovery image created in ${OUTPUT_DIR}"
