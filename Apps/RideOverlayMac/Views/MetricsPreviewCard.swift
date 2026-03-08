import AVFoundation
import RideOverlayCore
import SwiftUI

struct MetricsPreviewCard: View {
    let metrics: LiveMetrics
    let configuration: OverlayConfiguration
    let session: AVCaptureSession
    let isCameraPreviewRunning: Bool

    private let builder = OverlayHUDModelBuilder()

    var body: some View {
        let hud = builder.build(metrics: metrics, configuration: configuration)

        GroupBox("Overlay Preview") {
            ZStack(alignment: alignment(for: hud.placement)) {
                previewBackground

                VStack(alignment: .leading, spacing: 14) {
                    Text(statusLabel(for: hud.freshness))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(statusColor(for: hud.freshness))

                    HStack(spacing: 18) {
                        ForEach(hud.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(item.value)
                                    .font(.title3.weight(.semibold))
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial.opacity(hud.panelOpacity))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(28)
                .accessibilityLabel(hud.accessibilityLabel)
            }
            .scaleEffect(x: configuration.mirrorsOutput ? -1 : 1, y: 1)
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        if isCameraPreviewRunning {
            CameraPreviewView(session: session)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.14, blue: 0.18),
                            Color(red: 0.16, green: 0.20, blue: 0.26),
                            Color(red: 0.27, green: 0.19, blue: 0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                )
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 26, weight: .semibold))
                        Text("Start the camera preview above to composite the live overlay.")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(24)
                )
                .frame(height: 320)
        }
    }

    private func alignment(for placement: OverlayPlacement) -> Alignment {
        switch placement {
        case .topLeading:
            .topLeading
        case .topTrailing:
            .topTrailing
        case .bottomLeading:
            .bottomLeading
        case .bottomTrailing:
            .bottomTrailing
        }
    }

    private func statusColor(for freshness: MetricFreshness) -> Color {
        switch freshness {
        case .live:
            .green
        case .aging:
            .yellow
        case .stale:
            .red
        }
    }

    private func statusLabel(for freshness: MetricFreshness) -> String {
        switch freshness {
        case .live:
            "Live"
        case .aging:
            "Recent"
        case .stale:
            "Stale"
        }
    }
}
