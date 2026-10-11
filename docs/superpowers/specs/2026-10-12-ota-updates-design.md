# Over-the-air updates — design

Date: 2026-10-12 · Status: approved in chat, waiting for spec review

## Goal

gas finds a newer release on `github.com/gilador/gas` by itself and offers to install it. Users do not need someone to send them a pkg.

Success means:
- A new release shows up in gas within about 6 hours.
- Updating takes about 2 clicks in gas, plus the macOS "Allow" prompt and the password, which cannot be removed without a Developer ID.

## Non-goals

- Silent installs without a click.
- Signed checksums (EdDSA or minisign). See "Security" for the limit this leaves.
- Pre-releases or update channels.

## Behavior

**Checks**
- 1 minute after launch, then every 6 hours, while **"Check for updates automatically"** is on (Settings, on by default).
- At any time, from the **Check for updates** button in Settings.

**What counts as new:** the latest GitHub release that is not a draft and not a pre-release, with a version higher than the installed `CFBundleShortVersionString`. Versions compare as numbers, so 1.0.10 is higher than 1.0.9. A leading "v" in the tag is ignored.

**When a new release is found**
- **Menu:** a line at the top says "gas ‹version› is available", with **Update** and **Later** buttons.
- **Dots:** a small dot shows on the menu bar label and on the floating panel.
- **Later** saves that version as skipped. The line and the dots stay hidden until a check finds a version higher than the skipped one.

**Update**
1. gas downloads `gas-‹version›.pkg` and `gas-‹version›.pkg.sha256` from the release to its cache folder (`~/Library/Caches/com.gilad.agentusage/updates/`).
2. gas computes the SHA-256 of the pkg and compares it with the `.sha256` file.
3. If they match, gas opens the pkg with `NSWorkspace`, so the Installer starts. The existing pkg scripts quit gas, install it, and start the new version.
4. Because gas downloaded the file itself, the file has no quarantine mark, and Gatekeeper's "Open Anyway" step does not show.

**Failure**
- **During an automatic check** (no network, a GitHub error, the rate limit): gas writes one log line and tries again at the next check. It shows nothing in the UI.
- **During a manual check:** the Settings status line says "Couldn't check: ‹reason›".
- **During an update** (download error, checksum missing or wrong): the menu line says "Update failed: ‹reason›", with **Try again** and **Open release page**. gas deletes a pkg that fails the check and never opens it.

## Components

**UsageCore** (pure where possible, unit-tested)

1. **`AppVersion`** (`Comparable`): parses "v1.0.24" or "1.0.24" into numbers and compares them. Bad input gives nil.
2. **`ReleaseClient`**:
   - Calls `GET https://api.github.com/repos/gilador/gas/releases/latest`, with `Accept: application/vnd.github+json` and a `User-Agent` of `gas/‹version›`, through the existing `UsageHTTPClient`.
   - Parses `tag_name`, `html_url`, `draft`, `prerelease`, and the assets (`name`, `browser_download_url`).
   - Returns a `ReleaseInfo` only if both assets exist and both URLs start with `https://github.com/gilador/gas/releases/download/`.
3. **`UpdateDecision`**: takes the installed version, the `ReleaseInfo` and the skipped version, and returns `.upToDate`, `.available(ReleaseInfo)` or `.skipped`.
4. **`UpdateDownloader`**:
   - Downloads both files, parses the `.sha256` file (the `shasum -a 256` format: the hex digest, then the file name).
   - Compares the digest with CryptoKit `SHA256`.
   - Returns the verified file URL, or an error (download, checksum missing, checksum mismatch).

**App**

5. **`UpdateModel`** (`@MainActor`, `ObservableObject`):
   - Runs the timer, keeps the state (idle, checking, available, downloading, failed, up to date) and the last error.
   - Saves the skipped version (`skippedUpdateVersion`) and the toggle (`checkForUpdates`) in UserDefaults.
   - Runs the actions: check now, update, later.
6. **UI**:
   - The menu line in `MenuContentView`.
   - The dot in `MenuBarLabelView` and `DesktopPanelView`.
   - An **Updates** section in `PreferencesView`: the toggle, the **Check for updates** button, and a status line, for example "Up to date (1.0.24)" or "Checking…".

**Release scripts**

7. `scripts/package.sh` also writes `dist/gas-‹version›.pkg.sha256`, with `shasum -a 256`.
8. A new `scripts/publish.sh ‹version›` creates the GitHub release `v‹version›` with the pkg, the dmg and the `.sha256` file. It uses `gh`. If `GH_TOKEN` is set, `gh` uses it, so a personal account can publish while a different `gh` account is active.

## Security

- Downloads use https only, and only from this repo's release download URLs.
- A pkg is opened only after its SHA-256 matches the published checksum.
- **Limit:** the checksum is published in the same release as the pkg. It protects against a broken or changed download, but not against someone who takes over the GitHub account. A signed checksum would close that gap. It is a non-goal for now.
- No tokens are needed. The GitHub API is public, with a limit of 60 requests an hour for each IP, and gas uses at most a few a day.

## Logging

Each check and update writes one line to `UsageLog`, for example `update check latest=1.0.24 installed=1.0.23` or `update download failed: checksum mismatch`. **Copy diagnostics** shows these lines.

## Rollout

Installs of 1.0.23 or older have no updater. They must install the first version with the updater by hand, one time. After that, updates come from inside gas.

## Testing

**Unit tests, written first:**
- `AppVersion`: 1.0.9 < 1.0.10, the "v" prefix, equal versions, bad input.
- `ReleaseClient`: parsing a fixture, a draft or pre-release, a missing asset, URLs from another repo, plain http.
- `UpdateDecision`: up to date, available, skipped, and a newer release after a skip.
- `UpdateDownloader`: a matching checksum, a mismatch, a missing `.sha256`, a bad `.sha256` format. The downloads are injected.

**Manual:** publish a test release with a higher version. Then check the dot, the menu line, the download, the checksum and the Installer. After that, delete the test release.
