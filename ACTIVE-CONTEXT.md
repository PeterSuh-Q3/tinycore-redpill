# Active Context

Last updated: 2026-09-07

This is a compact, evidence-based handoff for the active MSHELL work. It is
not a credential store. Read it together with `AGENTS.md`.

## Current scope

Investigate DSM 7.4 `Unknown symbol` errors on the epyc7002 / sa6400 module
path, remove unsafe unconditional loads, and prepare a matched provider-only
build pilot before any module-pack publication.

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

### Published-archive and hardware cross-check

- The actual `/exts/all-modules/epyc7002-7.4-5.10.55.tgz` used by the
  diagnostic system contains `r8153_ecm.ko`, `adm9240.ko`, `lm75.ko`, and
  `i2c-i801.ko`, but does not contain `cdc_ether.ko`, `regmap-i2c.ko`, or
  `regmap-core.ko`.
- `mshell-modules/blacklist.lst` explicitly excludes `cdc_ether.ko`,
  `check_signature.ko`, and `regmap-i2c.ko`. The 5.10.55 USB Makefile also
  comments out `CONFIG_USB_NET_CDCETHER`, while keeping `r8153_ecm` enabled.
  The resulting `r8153_ecm` artifact is therefore structurally unloadable.
- No USB devices and no USB network controller were present on the diagnostic
  system. Its NICs are PCIe Realtek `10ec:8168` and Intel `8086:125c`; the
  unconditional USB `r8153_ecm` preload is unnecessary there.
- The Intel Haswell SMBus PCI controller `8086:8ca2` is physically present.
  However, the supplied `i2c-i801.ko` declares a dependency on
  `check_signature`, which is neither in the live module set nor exported by
  the running kernel. It is an incompatible artifact, not a provider that can
  safely be added alone.
- The only working I2C adapters are graphics-display buses. There is no
  successfully registered I801 SMBus adapter and no evidence of an ADM9240 or
  LM75 client device. The unconditional `adm9240` and `lm75` probes have no
  hardware basis on this system.

### Decision split

#### Remove or gate; do not add providers yet

- Remove `r8153_ecm` from unconditional `ddsml` USB-LAN preload. It must only
  be considered after a matching USB ECM device is detected and a complete,
  kernel-matched `cdc_ether` provider chain has been built.
- Stop unconditional loading of `adm9240` and `lm75` in `etc-modules-load`.
  They require a complete regmap chain and should be loaded only after a real
  matching I2C client has been identified.
- Do not retain `i2c-i801.ko` in the epyc7002 5.10.55 final pack until it is
  rebuilt against a runtime that exports `check_signature`. Its mere presence
  makes stock DSM attempt an incompatible load.

#### Preserve or validate separately

- Keep the successfully loaded non-regmap sensor drivers (`coretemp`,
  `nct6775`, `adt7470`, `adt7475`, `adm1021`, `adm1031`, `lm78`, and `lm90`)
  subject to per-platform validation; they did not produce the reported symbol
  errors on the diagnostic system.
- A future USB ECM support change must build and ship the complete matched set
  (`cdc_ether`, `usbnet`, and the relevant USB-core symbols) rather than merely
  unblacklisting one provider.
- A future I801 support change must use a matching DSM 5.10.55 build context
  that supplies both `i2c-i801` and `check_signature`; do not copy either
  module from another platform or kernel family.

### Build-host facts and pilot preparation

- The original Ubuntu build host is `192.168.45.139`. Its authoritative,
  root-owned Git checkout is `/root/mshell-modules` on branch `main`.
  `/home/dante90/mshell-modules` is an older non-Git copy and must not be used
  as the build source of truth.
- The root checkout contains the existing epyc7002 DSM 7.4 5.10.55 output and
  the `dante90/syno-compiler:7.4` image, but its trimmed input source lacks
  `lib/check_signature.c` and `drivers/base/regmap/regmap.c`. Those omissions
  explain why the old build can emit consumers without the complete provider
  closure.
- A pilot script is prepared at
  `/Users/yousuk/mshell-modules/tools/build-epyc7002-74-sensor-pilot.sh`.
  It deliberately requires a matching DSM runtime archive with `.config` and
  `Module.symvers` and a matching Synology GPL `linux-5.10.x.txz`; it refuses
  to build if those inputs or source files are absent.
- The pilot output is limited to the closure:
  `check_signature.ko`, `regmap-core.ko`, `regmap-i2c.ko`, `i2c-i801.ko`,
  `adm9240.ko`, and `lm75.ko`. `cdc_ether` and `r8153_ecm` are outside this
  pilot and remain candidates for removal or hardware-gated support.
- `tcrp-modules/etc-modules-load/src/install.sh` has an uncommitted safety
  change: it now resolves direct `modinfo` dependencies recursively, requires
  provider files before loading a consumer, and logs skips instead of allowing
  `Unknown symbol` failures. This is stricter than the former consumer-file
  existence check.

### Hardware evidence from the diagnostic system

- Intel Haswell SMBus controller is present, so the I801 host controller is
  physically relevant but its currently supplied module is ABI-incompatible.
- No USB Realtek NIC was observed. Unconditional `r8153_ecm` loading is not
  needed on this hardware.

## Recommended next work

1. Change `ddsml` to remove `r8153_ecm` from unconditional preload, then test
   a matching USB ECM device separately with a complete dependency build.
2. Copy the pilot script to the Ubuntu build host and run it only after the
   exact DSM runtime archive and Synology GPL source archive are identified.
3. Test the resulting six-module closure on the target epyc7002 DSM 7.4
   device before changing the published pack.
4. Keep or remove `i2c-i801.ko` according to the pilot result; do not ship its
   current unresolved version.
5. Test a system with the relevant hardware and one without it; confirm no
   `Unknown symbol` messages and no loss of intended devices.

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
