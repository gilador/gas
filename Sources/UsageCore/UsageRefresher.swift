import Foundation

public enum UsageRefresher {
    public static func refresh(_ board: UsageBoard, providers: [any UsageProvider],
                               now: Date = Date(), manual: Bool = false) async -> UsageBoard {
        let dueProviders = providers.filter { provider in
            if case .rateLimited(let until, _)? = board.snapshot(for: provider.id)?.status, until > now {
                return credentialChanged(provider, since: board)
            }
            let interval = manual ? provider.manualMinimumInterval : provider.minimumInterval
            if let last = board.lastRequest(for: provider.id), now.timeIntervalSince(last) < interval {
                return false
            }
            return true
        }

        let fetched = await withTaskGroup(of: (UsageSnapshot, String?).self,
                                          returning: [(UsageSnapshot, String?)].self) { group in
            for provider in dueProviders {
                group.addTask {
                    let fingerprint = provider.credentialFingerprint()
                    do {
                        return (try await provider.fetch(), fingerprint)
                    } catch {
                        return (UsageSnapshot(provider: provider.id, fetchedAt: Date(),
                                              limits: [], status: .error(message: "Fetch failed")), fingerprint)
                    }
                }
            }
            var results: [(UsageSnapshot, String?)] = []
            for await result in group { results.append(result) }
            return results
        }

        var updated = board
        for (snapshot, _) in fetched where snapshot.status != .needsSignIn && snapshot.status != .keychainDenied {
            updated.markRequested(snapshot.provider, at: now)
        }
        for (snapshot, fingerprint) in fetched {
            let previous = board.snapshot(for: snapshot.provider)
            let normalized: UsageSnapshot
            if case .rateLimited(_, let headerWait) = snapshot.status {
                let wait = RateLimitBackoff.wait(retryAfter: headerWait, previous: previous?.status)
                normalized = UsageSnapshot(provider: snapshot.provider, fetchedAt: snapshot.fetchedAt,
                                           limits: snapshot.limits,
                                           status: .rateLimited(until: snapshot.fetchedAt.addingTimeInterval(wait), wait: wait))
                updated.setRateLimitedCredential(fingerprint, for: snapshot.provider)
            } else {
                normalized = snapshot
                updated.setRateLimitedCredential(nil, for: snapshot.provider)
            }
            updated.replace(normalized.mergingLastGood(previous: previous))
        }
        return updated
    }

    private static func credentialChanged(_ provider: any UsageProvider, since board: UsageBoard) -> Bool {
        guard let limited = board.rateLimitedCredential(for: provider.id),
              let current = provider.credentialFingerprint() else { return false }
        return current != limited
    }
}
