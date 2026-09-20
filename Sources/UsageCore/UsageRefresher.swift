import Foundation

public enum UsageRefresher {
    public static func refresh(_ board: UsageBoard, providers: [any UsageProvider],
                               now: Date = Date()) async -> UsageBoard {
        let dueProviders = providers.filter { provider in
            guard case .rateLimited(let until, _)? = board.snapshot(for: provider.id)?.status else { return true }
            return until <= now
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
