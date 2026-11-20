# alpine-redpill v1.4.7.3

## Configure Wi-Fi for DSM junior

Previously, setting up a wireless connection for DSM junior could require editing the configuration by hand, especially when the loader had no working network yet. The menu now lets you scan for an access point or enter its SSID manually, then save WPA2-Personal credentials for the next loader build. A compatible wireless adapter and driver are still required. The credentials are included in the configuration and generated initrd, so protect the loader files.

## Intel Mac USB boot compatibility

Some Intel-based MacBooks and Mac mini systems may hand off USB controller routing in a state that prevents DSM from finding the loader's USB partitions. This release adds a guarded early xHCI routing correction toward broader Intel Mac compatibility. The automatic correction is currently enabled only for the specifically identified MacBookPro11,1 controller and its verified register state; other Mac models remain unverified and are left unchanged.

## Gen8 CPU compatibility warning

Gen8 systems with non-Atom Intel CPUs from the 3rd generation or earlier are not recommended for installing models that need newer CPU features. Denverton (DVA3221), Apollo Lake (DS918+), and Gemini Lake (DS920+) entries are hidden from the model menu in this case because booting them on Gen8 may cause a kernel panic or freeze.
