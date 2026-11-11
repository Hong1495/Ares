#!/usr/bin/env python3
import json
import sys

release = json.load(open(sys.argv[1]))
arch = sys.argv[2]
if arch not in ('arm64', 'amd64'):
    raise SystemExit('Unsupported core architecture')
assets = [a for a in release['assets'] if a['name'].startswith(f'mihomo-darwin-{arch}-') and a['name'].endswith('.gz')]
preferred = [a for a in assets if '-go' not in a['name'] and 'compatible' not in a['name']]
if not assets:
    raise SystemExit('No matching core archive')
exact = [a for a in assets if a['name'] == f"mihomo-darwin-{arch}-{release['tag_name']}.gz"]
print((exact or preferred or assets)[0]['browser_download_url'])
