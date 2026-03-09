# RideOverlay Agent Notes

Build and install from the repo root:

```bash
cd /Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade
swift test
xcodebuild -allowProvisioningUpdates \
  -project RideOverlay/RideOverlay.xcodeproj \
  -scheme RideOverlay \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode \
  build
```

The built app will be at:

```text
.build/xcode/Build/Products/Debug/RideOverlay.app
```

Copy the fresh build into `/Applications` before testing the virtual camera:

```bash
rsync -a --delete '.build/xcode/Build/Products/Debug/RideOverlay.app/' '/Applications/RideOverlay.app/'
open -n /Applications/RideOverlay.app
```

Use the `/Applications` copy, not the Xcode-run copy, when testing:

- `Activate Virtual Camera`
- Photo Booth / Zoom / Meet / Slack camera selection
- macOS system-extension approval flow

Why: the camera extension must be embedded inside the installed app bundle, and the `/Applications` copy is the most reliable path for system-extension activation.

If you change the virtual camera or shared overlay rendering code, macOS may keep serving an older system extension unless the versions are bumped first. When changing either of these areas:

- [Apps/RideOverlayCameraExtension](/Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade/Apps/RideOverlayCameraExtension)
- [Sources/RideOverlayCore](/Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade/Sources/RideOverlayCore) if the change affects rendered output or extension behavior

bump both of these files together:

- [RideOverlayMac-Info.plist](/Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade/Apps/RideOverlayMac/Resources/RideOverlayMac-Info.plist)
- [Info.plist](/Users/davidmokos/conductor/workspaces/wahoo-webcam/belgrade/Apps/RideOverlayCameraExtension/Resources/Info.plist)

Useful checks:

```bash
systemextensionsctl list
```

If the new virtual camera does not appear in other apps after activation, restart the host app first. If macOS still shows old extension versions as `waiting to uninstall on reboot`, a full reboot may be required before AVFoundation picks up the latest camera extension.
