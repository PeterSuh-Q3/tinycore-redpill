#!/usr/bin/env bash
# Inspect the GRUB EFI executable and installed module code. Embedded EFI
# module blobs and the compressed BIOS core are not fully disassembled here.
set -euo pipefail

root=${1:?usage: check-grub-x86-baseline.sh MOUNTED_GRUB_PARTITION}
efi="$root/EFI/BOOT/BOOTX64.EFI"
command -v objdump >/dev/null || { echo 'objdump is required' >&2; exit 1; }
[[ -f "$efi" ]] || { echo "Missing EFI executable: $efi" >&2; exit 1; }
for arch in i386-pc x86_64-efi; do
  [[ -d "$root/boot/grub/$arch" ]] || { echo "Missing GRUB module directory: $arch" >&2; exit 1; }
  [[ -n "$(find "$root/boot/grub/$arch" -type f -name '*.mod' -print -quit)" ]] || {
    echo "No GRUB modules found in $arch" >&2; exit 1;
  }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
files=("$efi")
[[ ! -f "$root/EFI/AlpineRedpill/grubx64.efi" ]] || files+=("$root/EFI/AlpineRedpill/grubx64.efi")
while IFS= read -r -d '' file; do files+=("$file"); done < <(
  find "$root/boot/grub/i386-pc" "$root/boot/grub/x86_64-efi" -type f -name '*.mod' -print0
)
(( ${#files[@]} > 1 )) || { echo 'No GRUB modules found' >&2; exit 1; }
bad=0
for file in "${files[@]}"; do
  if ! objdump -d --no-show-raw-insn "$file" > "$tmp/disassembly" 2> "$tmp/error"; then
    echo "Cannot disassemble $file:" >&2
    cat "$tmp/error" >&2
    exit 1
  fi
  # x86-64 baseline excludes BMI1/2, AVX and common v2/v3 extensions.
  # VEX/EVEX vector mnemonics start with v; exclude older unrelated opcodes.
  if awk '
    $1 ~ /^[[:xdigit:]]+:$/ {
      op=tolower($2)
      if (op ~ /^(andn|bextr|blsi|blsmsk|blsr|bzhi|mulx|pdep|pext|rorx|sarx|shlx|shrx|tzcnt|lzcnt|popcnt|movbe|crc32|aesenc|aesenclast|aesdec|aesdeclast|aesimc|aeskeygenassist|pclmulqdq)$/ ||
          (op ~ /^v[[:alpha:]][[:alnum:]_.]*$/ && op !~ /^(verr|verw|vmcall|vmclear|vmlaunch|vmptrld|vmptrst|vmread|vmresume|vmwrite|vmxoff|vmxon|vmmcall)$/)) {
        print; bad=1
      }
    }
    END { exit !bad }
  ' "$tmp/disassembly" > "$tmp/matches"; then
    echo "Unsupported x86 instruction(s) in $file:" >&2
    head -20 "$tmp/matches" >&2
    bad=1
  fi
done
(( bad == 0 )) || exit 1
echo "GRUB x86 baseline check passed for ${#files[@]} files ($root)"
