#!/bin/sh
# Manual recovery for Alpine loader P3 and its P4 persistence archive. Not a boot hook.
# Usage: sudo sh recover-alpine-p3.sh [--check|--apply]
set -eu

mode=${1:---check}
case "$mode" in --check|--apply) ;; *) echo 'Usage: recover-alpine-p3.sh [--check|--apply]' >&2; exit 2 ;; esac
[ "$(id -u)" -eq 0 ] || { echo 'Run as root (sudo).' >&2; exit 2; }

dev=$(blkid -t UUID=6234-C863 -o device 2>/dev/null | head -n 1)
[ -n "$dev" ] && [ -b "$dev" ] || { echo 'Loader P3 UUID 6234-C863 not found.' >&2; exit 1; }
dev=$(readlink -f "$dev")
[ "$(blkid -s TYPE -o value "$dev" 2>/dev/null)" = vfat ] || {
    echo "Refusing non-VFAT device: $dev" >&2; exit 1;
}
name=${dev##*/}
point="/mnt/$name"
media="/media/$name"
mm=$(cat "/sys/class/block/$name/dev" 2>/dev/null)
[ -n "$mm" ] || exit 1
[ "$(blockdev --getro "$dev")" = 0 ] || { echo "Block device is read-only: $dev" >&2; exit 1; }

mkdir -p /run
exec 9>/run/mshell-p3-recovery.lock
flock -x 9 || exit 1
mounts() { awk -v mm="$mm" '$3 == mm { print $5 }' /proc/self/mountinfo; }
options() {
    awk -v mm="$mm" -v p="$point" '$3 == mm && $5 == p { opts=$6 "," $NF } END { print opts }' /proc/self/mountinfo
}

echo "P3 device: $dev ($mm)"
echo 'Current mounts:'
awk -v mm="$mm" '$3 == mm { print "  id=" $1 " target=" $5 " options=" $6 " super=" $NF }' /proc/self/mountinfo
echo "P3 alias: $(readlink /mnt/tcrp 2>/dev/null || echo absent)"
if [ -f /home/tc/user_config.json ] && [ -f "$point/user_config.json" ] &&
   [ ! -L /home/tc/user_config.json ] && ! cmp -s /home/tc/user_config.json "$point/user_config.json"; then
    echo 'Warning: home and P3 user_config.json differ; --apply will preserve home as a backup and link to P3.' >&2
fi

for path in $(mounts); do
    case "$path" in "$point"|"$media") ;; *)
        echo "Refusing unexpected mount target: $path" >&2; exit 1 ;;
    esac
done
if awk -v p="$point/" -v q="$media/" 'NR>1 && (index($1,p)==1 || index($1,q)==1) {busy=1} END {exit !busy}' /proc/swaps; then
    echo 'P3 swapfile is active; refusing to unmount.' >&2
    exit 1
fi
if [ -e /mnt/tcrp ] && [ ! -L /mnt/tcrp ]; then
    echo '/mnt/tcrp is not a symlink; refusing to replace it.' >&2
    exit 1
fi

if [ "$mode" = --check ]; then
    echo 'Check only. Pass --apply to drain P3 mounts and mount it with rw,umask=000.'
    exit 0
fi

restore_home_config_link() {
    config=/mnt/tcrp/user_config.json
    home=/home/tc/user_config.json
    if [ ! -f "$config" ] || ! jq -e 'type == "object"' "$config" >/dev/null 2>&1; then
        echo "P3 user_config.json is missing or invalid: $config" >&2; return 1;
    fi
    sudo -u tc test -w "$config" || { echo 'tc cannot write the P3 configuration.' >&2; return 1; }

    if [ -L "$home" ] && [ "$(readlink "$home")" = "$config" ]; then
        chown -h tc:staff "$home"
        return 0
    fi
    [ ! -e "$home" ] || [ -f "$home" ] || [ -L "$home" ] || {
        echo "Refusing to replace non-file $home" >&2; return 1;
    }

    backup=""
    if [ -e "$home" ] || [ -L "$home" ]; then
        backup="${home}.backup-before-p3-link.$(date -u +%Y%m%d%H%M%S).$$"
        mv "$home" "$backup" || return 1
        echo "Saved previous home configuration at $backup"
        if [ -f "$backup" ] && [ ! -L "$backup" ]; then
            persistent="$point/$(basename "$backup")"
            if ! cp "$backup" "$persistent"; then
                mv "$backup" "$home"
                echo 'Could not preserve the prior home configuration on P3.' >&2
                return 1
            fi
            echo "Saved persistent copy at $persistent"
        fi
    fi
    if ! ln -s "$config" "$home" || ! chown -h tc:staff "$home"; then
        [ ! -L "$home" ] || rm -f "$home"
        [ -z "$backup" ] || mv "$backup" "$home"
        return 1
    fi
    sudo -u tc test -w "$home" || return 1
    echo "Restored tc-owned symlink: $home -> $config"
}

