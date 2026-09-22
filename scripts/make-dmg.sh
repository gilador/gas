#!/bin/bash
# Builds a Release Tokens.app and wraps it in a drag-to-/Applications DMG under dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
STAGE=dist/stage
rm -f "dist/Tokens-$VERSION.dmg"
APP=$(scripts/build-release.sh)
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tokens $VERSION" -srcfolder "$STAGE" -ov -format UDZO "dist/Tokens-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
echo "dist/Tokens-$VERSION.dmg"
