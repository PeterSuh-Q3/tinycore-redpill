d43089212ed814fc88e2d0ea96cfe46d2d7267c9
75e64ab958d984194a4e69ec836d55061d064ffe
bab81ae47929bebd4b51a80aebffe97c0aa65ddb

    1.3.1.1 Added DHCP lease-renewal suppression for the TinyCore loader session. Freezes the DHCP-assigned IP right
before the build, stopping periodic renew/rebind traffic and preventing mid-build IP changes.
