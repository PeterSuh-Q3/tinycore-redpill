# alpine-redpill v1.4.6.4

## Restore DHCP connectivity when saved IP settings are incomplete

A blank or incomplete saved static-IP entry could be mistaken for a configured static network. The loader would then suppress DHCP gateway handling without installing a usable static gateway, preventing internet checks and online updates.

This release removes unusable static-IP entries and returns to an empty `ipsettings` list when no usable primary gateway is configured. It also renews an existing DHCP lease when the old static policy left the default route missing. DHCP can then provide the address, gateway, and DNS, while complete static NIC entries remain available.

If an older loader is already offline because of this saved setting, set `ipsettings` to `[]` before updating so DHCP can restore internet access.
