# AGENTS

## Project summary
- Purpose: observe global trackpad multitouch events via the private MultitouchSupport.framework.
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
- `README.md`: public usage and device selection docs.

## Working agreements
- Keep Swift API changes in `Sources/OpenMultitouchSupport/`.
- Keep framework changes in `Framework/OpenMultitouchSupportXCF/`.
- Treat `OpenMultitouchSupportXCF.xcframework` as generated output (rebuild instead of hand-editing).
- Call out testing gaps when relevant.
- GlassToKey build command (if the change was big automatically run): `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
- If build fails due to added files, please add them to the project to fix the error. 

## Common workflows
### Swift wrapper changes only
1. Edit files under `Sources/OpenMultitouchSupport/`.
2. Commit and push (consumers tracking `main` pick up changes).

## Performance notes
- UI visuals are coalesced by touch revision (only redraw on new touch frames).
- Key dispatch posts on a dedicated queue with a cached `CGEventSource`.
- OMS touch timestamps are disabled by default (`OMSManager.shared.isTimestampEnabled = false`) but can be re-enabled with the flag.
- Two-finger tap suppression uses a configurable interval (0–250 ms) in the settings so accidental taps don’t fire key presses.
- Touch routing now uses a stable `deviceIndex` for cheaper comparisons in hot paths.
  
## Important notes for next instance of Codex
- Debug logging: `ContentViewModel.TouchProcessor` logs key dispatches and disqualification reasons under `KeyDiagnostics` in DEBUG builds.

## TODO
- refactor 2 finger click??
- Refactor from the driver/api layer, any efficiency we can gain by rewrites?
###
- Have Codex refactor the code for compiler efficiency and runtime efficiency. Leave no stone unturned!
- Have Codex refactor the GUI for effiency
- "Auto" set column x,y based on finger splay "4 finger touch"
- Toggle for capturing clicks using CGEventTapCreate??
