# Grok (xAI) Usage Provider — Design

_Date: 2026-10-24. Status: draft, reviewed. The data source is verified. The CLI-agent route was rejected after a security review; this design uses the CLI's own HTTP call instead, with the reviewer's corrections applied._

## Goal

Show the Grok plan allowance next to Claude and OpenAI: in the menu bar label, the menu, the floating panel, and the threshold alerts. `ProviderID.xai` already exists but is not in `displayOrder`.

## Data source (verified 2026-10-24)

There is no public Grok plan-usage API; docs.x.ai covers API-key rate limits only. The Grok CLI (1.0.70 here) shows the allowance in `/usage` → **Usage limit**, and gets it with one HTTP call. gas makes the same call:

`GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`

Headers: `Authorization: Bearer <key>`, `Accept: application/json`. The CLI also sends `x-grok-client-version` and `x-grok-client-mode`; the response was the same with and without the mode header, and gas sends only the version, read from `~/.grok/version.json`.

Response fields used (everything else ignored):

```json
{ "config": {
    "creditUsagePercent": 42.5,
    "currentPeriod": { "type": "USAGE_PERIOD_TYPE_WEEKLY",
                       "start": "2026-01-05T09:00:00.000000+00:00",
                       "end":   "2026-01-12T09:00:00.000000+00:00" },
    "billingPeriodStart": "…", "billingPeriodEnd": "…" } }
```

Also present and ignored: `onDemandCap`, `onDemandUsed`, `prepaidBalance`, `isUnifiedBillingUser`, `topUpMethod`.

How it was found: the CLI logs "billing: fetched credits config" with this body (the same code path that builds `/billing?format=credits`), and a direct call with a valid token returned the same fields.

**Gotcha: an expired token does not fail.** With an expired `key`, the endpoint answered **HTTP 200 without `creditUsagePercent`**, not 401. gas must check `expires_at` first, and treat a 200 without the percent as "needs sign-in" (expired) or as an error (not expired).

**The period is weekly.** `currentPeriod.type` was `USAGE_PERIOD_TYPE_WEEKLY` for this account, not monthly.

## Credentials — read-only, like Codex

`~/.grok/auth.json` holds one entry keyed by `<issuer>::<client id>`. AGENTS.md already lists this file as read-only for gas. Normal polling uses only the access token (`key`) and `expires_at`. It never extracts or uses `refresh_token` (its bytes are in the raw read buffer, but nothing decodes them), and it never refreshes, writes, repairs, chmods or locks the file.

- **Lifetime.** The token was observed to live about 6 hours, refreshed only by a running Grok CLI (`auth.refresh.success` in its log). That is an observation, not a guarantee.
- **Choosing the entry.** Use the entry for the supported issuer (`https://auth.x.ai`) and the Grok CLI client id. A missing, unsupported or ambiguous entry is an error, never "pick the first one" (dictionary order is not stable, and that could silently choose another account).
- **Decoding.** A typed decoder for just `key`, `expires_at` and `user_id` (not a secret, used only for the account fingerprint), with no generic dictionary of credentials kept around. `expires_at` is ISO 8601 UTC with fractional seconds. `key` must be non-empty, bounded in length, and safe as a header value.
- **Reading the file.** One read from a read-only descriptor. Check it is a regular file owned by the current user, not a symlink, with restrictive permissions, and bound its size. The CLI replaces the file by rename, so an open descriptor sees one consistent snapshot; `key` and `expires_at` come from the same snapshot. On a partial or missing file (an in-place write or the moment of a rename), retry once or twice briefly, then report a neutral read error. A malformed file is **not** treated as "needs sign-in".
- **Memory.** The raw bytes, token, headers and `URLRequest` live only for one fetch. gas doesn't promise to wipe Swift/Foundation copies. Afterwards it keeps only the account fingerprint, a hash of the entry key and `user_id`, never of the token (see "Backoff").
- **Logging.** The token never appears in logs, diagnostics, errors or crash text (see "Logging").

