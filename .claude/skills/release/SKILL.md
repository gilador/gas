---
name: release
description: Use when the user asks to release, publish or ship a new version of gas. For repo admins only. Takes the latest main from GitHub, bumps the version, runs the tests, builds and signs ad-hoc, and publishes the GitHub release that the in-app updater installs. Do it the same way every time.
---

# Release gas

A release is public: it creates a GitHub release that every installed gas offers as an update. Only repo admins release. Follow these steps the same way every time, and confirm the version with the user before step 4. The project rules are in `AGENTS.md`.

1. **Changes are on GitHub.** The script releases `origin/main` only, from a clean working tree. If the user has local commits, push them first, after the user agrees.

2. **Dry run.** The `gh` account must have **admin** rights on the repo. If the active `gh` account does not, pass the token of one that does:

   ```bash
   GH_TOKEN="$(gh auth token --user <admin-account>)" scripts/release.sh --dry-run
   ```

   With an admin account active, `scripts/release.sh --dry-run` is enough. It prints `main <sha> (<n> commit(s) after <last tag>): <old> (<build>) → <new> (<build>)`. To pick a version, add it: `scripts/release.sh --dry-run 1.1.0`.

3. **Confirm.** Tell the user the new version, the commit, and the commits since the last release, and show the release notes the dry run printed. Wait for a yes.

4. **Release.** Run the same command without `--dry-run`. It takes a few minutes: it runs the tests, commits and pushes the version bump, builds, signs ad-hoc, and publishes the pkg, the dmg and the `.sha256` file.

5. **Check.**

   ```bash
   curl -fsS https://api.github.com/repos/gilador/gas/releases/latest | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['tag_name'], [a['name'] for a in d['assets']])"
   ```

   The tag must be the new version, with 3 assets.

   And the Homebrew cask points at it:

   ```bash
   curl -fsS https://raw.githubusercontent.com/gilador/homebrew-tap/main/Casks/gas.rb | grep -E '^  (version|sha256) '
   ```

   `version` must be the new version, and `sha256` must match `shasum -a 256 dist/gas-<version>.dmg`. If not, run `scripts/update-tap.sh <version>` (with the same `GH_TOKEN`).

6. **Report.** Give the release link. Installed copies offer the update within 6 hours, or at once with Settings → Check for updates.

**If something fails:** the script stops at the first error and says what to do.
- No admin rights, no new commits, or a dirty tree: fix the cause. Do not work around the check.
- The push worked but publishing failed: run `scripts/publish.sh <version>` after the fix.
- Never delete or re-tag a published release without the repo owner's OK.
