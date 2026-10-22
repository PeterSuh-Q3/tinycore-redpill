# alpine-redpill v1.4.5.7

## Keep large optional package downloads out of the loader image

MSHELL Manager, Syno Smart Info, and (on supported AMD systems) AMD GPU Runtime can make the DSM initrd much larger when their complete package files are embedded during a loader build. The loader now carries verified release metadata instead; DSM downloads the package to a mounted data volume after its package services are available, checks its size and SHA-256, and then installs it. An already-current package is left alone. Temporary download or service failures do not block DSM startup and can be retried on a later boot. This reduces initrd size without changing the normal DSM boot path. The post-boot installation flow has passed isolated loader-image and mock tests; end-to-end validation on a real DSM system is still pending.

## Choose the NVIDIA kernel-module flavor where supported

On supported kernel 5.10.55 systems, the NVIDIA driver menu now offers Open and Proprietary module flavors for compatible driver branches. Open modules are restricted to Turing-or-newer GPUs; older supported GPUs continue to use the Proprietary flavor. This lets users select a suitable module family without changing the rest of the driver options.

## Match device-specific options to the selected hardware

The NVMe mapping option now describes PAS7700 data-volume mapping only when PAS7700 is selected; other models are shown the M.2 cache mapping label. The system monitor also lists detected display GPUs, which makes multi-GPU systems easier to identify during setup.

PCI module suggestions now request the alias index matching the selected kernel and skip the optional suggestion step with a clear warning if that index is unavailable, rather than presenting a missing-file parse error. Automatic inclusion of Junior Realtime Helper has been paused while its display/KMS stability is being investigated; users should not expect it to be added automatically by the model list in this release.
