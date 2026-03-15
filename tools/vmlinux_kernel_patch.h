function vmlinux_kpatch() {

# Add ARPL's vmlinux kernel patch 2023.10.26

# Track whether any extension provided a platform-specific "_custom" override directory.
# We detect this BEFORE the custom initramfs layer is packed/removed.
BRP_HAS_EXT_CUSTOM_DIR=0
shopt -s nullglob
for _d in "${BRP_USER_DIR}"/extensions/*/*_custom/; do
  BRP_HAS_EXT_CUSTOM_DIR=1
  break
done
shopt -u nullglob
pr_process "Found *_custom extension override dirs? %s" "${BRP_HAS_EXT_CUSTOM_DIR}"

pr_info "Found patched zImage at \"%s\" - skipping patching & repacking" "${BRP_ZLINUX_PATCHED_FILE}"
chmod -R a+x $PWD/buildroot/board/syno/rootfs-overlay/root
$PWD/buildroot/board/syno/rootfs-overlay/root/bzImage-to-vmlinux.sh "${BRP_ZLINUX_FILE}" "${BRP_CACHE_DIR}/vmlinux"
$PWD/buildroot/board/syno/rootfs-overlay/root/kpatch "${BRP_CACHE_DIR}/vmlinux" "${BRP_CACHE_DIR}/vmlinux-mod"
# If an extension "_custom" directory is present and the repo provides a custom kernel image,
# use it for zImage. Otherwise, fall back to the patched zImage.
if [[ "${BRP_HAS_EXT_CUSTOM_DIR:-0}" -eq 1 && "${BPR_LOWER_PLATFORM}" =~ ^(epyc7002|geminilakenk)$ ]]; then
  BRP_DSM_VER_FULL="${BRP_SW_VERSION%%-*}" # e.g. 7.2.1
  BRP_OLD_IFS="${IFS}"
  IFS='.' read -r _brp_dsm_mm1 _brp_dsm_mm2 _brp_dsm_rest <<< "${BRP_DSM_VER_FULL}"
  IFS="${BRP_OLD_IFS}"
  BRP_DSM_VER_MM="${_brp_dsm_mm1}.${_brp_dsm_mm2}"
  BRP_CUST_ZIMG_DIR="${BRP_EXT_DIR}/custom-zImage"
  BRP_CUST_ZIMG_GZ=""

  BRP_CUST_ZIMG_GZ="bzImage-${BPR_LOWER_PLATFORM}-${BRP_DSM_VER_MM}-5.10.55.gz"

  if [[ -n "${BRP_CUST_ZIMG_GZ}" ]] && [[ -f "${BRP_CUST_ZIMG_DIR}/${BRP_CUST_ZIMG_GZ}" ]]; then
    pr_process "Using custom bzImage for %s" "${BRP_ZLINUX_PATCHED_FILE}"
    "${GZIP_PATH}" -dc "${BRP_CUST_ZIMG_DIR}/${BRP_CUST_ZIMG_GZ}" > "${BRP_ZLINUX_PATCHED_FILE}" \
      || pr_crit "Failed to decompress %s" "${BRP_CUST_ZIMG_DIR}/${BRP_CUST_ZIMG_GZ}"
    pr_process_ok
  elif [[ -n "${BRP_CUST_ZIMG_GZ}" ]]; then
    pr_warn "Custom kernel requested but missing: %s (falling back to patched zImage)" "${BRP_CUST_ZIMG_DIR}/${BRP_CUST_ZIMG_GZ}"
  fi
else
  $PWD/buildroot/board/syno/rootfs-overlay/root/vmlinux-to-bzImage.sh "${BRP_CACHE_DIR}/vmlinux-mod" "${BRP_ZLINUX_PATCHED_FILE}"  
fi
rm -f "${BRP_CACHE_DIR}/vmlinux" "${BRP_CACHE_DIR}/vmlinux-mod"

}