import Foundation

public struct OverlayHUDModelBuilder: Sendable {
    public init() {}

    public func build(
        metrics: LiveMetrics,
        configuration: OverlayConfiguration = .defaultConfiguration,
        now: Date = .now
    ) -> OverlayHUDModel {
        var items: [OverlayHUDModel.Item] = []

        if configuration.showsWatts {
            items.append(
                .init(
                    kind: .watts,
                    title: "Watts",
                    value: metrics.watts.map { "\($0) W" } ?? "-- W"
                )
            )
        }

        if configuration.showsHeartRate {
            items.append(
                .init(
                    kind: .heartRate,
                    title: "Heart Rate",
                    value: metrics.heartRate.map { "\($0) bpm" } ?? "-- bpm"
                )
            )
        }

        let freshness = metrics.freshness(
            relativeTo: now,
            agingAfter: configuration.agingAfter,
            staleAfter: configuration.staleAfter
        )

        let labelPrefix = switch freshness {
        case .live:
            "Live metrics"
        case .aging:
            "Recent metrics"
        case .stale:
            "Stale metrics"
        }

        let values = items.map { "\($0.title) \($0.value)" }.joined(separator: ", ")
        let accessibilityLabel = values.isEmpty ? labelPrefix : "\(labelPrefix): \(values)"

        return OverlayHUDModel(
            items: items,
            freshness: freshness,
            placement: configuration.placement,
            panelOpacity: configuration.panelOpacity,
            accessibilityLabel: accessibilityLabel
        )
    }
}

