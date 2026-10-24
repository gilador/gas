# Safe logging and request limits — Design

_Date: 2026-10-24. Applies to every provider (Claude, OpenAI, and Grok when it lands). Comes from the security review of the Grok provider; see `2026-10-24-grok-usage-provider-design.md`._

## Goal

- Nothing secret can reach gas's log or the Copy diagnostics report, whatever a server sends back.
- gas never hammers a provider: every request counts toward a per-provider minimum interval, and a rate-limit wait isn't cut short by a routine token change.

## Logging

Today `UsageLog.response` adds `errorSummary(data)`, which copies the server's error `type` and up to 200 characters of `message` into the log, logged as public and kept in the 50-line buffer that Copy diagnostics includes. If a server echoed a credential in an error, it would be logged and shared. `UpdateModel` also logs `"\(error)"`.

Change:

- **No server text in the log.** A response line is: provider, HTTP status, a category gas maps itself (`ok`, `unauthorized` 401, `forbidden` 403, `rate_limited` 429, `client_error` other 4xx, `server_error` 5xx), the Retry-After as validated seconds (or `date`, or `-`), and the body size. The error type and message are no longer logged. `errorSummary` is removed.
- **Fixed text only.** Every other log line (`UsageLog.note`) is built from gas's own constants and numbers. Lines that today interpolate a Swift error (`UpdateModel`) log a fixed category instead (for example `update check failed: network` or `… : decode`).
- **A redaction backstop in `record`.** Before a line reaches `Logger` or the buffer, gas replaces `Bearer <anything>`, JWT-shaped strings (`xxx.yyy.zzz` in base64url), and any run of 32 or more token characters (`[A-Za-z0-9_\-+/=]`) with `[redacted]`. This is a safety net, not the main protection.
- **Diagnostics.** The report keeps its sections. The recent-requests lines come from the redacted buffer.

Tests feed responses whose error type, message, code, headers and body carry synthetic secret markers (for example `sk-test-SECRET-MARKER-0123456789abcdef`), plus a `Bearer …` and a JWT-shaped value through `note`, then assert that no marker appears in `UsageLog.recentLines()` or in `DiagnosticsReport`. No test uses a real token.

## Request limits

Today:

- `UsageProvider.minimumInterval` defaults to 0, so Codex has no floor of its own beyond the 5-minute timer and the 60 s manual debounce.
- `UsageRefresher` doesn't mark `.needsSignIn` or `.keychainDenied` results as requested. A credential the server rejected (401) is therefore sent again on every tick and every manual refresh.
- `mergingLastGood` drops the last good values on `.needsSignIn`.
- The refresher reads `credentialFingerprint()` separately from the fetch, and a changed fingerprint ends a rate-limit wait. Claude Code rotates its token routinely, so a routine rotation can end a 429 wait early. The fingerprint can also belong to a different token than the one sent.
- `RetryAfter` reads only whole seconds and ignores the HTTP-date form, and `RateLimitBackoff` caps even a server's own wait at 2 hours.

Change:

- **A floor for everyone.** The protocol default becomes 5 minutes minus 30 s (Claude's current value). Manual refresh keeps its 60 s debounce per provider.
- **Every request counts.** A fetch that sent a request to the server is marked requested, whatever the result, including 401 and 403. Only results where nothing was sent (no credentials found, Keychain denied) are not marked. Providers report this explicitly: `fetch` returns the snapshot plus whether a request was sent and the fingerprint of the credential actually used.
- **Keep the last good values** for a rejected credential: show them as stale with the sign-in status, instead of dropping them.
- **The wait belongs to the account.** A rate-limit wait ends early only when the **account** changes, not on any token change. The fingerprint becomes an account identity where the credential has one (Codex: `account_id`; Grok: issuer, client id and user id). Claude's Keychain token has no account id, so it never ends a wait early and the wait runs its course. The fingerprint saved with a rate limit is the one returned by the fetch that hit it.
- **Retry-After.** Accept whole seconds and the HTTP-date form, and ignore negative or unparsable values. A server-sent wait is honored up to 24 hours. Without a header, gas keeps its doubling backoff (15 min to 2 h).
- **One path.** Setup's "refresh this provider" goes through the same limits as the timer and the menu's refresh button.

## Out of scope

- Grok-specific handling (`auth.json` parsing, HTTP session settings), which lives in the Grok spec.
- Sandboxing gas.
