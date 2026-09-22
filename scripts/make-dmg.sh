#!/bin/bash
# Builds a Release Tokens.app and wraps it in a drag-to-/Applications DMG under dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
DERIVED=build-release
STAGE=dist/stage
mkdir -p dist
rm -rf "$STAGE" "dist/Tokens-$VERSION.dmg"
xcodegen generate >/dev/null
xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build | grep -E 'error:|BUILD' || true
APP="$DERIVED/Build/Products/Release/AgentUsageApp.app"
[ -d "$APP" ] || { echo "build failed: $APP missing" >&2; exit 1; }
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Tokens.app"
codesign --force --deep --options runtime --sign "${SIGN_IDENTITY:--}" "$STAGE/Tokens.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tokens $VERSION" -srcfolder "$STAGE" -ov -format UDZO "dist/Tokens-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
echo "dist/Tokens-$VERSION.dmg"
