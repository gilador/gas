#!/bin/bash
# Publishes dist/gas-<version>.{pkg,dmg,pkg.sha256} as the GitHub release v<version>.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/publish.sh <version>   (set GH_TOKEN to publish with another gh account)}"
REPO="${GAS_REPO:-gilador/gas}"
FILES=("dist/gas-$VERSION.pkg" "dist/gas-$VERSION.dmg" "dist/gas-$VERSION.pkg.sha256")

for file in "${FILES[@]}"; do
  [ -f "$file" ] || { echo "publish.sh: $file not found. Run scripts/package.sh all first." >&2; exit 1; }
done
(cd dist && shasum -a 256 -c "gas-$VERSION.pkg.sha256") >&2

PREV=$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null || true)
[ -n "$PREV" ] || PREV=$(git rev-list --max-parents=0 HEAD | tail -1)
NOTES=$(mktemp)
scripts/release-notes.sh "$PREV" HEAD >"$NOTES"

gh release create "v$VERSION" "${FILES[@]}" --repo "$REPO" --target main \
  --title "gas $VERSION" --notes-file "$NOTES"
