cb0a9eaae9062f0a39d6a364c02912697a640da5
205980ded48ff1f6fbb3986aaf4826798a671aff
e9d886e2c83d748795ec75a2c6b9b2ce49e53bd7

    1.4.3.0 Fixed several non-interactive/friend-kernel build issues: prerelease tag lookup no
longer fails TLS verification without a CA bundle, PAT cache and extension index/
recipe files written via sudo on a friend kernel are no longer left unreadable to
the tc user, and the build progress bar no longer errors when no controlling
terminal is attached.
