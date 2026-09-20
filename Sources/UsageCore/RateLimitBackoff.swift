import Foundation

public enum RateLimitBackoff {
    public static let minimumWait: TimeInterval = 15 * 60
    public static let maximumWait: TimeInterval = 2 * 60 * 60

    /// Server value wins; without one, start at 15 min and double per consecutive limit, capped at 2 h.
    public static func wait(retryAfter: TimeInterval, previous: FetchStatus?) -> TimeInterval {
        if retryAfter > 0 { return min(retryAfter, maximumWait) }
        if case .rateLimited(_, let previousWait)? = previous {
            return min(max(previousWait, minimumWait) * 2, maximumWait)
        }
        return minimumWait
    }
}