## Design

### Mapping (`UsageCore`, test first)

- One limit. If `currentPeriod.type` is weekly: `id: "weekly_all"`, label "Weekly", so the panel's weekly bar and the "w" letter apply. If it's monthly: `id: "monthly"`, label "Monthly". Any other type: label "Usage" with the same `id: "monthly"`.
- `percentUsed` = `creditUsagePercent`; `resetsAt` = `currentPeriod.end`, falling back to `billingPeriodEnd`; severity from the usual thresholds.
- Before sending, compare `expires_at` with the clock minus a small safety margin (for example 60 s). After the response, check against the real clock again.
- A 200 without `creditUsagePercent`: renewal-needed (below) if the token has expired by then, otherwise `.error("Grok returned no usage")`. Never 0% and never success.
- Fixture tests use bodies with made-up values, and never a real token.

### Provider

- `XAIUsageProvider` mirrors `OpenAIUsageProvider`: a token reader (`GrokAuthReader`, file-based, read-only, with an injectable path for tests), an HTTP client, and the mapper.
- **Renewal-needed is a stale state, not `.needsSignIn`.** Today `UsageSnapshot.mergingLastGood` drops the last good limits for `.needsSignIn`, and `UsageRefresher` doesn't record those attempts as requests, so a rejected token would be retried on every tick. An expired token, or a 401 before local expiry (possibly revoked), keeps the last good values marked stale with "Open Grok CLI to renew its sign-in", and still counts as a request for the 5-minute interval. Either add that state or change the merge and request bookkeeping, with tests. `.needsSignIn` stays for "no Grok sign-in at all" (missing file), which leads to setup.
- 403 is **not** treated as expiry: it can mean access denied or insufficient scope (RFC 6750). It becomes `.error("Grok denied access")`.
- 429 becomes `.rateLimited` with Retry-After, and any other failure becomes `.error`, keeping the last good values.
- A 4.5-minute minimum for timer and manual refreshes alike (one 5-minute refresh, with slack for timer drift): billing changes slowly, and the endpoint is undocumented. This is gas's own policy, not a server allowance.

### HTTP request

- A fixed origin, port and path: `https://cli-chat-proxy.grok.com:443/v1/billing?format=credits`, GET only. The endpoint never comes from `auth.json`, the environment, response fields or user input.
- Refuse redirects for this request, rather than relying on how `Authorization` is forwarded.
- A dedicated `URLSessionConfiguration.ephemeral` session with cache, cookies and credential storage off, normal system certificate and hostname validation, no ATS exceptions and no trust-all delegate. Request and resource time limits, and a bounded response size. The existing `URLSessionHTTPClient` uses `.shared` and buffers whole responses, so it's not reused as is.
- No certificate or SPKI pinning: it's a third-party endpoint with no rotation plan we control, and the host allowlist above is enough.
- `x-grok-client-version` comes from `~/.grok/version.json`, validated as short version text. gas never runs Grok to find it.

### Logging

- Not the shared `UsageLog.response` path: it logs server error type and message as public, and diagnostics include those lines, so an error that echoes a credential would leak it.
- For Grok, log only the HTTP status, gas's own mapped error category, a validated numeric Retry-After, and timing and size. Never the body, server error text, request or header descriptions, or decoder input.
- Tests send synthetic secret markers in the error message, type and code fields and in headers, and check that nothing reaches the log or diagnostics. Tests never use live tokens.

### Backoff

