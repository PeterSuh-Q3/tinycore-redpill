d43089212ed814fc88e2d0ea96cfe46d2d7267c9
3a9652b5f4888f72b47d08b8593fe32940d4015c
bab81ae47929bebd4b51a80aebffe97c0aa65ddb

    1.3.1.1 Added DHCP lease-renewal suppression for the TinyCore loader session. Freezes the DHCP-assigned IP right
before the build, stopping periodic renew/rebind traffic and preventing mid-build IP changes.
