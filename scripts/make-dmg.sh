#!/bin/bash
# Wraps a Release Tokens.app in a drag-to-/Applications DMG under dist/. Builds and signs it first, unless an already-built app path is given as $1.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
rm -f "dist/Tokens-$VERSION.dmg"
if [ $# -ge 1 ]; then
  APP="$1"
  STAGE=dist/dmg-stage
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/Tokens.app"
else
  APP=$(scripts/build-release.sh)
  STAGE=dist/stage
fi
ln -s /Applications "$STAGE/Applications"
echo "→ Creating DMG…" >&2
hdiutil create -volname "Tokens $VERSION" -srcfolder "$STAGE" -ov -format UDZO "dist/Tokens-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
echo "dist/Tokens-$VERSION.dmg"
