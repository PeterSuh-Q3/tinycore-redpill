# alpine-redpill v1.4.4.2

## DVA7400 platform support

- Adds DVA7400 to the supported model list and model suggestion menu.
- Maps DVA7400 to the V1000NK platform and kernel 5.10 family.
- CPU: AMD Ryzen 1780B.
- AI acceleration: NVIDIA RTX 2000 Ada or RTX PRO 2000 Blackwell-class discrete GPU.
- Capacity: up to 100 cameras and up to 40 concurrent real-time AI analysis tasks.
- Designed for face and license-plate recognition, person and vehicle attribute or behavior analysis, intrusion and loitering detection, and natural-language video search.
- When the official NVIDIA runtime libraries are installed, the NVIDIA page can report NVIDIA-SMI 580.126.09 with CUDA 13.0, as verified on the included reference system.

![DVA7400 NVIDIA runtime status](https://raw.githubusercontent.com/PeterSuh-Q3/tinycore-redpill/alpine-redpill/docs/assets/DVA7400-nvidia-smi.png)

## Loader partition alias reliability

- Makes the stable `/mnt/tcrp` loader-partition alias safe to refresh repeatedly.
- Uses a non-dereferencing symbolic-link update so an existing `/mnt/tcrp` link is replaced directly rather than followed into the FAT loader partition.
- Verifies the resulting alias target and propagates a failure to the caller when the alias cannot be maintained.
