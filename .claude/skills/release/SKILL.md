---
name: release
description: Use when the user asks to release, publish or ship a new version of gas. Takes the latest main from GitHub, bumps the version, runs the tests, builds and signs ad-hoc, and publishes the GitHub release that the in-app updater installs.
---

# Release gas

A release is public: it creates a GitHub release that every installed gas offers as an update. Confirm the version with the user before step 3.

1. **Changes are on GitHub.** The script releases `origin/main` only. If the user has local commits, push them first, after the user agrees.

2. **Dry run.** Use the gh account that owns the repo. On the maintainer's Mac that is `gilador`:

   ```bash
   GH_TOKEN="$(gh auth token --user gilador)" scripts/release.sh --dry-run
   ```

   It prints `main <sha>: <old> (<build>) → <new> (<build>)`. To pick a version, add it: `scripts/release.sh --dry-run 1.1.0`.

3. **Confirm.** Tell the user the new version and the commit, and wait for a yes.

4. **Release.** Run the same command without `--dry-run`. It takes a few minutes: it runs the tests, commits and pushes the version bump, builds, signs ad-hoc, and publishes the pkg, the dmg and the `.sha256` file.

5. **Check.**

   ```bash
   curl -fsS https://api.github.com/repos/gilador/gas/releases/latest | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['tag_name'], [a['name'] for a in d['assets']])"
   ```

   The tag must be the new version, with 3 assets.

6. **Report.** Give the release link. Installed copies offer the update within 6 hours, or at once with Settings → Check for updates.

**If something fails:** the script stops at the first error and says what to do. If the push worked but publishing failed, run `scripts/publish.sh <version>` after the fix. Never delete or re-tag a published release without the user's OK.
