#!/bin/sh
# Installed only for a confirmed MacBookPro11,1 loader build. The DSM kernel
# may not expose DMI, so verify the PCI identity and exact observed masks here.

log() {
    echo "apple-xhci-route: $*"
    if [ -w /dev/kmsg ]; then
        printf '<6>apple-xhci-route: %s\n' "$*" > /dev/kmsg 2>/dev/null || :
    fi
}

pci=/sys/bus/pci/devices/0000:00:14.0
config="$pci/config"
for pair in vendor:0x8086 device:0x9c31 subsystem_vendor:0x8086 subsystem_device:0x7270; do
    key=${pair%%:*}
    expected=${pair#*:}
    [ -r "$pci/$key" ] && [ "$(cat "$pci/$key" 2>/dev/null)" = "$expected" ] || {
        log "PCI identity mismatch or unavailable; skipping"
        exit 0
    }
done
[ -r "$config" ] && [ -w "$config" ] && [ -x /usr/bin/cksum ] || {
    log "PCI config or checksum tool unavailable; skipping"
    exit 0
}

# Compare exact 16-byte register snapshots; no hexdump or setpci is required.
# d0=0, d4=0x1ff, d8=0, dc=0xf is the observed affected handoff.
before=$(dd if="$config" bs=16 skip=13 count=1 2>/dev/null | /usr/bin/cksum) || exit 0
disabled=$(printf '\000\000\000\000\377\001\000\000\000\000\000\000\017\000\000\000' | /usr/bin/cksum) || exit 0
enabled=$(printf '\377\001\000\000\377\001\000\000\017\000\000\000\017\000\000\000' | /usr/bin/cksum) || exit 0
if [ "$before" = "$enabled" ]; then
    log "routing already enabled; no change"
    exit 0
fi
if [ "$before" != "$disabled" ]; then
    log "unexpected routing or masks ($before); skipping"
    exit 0
fi

log "restoring observed USB2 and USB3 routes (d0=0x1ff d8=0xf)"
if ! printf '\377\001\000\000' | dd of="$config" bs=4 seek=52 count=1 2>/dev/null; then
    log "USB2 routing write failed"
    exit 0
fi
if ! printf '\017\000\000\000' | dd of="$config" bs=4 seek=54 count=1 2>/dev/null; then
    log "USB3 routing write failed; USB2 routing may already have changed"
    exit 0
fi
after=$(dd if="$config" bs=16 skip=13 count=1 2>/dev/null | /usr/bin/cksum) || exit 0
if [ "$after" = "$enabled" ]; then
    log "routing restored and verified"
else
    log "routing readback did not match expected values ($after)"
fi
exit 0
