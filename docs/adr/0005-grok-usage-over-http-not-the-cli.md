# 0005. Grok usage is read over HTTP with the CLI's access token, not by driving the CLI

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

Grok has no public plan-usage API. The Grok CLI shows the allowance in `/usage`, and there are two ways for gas to get the same numbers:

- **Drive the CLI.** Start `grok agent stdio` and call `_x.ai/billing` over ACP. It works and returns the same body.
- **Make the CLI's own HTTP call.** `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with the access token from `~/.grok/auth.json`.

On 2026-10-24 a Codex security reviewer and a Grok session testing CLI 1.0.70 reviewed the agent route and found:

1. The CLI is a full agent for any ACP client. Without a session or prompt, `_x.ai/fs/read_file` returned `auth.json` including `refresh_token`, `_x.ai/fs/write_file` wrote a file, `session/list` listed sessions, and `session/new` + `session/prompt` can spend credits. No flag restricts it.
2. Startup is not inert. User plugins, hook definitions (including `~/.claude/settings.json`), MCP definitions, a skills watcher and a network skill sync load on every start, even from a temp directory.
3. Starting it every 5 minutes multiplies that, needs binary-signature checks that can't stop misuse of the genuine binary, and leaves open whether a token refresh during the run writes the credential store.

A compromised gas gains no extra file access from the agent route, because it can already read `auth.json`. The difference is the attack surface and the side effects of every poll.

## Decision

gas reads Grok usage with one HTTPS GET to the fixed billing endpoint, using only the access token and its expiry from `~/.grok/auth.json`, and meets ADR 0004's baseline (spec: `docs/superpowers/specs/2026-10-24-grok-usage-provider-design.md`).

- Polling never runs a Grok process. Setup runs the official installer or `grok login` only on the user's click, and reads the login status from `auth.json`, not from grok.
- gas never refreshes or writes the Grok credentials. An expired token shows the last good values as stale, with "Open Grok CLI to renew its sign-in", and sends no request.
- The request uses its own hardened session: no redirects, no cache, cookies or credential storage, a bounded response, and normal certificate checks.
- xAI is off by default and turned on in Settings → Providers, whose help text says gas reads the Grok CLI's sign-in.

## Consequences

- Routine polling has no agent, plugins, hooks, MCP servers or skill sync behind it.
- The token lives about 6 hours and only a running Grok CLI renews it, so people who rarely use the CLI often see stale Grok data.
- gas depends on an undocumented endpoint and on the shape of `auth.json`, and either can change.
- This does not contain a compromised gas: it can still read the whole `auth.json`, the same trust the user already gives gas for Claude and Codex.
- Reconsider the agent route only if the CLI gains a restricted, read-only mode with an inert startup.
