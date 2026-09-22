# Packaging scripts

One command builds and packages Gas.app:

```
scripts/package.sh [dmg|pkg|all] [--identity "<codesign identity or SHA-1>"]
scripts/package.sh --help
```

Targets (default `all`):
- `dmg` — `dist/Gas-<version>.dmg`, a drag-to-/Applications disk image.
- `pkg` — `dist/Gas-<version>.pkg`, an installer that puts the app in /Applications and launches it.
- `all` — builds both; the app is built and signed once and reused for both.

## Scripts

| Script | Does |
| --- | --- |
| `build-release.sh` | Builds a Release `Gas.app` and signs it. Prints the signed app path. |
| `make-dmg.sh` | Wraps the app in a DMG. Builds it first, or reuses a built app path given as `$1`. |
| `make-pkg.sh` | Wraps the app in a `.pkg` installer. Builds it first, or reuses a built app path given as `$1`. |
| `package.sh` | The one entry point above: checks prerequisites, resolves signing, calls the scripts above. |

Run `build-release.sh`, `make-dmg.sh`, or `make-pkg.sh` directly if you only need that one step.

## Signing setup

The identity is picked in this order: `--identity` flag, `SIGN_IDENTITY` env var, `scripts/sign-identity.local`
(one line, git-ignored), else ad-hoc.

List available identities:

```
security find-identity -v -p codesigning
```

Put the identity (name or SHA-1) you want to use by default in `scripts/sign-identity.local`. Ad-hoc signing
works, but macOS Keychain "Always Allow" does not survive rebuilds with it.

## What a friend needs to do

- First launch: right-click Gas → Open (Gatekeeper), once.
- Claude Code signed in, for the Claude numbers.
- Codex CLI signed in, for the OpenAI numbers.

A Developer ID certificate + notarization (paid Apple Developer Program) removes the right-click → Open step.
