import Foundation
import UsageCore

enum ProviderSettings {
    static func key(_ provider: ProviderID) -> String { "providerEnabled.\(provider.rawValue)" }

    static func isEnabled(_ provider: ProviderID, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key(provider)) as? Bool ?? true
    }

    static func enabled(defaults: UserDefaults = .standard) -> [ProviderID] {
        ProviderID.displayOrder.filter { isEnabled($0, defaults: defaults) }
    }
}
