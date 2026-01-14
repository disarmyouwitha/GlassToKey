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
- `Sources/OpenMultitouchSupport/OMSTouchData.swift`: touch data model (includes deviceID).
- `GlassToKey/GlassToKeyApp.swift`: menu bar status item + app lifecycle.
- `GlassToKey/ContentView.swift`: main UI for trackpad visualization and settings.
- `GlassToKey/ContentViewModel.swift`: touch filtering, typing mode state, key dispatch.
- `README.md`: public usage and device selection docs.

## Working agreements
- Keep Swift API changes in `Sources/OpenMultitouchSupport/`.
- Keep framework changes in `Framework/OpenMultitouchSupportXCF/`.
- Treat `OpenMultitouchSupportXCF.xcframework` as generated output (rebuild instead of hand-editing).
- Call out testing gaps when relevant.
- GlassToKey build command .^(ask): `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`

## Common workflows
### Swift wrapper changes only
1. Edit files under `Sources/OpenMultitouchSupport/`.
2. Commit and push (consumers tracking `main` pick up changes).

## Important notes for next instance of Codex
- No notes left

## TODO
- Need to make sure 2 finger taps do not trigger key presses.
- Can we try to reduce the amount of movement needed for drag detection? I think we set it to 5px or something and I want to half that
- can we round the corners to give the visuals a softer look?
- option to enable 6x4, 6x3, 5x4, 5x3 columns layout. Also include a None layout for no keys.
###
- Have GPT show x,y instead of % or at least have it explain why it did that.. Each % is different even if they are in the same place!
- "Auto" set column x,y based on finger splay "4 finger touch"
- Maybe I can turn off single-finger tap at the Mac OS level but implement single finger tap-to-click if under a minimum ms typing term?
- Add functionality to use trackpad as a scale! Lovely repo @ https://github.com/KrishKrosh/TrackWeight