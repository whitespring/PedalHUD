# Xcode Project Setup

The repository contains source folders and resource templates, but no generated Xcode project.

## Targets

Create these targets:

1. `RideOverlayMac`
   - type: macOS App
   - frameworks: `SwiftUI`, `AVFoundation`, `CoreBluetooth`, `SystemExtensions`
   - local package dependency: `RideOverlayCore`

2. `RideOverlayCameraExtension`
   - type: Camera Extension
   - frameworks: `CoreMediaIO`, `CoreVideo`, `CoreImage`, `SwiftUI`
   - local package dependency: `RideOverlayCore`
   - embed in: `RideOverlayMac`

3. `RideOverlayPhoneRelay`
   - type: iOS App
   - frameworks: `SwiftUI`, `WatchConnectivity`
   - local package dependency: `RideOverlayCore`

4. `RideOverlayWatchRelay`
   - type: watchOS App
   - frameworks: `SwiftUI`, `HealthKit`
   - local package dependency: `RideOverlayCore`

## App Group

Replace every placeholder App Group with your real identifier, for example:

```text
group.com.yourcompany.ride-overlay
```

The same App Group must be present in:

- the macOS app entitlements
- the camera extension entitlements
- any future XPC helper that shares metric state

## Bundle identifiers

Replace the placeholders before signing:

- `com.example.RideOverlayMac`
- `com.example.RideOverlayCameraExtension`
- `com.example.RideOverlayPhoneRelay`
- `com.example.RideOverlayWatchRelay`

## Recommended initial wiring order

1. Create the macOS app target and attach everything under `Apps/RideOverlayMac/`.
2. Create the camera extension target and attach everything under `Apps/RideOverlayCameraExtension/`.
3. Add the entitlements and App Group to both macOS targets.
4. Confirm the synthetic virtual camera appears in the system camera list.
5. Create the iPhone and watch targets and attach their folders.

## Important implementation gap

The extension currently renders a synthetic frame plus a metrics panel. That is deliberate for the first milestone. Once the virtual camera is stable, replace the synthetic background with a real camera capture source.

