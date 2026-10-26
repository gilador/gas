import Foundation

public enum UsageRefresher {
    public static func refresh(_ board: UsageBoard, providers: [any UsageProvider],
                               now: Date = Date(), manual: Bool = false) async -> UsageBoard {
        let dueProviders = providers.filter { provider in
            if case .rateLimited(let until, _)? = board.snapshot(for: provider.id)?.status, until > now {
                return accountChanged(provider, since: board)
            }
            return nextRequestDate(board, provider: provider, now: now, manual: manual) <= now
        }

        let fetched = await withTaskGroup(of: FetchOutcome.self, returning: [FetchOutcome].self) { group in
            for provider in dueProviders {
                group.addTask {
                    do {
                        return try await provider.fetch()
                    } catch {
                        // Unknown whether a request went out, so it counts.
                        return FetchOutcome(snapshot: UsageSnapshot(provider: provider.id, fetchedAt: Date(), limits: [],
                                                                    status: .error(message: "Fetch failed")),
                                            requestSent: true)
                    }
                }
            }
            var results: [FetchOutcome] = []
            for await result in group { results.append(result) }
            return results
        }

        var updated = board
        for outcome in fetched where outcome.requestSent {
            updated.markRequested(outcome.snapshot.provider, at: now)
        }
        for outcome in fetched {
            let snapshot = outcome.snapshot
            let previous = board.snapshot(for: snapshot.provider)
            let normalized: UsageSnapshot
            if case .rateLimited(_, let headerWait) = snapshot.status {
                let wait = RateLimitBackoff.wait(retryAfter: headerWait, previous: previous?.status)
                normalized = UsageSnapshot(provider: snapshot.provider, fetchedAt: snapshot.fetchedAt,
                                           limits: snapshot.limits,
                                           status: .rateLimited(until: snapshot.fetchedAt.addingTimeInterval(wait), wait: wait))
                updated.setRateLimitedCredential(outcome.credentialFingerprint, for: snapshot.provider)
            } else {
                normalized = snapshot
                updated.setRateLimitedCredential(nil, for: snapshot.provider)
            }
            updated.replace(normalized.mergingLastGood(previous: previous, requestSent: outcome.requestSent))
        }
        return updated
    }

    public static func nextRequestDate(_ board: UsageBoard, provider: any UsageProvider,
                                       now: Date = Date(), manual: Bool = false) -> Date {
        var next = now
        let interval = manual ? provider.manualMinimumInterval : provider.minimumInterval
        if let last = board.lastRequest(for: provider.id) {
            next = max(next, last.addingTimeInterval(interval))
        }
        if case .rateLimited(let until, _)? = board.snapshot(for: provider.id)?.status {
            next = max(next, until)
        }
        return next
    }

    public static func nextRefreshDate(_ board: UsageBoard, providers: [any UsageProvider],
                                       now: Date = Date(), manual: Bool = false) -> Date? {
        providers.map { nextRequestDate(board, provider: $0, now: now, manual: manual) }.min()
    }

    private static func accountChanged(_ provider: any UsageProvider, since board: UsageBoard) -> Bool {
        guard let limited = board.rateLimitedCredential(for: provider.id),
              let current = provider.credentialFingerprint() else { return false }
        return current != limited
    }
}
