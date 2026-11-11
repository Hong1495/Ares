#!/bin/bash
set -euo pipefail
# Hosted runners may default to an older compiler than this project's Swift syntax.
XCODE_PATH=$(python3 - <<'PY'
import glob, re
candidates=[]
for path in glob.glob('/Applications/Xcode*.app'):
    version=re.search(r'Xcode_(\d+)\.(\d+)',path)
    if version and tuple(map(int,version.groups())) >= (26,2):
        candidates.append((tuple(map(int,version.groups())),path))
if not candidates: raise SystemExit('Xcode 26.2 or later is required')
print(max(candidates)[1]+'/Contents/Developer')
PY
)
echo "DEVELOPER_DIR=$XCODE_PATH" >> "$GITHUB_ENV"
