# Grok (xAI) Usage Provider — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-10-24-grok-usage-provider-design.md` (reviewed 2026-10-24).

**Goal:** Show the Grok plan allowance (weekly credit usage) next to Claude and OpenAI, read with one HTTPS GET using the Grok CLI's access token. gas never runs Grok to poll, and never refreshes or writes its credentials.

**Architecture:** Mirrors the OpenAI provider: a read-only auth reader, then one GET, then a DTO and a mapper, producing a `UsageSnapshot`. It differs in having its own hardened HTTP client and logging, a safer file reader, and a fingerprint per account.

## Rules for every task

- Test first for all `UsageCore` logic: write the test, run `swift test --filter <Class>`, see it fail, then make it pass. Keep the whole suite green.
- Never use a real token, user id or email. Fixtures are synthetic, and secret-marker tests use obvious fake strings such as `SECRET-MARKER-1`.
- No logging of bodies, headers, server error text or tokens (spec "Logging").
- One commit per task, in the form `type(scope): summary`.
- Run `swift test` and `xcodebuild` one at a time.

## Decisions taken in this plan (the spec left them open)

- **Renewal-needed = the existing `.stale(reason:)`.** `UsageSnapshot.mergingLastGood` already keeps the last good limits for `.stale`, and `UsageRefresher` counts it as a request, so the 5-minute interval holds. Expired token and 401 → `.stale("Open Grok CLI to renew its sign-in")`. A missing `auth.json` → `.needsSignIn`, which leads to setup.
- **The fingerprint is per account:** a SHA-256 of `<issuer>::<client id>` plus `user_id` from `auth.json` (not a secret). Routine token refreshes keep it the same, so a rate-limit wait survives them, and signing in as another account changes it. This replaces the spec's "digest of the token used", which a token refresh would break.
- **Retry-After:** parse the HTTP-date form too (shared `RetryAfter`, which helps every provider). Keep the existing 2-hour cap and document it in the spec as gas's policy.

## Tasks

### 1. `GrokAuth` and `FileGrokAuthReader` (UsageCore)

Files: `Sources/UsageCore/Keychain/GrokAuthReader.swift`, `Tests/UsageCoreTests/GrokAuthReaderTests.swift`, fixture `Tests/UsageCoreTests/Fixtures/grok_auth.json` (synthetic).

- `struct GrokAuth { accessToken: String; expiresAt: Date; accountFingerprint: String }`, plus a `protocol GrokAuthReader { func readGrokAuth() throws -> GrokAuth }` with errors `.notFound`, `.unreadable`, `.malformed`, `.ambiguous`.
- `FileGrokAuthReader(url:)`, defaulting to `~/.grok/auth.json` (`$GROK_HOME/auth.json` when set):
  - `lstat` first: it must be a regular file (no symlink), owned by the current uid, with no group or other permissions, and at most 64 KB. Otherwise `.unreadable`.
  - Open read-only, read once, and decode with a typed `Decodable`: only the entry whose key is `https://auth.x.ai::<grok client id>`, and only `key`, `expires_at` and `user_id`. A missing entry is `.notFound`; more than one matching entry is `.ambiguous`.
  - `expires_at`: ISO 8601 with fractional seconds, in UTC. `key`: 1…4096 characters, header-safe (no CR, LF or control characters).
  - On a partial file or one that's missing for a moment: retry up to 2 times, 50 ms apart, then `.unreadable` (not `.notFound`).
- Tests: a valid file; missing file → `.notFound`; symlink → `.unreadable`; group-readable mode → `.unreadable`; oversized → `.unreadable`; malformed JSON → `.malformed`; another issuer only → `.notFound`; two matching entries → `.ambiguous`; bad `key` characters → `.malformed`; the fingerprint stays the same when only `key` and `expires_at` change, and differs for another `user_id`; `refresh_token` never appears in `GrokAuth` (check its `Mirror`).

### 2. DTO and mapper (UsageCore)

Files: `Sources/UsageCore/Providers/XAI/XAIUsageDTO.swift`, `XAIUsageMapper.swift`, tests `XAIUsageDTOTests`, `XAIUsageMapperTests`, fixture `xai_billing_response.json` (synthetic, the shape from the spec).

- Decode `config.creditUsagePercent` (optional Double), `currentPeriod { type, end }`, and `billingPeriodEnd`. Ignore every other field.
- Map: `USAGE_PERIOD_TYPE_WEEKLY` → `id "weekly_all"`, label "Weekly"; `…MONTHLY` → `id "monthly"`, label "Monthly"; anything else → `id "monthly"`, label "Usage". `resetsAt` = `currentPeriod.end`, falling back to `billingPeriodEnd`. Severity comes from the usual thresholds.
- A missing percent maps to no limits (the provider decides the status).
- Tests: weekly, monthly, unknown type, the reset fallback, a missing percent, severity at the thresholds, and fractional-second dates with `+00:00` offsets.

### 3. `RetryAfter` HTTP-date (UsageCore)

Files: `Sources/UsageCore/Network/RetryAfter.swift`, `RetryAfterTests` (new or extended).

