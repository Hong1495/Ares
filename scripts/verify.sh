#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT_DIR/Ares/Resources/clash-meta"
PROJECT_FILE="$ROOT_DIR/Ares.xcodeproj/project.pbxproj"
APPICON_DIR="$ROOT_DIR/Ares/Assets.xcassets/AppIcon.appiconset"

if [[ ! -x "$CORE" ]]; then
  echo "Core binary is missing or not executable: $CORE" >&2
  exit 1
fi

echo "Core version:"
"$CORE" -v

echo
echo "Checking project settings..."
if git ls-files | grep -E '(^|/)xcuserdata/|\.xcuserstate$|(^|/)\.DS_Store$|^build/' >/dev/null; then
  echo "Repository contains local user/build artifacts" >&2
  git ls-files | grep -E '(^|/)xcuserdata/|\.xcuserstate$|(^|/)\.DS_Store$|^build/' >&2
  exit 1
fi

if grep -q 'MACOSX_DEPLOYMENT_TARGET = 26' "$PROJECT_FILE"; then
  echo "Deployment target is still pinned to macOS 26.x" >&2
  exit 1
fi

if grep -RInE 'as!|first!|last!|NWEndpoint\.Port\(rawValue: .*!\)|sec_identity_create\(identity\)!|TODO' "$ROOT_DIR/Ares" "$ROOT_DIR/AresTests" >/tmp/ares_static_scan.txt; then
  echo "Static scan found force casts/unwraps or TODO markers:" >&2
  cat /tmp/ares_static_scan.txt >&2
  rm -f /tmp/ares_static_scan.txt
  exit 1
fi
rm -f /tmp/ares_static_scan.txt

if [[ -d "$APPICON_DIR" ]]; then
  while IFS= read -r image; do
    file="$(basename "$image")"
    if ! grep -q "\"$file\"" "$APPICON_DIR/Contents.json"; then
      echo "Unreferenced app icon asset: $image" >&2
      exit 1
    fi
  done < <(find "$APPICON_DIR" -maxdepth 1 -type f -name '*.png' | sort)
fi

echo
echo "Checking latest mihomo release asset..."
python3 - <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

def choose_asset(names):
    matches = [
        name for name in names
        if "darwin" in name.lower()
        and "arm64" in name.lower()
        and name.lower().endswith((".gz", ".zip"))
    ]
    preferred = [name for name in matches if "-go" not in name.lower() and "compatible" not in name.lower()]
    return (preferred or matches)[0] if matches else None

assert choose_asset([
    "mihomo-darwin-arm64-go120-v1.2.3.gz",
    "mihomo-darwin-arm64-v1.2.3.gz",
]) == "mihomo-darwin-arm64-v1.2.3.gz"
assert choose_asset(["mihomo-linux-arm64-v1.2.3.gz"]) is None

request = urllib.request.Request(
    "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest",
    headers={"Accept": "application/vnd.github+json", "User-Agent": "Ares-verify"},
)
token = os.environ.get("GITHUB_TOKEN")
if token:
    request.add_header("Authorization", f"Bearer {token}")

try:
    with urllib.request.urlopen(request, timeout=15) as response:
        release = json.load(response)
except (TimeoutError, OSError, urllib.error.URLError, urllib.error.HTTPError) as error:
    if os.environ.get("ARES_VERIFY_STRICT_NETWORK") == "1":
        raise
    print(f"Skipping latest mihomo release check: {error}", file=sys.stderr)
    sys.exit(0)

asset_name = choose_asset([asset.get("name", "") for asset in release.get("assets", [])])
if asset_name is None:
    print("No darwin arm64 asset found in latest mihomo release", file=sys.stderr)
    sys.exit(1)

print(f"{release.get('tag_name', 'unknown')}: {asset_name}")
PY

CONFIG_DIR="$HOME/Library/Application Support/Ares/clash_user"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
  echo
  echo "Validating existing user config..."
  "$CORE" -t -d "$CONFIG_DIR"
else
  echo
  echo "Skipping config validation: $CONFIG_FILE not found"
fi

echo
echo "Checking PKCS12 identity import..."
TMP_CERT_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_CERT_DIR"' EXIT
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP_CERT_DIR/test.key" \
  -out "$TMP_CERT_DIR/test.crt" \
  -subj "/CN=ares.local" \
  -days 1 >/dev/null 2>&1
/usr/bin/openssl pkcs12 -export \
  -in "$TMP_CERT_DIR/test.crt" \
  -inkey "$TMP_CERT_DIR/test.key" \
  -out "$TMP_CERT_DIR/test.p12" \
  -passout "pass:ares" >/dev/null 2>&1
cat > "$TMP_CERT_DIR/check_pkcs12.c" <<'C'
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: check_pkcs12 file.p12\n");
        return 2;
    }

    FILE *file = fopen(argv[1], "rb");
    if (file == NULL) {
        fprintf(stderr, "failed to open p12\n");
        return 1;
    }
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    UInt8 *buffer = malloc((size_t)length);
    if (buffer == NULL || fread(buffer, 1, (size_t)length, file) != (size_t)length) {
        fprintf(stderr, "failed to read p12\n");
        fclose(file);
        return 1;
    }
    fclose(file);

    CFDataRef data = CFDataCreate(NULL, buffer, length);
    free(buffer);
    if (data == NULL) {
        fprintf(stderr, "failed to create p12 data\n");
        return 1;
    }

    const void *keys[] = { kSecImportExportPassphrase };
    const void *values[] = { CFSTR("ares") };
    CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
    CFArrayRef items = NULL;
    OSStatus status = SecPKCS12Import(data, options, &items);
    if (status != errSecSuccess || items == NULL || CFArrayGetCount(items) == 0) {
        fprintf(stderr, "SecPKCS12Import failed: %d\n", (int)status);
        return 1;
    }

    CFDictionaryRef item = CFArrayGetValueAtIndex(items, 0);
    SecIdentityRef identity = (SecIdentityRef)CFDictionaryGetValue(item, kSecImportItemIdentity);
    if (identity == NULL) {
        fprintf(stderr, "SecPKCS12Import returned no identity\n");
        return 1;
    }

    CFRelease(items);
    CFRelease(options);
    CFRelease(data);
    return 0;
}
C
clang "$TMP_CERT_DIR/check_pkcs12.c" -framework Security -framework CoreFoundation -o "$TMP_CERT_DIR/check_pkcs12"
"$TMP_CERT_DIR/check_pkcs12" "$TMP_CERT_DIR/test.p12"

echo
echo "Building Ares Debug..."
BUILD_LOG="$(mktemp)"
if ! xcodebuild -project "$ROOT_DIR/Ares.xcodeproj" -scheme Ares -configuration Debug build >"$BUILD_LOG" 2>&1; then
  tail -n 120 "$BUILD_LOG"
  rm -f "$BUILD_LOG"
  exit 1
fi
tail -n 20 "$BUILD_LOG"
rm -f "$BUILD_LOG"

echo
echo "Running XCTest..."
TEST_LOG="$(mktemp)"
if ! xcodebuild -project "$ROOT_DIR/Ares.xcodeproj" -scheme Ares -configuration Debug -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO >"$TEST_LOG" 2>&1; then
  tail -n 160 "$TEST_LOG"
  rm -f "$TEST_LOG"
  exit 1
fi
grep -E "Executed [0-9]+ tests|TEST SUCCEEDED" "$TEST_LOG" || tail -n 40 "$TEST_LOG"
rm -f "$TEST_LOG"

echo
echo "Verification completed."
