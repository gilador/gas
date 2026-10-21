#!/bin/bash
# Releases the latest main: version bump, tests, commit and push, ad-hoc build and sign, GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) echo "usage: scripts/release.sh [--dry-run] [version]   (set GH_TOKEN to publish with another gh account)"; exit 0 ;;
    *) VERSION="$arg" ;;
  esac
done

fail() { echo "release.sh: $*" >&2; exit 1; }

REPO="${GAS_REPO:-gilador/gas}"
command -v gh >/dev/null 2>&1 || fail "gh not found. Install it: brew install gh"
PERMISSION=$(gh repo view "$REPO" --json viewerPermission --jq .viewerPermission 2>/dev/null || true)
[ "$PERMISSION" = "ADMIN" ] || fail "only repo admins release; the gh account has ${PERMISSION:-no} permission on $REPO. Set GH_TOKEN for an admin account."

[ -z "$(git status --porcelain)" ] || fail "the working tree has uncommitted or untracked files. Commit, stash or remove them first."
git fetch -q origin
git checkout -q main
git pull -q --ff-only origin main
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] || fail "local main is not equal to origin/main. Push or reset it first."

git fetch -q --tags origin
LATEST_TAG=$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null || true)
SINCE="first release"
if [ -n "$LATEST_TAG" ]; then
  RELEASED=$(git rev-parse "$LATEST_TAG^{commit}" 2>/dev/null) || fail "the latest release tag $LATEST_TAG is not in this repo. Run: git fetch --tags"
  NEW_COMMITS=$(git rev-list --count "$RELEASED..main")
  [ "$NEW_COMMITS" -gt 0 ] || fail "main ($(git rev-parse --short main)) has no commits after $LATEST_TAG ($(git rev-parse --short "$RELEASED")); nothing new to release"
  SINCE="$NEW_COMMITS commit(s) after $LATEST_TAG"
fi

CURRENT=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
[ -n "$VERSION" ] || VERSION="${CURRENT%.*}.$(( ${CURRENT##*.} + 1 ))"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || fail "version '$VERSION' must look like 1.0.26"
NEXT_BUILD=$((BUILD + 1))
if git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1; then
  fail "the tag v$VERSION already exists on origin"
fi

echo "release.sh: main $(git rev-parse --short HEAD) ($SINCE): $CURRENT ($BUILD) → $VERSION ($NEXT_BUILD), repo $REPO" >&2
if [ "$DRY_RUN" = 1 ]; then
  echo "release.sh: release notes:" >&2
  scripts/release-notes.sh "${LATEST_TAG:-$(git rev-list --max-parents=0 origin/main | tail -1)}" origin/main >&2
  echo "release.sh: dry run, nothing changed" >&2
  exit 0
fi

echo "→ Running tests…" >&2
TEST_LOG=$(mktemp)
swift test >"$TEST_LOG" 2>&1 || { tail -20 "$TEST_LOG" >&2; fail "tests failed (full log: $TEST_LOG)"; }
grep -E "Executed [0-9]+ tests" "$TEST_LOG" | tail -1 >&2

sed -i '' "s/MARKETING_VERSION: \"$CURRENT\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \"$BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml
git add project.yml
git commit -q -m "release: gas $VERSION"
git push -q origin main

# Public builds are always ad-hoc, so no developer name ends up in the signature.
SIGN_IDENTITY=- scripts/package.sh all >&2
scripts/publish.sh "$VERSION" || fail "the push worked but publishing failed. Fix it, then run: scripts/publish.sh $VERSION"
