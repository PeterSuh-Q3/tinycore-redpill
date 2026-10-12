#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="${ROOT}/alpine/rebuildnetifaces"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

SYS="${TMP}/sys/class/net"
IFACES="${TMP}/etc/network/interfaces"
mkdir -p "${SYS}/lo" "${SYS}/eth0" "$(dirname "$IFACES")"

run_reconcile() {
  MSHELL_SYS_CLASS_NET="$SYS" MSHELL_NETWORK_INTERFACES="$IFACES" sh "$SCRIPT"
}

echo "[TEST] Remove stale eth1 while retaining the active eth0 stanza"
cat > "$IFACES" <<'EOF'
auto lo
iface lo inet loopback

auto eth0 eth1
iface eth0 inet dhcp

auto eth1
iface eth1 inet dhcp
EOF
run_reconcile
grep -q '^iface eth0 inet dhcp$' "$IFACES"
! grep -Eq '(^|[[:space:]])eth1([[:space:]]|$)' "$IFACES"

echo "[TEST] Preserve static settings for present NICs and do not invent eth2"
mkdir -p "${SYS}/eth1"
cat > "$IFACES" <<'EOF'
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
    address 192.0.2.10
auto eth1
iface eth1 inet dhcp
EOF
run_reconcile
grep -q '^iface eth0 inet static$' "$IFACES"
grep -q 'address 192.0.2.10' "$IFACES"
grep -q '^iface eth1 inet dhcp$' "$IFACES"
! grep -q 'eth2' "$IFACES"

echo "[TEST] Remove eth1 again and discard only its now-stale configuration"
rmdir "${SYS}/eth1"
run_reconcile
! grep -Eq '(^|[[:space:]])eth1([[:space:]]|$)' "$IFACES"

echo "[TEST] Add newly detected eth2 as DHCP without replacing existing config"
mkdir -p "${SYS}/eth2"
run_reconcile
grep -q '^iface eth2 inet dhcp$' "$IFACES"
grep -q 'address 192.0.2.10' "$IFACES"

echo "[TEST] Refuse to rewrite when sysfs is unavailable"
cp "$IFACES" "${TMP}/before"
if MSHELL_SYS_CLASS_NET="${TMP}/missing" MSHELL_NETWORK_INTERFACES="$IFACES" sh "$SCRIPT"; then
  echo "Expected reconciliation to fail without sysfs." >&2
  exit 1
fi
cmp -s "${TMP}/before" "$IFACES"

echo "All Alpine network-interface reconciliation tests passed."
