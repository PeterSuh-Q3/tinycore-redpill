# SynoXtract PAT extractor

This directory vendors the original SynoXtract source and includes a Linux x86-64 CLI binary for extracting encrypted Synology PAT files.

## Contents

- `synoxtract`: statically linked Linux x86-64 CLI built from the source in `source/`.
- `synoxtract-1.1-linux.tar.gz`: upstream build script's packaged copy of that CLI.
- `source/`: tracked files from the upstream SynoXtract repository at the commit recorded below.
- `BUILD.md`: upstream provenance, build environment, hashes, and validation notes.

## Usage

```sh
./synoxtract -i DSM_SA6400_90080.pat -l
./synoxtract -i DSM_SA6400_90080.pat -d extracted -f VERSION zImage rd.gz hda1.tgz
```

This is a Linux x86-64 binary; it does not run natively in macOS. Run it in a Linux environment such as Docker Desktop.
