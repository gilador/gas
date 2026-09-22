#!/bin/bash
# Builds a .pkg that installs Tokens.app to /Applications and launches it. Builds and signs the app first, unless an already-built app path is given as $1.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
ROOT=dist/pkgroot
rm -rf "$ROOT" dist/Tokens-component.pkg "dist/Tokens-$VERSION.pkg"
if [ $# -ge 1 ]; then
  APP="$1"
  KEEP_STAGE=1
else
  APP=$(scripts/build-release.sh)
  KEEP_STAGE=0
fi
mkdir -p "$ROOT/Applications"
ditto "$APP" "$ROOT/Applications/Tokens.app"
echo "→ Creating PKG…" >&2
pkgbuild --root "$ROOT" --install-location / --identifier com.gilad.agentusage --version "$VERSION" \
  --scripts scripts/pkg/scripts dist/Tokens-component.pkg >/dev/null
sed "s/version=\"0.1.0\"/version=\"$VERSION\"/" scripts/pkg/distribution.xml > dist/distribution.xml
productbuild --distribution dist/distribution.xml --resources scripts/pkg/resources \
  --package-path dist "dist/Tokens-$VERSION.pkg" >/dev/null
if [ "$KEEP_STAGE" = 1 ]; then
  rm -rf "$ROOT" dist/Tokens-component.pkg dist/distribution.xml
else
  rm -rf "$ROOT" dist/stage dist/Tokens-component.pkg dist/distribution.xml
fi
echo "dist/Tokens-$VERSION.pkg"
