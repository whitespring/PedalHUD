import SwiftUI

struct OverlayHeroMetricView: View {
    let item: OverlayHUDModel.Item
    let freshness: MetricFreshness

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: item.accentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.24),
                            .white.opacity(0.04),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(item.shortLabel, systemImage: item.symbolName)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.18), in: Capsule(style: .continuous))

                    Spacer(minLength: 8)

                    OverlayStatusBadgeView(freshness: freshness)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.displayValue)
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    if let unit = item.displayUnit {
                        Text(unit)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }

                Text(item.title.uppercased())
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.16))
        )
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
    }
}
