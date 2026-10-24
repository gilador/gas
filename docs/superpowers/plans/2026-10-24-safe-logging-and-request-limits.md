# Safe logging and request limits — Plan

Spec: `docs/superpowers/specs/2026-10-24-safe-logging-and-request-limits-design.md`. All logic is in `UsageCore`, test first: write the test, watch it fail, then make it pass.

1. **Leak tests first.** In `UsageLogTests` and `DiagnosticsReportTests`, send synthetic secret markers through error JSON (type, message, code), a non-JSON body, `note` lines with a `Bearer …` and a JWT-shaped string, and an HTTP-date Retry-After. Assert that no marker reaches `recentLines()` or the diagnostics report, and that the status category and Retry-After seconds do.
2. **`UsageLog`.** Category mapping, removal of `errorSummary`, and the `record` redaction backstop. Update `UpdateModel` (the App target) to log fixed categories instead of `\(error)`.
3. **`RetryAfter`.** Tests for seconds, the HTTP-date form (relative to an injected `now`), and negative or garbage values. `RateLimitBackoff` honors server waits up to 24 h, and its tests are updated.
4. **Fetch outcome.** `UsageProvider.fetch` returns `FetchOutcome { snapshot, requestSent, credentialFingerprint }`. Claude and OpenAI set `requestSent` only when an HTTP request went out, and the fingerprint of the credential they actually used. Codex's fingerprint is its `account_id`, falling back to nil. Claude's is nil for the rate-limit check. (The logged-out-token tracking inside `ClaudeUsageProvider` keeps its own token hash.)
5. **`UsageRefresher`.** Mark requested when `requestSent`. Store the fingerprint returned with the rate-limited result. End a wait early only when the current account fingerprint is non-nil and differs. Protocol default `minimumInterval` = 270 s. Tests: a 401 isn't retried before the interval, manual refresh is held by the 60 s debounce, a token rotation without an account change doesn't end a wait, and an account change does.
6. **`mergingLastGood`.** Keep the last good limits for `.needsSignIn` when the snapshot comes from a sent request (a rejected credential). Test both cases.
7. **Setup.** `SetupModel.refresh` goes through `UsageRefresher`'s limits (check the current path, and route it if it bypasses them).
8. `swift test`, then the app build. Check Copy diagnostics in the running app shows status categories and no server text.
