import RideOverlayCore
import SwiftUI

struct OverlayPanelView: View {
    let model: OverlayHUDModel

    var body: some View {
        HStack(spacing: 18) {
            ForEach(model.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(item.value)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(model.panelOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .accessibilityLabel(model.accessibilityLabel)
    }
}

