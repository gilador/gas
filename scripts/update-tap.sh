#!/bin/bash
# Points the Homebrew cask in gilador/homebrew-tap at the published release v<version>.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/update-tap.sh <version>   (set GH_TOKEN to use another gh account)}"
TAP="${GAS_TAP:-gilador/homebrew-tap}"
CASK="Casks/gas.rb"
DMG="dist/gas-$VERSION.dmg"
fail() { echo "update-tap.sh: $1" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3"
[ -f "$DMG" ] || fail "$DMG not found. Run scripts/package.sh all first."
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

FILE_SHA=$(gh api "repos/$TAP/contents/$CASK" --jq .sha) || fail "can't read $CASK in $TAP"
CURRENT=$(gh api "repos/$TAP/contents/$CASK" --jq .content | base64 --decode)
UPDATED=$(printf '%s\n' "$CURRENT" | sed -E "s/^  version \"[^\"]*\"/  version \"$VERSION\"/; s/^  sha256 \"[^\"]*\"/  sha256 \"$SHA\"/")
grep -q "^  version \"$VERSION\"" <<<"$UPDATED" && grep -q "^  sha256 \"$SHA\"" <<<"$UPDATED" || fail "$CASK has no version or sha256 line to update"
[ "$UPDATED" != "$CURRENT" ] || { echo "update-tap.sh: $TAP already points at $VERSION" >&2; exit 0; }

gh api -X PUT "repos/$TAP/contents/$CASK" \
  -f message="feat(cask): gas $VERSION" \
  -f content="$(printf '%s\n' "$UPDATED" | base64)" \
  -f sha="$FILE_SHA" --jq .commit.sha >/dev/null
echo "update-tap.sh: $TAP now installs gas $VERSION" >&2
