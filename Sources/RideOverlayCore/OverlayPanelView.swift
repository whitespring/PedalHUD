import SwiftUI

public struct OverlayPanelView: View {
    public let model: OverlayHUDModel

    public init(model: OverlayHUDModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            OverlayHeroMetricView(
                item: heroItem,
                freshness: model.freshness
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if !secondaryItems.isEmpty {
                HStack(spacing: 10) {
                    ForEach(secondaryItems) { item in
                        OverlayMetricChipView(item: item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(max(model.panelOpacity, 0.78)),
                            Color(red: 0.05, green: 0.07, blue: 0.11).opacity(max(model.panelOpacity, 0.88)),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.32), radius: 26, y: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private var heroItem: OverlayHUDModel.Item {
        model.items.first ?? OverlayHUDModel.Item(kind: .watts, title: "Watts", value: "-- W")
    }

    private var secondaryItems: [OverlayHUDModel.Item] {
        Array(model.items.dropFirst())
    }
}
