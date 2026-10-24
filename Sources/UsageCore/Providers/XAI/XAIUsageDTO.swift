import Foundation

struct XAIBillingResponse: Decodable, Sendable {
    let config: Config?

    struct Config: Decodable, Sendable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
        let billingPeriodEnd: String?
    }

    struct Period: Decodable, Sendable {
        let type: String?
        let end: String?
    }
}
