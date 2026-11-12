#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
git diff --check
plutil -lint Ares.xcodeproj/project.pbxproj Configuration/Ares-Info.plist
scripts/test-safe-functions.sh
scripts/test-proxy-controller.sh
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
scripts/preview-ui.sh
# Production compilation is allowed; do not launch the resulting app on the host.
xcodebuild -project Ares.xcodeproj -scheme Ares -configuration Debug \
  -derivedDataPath .build/verification CODE_SIGNING_ALLOWED=NO build
