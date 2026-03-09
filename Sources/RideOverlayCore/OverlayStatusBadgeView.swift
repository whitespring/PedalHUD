import SwiftUI

struct OverlayStatusBadgeView: View {
    let freshness: MetricFreshness

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor.opacity(0.28))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.14))
            )
            .accessibilityHidden(true)
    }

    private var title: String {
        switch freshness {
        case .live:
            "LIVE"
        case .aging:
            "RECENT"
        case .stale:
            "STALE"
        }
    }

    private var symbolName: String {
        switch freshness {
        case .live:
            "dot.radiowaves.left.and.right"
        case .aging:
            "clock.fill"
        case .stale:
            "exclamationmark.triangle.fill"
        }
    }

    private var backgroundColor: Color {
        switch freshness {
        case .live:
            Color(red: 0.09, green: 0.78, blue: 0.42)
        case .aging:
            Color(red: 0.95, green: 0.66, blue: 0.12)
        case .stale:
            Color(red: 0.95, green: 0.27, blue: 0.22)
        }
    }
}