- The rate-limit wait belongs to the account, not to one access token. A routine token refresh (a new `key` every ~6 h) must not end a Retry-After wait. So `credentialFingerprint()` is per account: a hash of the entry key (`<issuer>::<client id>`) and `user_id`, not of the token. Token refreshes keep it, and a different account changes it. This also removes the race between reading the fingerprint and the fetch.
- One fetch at a time. The 5-minute minimum applies to timer ticks, manual refresh, wake and failures alike.
- Respect Retry-After, including the HTTP-date form (`RetryAfter` learns it). Server waits stay capped at 2 hours by `RateLimitBackoff`. That is gas's own policy, and it holds for all providers.
- Renewal-needed uses the existing `.stale(reason:)`. It keeps the last good values and counts as a request, so no new state is needed.

### UI

- `ProviderID.displayOrder` gains `.xai` after OpenAI. Settings → Providers gets an "xAI (Grok)" toggle, **off by default**, whose help says gas reads the Grok CLI's sign-in from `~/.grok/auth.json`. While it is off, xAI is hidden everywhere, including setup.
- First-time setup, like Codex: if `~/.grok/bin/grok` is missing, "Set up" runs the official `curl -fsSL https://x.ai/cli/install.sh | bash`, only on the user's click, and then "Sign in" starts `grok login`. The login status comes only from the `auth.json` entry: present and unexpired is signed in, missing or expired is signed out, unreadable is unknown. Setup never runs grok to ask.
- Icon: no asset and no xAI or Grok logo is bundled; `ProviderIcon` draws the "✕" glyph.
- One bar in both panel layouts. A weekly-only provider already works in Separate bars mode.
- ADR 0002's reset format applies ("Resets on Monday at 9am").

## Security

Compared with the rejected CLI-agent route below:

- **Routine polling runs no Grok process**, so no ACP agent, plugins, hooks, MCP servers, skill sync or extension methods are involved. Explicit setup still runs the official installer or `grok login`, but only on the user's click.
- Normal polling extracts only the access token and its expiry, and never refreshes or writes credentials. **This reduces routine handling and side effects; it does not contain a compromised gas.** gas is unsandboxed and can read the whole `auth.json`, including `refresh_token`, and could collect future tokens. An exposed access token authorizes whatever its server-side scope permits until it expires or is revoked. A newer token in the file does not prove the old one was revoked. The token's exact account privileges weren't established.
- This is the same trust the user already gives gas for Claude and Codex. The Settings toggle text says gas reads the Grok CLI's sign-in.
- gas never writes `auth.json`, so the read-only rule holds without exceptions.

## Rejected: the CLI-agent route (`grok agent stdio` + `_x.ai/billing`)

It works (`_x.ai/billing` over ACP returns the same body, and the leading underscore is required). A review on 2026-10-24 by a Codex security reviewer and a Grok session that tested CLI 1.0.70 rejected it as a default:

1. The CLI is a full agent for any ACP client. Without a session or prompt, `_x.ai/fs/read_file` returned `auth.json` including `refresh_token`, `_x.ai/fs/write_file` wrote a file, `session/list` listed sessions, and `session/new` + `session/prompt` can spend credits. No flag restricts it.
2. Startup is not inert. User plugins, hook definitions (including `~/.claude/settings.json`), MCP definitions, a skills watcher and a network skill sync all load on every start, even from a temp cwd.
3. Starting it every 5 minutes multiplies that, needs binary-signature checks (X.AI team `5Y6N3AJ54S`) that can't stop misuse of the genuine binary, and leaves unresolved whether a refresh during the run writes the credential store.

A fully compromised gas gains no extra file access from that route, because it can already read `auth.json`. The route was rejected for its far larger attack surface and side effects on every poll, not for a difference in what a compromised gas could do.

## Risks

- The endpoint is undocumented and can change. The README already says so for the others.
- The 200-without-percent behavior for expired tokens might change to a 401; both are handled.
- The 6-hour token means Grok often shows stale data for people who don't use the CLI daily. This is acceptable for v1; a later version could offer an explicit "Renew" that opens the Grok CLI, like Claude's renewal.

## Out of scope

- API-key (console.x.ai) usage, team admin views, on-demand spend, top-ups, prepaid balance.
- Refreshing the Grok token in gas.
