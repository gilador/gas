import Foundation

public enum UsageRefresher {
    public static func refresh(_ board: UsageBoard, providers: [any UsageProvider],
                               now: Date = Date(), manual: Bool = false) async -> UsageBoard {
        let dueProviders = providers.filter { provider in
            if case .rateLimited(let until, _)? = board.snapshot(for: provider.id)?.status, until > now {
                return false
            }
            let interval = manual ? provider.manualMinimumInterval : provider.minimumInterval
            if let last = board.lastRequest(for: provider.id), now.timeIntervalSince(last) < interval {
                return false
            }
            return true
        }

        let fetched = await withTaskGroup(of: UsageSnapshot.self,
                                          returning: [UsageSnapshot].self) { group in
            for provider in dueProviders {
                group.addTask {
                    do {
                        return try await provider.fetch()
                    } catch {
                        return UsageSnapshot(provider: provider.id, fetchedAt: Date(),
                                             limits: [], status: .error(message: "Fetch failed"))
                    }
                }
            }
            var results: [UsageSnapshot] = []
            for await snapshot in group { results.append(snapshot) }
            return results
        }

        var updated = board
        for snapshot in fetched where snapshot.status != .needsSignIn && snapshot.status != .keychainDenied {
            updated.markRequested(snapshot.provider, at: now)
        }
        for snapshot in fetched {
            let previous = board.snapshot(for: snapshot.provider)
            let normalized: UsageSnapshot
            if case .rateLimited(_, let headerWait) = snapshot.status {
                let wait = RateLimitBackoff.wait(retryAfter: headerWait, previous: previous?.status)
                normalized = UsageSnapshot(provider: snapshot.provider, fetchedAt: snapshot.fetchedAt,
                                           limits: snapshot.limits,
                                           status: .rateLimited(until: snapshot.fetchedAt.addingTimeInterval(wait), wait: wait))
            } else {
                normalized = snapshot
            }
            updated.replace(normalized.mergingLastGood(previous: previous))
        }
        return updated
    }
}
