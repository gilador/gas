import Foundation

struct OpenAIUsageResponse: Decodable, Sendable {
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable, Sendable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }

        init(primaryWindow: Window?, secondaryWindow: Window?) {
            self.primaryWindow = primaryWindow
            self.secondaryWindow = secondaryWindow
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Double
        let limitWindowSeconds: Int?
        let resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }

        init(usedPercent: Double, limitWindowSeconds: Int?, resetAt: Double?) {
            self.usedPercent = usedPercent
            self.limitWindowSeconds = limitWindowSeconds
            self.resetAt = resetAt
        }
    }
}
