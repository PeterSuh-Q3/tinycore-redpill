#!/bin/sh
# Runs only from the Alpine migration TinyCore initramfs boot hook.

set -u

STAGE=/mnt/alpine-migrate
STATUS="$STAGE/STATUS"
P2_MOUNT="$STAGE"
RAM_STAGE=/tmp/alpine-migrate
P1_MOUNT=/mnt/alpine-migrate-p1
P4_MOUNT=/mnt/alpine
DOSFSTOOLS_MOUNT="$STAGE/dosfstools"

note() {
    echo "alpine-migrate: $*" | tee -a "$STATUS" >/dev/console
}

fail() {
    note "FAILED: $*"
    note "Manual recovery: do not boot the normal TinyCore entry after p3 was resized."
    note "Boot 'Alpine migration' again and read $STATUS on partition 2."
    exit 1
}

mounted_at() {
    awk -v device="$1" '$1 == device { print $2; exit }' /proc/mounts
}

wait_for_partition() {
    partition_name=${1##*/}
    timeout=20
    while [ "$timeout" -gt 0 ]; do
        [ -b "$1" ] && [ -e "/sys/class/block/$partition_name" ] && return 0
        sleep 1
        timeout=$((timeout - 1))
    done
    return 1
}

if ! grep -qw alpine_migrate /proc/cmdline; then
    exit 0
fi

[ -r "$STAGE/migration.env" ] || fail "migration manifest is missing from partition 2"
# shellcheck disable=SC1091
. "$STAGE/migration.env"

case "$DISK:$P1:$P2:$P3:$P4" in
    /dev/[A-Za-z0-9]*:/dev/[A-Za-z0-9]*:/dev/[A-Za-z0-9]*:/dev/[A-Za-z0-9]*:/dev/[A-Za-z0-9]*) ;;
    *) fail "unsafe device name in migration manifest" ;;
esac

[ "$(mounted_at "$P2")" = "$P2_MOUNT" ] || fail "partition 2 is not mounted at $P2_MOUNT"
[ -s "$STAGE/alpine-grub.cfg" ] || fail "staged Alpine GRUB configuration is missing"
[ -s "$STAGE/dosfstools.tcz" ] || fail "staged dosfstools extension is missing"

printf 'running\n' >"$STATUS"
note "minimal norestore boot confirmed; checking that partition 3 has no users"

if grep -q "^$P3 " /proc/mounts; then
    fail "$P3 is mounted; this boot is not safe to migrate"
fi
for backing_file in /sys/block/loop*/loop/backing_file; do
    [ -r "$backing_file" ] || continue
    if grep -q "$P3" "$backing_file"; then
        fail "a loop device still backs a file on $P3"
    fi
done

[ -b "$DISK" ] && [ -b "$P1" ] && [ -b "$P2" ] && [ -b "$P3" ] || fail "loader partitions disappeared"

mkdir -p "$RAM_STAGE" || fail "cannot create RAM staging directory"
cp "$STAGE/migration.env" "$RAM_STAGE/migration.env" \
    && cp "$STAGE/alpine-grub.cfg" "$RAM_STAGE/alpine-grub.cfg" \
    && cp "$STAGE/dosfstools.tcz" "$RAM_STAGE/dosfstools.tcz" \
    || fail "cannot copy migration assets to RAM"
sync
printf 'partition-table-update\n' >"$STATUS"
umount "$P2_MOUNT" || fail "could not unmount staging partition $P2 before updating $DISK"
STAGE="$RAM_STAGE"
STATUS="$RAM_STAGE/STATUS"
printf 'partition-table-update\n' >"$STATUS"

case "$PARTITION_TABLE" in
    dos)
        FDISK_INPUT="d
3
n
p
3
$P3_START
$P3_END
n
p
4

+1G
w"
        ;;
    gpt)
        FDISK_INPUT="d
3
n
3
$P3_START
$P3_END
n
4

+1G
w"
        ;;
    *) fail "unsupported partition table $PARTITION_TABLE" ;;
esac

mkdir -p "$DOSFSTOOLS_MOUNT" "$P1_MOUNT" "$P4_MOUNT" || fail "cannot create mount points"
mount -o loop,ro "$STAGE/dosfstools.tcz" "$DOSFSTOOLS_MOUNT" || fail "cannot mount staged dosfstools"
MKFS_FAT=
for candidate in "$DOSFSTOOLS_MOUNT"/usr/local/sbin/mkfs.fat "$DOSFSTOOLS_MOUNT"/usr/sbin/mkfs.fat; do
    [ -x "$candidate" ] && MKFS_FAT=$candidate && break
