import Foundation

public struct SharedOverlayConfigurationStore {
    private let defaults: UserDefaults
    private let key = "rideOverlay.overlayConfiguration"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(appGroupIdentifier: String = RideOverlayIdentifiers.appGroup) {
        defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    public func load() -> OverlayConfiguration {
        guard let data = defaults.data(forKey: key),
              let configuration = try? decoder.decode(OverlayConfiguration.self, from: data) else {
            return .defaultConfiguration
        }

        return configuration
    }

    public func save(_ configuration: OverlayConfiguration) {
        guard let data = try? encoder.encode(configuration) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
