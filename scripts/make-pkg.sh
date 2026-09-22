#!/bin/bash
# Builds a Release Tokens.app and wraps it in a .pkg that installs to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
APP=$(scripts/build-release.sh)
ROOT=dist/pkgroot
rm -rf "$ROOT" dist/Tokens-component.pkg "dist/Tokens-$VERSION.pkg"
mkdir -p "$ROOT/Applications"
ditto "$APP" "$ROOT/Applications/Tokens.app"
pkgbuild --root "$ROOT" --install-location / --identifier com.gilad.agentusage --version "$VERSION" \
  --scripts scripts/pkg/scripts dist/Tokens-component.pkg >/dev/null
sed "s/version=\"0.1.0\"/version=\"$VERSION\"/" scripts/pkg/distribution.xml > dist/distribution.xml
productbuild --distribution dist/distribution.xml --resources scripts/pkg/resources \
  --package-path dist "dist/Tokens-$VERSION.pkg" >/dev/null
rm -rf "$ROOT" dist/stage dist/Tokens-component.pkg dist/distribution.xml
echo "dist/Tokens-$VERSION.pkg"
