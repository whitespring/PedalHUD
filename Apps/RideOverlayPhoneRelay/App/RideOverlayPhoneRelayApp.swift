import SwiftUI

@main
struct RideOverlayPhoneRelayApp: App {
    @State private var model = PhoneRelayModel()

    var body: some Scene {
        WindowGroup {
            PhoneRelayView(model: model)
        }
    }
}