verify_recovered_state() {
    config=/mnt/tcrp/user_config.json
    home=/home/tc/user_config.json

    [ "$(mounts | wc -l | tr -d ' ')" -eq 1 ] || {
        echo 'P3 must have exactly one active mount before persistence.' >&2; return 1;
    }
    [ "$(mounts)" = "$point" ] || {
        echo "P3 is not mounted at the expected path: $point" >&2; return 1;
    }
    opts=$(options)
    case ",$opts," in *,rw,*fmask=0000,*dmask=0000,*) ;; *)
        echo "P3 mount options are not writable and permissive: $opts" >&2; return 1 ;;
    esac
    [ "$(readlink /mnt/tcrp 2>/dev/null)" = "$point" ] || {
        echo '/mnt/tcrp does not point to the recovered P3 mount.' >&2; return 1;
    }
    [ -L "$home" ] && [ "$(readlink "$home")" = "$config" ] || {
        echo '/home/tc/user_config.json is not the expected P3 symlink.' >&2; return 1;
    }
    [ "$(stat -c '%U:%G' "$home")" = 'tc:staff' ] || {
        echo 'The user_config.json symlink is not owned by tc:staff.' >&2; return 1;
    }
    jq -e 'type == "object"' "$config" >/dev/null 2>&1 || {
        echo 'The P3 user_config.json is missing or invalid.' >&2; return 1;
    }
    sudo -u tc test -w "$home" || {
        echo 'tc cannot write user_config.json through the recovered symlink.' >&2; return 1;
    }
    [ "$(blockdev --getro "$dev")" = 0 ] || {
        echo 'The P3 block device became read-only.' >&2; return 1;
    }
}

migrate_legacy_p3_overlay() {
    legacy="$point/localhost.apkovl.tar.gz"
    baseline="$point/localhost.apkovl.baseline.tar.gz"
    [ -f "$legacy" ] || return 0
    tar -tzf "$legacy" >/dev/null 2>&1 || {
        echo "Invalid legacy P3 overlay; leaving it untouched: $legacy" >&2; return 1;
    }
    if [ -e "$baseline" ]; then
        tar -tzf "$baseline" >/dev/null 2>&1 || {
            echo "Invalid P3 baseline; leaving $legacy untouched." >&2; return 1;
        }
        withdrawn="$point/localhost.apkovl.withdrawn.$(date +%Y%m%d%H%M%S).$$.tar.gz"
        [ ! -e "$withdrawn" ] || return 1
        mv "$legacy" "$withdrawn" || return 1
        echo "Preserved the former P3 overlay at $withdrawn"
    else
        mv "$legacy" "$baseline" || return 1
        echo "Renamed the P3 comparison overlay to $baseline"
    fi
    [ ! -e "$legacy" ]
}

persist_recovered_state() {
    echo '[PERSIST] Including the recovered user_config.json link in Alpine persistence...'
    lbu include /home/tc/user_config.json || {
        echo 'Could not include the recovered config link in Alpine persistence.' >&2
        return 1
    }
    repair_p4_archive
}

