#!/usr/bin/env python3
"""Generate offline policy copies from the compiled resolver catalog."""
import argparse
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
catalog = json.loads((root / 'config/dsm-targets.v1.json').read_text())
policy = dict(catalog['platform_policy'])
policy['catalog_id'] = catalog['catalog_id']
legacy = {}
for target in catalog['targets']:
    if target['platform'] not in policy['kernel5_platforms'] or not target['kernel'].startswith('5.'):
        continue
    builds = legacy.setdefault(target['platform'], {})
    build = str(target['tuple'][3])
    if build in builds and builds[build] != target['kernel']:
        raise SystemExit(f"Ambiguous kernel for {target['platform']} build {build}")
    builds[build] = target['kernel']
policy['legacy_kernels'] = legacy
text = json.dumps(policy, indent=2) + '\n'
paths = [root.parent / 'redpill-load/config/platform-policy.v1.json',
         root.parent / 'tcrpfriend/buildroot/board/tcrpfriend/rootfs-overlay/root/platform-policy.v1.json']
for path in paths:
    if args.check:
        if not path.is_file() or json.loads(path.read_text()) != policy:
            raise SystemExit(f'Outdated or missing platform policy: {path}')
    else:
        path.write_text(text)
