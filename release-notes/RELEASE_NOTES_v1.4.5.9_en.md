# alpine-redpill v1.4.5.9

## Select only reviewed DSM targets

DSM model, build, kernel, module mode, and target CPU decisions now flow through one reviewed resolver. This keeps unsupported builds blocked and prevents a remote builder CPU from standing in for the destination. FRIEND accepts the saved kernel version only when its platform and build match the boot metadata. A PAT entry alone still does not approve a DSM target.
