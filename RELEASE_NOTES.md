cb0a9eaae9062f0a39d6a364c02912697a640da5
7dffefba641bbacd5411809d7fd6060d968f85c6
a6a3bc948b72c451b1bb3f51ae27aed82118aa27

    1.4.3.1 Promoted from the test track: /home/tc/user_config.json is now a symlink onto
/mnt/tcrp/user_config.json (a stable alias for the loader partition maintained
across disk-enumeration changes) instead of a second, separately-synced copy.
writeConfigKey()/sync_usb_line() now preserve that symlink across writes instead
