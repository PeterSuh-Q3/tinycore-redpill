#!/bin/sh
# Manual recovery for a multiply mounted Alpine loader P3. Not a boot hook.
# Usage: sudo sh recover-alpine-p3.sh [--apply]
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
    [ -f "$config" ] && jq -e 'type == "object"' "$config" >/dev/null 2>&1 || {
        echo "P3 user_config.json is missing or invalid: $config" >&2; return 1;
    }
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

persist_recovered_state() {
    command -v lbu >/dev/null 2>&1 || { echo 'lbu is unavailable; persistence skipped.' >&2; return 1; }
    command -v tar >/dev/null 2>&1 || { echo 'tar is unavailable; persistence skipped.' >&2; return 1; }

    # Ensure the restored link is part of the apkovl, then commit and verify
    # the generated archive before reporting recovery as complete.
    lbu include /home/tc/user_config.json || {
        echo 'Could not include the recovered config link in Alpine persistence.' >&2; return 1;
    }
    lbu commit || { echo 'Alpine persistence backup failed.' >&2; return 1; }

    archive="/mnt/alpine/$(hostname).apkovl.tar.gz"
    [ -s "$archive" ] && tar -tzf "$archive" >/dev/null 2>&1 || {
        echo "Persistence archive is missing or invalid: $archive" >&2; return 1;
    }
    if ! tar -tzf "$archive" | grep -Eq '(^|/)home/tc/user_config\.json$'; then
        echo 'The verified persistence archive does not contain the recovered config link.' >&2
        return 1
    fi
    echo "Alpine persistence backup verified: $archive"
}

finish_recovery() {
    verify_recovered_state || return 1
    echo 'P3 mount, alias, user_config.json link, ownership, and write access verified.'
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
