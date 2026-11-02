# Build and provenance

- Upstream: https://github.com/prt1999/SynoXtract
- Upstream source commit: `158aa98995282b1da809a83318e26b2fcc878e69`
- Upstream version: 1.1
- Linux build script: `source/build.sh`
- Build environment: local `dante90/syno-compiler:7.4` Docker image, Debian 12 bookworm, amd64
- Compiler: Synology target GCC/G++ 12.2.0 (`x86_64-pc-linux-gnu`)
- Build script dependencies downloaded from Debian Bookworm: `libsodium-dev` 1.0.18-1+deb12u1 and `libmsgpack-cxx-dev` 4.1.3-1
- Compiler defaults: `-march=x86-64`, `-mtune=generic`; AVX, AVX2, BMI, BMI2, and ADX disabled
- Output: statically linked Linux x86-64 executable

## SHA-256

- `synoxtract`: `66503d9d61e99cd2534e6ab39b880c83d5466322ea294efb700e9ac2e90cbe90`
- `synoxtract-1.1-linux.tar.gz`: `413598b26ae2b615e02cad75051c5c6176925fecb6f942e3ce191f0634b175b9`

## Validation

Built the CLI from the vendored source in the stated Debian container. It listed and extracted `VERSION`, `zImage`, `rd.gz`, and `hda1.tgz` from the official SA6400 DSM 7.4.1-90080 PAT. PAT files and extracted DSM contents are not included here.

Static disassembly shows AVX2 instructions in an optimized libsodium implementation and CPU feature detection using CPUID/XGETBV. No BMI2 mnemonics were found by the inspection performed. The AVX2 implementation appears to be runtime-dispatched; execution has not been tested on a CPU without AVX. This binary is x86-64 Linux and is not a native macOS executable.

The upstream repository did not include a license file at the pinned commit. This directory preserves the upstream source and attribution; confirm upstream licensing terms before redistribution beyond this repository.
