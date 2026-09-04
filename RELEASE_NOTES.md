89138c0486b59dcd4bcb2523ea2427c7cdc33423
d32116efe1db70ca8b5d3f7dc4227aefdd8b9dce
a8f15bbb908950c5e574e0ec44b196b5ce23639e

    1.4.3.8 Multi NIC static routing and GPU package integration
Static IP activation now removes stale DHCP/default routes before
applying addresses and reasserts one primary gateway afterwards.
This prevents same-subnet multi-NIC systems from sending DNS and
HTTPS traffic through an unpredictable interface.
The routing cleanup is centralized in apply_static_ip_now() so all
static-IP application paths share the same behavior; no automatic
fallback DNS server is added.
