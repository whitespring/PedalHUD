import CoreMediaIO
import Foundation

let providerSource = RideOverlayCameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()

