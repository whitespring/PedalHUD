# Ride Overlay

Ride Overlay is a starter scaffold for the project described in the attached brief: a macOS virtual camera that combines webcam video with live ride metrics from a Wahoo trainer and heart-rate source.

This repository currently contains:

- A compileable Swift package, `RideOverlayCore`, for shared metric models, transport payloads, overlay state, preview simulation, and file-backed metric sharing.
- Xcode-ready source folders for:
  - a macOS host app
  - a CoreMediaIO camera extension
  - an iPhone relay app
  - a watchOS heart-rate app
- plist and entitlement templates for the targets above
- architecture and Xcode setup notes in [docs/architecture.md](/Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade/docs/architecture.md) and [docs/xcode-project-setup.md](/Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade/docs/xcode-project-setup.md)

What is intentionally missing:

- An `.xcodeproj` or `.xcworkspace`. The workspace started empty, and no project generator such as `xcodegen` or `tuist` is installed locally.
- The real BLE trainer integration, watch workout implementation, and physical camera capture path. The source layout is prepared for those next steps, but the current scaffold uses a simulated metric feed and a synthetic camera frame.

## Validate the shared core

```bash
swift test
```

## Create the Apple targets in Xcode

1. Create a new Xcode project in this repository root.
2. Add these targets:
   - macOS App: `RideOverlayMac`
   - Camera Extension: `RideOverlayCameraExtension`
   - iOS App: `RideOverlayPhoneRelay`
   - watchOS App: `RideOverlayWatchRelay`
3. Add the local Swift package at the repository root.
4. Attach the source folders under `Apps/` to the matching targets.
5. Replace the placeholder bundle identifiers and app group names in the plist and entitlement files.

The detailed target checklist is in [docs/xcode-project-setup.md](/Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade/docs/xcode-project-setup.md).

