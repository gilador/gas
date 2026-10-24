# gas — project rules

These rules apply to everyone who works on this repo, people and coding agents (Claude Code, Codex, Grok, and others). Follow them the same way every time.

## Build and test

- Core logic is in the SwiftPM package `UsageCore`. Run its tests with `swift test`.
- Build the app with:
  ```bash
  xcodegen generate && xcodebuild -project AgentUsage.xcodeproj -scheme AgentUsageApp -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  ```
- To run a Debug test copy, sign it ad-hoc **without** the hardened runtime: `codesign --force --deep --sign - build/Build/Products/Debug/AgentUsageApp.app`. With `--options runtime`, dyld rejects the Debug dylib and the app crashes at launch.
- Write the test first for logic in `UsageCore`, watch it fail, then make it pass. Keep all tests passing.
- Larger features get a spec in `docs/superpowers/specs/` and a plan in `docs/superpowers/plans/` before code.
- A decision that shapes how gas looks or works, or that is easy to undo by accident, gets an ADR in `docs/adr/` (see `docs/adr/index.md`). Read the related ADRs before changing such behavior.

## Code style

- No comments, except one short line that explains a non-obvious WHY. Never mention tasks or tickets in code.
- Match the code around your change.
- The repo has one README, `README.md` at the root. Other docs go in `docs/` with their own names, for example `docs/adr/index.md`.

## Commits and pull requests

- Commit messages and PR titles use `type(scope): summary`, for example `feat(settings): About section with a GitHub link` or `fix(panel): the floating panel can be dragged again`. Types: `feat`, `fix`, `docs`, `build`, `chore`, `refactor`, `test`, `release`.
- PRs are squash-merged, so the PR title becomes the commit on `main`. Give it the same form.

## Security

- Never read, print, log or commit token values.
- Every provider meets the security baseline in `docs/adr/0004-provider-security-baseline.md`: no server text in logs or diagnostics, read-only credentials, a request floor, rate-limit waits per account, fixed HTTPS endpoints, and leak tests. Review a new provider against it before it ships.
- The credential stores of other tools are read-only for gas: Claude Code's Keychain entry, `~/.codex/auth.json`, and `~/.grok/auth.json`. Never write them.
- Never commit secrets, signing keys or certificates. `scripts/sign-identity.local` and `*.p8` are git-ignored on purpose.
- Public builds are always signed ad-hoc, so no developer name or email is in the signature.

## Releases

Releases are public: every installed gas offers a new release as an update. Only **repo admins** release, and always the same way.

- Release only with `scripts/release.sh`. In Claude Code, use the `release` skill (`.claude/skills/release/SKILL.md`). Other agents follow the same steps from that file.
- A release must contain at least one new commit after the latest release. The script stops when there is none.
- The script releases `origin/main` only, from a clean working tree. Never release from another branch or with local changes.
- Steps: dry run → tell the owner the version and the commit and wait for a yes → release → check that the GitHub API reports the new version with 3 assets (pkg, dmg, `.sha256`).
- Never publish a release by hand, and never delete or re-tag a published release, without the repo owner's OK.
