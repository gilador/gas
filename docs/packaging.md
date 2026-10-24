# Packaging scripts

One command builds and packages gas.app:

```
scripts/package.sh [dmg|pkg|all] [--identity "<codesign identity or SHA-1>"]
scripts/package.sh --help
```

Targets (default `all`):
- `dmg` — `dist/gas-<version>.dmg`, a drag-to-/Applications disk image.
- `pkg` — `dist/gas-<version>.pkg`, an installer that puts the app in /Applications and launches it.
- `all` — builds both; the app is built and signed once and reused for both.

## Scripts

| Script | Does |
| --- | --- |
| `build-release.sh` | Builds a Release `gas.app` and signs it. Prints the signed app path. |
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

Ad-hoc is recommended for public builds. gas reads the Claude token through `/usr/bin/security`, so its own
signature does not change Keychain access. A certificate puts its name, often an email address, into every build
(`codesign -dv` shows it). To sign with one anyway, put its name or SHA-1 in `scripts/sign-identity.local`.

## What a friend needs to do

- macOS blocks the downloaded installer ("Apple could not verify … is free of malware"). Once: click Done,
  then System Settings → Privacy & Security → Security → "gas-1.0.1.pkg was blocked" → Open Anyway,
  and enter the Mac password. (macOS 15+ removed the right-click → Open shortcut.)
  Terminal alternative: `xattr -d com.apple.quarantine ~/Downloads/gas-<version>.pkg`.
- The installer clears the block on the app itself, so gas launches without a second warning.
- Claude Code signed in, for the Claude numbers.
- Codex CLI signed in, for the OpenAI numbers.

A Developer ID certificate + notarization (paid Apple Developer Program) removes the Open Anyway step (and enables macOS notifications).

## Release (one command)

`scripts/release.sh` takes the latest `main` from GitHub, bumps the version (1.0.25 → 1.0.26, or the version you give), runs the tests, commits and pushes the bump, builds and signs ad-hoc, and publishes the GitHub release. Run `scripts/release.sh --dry-run` first: it runs the checks and prints the new version, but changes nothing. In Claude Code, the `release` skill runs these steps for you.

## Publish a release (by hand)

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, and commit.
2. Run `scripts/package.sh all`. It writes the pkg, the dmg and `gas-<version>.pkg.sha256` to `dist/`.
3. Push `main`, then run `scripts/publish.sh <version>`. It checks the checksum, then creates the GitHub release `v<version>` with the three files.
   To publish with a gh account that is not the active one: `GH_TOKEN="$(gh auth token --user <account>)" scripts/publish.sh <version>`.

gas checks the latest release on GitHub. It installs a release only if the release has both `gas-<version>.pkg` and `gas-<version>.pkg.sha256`.
