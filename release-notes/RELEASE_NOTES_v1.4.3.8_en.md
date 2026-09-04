# alpine-redpill v1.4.3.8

## Network reliability for mixed Static IP and DHCP configurations

The multi-NIC Static IP feature introduced in v1.4.3.7 has been hardened for real mixed-network use.

- Static NICs now stop only their own DHCP client before an address is applied. Other NICs remain on DHCP.
- DHCP routes and DNS can no longer replace the selected primary static gateway. Per-interface source routing preserves return traffic on DHCP interfaces.
- Removing a static IP entry immediately restores that interface to DHCP, instead of leaving its previous static address active.
- Saved multi-NIC settings are applied correctly during loader startup using the current array-based configuration format.

## AMD GPU detection and package staging

- AMD GPU detection now recognizes PCI display classes `0300`, `0302`, and `0380`. This includes headless and server GPUs that are not reported as a conventional VGA controller.
- AMD firmware is retained whenever a supported AMD display device is found, preventing a userspace runtime from being embedded without the firmware required by the kernel driver.
- The AMDGPU runtime and `amdgpu_top` are now staged and verified as separate packages.

## Intel GPU Top is included automatically

`syno-intel-gpu-top` is now embedded in `/addons` and queued for DSM installation on every loader build. It does not require an Intel GPU detection result or a loader kernel-family condition.

![Intel GPU Top](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/assets/07-intel-GPU.png)
