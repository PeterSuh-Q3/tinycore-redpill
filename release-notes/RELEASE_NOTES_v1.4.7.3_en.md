# alpine-redpill v1.4.7.3

## Configure Wi-Fi for DSM junior

Previously, setting up a wireless connection for DSM junior could require editing the configuration by hand, especially when the loader had no working network yet. The menu now lets you scan for an access point or enter its SSID manually, then save WPA2-Personal credentials for the next loader build. A compatible wireless adapter and driver are still required. The credentials are included in the configuration and generated initrd, so protect the loader files.

## MacBook Pro 2014 USB boot compatibility

Some MacBook Pro 2014 systems can hand off USB controller routing in a state that prevents DSM from finding the loader's USB partitions. For the specifically identified MacBookPro11,1 model, an early routing correction is attempted only when the expected controller identity and register state match; other states are left unchanged.

## Gen8 CPU compatibility warning

Gen8 systems with non-Atom Intel CPUs from the 3rd generation or earlier are not recommended for installing models that need newer CPU features. Denverton (DVA3221), Apollo Lake (DS918+), and Gemini Lake (DS920+) entries are hidden from the model menu in this case because booting them on Gen8 may cause a kernel panic or freeze.