- Accept integer seconds or an IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`), relative to an injected `now`. A date in the past or garbage gives 0.
- Tests: seconds, a future date, a past date, garbage, missing. The existing callers' behavior doesn't change for the seconds form.

### 4. `GrokHTTPClient` (UsageCore)

Files: `Sources/UsageCore/Network/GrokHTTPClient.swift`, `GrokHTTPClientTests`.

- Conforms to `UsageHTTPClient`. Its own `URLSession` uses `.ephemeral` with `urlCache = nil`, `httpCookieStorage = nil`, `urlCredentialStorage = nil`, `httpShouldSetCookies = false`, a request timeout of 15 s and a resource timeout of 30 s.
- A delegate refuses redirects (`willPerformHTTPRedirection` → `nil`) and caps the body at 256 KB (cancel past it). There is no custom trust handling.
- `get` only accepts the fixed URL `https://cli-chat-proxy.grok.com/v1/billing?format=credits`. Any other URL throws before any network call.
- Tests (with a `URLProtocol` stub): a redirect response is not followed and returns the 3xx; an oversized body throws; another URL is rejected; the session has no cache, cookies or credential storage.

### 5. Safe logging for Grok (UsageCore)

Files: `Sources/UsageCore/Network/UsageLog.swift` (a new `grok(status:category:retryAfter:bytes:elapsed:)` that takes only numbers and an enum), `UsageLogTests`.

- The line looks like `xai: HTTP 401 stale bytes=512 ms=230`. There is no path that accepts `Data`, `HTTPURLResponse` or `String` from the server.
- Tests: feed a response whose body, error `type`, `message` and `code`, and headers contain `SECRET-MARKER-*`. Check that `UsageLog.recentLines()` and the diagnostics report never contain a marker.

### 6. `XAIUsageProvider` (UsageCore)

Files: `Sources/UsageCore/Providers/XAI/XAIUsageProvider.swift`, `XAIUsageProviderTests`, `XAIUsageProviderContractTests` (reuse `Contract/UsageProviderContract.swift`).

- `id = .xai`, `minimumInterval = 300`, `manualMinimumInterval = 300`. `credentialFingerprint()` = `GrokAuth.accountFingerprint` (nil when it can't be read).
- `fetch()`:
  1. Read the auth: `.notFound` → `.needsSignIn`; `.unreadable`, `.malformed` or `.ambiguous` → `.error("Can't read Grok sign-in")`.
  2. If `expiresAt <= now + 60 s` → `.stale("Open Grok CLI to renew its sign-in")`, with no request.
  3. GET with `Authorization`, `Accept`, and `x-grok-client-version` from `~/.grok/version.json` (validated `^[0-9A-Za-z.+-]{1,32}$`, or left out).
  4. Status: 200 with a percent → `.ok`; 200 without one → `.stale(...)` if expired by the real clock now, otherwise `.error("Grok returned no usage")`; 401 → `.stale(...)`; 403 → `.error("Grok denied access")`; 429 → `.rateLimited` (Task 3); other → `.error("HTTP n")`; a URLError → `.stale("Network unavailable — retrying")`.
  5. Log only through `UsageLog.grok`.
- Tests with a stub client and reader: each branch above; no request when expired; the clock margin; a 200 without a percent before and after expiry; the version header present or left out; and the contract tests.

### 7. Refresher and board behavior (UsageCore)

Files: `UsageRefresherTests` (extended).

- A test that a rate-limited xAI provider whose token rotates (the same account fingerprint) is **not** fetched again before `until`, and one whose account changes is.
- A test that `.stale` from xAI keeps the last good limits and records the request (5 minutes are respected).
- A test that two refreshes in flight don't double-fetch, if it isn't already covered. If it isn't single-flight today, add a guard in the app's refresh entry point, not in `UsageCore`.

### 8. Registry, ProviderID and settings (UsageCore and App)

- `ProviderID.displayOrder` = `[.claude, .openai, .xai]`. Update `ProviderIDTests` and any test assuming two providers.
- `ProviderRegistry.makeDefault` takes a `grokAuthReader` and adds `XAIUsageProvider` with `GrokHTTPClient()`.
- `ProviderSettings`: xAI is **off by default** (`isEnabled(.xai)` defaults to false, while the others stay true). Replace `.constant(false)` in `PreferencesView` with a real binding.
- Settings → Providers row text: "xAI (Grok) — reads the Grok CLI's sign-in".

### 9. App: icon, setup, menu (App)

- Icon: an `xAIIcon` template asset. **Needs the owner to supply the mark**: use only a mark xAI allows for this use. Until then `ProviderIcon` keeps the "✕" fallback, which is already wired.
- Setup: add `CLITool.grok` (`~/.grok/bin/grok`; install with `curl -fsSL https://x.ai/cli/install.sh | bash` only on the user's click; sign in with `grok login` in Terminal; the login status comes from `auth.json`'s presence and expiry, without running grok). Follow the Codex flow in `SetupModel`/`SetupView`.
- The menu, menu bar label and panel need no new code: they render `visibleSnapshots`. Check by hand that the one weekly bar appears in compact and Separate bars mode, and that "Resets on Monday at 9am" reads right.

### 10. Docs

- ADR 0004: "Grok usage is read over HTTP with the CLI's access token, not by driving the CLI", recording the rejected agent route and the review.
- README: add Grok to the intro, the "How it works" table (`~/.grok/auth.json`, `cli-chat-proxy.grok.com/v1/billing`), and Requirements; note the 6-hour token and that it's off by default.
- Spec: the backoff bullet now says the fingerprint is per account, and the Retry-After cap is documented.

### 11. Verify

- `swift test` all green, and the app builds.
- A live check with the owner's account: enable xAI and see Weekly NN%. Quit Grok for 6 hours (or set the clock forward in a test build) to see the stale text and that no request is sent. Turn the network off to see "Network unavailable".
- `grep` the diagnostics report and `UsageLog` output after a live run for the token's first 8 characters (computed locally, never printed), and expect zero hits.

## Out of scope

On-demand spend, prepaid balance, top-ups, API-key usage, refreshing the Grok token, and running Grok to renew.
