# AGENTS

## Project summary
- Purpose: observe global trackpad multitouch events via the private MultitouchSupport.framework. Build keyboard on top of apple magic trackpad.
- Deliverables: Swift wrapper API + Objective-C framework shipped as an XCFramework.
- Platform: macOS 13+, Xcode 16+, Swift tools 6.0.
- Sandbox: App Sandbox must be disabled for consumers and the GlassToKey app.

## Repository map
- `Sources/OpenMultitouchSupport/`: Swift wrapper API.
- `Framework/OpenMultitouchSupportXCF/`: Objective-C framework source.
- `Framework/OpenMultitouchSupportXCF.xcodeproj`: framework build target.
- `GlassToKey/`: menu bar app.
- `OpenMultitouchSupportXCF.xcframework`: local dev output (generated).
- `Package.swift` / `Package.swift.template`: SPM manifest (release vs template).

## Key files and responsibilities
- `Framework/OpenMultitouchSupportXCF/OpenMTManager.h`: public API for device listing/selection and haptics.
- `Framework/OpenMultitouchSupportXCF/OpenMTManager.m`: device enumeration, device ID mapping, callbacks.
- `Framework/OpenMultitouchSupportXCF/OpenMTEvent.h` / `OpenMTEvent.m`: event payloads (includes deviceID).
- `Sources/OpenMultitouchSupport/OMSManager.swift`: Swift API for device selection and event streaming.
- `Sources/OpenMultitouchSupport/OMSTouchData.swift`: touch data model (includes deviceID + deviceIndex).
- `GlassToKey/GlassToKeyApp.swift`: menu bar status item + app lifecycle.
- `GlassToKey/ContentView.swift`: main UI for trackpad visualization and settings.
- `GlassToKey/ContentViewModel.swift`: touch filtering, typing mode state, key dispatch.
- `GlassToKey/GlassToKeyController.swift`: orchestrates app startup, persists layout/mapping defaults, and forwards user defaults, layouts, and devices into the view model for live trackpad control.
- `GlassToKey/GlassToKeyDefaultsKeys.swift`: defines every UserDefaults key the app uses to store device IDs, layout presets, custom buttons, interaction thresholds, and auto-resync settings.
- `GlassToKey/ColumnLayoutSettings.swift`: serializes per-column scale/offset/spacing adjustments, provides normalized defaults, and migrates legacy layouts for UI editing.
- `GlassToKey/TrackpadLayoutPreset.swift`: enumerates grid presets, label matrices, and anchor points that power the surface layout generator in `ContentView`.
- `GlassToKey/KeyEventDispatcher.swift`: serializes Core Graphics keyboard events through `CGEventSource`, supplying a single entry point for posting key strokes and individual key down/up signals.
- `GlassToKey/Notifications.swift`: centralizes the custom `Notification.Name` used when the user switches edit focus inside the UI.
- `Framework/OpenMultitouchSupportXCF/OpenMTListener.h` / `OpenMTListener.m`: lightweight listener wrapper that delivers `OpenMTEvent` callbacks either via target-selector or block to the Objective-C API.
- `Framework/OpenMultitouchSupportXCF/OpenMTTouch.h` / `OpenMTTouch.m`: models the raw touch identifiers, positions, velocities, pressure, and state that `OpenMTEvent` exposes to Swift.


## Working agreements
- Keep Swift API changes in `Sources/OpenMultitouchSupport/`.
- Keep framework changes in `Framework/OpenMultitouchSupportXCF/`.
- Treat `OpenMultitouchSupportXCF.xcframework` as generated output (rebuild instead of hand-editing).
- Call out testing gaps when relevant.
- GlassToKey build command (if the change was big automatically run): `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
- If build fails due to added files, please add them to the project to fix the error.
- Always write the most performant and efficient code to turn an Apple Magic Trackpad into a keyboard with an emphasis on running in the background as a status app and instant key detection.
  
## Important notes for next instance of Codex
- None given.
