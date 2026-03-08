import SwiftUI
import RideOverlayCore

struct SetupChecklistCard: View {
    let model: RideOverlayAppModel

    var body: some View {
        GroupBox("Next Actions") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Running from Xcode only launches the host app. To make the virtual camera appear in Photo Booth, Zoom, Meet, or Slack, copy the built app to /Applications, launch that copy, then click Activate Virtual Camera.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    Button("Request Camera Access", systemImage: "video", action: requestCameraAccess)
                    Button("Activate Virtual Camera", systemImage: "camera.badge.ellipsis", action: installCameraExtension)
                }

                HStack(spacing: 12) {
                    Button("Scan for Wahoo", systemImage: "bolt.horizontal", action: connectTrainer)
                    Button("Scan for HR Belt", systemImage: "heart", action: connectHeartRateMonitor)
                    Button(mirrorButtonTitle, systemImage: "arrow.left.and.right", action: model.toggleMirrorOutput)
                }

                HStack(spacing: 12) {
                    Button("Use Simulated Feed", systemImage: "play.fill", action: model.startSimulation)
                    Button("Stop Simulated Feed", systemImage: "pause.fill", action: model.stopSimulation)
                }

                Text(model.cameraStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }

    private func requestCameraAccess() {
        Task {
            await model.requestCameraAccess()
        }
    }

    private func installCameraExtension() {
        Task {
            await model.installCameraExtension()
        }
    }

    private func connectTrainer() {
        Task {
            await model.connectTrainer()
        }
    }

    private func connectHeartRateMonitor() {
        Task {
            await model.connectHeartRateMonitor()
        }
    }

    private var mirrorButtonTitle: String {
        model.overlayConfiguration.mirrorsOutput ? "Unmirror Output" : "Mirror Output"
    }
}
