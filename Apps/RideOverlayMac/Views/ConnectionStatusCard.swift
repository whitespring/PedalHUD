import SwiftUI

struct ConnectionStatusCard: View {
    let model: RideOverlayAppModel

    var body: some View {
        GroupBox("Pipeline Status") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Trainer")
                        .foregroundStyle(.secondary)
                    Text(model.trainerConnectionState)
                }

                GridRow {
                    Text("Heart Rate")
                        .foregroundStyle(.secondary)
                    Text(model.heartRateConnectionState)
                }

                GridRow {
                    Text("Metrics Relay")
                        .foregroundStyle(.secondary)
                    Text(model.relayStatus)
                }

                GridRow {
                    Text("Virtual Camera")
                        .foregroundStyle(.secondary)
                    Text(model.cameraStatus)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }
}
