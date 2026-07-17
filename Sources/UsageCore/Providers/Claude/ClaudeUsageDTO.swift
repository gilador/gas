import Foundation

struct ClaudeUsageResponse: Codable, Sendable {
    let limits: [Entry]

    struct Entry: Codable, Sendable {
        let kind: String
        let group: String?
        let percent: Double
        let severity: String?     // server-computed; ignored, recomputed in the mapper
        let resetsAt: String?     // ISO8601 string with fractional seconds; parsed in the mapper
        let scope: Scope?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case kind
            case group
            case percent
            case severity
            case resetsAt = "resets_at"
            case scope
            case isActive = "is_active"
        }

        init(kind: String, group: String?, percent: Double, severity: String?,
             resetsAt: String?, scope: Scope?, isActive: Bool?) {
            self.kind = kind
            self.group = group
            self.percent = percent
            self.severity = severity
            self.resetsAt = resetsAt
            self.scope = scope
            self.isActive = isActive
        }
    }

    struct Scope: Codable, Sendable {
        let model: Model?
        init(model: Model?) { self.model = model }
    }

    struct Model: Codable, Sendable {
        let id: String?
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }

        init(id: String?, displayName: String?) {
            self.id = id
            self.displayName = displayName
        }
    }
}
