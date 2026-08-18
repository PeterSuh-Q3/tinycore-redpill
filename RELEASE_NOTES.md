dceafd32b684436f9485e8f9570f541a75fc16ff
b27110912f1780e901d1c4a604f8028135c0e69f
a6a3bc948b72c451b1bb3f51ae27aed82118aa27

    1.4.3.1 Promoted from the test track: /home/tc/user_config.json is now a symlink onto
/mnt/tcrp/user_config.json (a stable alias for the loader partition maintained
across disk-enumeration changes) instead of a second, separately-synced copy.
writeConfigKey()/sync_usb_line() now preserve that symlink across writes instead
