#!/bin/bash
# Builds a .pkg that installs gas.app to /Applications and launches it. Builds and signs the app first, unless an already-built app path is given as $1.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
ROOT=dist/pkgroot
rm -rf "$ROOT" dist/gas-component.pkg "dist/gas-$VERSION.pkg"
if [ $# -ge 1 ]; then
  APP="$1"
  KEEP_STAGE=1
else
  APP=$(scripts/build-release.sh)
  KEEP_STAGE=0
fi
mkdir -p "$ROOT/Applications"
ditto "$APP" "$ROOT/Applications/gas.app"
echo "→ Creating PKG…" >&2
# Installer otherwise "relocates" the app onto any copy with the same bundle id (e.g. a build folder).
pkgbuild --analyze --root "$ROOT" dist/component.plist >/dev/null
i=0
while plutil -extract "$i" xml1 -o /dev/null dist/component.plist 2>/dev/null; do
  plutil -replace "$i.BundleIsRelocatable" -bool NO dist/component.plist
  i=$((i + 1))
done
pkgbuild --root "$ROOT" --component-plist dist/component.plist --install-location / \
  --identifier com.gilad.agentusage --version "$VERSION" \
  --scripts scripts/pkg/scripts dist/gas-component.pkg >/dev/null
rm -f dist/component.plist
sed "s/version=\"0.1.0\"/version=\"$VERSION\"/" scripts/pkg/distribution.xml > dist/distribution.xml
productbuild --distribution dist/distribution.xml --resources scripts/pkg/resources \
  --package-path dist "dist/gas-$VERSION.pkg" >/dev/null
if [ "$KEEP_STAGE" = 1 ]; then
  rm -rf "$ROOT" dist/gas-component.pkg dist/distribution.xml
else
  rm -rf "$ROOT" dist/stage dist/gas-component.pkg dist/distribution.xml
fi
echo "dist/gas-$VERSION.pkg"
