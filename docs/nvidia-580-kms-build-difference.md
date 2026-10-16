# NVIDIA 580 Proprietary KMS build difference (2026-10-16)

## Confirmed physical results

- The canonical EPYC7002 580.173.02 Proprietary module archive successfully
  loaded `nvidia-drm modeset=1` on a DSM 7.4, kernel 5.10.55+ device. Its
  archive SHA-256 is
  `df457fbb6559938afcfc8816ebe06c56d0e8b1a53e920a9dce54dcc1346884a4`.
- A later EPYC7002 focused3 rebuild and the r1000nk candidate both triggered
  an Oops in DRM `add_dr` / `drm_dev_register` while inserting
  `nvidia-drm.ko modeset=1`. These are not safe release replacements.
- The same failing build rule produced untested icelaked and v1000nk
  candidates. Do not load them based only on successful compilation or
  imported-symbol-name checks.

## The key observed difference

The successful EPYC7002 `nvidia-drm.ko` imports 132 unique DRM symbols. Both
Oops-producing modules import 124, with identical DRM import sets. Relative
to the failing modules, the successful module additionally imports
`drm_aperture_remove_conflicting_framebuffers`,
`drm_aperture_remove_conflicting_pci_framebuffers`,
`drm_atomic_helper_shutdown`, `drm_connector_atomic_hdr_metadata_equal`,
`drm_connector_attach_colorspace_property`,
`drm_connector_attach_hdr_output_metadata_property`,
`drm_edid_override_connector_update`, `drm_file_get_master`,
`drm_mode_create_dp_colorspace_property`, and
`drm_mode_create_hdmi_colorspace_property`. The failing modules instead
import `drm_gem_handle_delete` and `drm_master_get`.

This points to different NVIDIA `conftest` / DRM API selection. It is not yet
proof that these symbol differences alone caused the Oops. The live/released
r1000nk `drm.ko` and a freshly built provider copy have different whole-file
CRCs but identical `.text` SHA-256, so CRC difference alone does not establish
a provider ABI mismatch.

## Shim and reproducibility boundary

The successful EPYC7002 build **did use** the pinned symbol-alias shim at
`/Users/yousuk/syno_nvidia_driver/scripts/kms-compat/580.173.02/focused3-shim/drm-provider-symbol-aliases.h`.
The failed r1000nk build also passed a symbol-alias shim through
`EXTRA_CFLAGS`. Therefore shim presence is **not** the distinguishing factor.
No separate DRM-provider module pack was loaded for the successful EPYC7002
test; that does not mean the shim was absent.

The preserved EPYC7002 attempt-6 log confirms `NO_BACKLIGHT=1`, module
linking, and artifact hash. It does not preserve the full original
`EXTRA_CFLAGS`, `KBUILD_EXTRA_SYMBOLS`, or job count. The exact configuration
difference and a byte-for-byte reproducible build command are therefore not
yet established. Preserve the verified archive while investigating the
NVIDIA conftest/header/config selection before another device load.
