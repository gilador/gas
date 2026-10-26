# 0006. Recover refreshes after network reconnection

- **Status:** Accepted
- **Date:** 2026-10-26

## Context

gas already watches network paths, but a reconnect uses the normal refresh path. Offline failures were recorded as sent requests, so a reconnect could be skipped by the provider floor. A reconnect during a fetch only waited for that fetch and never retried. The manual refresh button also waited for the longest provider cooldown even when another provider could fetch.

## Decision

- A URL loading failure with `URLError.notConnectedToInternet` does not count as a sent request. No usage request could leave the machine. Other transport errors remain conservatively counted, including timeouts and lost connections. A response received before a failed retry still counts, and its rate-limit wait is preserved.
- A reconnect waits for an active refresh to finish, then retries providers as soon as their existing automatic request floors and rate-limit deadlines allow. Losing connectivity cancels pending recovery waits. Duplicate connected path updates do not start another recovery.
- Refresh eligibility and recovery scheduling use the same UsageCore policy. A reconnect never clears request timestamps or rate-limit waits. Last good limits stay visible after a failed fetch.
- The manual refresh button becomes available when any enabled provider is eligible, using that provider's manual interval and rate-limit deadline.

## Consequences

Users can recover after going offline without restarting gas. A known offline failure does not create a new cooldown; requests that may have reached the server retain the baseline in ADR 0004. Recovery may still wait for a real request's floor or a server rate limit, and the regular timer remains a fallback if the path monitor does not detect an internet outage.
