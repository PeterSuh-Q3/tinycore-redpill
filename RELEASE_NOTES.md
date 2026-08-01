11042014f83f4bf1bd1f460aeb1584fc2a9596bb
693347b98673923558c0f0107ebf4e1143c2ea48
9467bea609f96aac39f93078ef714d47524fde20

    1.4.2.5 Disabled the legacy TinyCore-only multi-NIC eth* reorder and DHCP/default-route reset
             at menu startup: Alpine and xTCRP already enumerate NICs in PCI order, preserving
             active SSH management sessions. Expanded BMI2-free custom-modules support on
             kernel-5 platforms through DSM 7.4.1 and aligned version gating accordingly.
    1.4.2.4 Completed menu localization: every remaining hardcoded English string across the main
