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
- GlassToKey build command (if the change was big automatically run): `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
- If build fails due to added files, please add them to the project to fix the error. 

## Common workflows
### Swift wrapper changes only
1. Edit files under `Sources/OpenMultitouchSupport/`.
2. Commit and push (consumers tracking `main` pick up changes).

## Performance notes
- UI visuals are coalesced by touch revision (only redraw on new touch frames).
- Key dispatch posts on a dedicated queue with a cached `CGEventSource`.
- OMS touch timestamps can be disabled for the app (`OMSManager.shared.isTimestampEnabled = false`).

## Important notes for next instance of Codex
- no notes left.

## TODO
- Create a virtual keyboard device (robust, more work): macOS has official support for virtual HID devices via CoreHID, including HIDVirtualDevice: https://developer.apple.com/documentation/corehid/hidvirtualdevice
- Need to make sure 2 finger taps do not trigger key presses.
###
- Selecting custom buttons or keys makes the GUI incredibly laggy, Can you examine the code and see why this is? Please refactor the GUI to be the most efficient and performant code possible.
- Clicking the OffsetX/Y up/down too much gets very laggy and starts to repeat clicks. re: clamping doesmn't seem to work and I can't type into the field without resetting it? Can we fix? is there a better GUI element? 
- Issue with starting 2-finger drag when starting from SPACE area
###
- "Auto" set column x,y based on finger splay "4 finger touch"
- Maybe I can turn off single-finger tap at the Mac OS level but implement single finger tap-to-click if under a minimum ms typing term?
###
- Add functionality to use trackpad as a scale! Lovely repo @ https://github.com/KrishKrosh/TrackWeightm