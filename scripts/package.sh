#!/bin/bash
# One entry point for packaging gas.app into a DMG and/or a PKG installer.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'USAGE'
Usage: scripts/package.sh [dmg|pkg|all] [--identity "<codesign identity or SHA-1>"] [--help]

Targets (default: all):
  dmg   dist/gas-<version>.dmg — drag-to-/Applications disk image
  pkg   dist/gas-<version>.pkg — installer; puts the app in /Applications and launches it
  all   builds both dmg and pkg (the app is built and signed once, then reused for both)

Signing:
  The identity is picked in this order:
    1. --identity "<name or SHA-1>"
    2. SIGN_IDENTITY environment variable
    3. scripts/sign-identity.local (one line, git-ignored)
    4. ad-hoc (no developer name in the signature; recommended for public builds)
  List available identities: security find-identity -v -p codesigning

Prerequisites:
  xcodegen                         brew install xcodegen
  xcodebuild                       Xcode command line tools
  hdiutil, pkgbuild, productbuild  ship with macOS
USAGE
}

TARGET=all
IDENTITY_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    dmg|pkg|all)
      TARGET="$1"
      shift
      ;;
    --identity)
      [ $# -ge 2 ] || { echo "package.sh: --identity requires a value" >&2; exit 1; }
      IDENTITY_ARG="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "package.sh: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

command -v xcodegen >/dev/null 2>&1 || { echo "package.sh: xcodegen not found on PATH. Install it: brew install xcodegen" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "package.sh: xcodebuild not found. Install Xcode and its command line tools." >&2; exit 1; }
command -v hdiutil >/dev/null 2>&1 || { echo "package.sh: hdiutil not found. This tool ships with macOS." >&2; exit 1; }
command -v pkgbuild >/dev/null 2>&1 || { echo "package.sh: pkgbuild not found. This tool ships with macOS." >&2; exit 1; }
command -v productbuild >/dev/null 2>&1 || { echo "package.sh: productbuild not found. This tool ships with macOS." >&2; exit 1; }

IDENTITY="${IDENTITY_ARG:-${SIGN_IDENTITY:-$(cat scripts/sign-identity.local 2>/dev/null || true)}}"
IDENTITY="${IDENTITY:--}"
export SIGN_IDENTITY="$IDENTITY"

if [ "$IDENTITY" = "-" ]; then
  echo "package.sh: signing ad-hoc (no developer name in the signature)" >&2
fi

APP=$(scripts/build-release.sh)

DMG=""
PKG=""
case "$TARGET" in
  dmg)
    DMG=$(scripts/make-dmg.sh "$APP")
    ;;
  pkg)
    PKG=$(scripts/make-pkg.sh "$APP")
    ;;
  all)
    DMG=$(scripts/make-dmg.sh "$APP")
    PKG=$(scripts/make-pkg.sh "$APP")
    ;;
esac

rm -rf dist/stage

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
if [ -n "$DMG" ]; then
  echo "$DMG"
fi
if [ -n "$PKG" ]; then
  (cd "$(dirname "$PKG")" && shasum -a 256 "$(basename "$PKG")" > "$(basename "$PKG").sha256")
  echo "$PKG"
  echo "$PKG.sha256"
fi
echo "Version: $VERSION"
