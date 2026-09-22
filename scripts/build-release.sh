#!/bin/bash
# Builds a Release Tokens.app, signs it, and prints the path of the signed bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED=build-release
STAGE=dist/stage
mkdir -p dist
rm -rf "$STAGE"
xcodegen generate >/dev/null
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E 'error:|BUILD' >&2 || true
APP="$DERIVED/Build/Products/Release/AgentUsageApp.app"
[ -d "$APP" ] || { echo "build failed: $APP missing" >&2; exit 1; }
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Tokens.app"
IDENTITY="${SIGN_IDENTITY:-$(cat scripts/sign-identity.local 2>/dev/null || true)}"
codesign --force --deep --options runtime --sign "${IDENTITY:--}" "$STAGE/Tokens.app" >&2
echo "$STAGE/Tokens.app"