repair_p4_archive() {
    if ! command -v lbu >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
        echo 'lbu or tar is unavailable; P4 recovery cancelled.' >&2; return 1;
    fi
    p4dev="${dev%3}4"
    [ "$p4dev" != "$dev" ] && [ -b "$p4dev" ] &&
        [ "$(blkid -s TYPE -o value "$p4dev" 2>/dev/null)" = vfat ] || {
        echo 'Expected VFAT loader P4 device was not found.' >&2; return 1;
    }
    p4mm=$(cat "/sys/class/block/${p4dev##*/}/dev" 2>/dev/null) || return 1
    awk -v mm="$p4mm" '$3 == mm && $5 == "/mnt/alpine" && $6 ~ /(^|,)rw(,|$)/ && / - vfat / {found=1} END {exit !found}' /proc/self/mountinfo &&
        [ "$(blockdev --getro "$p4dev")" = 0 ] && [ -w /mnt/alpine ] || {
        echo 'P4 is not mounted read-write at /mnt/alpine.' >&2; return 1;
    }
    for protected in /etc/passwd /etc/group /etc/shadow /etc/sudoers.d /etc/sudoers.d/tc /etc/lbu/lbu.conf; do
        [ "$(stat -c '%u' "$protected" 2>/dev/null)" = 0 ] || {
            echo "Live protected path is not root-owned: $protected" >&2; return 1;
        }
    done

    archive="/mnt/alpine/$(hostname).apkovl.tar.gz"
    if [ -e "$archive" ] && { [ ! -f "$archive" ] || [ -L "$archive" ]; }; then
        echo "Refusing a non-regular P4 archive: $archive" >&2; return 1;
    fi
    pending="/mnt/alpine/.mshell-p4-recovery.$$.tmp"
    [ ! -e "$pending" ] || { echo "Temporary P4 path already exists: $pending" >&2; return 1; }
    stage=$(mktemp -d /tmp/mshell-p4-recovery.XXXXXX) || return 1
    trap 'rm -f -- "$pending"; rm -rf -- "$stage"' 0
    trap 'exit 1' 1 2 15
    previous="$stage/previous.tar.gz"
    candidate="$stage/candidate.tar.gz"
    inspect="$stage/inspect"
    had_previous=0
    if [ -e "$archive" ]; then
        cp "$archive" "$previous" || return 1
        cmp -s "$archive" "$previous" || return 1
        had_previous=1
    fi

    echo '[PERSIST] Packaging the current root-owned Alpine state outside P4...'
    lbu package "$candidate" || return 1
    if [ ! -s "$candidate" ] || ! tar -tzf "$candidate" >/dev/null 2>&1; then
        echo 'New P4 archive is empty or invalid.' >&2; return 1;
    fi
    mkdir "$inspect" || return 1
    tar -xzf "$candidate" -C "$inspect" || return 1
    for protected in etc/passwd etc/group etc/shadow etc/sudoers.d etc/sudoers.d/tc etc/lbu/lbu.conf; do
        [ "$(stat -c '%u' "$inspect/$protected" 2>/dev/null)" = 0 ] || {
            echo "New P4 archive has invalid ownership: $protected" >&2; return 1;
        }
    done
    [ "$(stat -c '%a' "$inspect/etc/sudoers.d/tc")" = 440 ] &&
        [ -L "$inspect/home/tc/user_config.json" ] &&
        [ "$(readlink "$inspect/home/tc/user_config.json")" = /mnt/tcrp/user_config.json ] || {
        echo 'New P4 archive has unsafe sudoers permissions or lacks the config link.' >&2; return 1;
    }
    echo '[PERSIST] New archive ownership and config link verified.'

    # Neither temporary file has Alpine's *.apkovl.tar.gz boot-discovery name.
    # Keep the former P4 archive only in /tmp for rollback; delete it on success.
    if ! cp "$candidate" "$pending" || ! cmp -s "$candidate" "$pending" ||
       ! mv -f "$pending" "$archive"; then
        echo 'Could not activate the verified P4 archive; previous archive left in place.' >&2
        return 1
    fi
    if ! sync || ! cmp -s "$candidate" "$archive" ||
       ! tar -tzf "$archive" >/dev/null 2>&1; then
        echo 'P4 verification failed after activation; restoring the previous archive.' >&2
        if [ "$had_previous" -eq 1 ]; then
            if ! cp "$previous" "$pending" || ! mv -f "$pending" "$archive" || ! sync; then
                rm -f -- "$pending"
                trap - 0 1 2 15
                echo "URGENT: automatic P4 rollback failed. Previous archive is preserved at $previous" >&2
                return 1
            fi
        else
            rm -f "$archive" || return 1
        fi
        return 1
    fi
    new_hash=$(sha256sum "$archive" | awk '{print $1}')
    rm -f -- "$pending"
    rm -rf -- "$stage"
    trap - 0 1 2 15
    echo "[PERSIST] SUCCESS: repaired P4 archive at $archive"
    echo "[PERSIST] SHA-256: $new_hash"
    echo '[PERSIST] Temporary backup and candidate removed.'
}

finish_recovery() {
    verify_recovered_state || return 1
    echo 'P3 mount, alias, user_config.json link, ownership, and write access verified.'
    migrate_legacy_p3_overlay || return 1
    persist_recovered_state
}

if [ "$(mounts | wc -l | tr -d ' ')" -eq 1 ] && [ "$(mounts)" = "$point" ]; then
    opts=$(options)
    case ",$opts," in *,rw,*fmask=0000,*dmask=0000,*)
        ln -sfn "$point" /mnt/tcrp
        restore_home_config_link
        finish_recovery
        echo 'P3 already has the required single writable mount.'
        exit 0
        ;;
    esac
fi

# A mount may be busy because a shell or swapfile still uses it. Never force
# or lazily unmount: stop and leave the remaining mount available for recovery.
sync
attempt=0
while [ -n "$(mounts)" ]; do
    attempt=$((attempt + 1))
    [ "$attempt" -le 8 ] || { echo 'Too many mount layers; stopped.' >&2; exit 1; }
    path=$(mounts | tail -n 1)
    umount "$path" || { echo "Busy mount; stopped at $path" >&2; exit 1; }
done

mkdir -p "$point"
if ! mount -t vfat -o rw,umask=000 "$dev" "$point"; then
    echo 'Writable mount failed. Trying read-only mount for inspection.' >&2
    mount -t vfat -o ro "$dev" "$point" 2>/dev/null || true
    exit 1
fi
opts=$(options)
case ",$opts," in *,rw,*) ;; *) echo 'Mount remains read-only.' >&2; exit 1 ;; esac
case ",$opts," in *,fmask=0000,*) ;; *) echo 'fmask is not 0000.' >&2; exit 1 ;; esac
case ",$opts," in *,dmask=0000,*) ;; *) echo 'dmask is not 0000.' >&2; exit 1 ;; esac
[ -w "$point" ] || exit 1
[ ! -f "$point/user_config.json" ] || [ -w "$point/user_config.json" ] || exit 1

ln -sfn "$point" /mnt/tcrp
[ "$(readlink /mnt/tcrp)" = "$point" ] || exit 1
restore_home_config_link
finish_recovery
echo "P3 recovered at $point (rw,fmask=0000,dmask=0000)."
echo 'Recovery and persistence completed; recheck the menu before rebooting.'
