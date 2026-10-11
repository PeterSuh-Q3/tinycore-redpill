#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOOK="${ROOT}/alpine/local.d-restore-packages.start"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT HUP INT TERM

HELPER="${TMP}/usr/local/sbin/mshell-autologin-tc"
BACKUP="${TMP}/etc/mshell/mshell-autologin-tc"
INITTAB="${TMP}/etc/inittab"
mkdir -p "$(dirname "${HELPER}")" "$(dirname "${BACKUP}")" "$(dirname "${INITTAB}")"

cat > "${BACKUP}" <<'EOF'
#!/bin/sh
attempt=0
while [ ! -x /usr/bin/sx ] && [ "${attempt}" -lt 180 ]; do
  sleep 1
  attempt=$((attempt + 1))
done
exec /bin/login -f tc
EOF
chown 0:0 "${BACKUP}"
chmod 0755 "${BACKUP}"
printf '%s\n' 'tty1::respawn:/sbin/getty -n -l /usr/local/sbin/mshell-autologin-tc 38400 tty1' > "${INITTAB}"

run_hook() {
  MSHELL_AUTOLOGIN_TEST_ONLY=1 \
  MSHELL_AUTOLOGIN_HELPER="${HELPER}" \
  MSHELL_AUTOLOGIN_BACKUP="${BACKUP}" \
  MSHELL_INITTAB_FILE="${INITTAB}" \
    sh "${HOOK}"
}

echo "[TEST] Recover a missing helper from its root-owned backup"
run_hook
cmp -s "${HELPER}" "${BACKUP}"
[ "$(stat -c '%u:%g' "${HELPER}")" = '0:0' ]
[ "$(stat -c '%a' "${HELPER}")" = '755' ]

echo "[TEST] Repair an existing helper that lost execute permission"
chmod 0644 "${HELPER}"
run_hook
[ -x "${HELPER}" ]

echo "[TEST] Fall back to an interactive getty when both copies are invalid"
rm -f "${HELPER}" "${BACKUP}"
if run_hook 2>"${TMP}/fallback.log"; then
  echo "Expected recovery to report failure when no valid helper copy exists." >&2
  exit 1
fi
grep -q '^tty1::respawn:/sbin/getty 38400 tty1$' "${INITTAB}"
grep -q 'switching tty1 to a normal login prompt' "${TMP}/fallback.log"

echo "All Alpine tty1 recovery tests passed."