done
[ -n "$MKFS_FAT" ] || fail "staged dosfstools does not contain mkfs.fat"
"$MKFS_FAT" --help >/dev/null 2>&1 || fail "staged mkfs.fat cannot run with the base TinyCore runtime"

if [ -b "$P4" ]; then
    [ "$(cat "/sys/class/block/${P3##*/}/start")" = "$P3_START_512" ] \
        && [ "$(cat "/sys/class/block/${P3##*/}/size")" = "$P3_NEW_SIZE_512" ] \
        || fail "existing partition layout does not match this migration manifest"
    note "resuming a prior migration attempt with existing partition 4"
else
    [ "$(cat "/sys/class/block/${P3##*/}/start")" = "$P3_START_512" ] \
        && [ "$(cat "/sys/class/block/${P3##*/}/size")" = "$P3_SIZE_512" ] \
        || fail "partition 3 changed before migration"
    note "creating partition 4; the original GRUB entries are still unchanged"
    if ! printf '%s\n' "$FDISK_INPUT" | fdisk "$DISK"; then
        fail "fdisk did not update $DISK"
    fi
    wait_for_partition "$P4" || fail "kernel did not expose $P4 after partition-table update"
fi

note "formatting and populating Alpine partition 4"
"$MKFS_FAT" -F 32 -n alpine "$P4" >/dev/null || fail "could not format $P4"
mount "$P4" "$P4_MOUNT" || fail "could not mount $P4"
if ! wget -O - "$PAYLOAD_URL" | tar xzf - -C "$P4_MOUNT"; then
    fail "Alpine payload download or extraction failed; retry this migration entry"
fi
wget -O "$P4_MOUNT/localhost.apkovl.tar.gz" "$OVERLAY_URL" || fail "could not download Alpine overlay"
[ -s "$P4_MOUNT/vmlinuz-lts" ] && [ -s "$P4_MOUNT/initramfs-lts" ] \
    || fail "Alpine payload is incomplete"
sync
umount "$P4_MOUNT" || fail "could not unmount populated $P4"

note "payload is ready; erasing former TinyCore partition 3"
"$MKFS_FAT" -F 16 -i 6234C863 "$P3" >/dev/null || fail "could not format $P3"

if [ -z "$(mounted_at "$P1")" ]; then
    mount "$P1" "$P1_MOUNT" || fail "could not mount GRUB partition $P1"
else
    P1_MOUNT="$(mounted_at "$P1")"
fi
[ -f "$P1_MOUNT/boot/grub/grub.cfg" ] || fail "GRUB configuration is missing on $P1"
cp "$P1_MOUNT/boot/grub/grub.cfg" "$P1_MOUNT/boot/grub/grub.cfg.pre-alpine" \
    || fail "could not back up BIOS GRUB configuration"
cp "$STAGE/alpine-grub.cfg" "$P1_MOUNT/boot/grub/grub.cfg.new" \
    && mv "$P1_MOUNT/boot/grub/grub.cfg.new" "$P1_MOUNT/boot/grub/grub.cfg" \
    || fail "could not install BIOS Alpine GRUB configuration"
if [ -f "$P1_MOUNT/EFI/BOOT/grub.cfg" ]; then
    cp "$P1_MOUNT/EFI/BOOT/grub.cfg" "$P1_MOUNT/EFI/BOOT/grub.cfg.pre-alpine" \
        || fail "could not back up EFI GRUB configuration"
    cp "$STAGE/alpine-grub.cfg" "$P1_MOUNT/EFI/BOOT/grub.cfg.new" \
        && mv "$P1_MOUNT/EFI/BOOT/grub.cfg.new" "$P1_MOUNT/EFI/BOOT/grub.cfg" \
        || fail "could not install EFI Alpine GRUB configuration"
fi
sync
mount "$P2" "$P2_MOUNT" || fail "could not remount staging partition $P2"
cp "$STATUS" "$P2_MOUNT/STATUS" || fail "could not persist migration status on $P2"
STATUS="$P2_MOUNT/STATUS"
printf 'complete\n' >"$STATUS"
note "COMPLETE: Alpine payload and GRUB were installed. Reboot into Alpine."

umount "$DOSFSTOOLS_MOUNT" 2>/dev/null || :
exit 0
