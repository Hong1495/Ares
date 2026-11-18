#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/ares-update-tests.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
# Sparkle only; no production delegate, proxy services, core, listener or installer.
# Override SPARKLE_FRAMEWORK when using a different DerivedData directory.
FRAMEWORK="${SPARKLE_FRAMEWORK:-$ROOT/.build/verification/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
if [[ ! -d "$FRAMEWORK" ]]; then
  echo 'Set SPARKLE_FRAMEWORK to the resolved Sparkle.framework after building Ares.' >&2
  exit 1
fi
APP="$OUT/Ares Update Test.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
xcrun swiftc -parse-as-library -module-name AppUpdateHarness \
  -F "$APP/Contents/Frameworks" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$ROOT/Ares/Utilities/AppUpdateRecovery.swift" \
  "$ROOT/Ares/Services/AppUpdateService.swift" \
  "$ROOT/scripts/fixtures/AppUpdateHarness.swift" \
  -o "$APP/Contents/MacOS/AppUpdateHarness" > "$OUT/compile.log" 2>&1 || { cat "$OUT/compile.log"; exit 1; }
python3 - "$APP" <<'PY'
import base64, pathlib, plistlib, sys, uuid
app = pathlib.Path(sys.argv[1])
plistlib.dump(dict(
    CFBundleIdentifier='studio.hera.ares.update-test.' + uuid.uuid4().hex,
    CFBundleExecutable='AppUpdateHarness', CFBundleName='Ares Update Test',
    CFBundlePackageType='APPL', CFBundleShortVersionString='1.0', CFBundleVersion='1',
    SUFeedURL='https://127.0.0.1:1/appcast-arm64.xml',
    SUPublicEDKey=base64.b64encode(bytes(32)).decode(),
    SUEnableAutomaticChecks=True, SUScheduledCheckInterval=3600,
    SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
    NSAppTransportSecurity=dict(NSAllowsLocalNetworking=True),
), open(app / 'Contents/Info.plist', 'wb'))
PY
"$APP/Contents/MacOS/AppUpdateHarness" > "$OUT/retry.log" 2>&1
"$APP/Contents/MacOS/AppUpdateHarness" --disable > "$OUT/disabled.log" 2>&1
"$APP/Contents/MacOS/AppUpdateHarness" --off > "$OUT/off.log" 2>&1
python3 - "$OUT" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
try:
    for name, checks, retries in [('retry', 4, 3), ('disabled', 1, 1), ('off', 0, 0)]:
        text = (out / (name + '.log')).read_text()
        assert 'HARNESS COMPLETE' in text, text
        assert text.count('[Ares Update] Checking for updates') == checks, text
        assert text.count('[Ares Update] Retrying failed update check') == retries, text
        assert text.count('error: 2001') == checks, text
        print(f'{name}: {checks} real Sparkle feed requests, {retries} bounded retries; passed')
except AssertionError:
    for name in ['retry', 'disabled', 'off']:
        print((out / (name + '.log')).read_text())
    raise
PY
