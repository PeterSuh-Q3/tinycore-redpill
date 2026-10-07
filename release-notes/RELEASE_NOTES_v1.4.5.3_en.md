# alpine-redpill v1.4.5.3

## NVIDIA driver package selection

Driver versions that are not published for the selected platform and DSM kernel could be chosen from the loader menu, leading to an unavailable package during installation. The menu now lists versions from the published SPK manifest for the matching kernel/platform and warns when the manifest or a saved selection is unavailable.

## xTCRP boot menu compatibility

The xTCRP image does not normally provide the Alpine partition used by the Alpine build entry, while menu numbering must remain stable for automation. Its menu slot now points to the same usable xTCRP configure/build entry as the following slot, with a distinct title. The normal Alpine entry generator remains unchanged and is used when the Alpine partition is available.
