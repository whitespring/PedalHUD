import SwiftUI

@main
struct RideOverlayWatchRelayApp: App {
    @State private var model = WatchRelayModel()

    var body: some Scene {
        WindowGroup {
            WatchRelayView(model: model)
        }
    }
}

