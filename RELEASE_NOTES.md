11042014f83f4bf1bd1f460aeb1584fc2a9596bb
693347b98673923558c0f0107ebf4e1143c2ea48
9467bea609f96aac39f93078ef714d47524fde20

    1.4.2.6 Added a standalone dialog-based loader burner that safely converts a legacy TinyCore
loader to Alpine: it preserves user_config.json when present, accepts TinyCore media without an
alpine partition, and requires 8GB RAM for the 5GB image. Recording continues when no saved
configuration exists.
    1.4.2.5 Retired the legacy TinyCore-only multi-NIC eth* reorder and DHCP/default-route reset
from automatic menu startup. Alpine and xTCRP already enumerate NICs in PCI order;
avoiding the reset preserves active SSH management sessions. Expanded the BMI2-free
custom-modules path on kernel-5 platforms through DSM 7.4.1, including the relevant
version cap, model-selection correction, picker filtering, and module-mode validation.
