import SwiftUI

@main
struct RideOverlayMacApp: App {
    @State private var model = RideOverlayAppModel()

    var body: some Scene {
        Window("Ride Overlay", id: "dashboard") {
            DashboardView(model: model)
                .frame(minWidth: 1080, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

