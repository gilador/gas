# 0004. Every provider meets the same security baseline

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

gas reads other tools' sign-ins (Claude Code's Keychain entry, `~/.codex/auth.json`, and soon `~/.grok/auth.json`) and calls their undocumented usage endpoints. A security review of the Grok provider found two gaps that weren't specific to Grok:

- Server error text was copied into gas's log and into Copy diagnostics, so a credential echoed in an error could end up in a report a user shares.
- Requests weren't limited the same way for every provider. A rejected sign-in was retried on every refresh, and a routine token renewal could end a rate-limit wait early.

Fixing these one provider at a time would leave the next provider exposed.

## Decision

Every provider, current and future, meets this baseline, and the shared code enforces as much of it as possible (spec: `docs/superpowers/specs/2026-10-24-safe-logging-and-request-limits-design.md`):

1. **Credentials stay out of logs and diagnostics.** Log lines hold gas's own text and numbers only: provider, HTTP status, a status category gas maps itself, Retry-After seconds and sizes. No server error text, bodies, headers or request descriptions. `UsageLog` redacts anything token-shaped as a backstop.
2. **Credentials are read-only and minimal.** A provider reads only the fields it needs from another tool's store and never writes, refreshes or repairs it (see AGENTS.md).
3. **Every provider has a request floor.** At least 4.5 minutes between requests by default, and a 60 s debounce for manual refresh. Every request that reached the server counts, whatever its result.
4. **Rate-limit waits belong to the account.** A wait ends early only when the account changes, never on a token renewal. gas honors the server's Retry-After (seconds or date, up to 24 hours). Without one, it backs off from 15 minutes to 2 hours.
5. **Network calls are narrow.** A fixed HTTPS host and path in code, no endpoint taken from files, the environment or responses, and normal certificate checks.
6. **Tests prove it.** Each provider's tests include synthetic secret markers in error responses, and check they never reach the log or diagnostics.

## Consequences

- A new provider is reviewed against this list before it ships, and the shared refresher and logger enforce points 1, 3 and 4 without extra work.
- Error logs are less detailed: diagnosing a provider error relies on the status category and the user's report, not on the server's message.
- gas can show older data for longer when a provider limits it, which is accepted over hammering an undocumented endpoint.
- This does not sandbox gas. A compromised gas could still read the credentials it has access to.
