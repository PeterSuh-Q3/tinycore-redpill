# Active Context

Last updated: 2026-09-07

This is a compact, evidence-based handoff for the active MSHELL work. It is
not a credential store. Read it together with `AGENTS.md` and `AGENTS.ms`.

## Current scope

Investigate DSM 7.4 `Unknown symbol` errors on the epyc7002 / sa6400 module
path and identify the addon or module-pack source before changing load logic.

## Confirmed facts

### Affected DSM system

- DSM kernel family: sa6400 / epyc7002 DSM 7.4, kernel `5.10.55+`.
- Observed errors:
  - `r8153_ecm`: missing `usbnet_cdc_bind`, `usbnet_cdc_status`,
    `usbnet_cdc_unbind`.
  - `adm9240` and `lm75`: missing `__devm_regmap_init_i2c`.
  - `i2c_i801`: missing `check_signature`.
- Live module files include `r8153_ecm.ko`, `usbnet.ko`, `adm9240.ko`,
  `lm75.ko`, `i2c-i801.ko`, and `i2c-smbus.ko`.
- Required providers were absent from the live module set:
  `cdc_ether.ko`, `regmap-i2c.ko`, `regmap-core.ko`, and a provider exporting
  `check_signature`.
- The live `modules.dep` is incomplete for this set. It omits `cdc_ether` for
  `r8153_ecm` and omits `regmap-i2c` for `adm9240`/`lm75`, even though module
  metadata declares those dependencies. Therefore plain `modprobe` can load a
  consumer without its real providers.

### Source ownership

- `tcrp-modules/ddsml/releases/check-all-modules.sh` unconditionally attempts
  to load `r8153_ecm` as part of `usblan_modprobe`.
- `tcrp-modules/etc-modules-load/src/install.sh` unconditionally attempts to
  load sensor modules including `adm9240` and `lm75`.
- `i2c-i801` is requested by stock DSM `linuxrc.syno.impl` for the relevant
  platform condition, rather than directly by `etc-modules-load`.
- In the clean
  `/Users/yousuk/mshell-modules/epyc7002-7.4-5.10.55` pack, `regmap-i2c.ko`
  exists and exports `__devm_regmap_init_i2c`; `i2c-i801.ko` and `k10temp.ko`
  do not. This indicates that the live `i2c-i801.ko` came through another
  module source and needs provenance tracing before it is retained.

### Hardware evidence from the diagnostic system

- Intel Haswell SMBus controller is present, so the I801 host controller is
  physically relevant but its currently supplied module is ABI-incompatible.
- No USB Realtek NIC was observed. Unconditional `r8153_ecm` loading is not
  needed on this hardware.

## Recommended next work

1. Trace the source that injects live `i2c-i801.ko` into the loader and compare
   its vermagic, symbols, and provenance against the target DSM kernel.
2. Change `ddsml` so `r8153_ecm` is loaded only when an applicable USB NIC is
   present, or remove it from unconditional preload.
3. Change `etc-modules-load` so I2C client sensor modules are not blindly
   loaded when their provider chain is absent. Preserve safe CPU/Super-I/O
   sensor support after dependency validation.
4. Test on both a system that contains the relevant hardware and one that does
   not; confirm no `Unknown symbol` messages and no loss of intended devices.

## Recent completed work in related repositories

- `tcrp-addons` commit `6260b34` fixes `misc` static-to-DHCP reconciliation:
  full DHCP restores prior MSHELL-owned interfaces, and mixed static/DHCP
  configurations restore only interfaces no longer represented by cmdline
  tokens. Its recipe checksum was updated and the full-DHCP case was verified
  on a DSM system.

## Tools and cautions

- TTYD client: `tools/ttyd-run.py`. Use it for terminal automation; browser
  terminal screenshots are not sufficient evidence.
- Do not store device credentials, private IP addresses, or tokens here.
- Existing historical handoff: `docs/handoff-v1.4.3.4-after.md`. It describes
  an older release checkpoint and must not override the newer facts above.
