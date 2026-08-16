cb0a9eaae9062f0a39d6a364c02912697a640da5
0284f6408a52fcbfdf404a87b11f0af508e7878b
a6a3bc948b72c451b1bb3f51ae27aed82118aa27

    1.4.3.1 Promoted from the test track: /home/tc/user_config.json is now a symlink onto
/mnt/tcrp/user_config.json (a stable alias for the loader partition maintained
across disk-enumeration changes) instead of a second, separately-synced copy.
writeConfigKey()/sync_usb_line() now preserve that symlink across writes instead
of replacing it with a plain file. DeleteConfigKey() and preserve_usb_line_options()
now drop general.usb_line entries for extra_cmdline keys (sn/mac1-8/vid/pid/
netif_num) that no longer exist, instead of leaving them orphaned indefinitely.
