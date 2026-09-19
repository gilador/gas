import Foundation

public enum UsageRefresher {
    public static func refresh(_ board: UsageBoard,
                               providers: [any UsageProvider]) async -> UsageBoard {
        let fetched = await withTaskGroup(of: UsageSnapshot.self,
                                          returning: [UsageSnapshot].self) { group in
            for provider in providers {
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
            updated.replace(snapshot.mergingLastGood(previous: board.snapshot(for: snapshot.provider)))
        }
        return updated
    }
}
