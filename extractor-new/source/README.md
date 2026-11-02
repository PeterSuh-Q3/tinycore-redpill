# SynoXtract CLI and GUI

Synology .pat/.spk file decryption and extraction utility.

## Dependencies

- `libsodium`
- `msgpack-cxx`

## GUI  Usage

1. Run synoxtract-gui.exe.
2. File -> Open or Drag a file into the window.
3. Select files and click Select Extract, or click All Extract.
4. Choose the destination. By default, the files go into a new folder next to the archive, named after it. Existing files are overwritten.
5. Check the Status Bar for progress.

## CLI Usage

```bash
# List files in archive
./synoxtract -i DSM.pat -l

# Extract all files to directory
./synoxtract -i DSM.pat -d output_dir

# Extract specific files
./synoxtract -i DSM.pat -d output_dir -f INFO
```

Without `-d`, files are extracted to the current directory. The exit code is 1 if any file could not be extracted or a name given with `-f` is not in the archive.

## Building on Windows

Requires Visual Studio 2022 with the C++ tools and [vcpkg](https://github.com/microsoft/vcpkg).

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 -VcpkgRoot C:\vcpkg
```

The zip files and their `.sha256sum` files are written to `dist\`.

## Building on Linux

Requires `g++` on a Debian-based system. Root is not needed: `apt-get download` fetches the dependencies, and they are unpacked into `build/linux/deps`.

```bash
bash build.sh
```

This builds a statically linked CLI, without the GUI. The `.tar.gz` file and its `.sha256sum` file are written to `dist/`.

Inspired by:
- [patology](https://github.com/sud0woodo/patology)
- [Synology_Archive_Extractor](https://github.com/K4L0dev/Synology_Archive_Extractor)
