# AGENTS

## Project summary
- Purpose: observe global trackpad multitouch events via the private MultitouchSupport.framework.
- Deliverables: Swift wrapper API + Objective-C framework shipped as an XCFramework.
- Platform: macOS 13+, Xcode 16+, Swift tools 6.0.
- Sandbox: App Sandbox must be disabled for consumers and the demo app.

## Repository map
- `Sources/OpenMultitouchSupport/`: Swift wrapper API.
- `Framework/OpenMultitouchSupportXCF/`: Objective-C framework source.
- `Framework/OpenMultitouchSupportXCF.xcodeproj`: framework build target.
- `Demo/OMSDemo/`: demo app.
- `OpenMultitouchSupportXCF.xcframework`: local dev output (generated).
- `Package.swift` / `Package.swift.template`: SPM manifest (release vs template).

## Key files and responsibilities
- `Framework/OpenMultitouchSupportXCF/OpenMTManager.h`: public API for device listing/selection and haptics.
- `Framework/OpenMultitouchSupportXCF/OpenMTManager.m`: device enumeration, device ID mapping, callbacks.
- `Framework/OpenMultitouchSupportXCF/OpenMTEvent.h` / `OpenMTEvent.m`: event payloads (includes deviceID).
- `Sources/OpenMultitouchSupport/OMSManager.swift`: Swift API for device selection and event streaming.
- `Sources/OpenMultitouchSupport/OMSTouchData.swift`: touch data model (includes deviceID).
- `Demo/OMSDemo/ContentView.swift`: UI with dual pickers/canvases.
- `Demo/OMSDemo/ContentViewModel.swift`: per-device touch filtering and state.
- `README.md`: public usage and device selection docs.

## Working agreements
- Keep Swift API changes in `Sources/OpenMultitouchSupport/`.
- Keep framework changes in `Framework/OpenMultitouchSupportXCF/`.
- Treat `OpenMultitouchSupportXCF.xcframework` as generated output (rebuild instead of hand-editing).
- No automated tests currently; call out testing gaps when relevant.

## Common workflows
### Swift wrapper changes only
1. Edit files under `Sources/OpenMultitouchSupport/`.
2. Commit and push (consumers tracking `main` pick up changes).

### Build the XCFramework
```bash
./build_framework.sh
```

### Build a release package
```bash
./build_framework.sh --release
```

### Create a GitHub release
```bash
./release.sh <version>
```
- Requires `gh` auth.
- Builds the XCFramework, creates the release, and updates `Package.swift`.

## Demo app
- Open `Demo/OMSDemo` in Xcode and run the app.
- Ensure App Sandbox is disabled in the demo target.

## Important notes for next instance of Codex
  Branch: drag-detection

  - Adds drag‑cancel gating so touches that move >10pt before qualifying do not trigger keys.
  - Key activation waits ~50ms of steady contact before modifiers/space/backspace engage.
  - File: Demo/OMSDemo/ContentViewModel.swift

  Branch: typing-toggle

  - Adds a typing mode toggle hotspot: bottom‑left on left pad, bottom‑right on right pad.
  - Toggle region is drawn (green = typing on, red = typing off). Tapping it flips typing and releases held keys.
  - Files: Demo/OMSDemo/ContentView.swift, Demo/OMSDemo/ContentViewModel.swift

## TODO, first
- Add scale to the keysize. Should be configurable, allow decimal percision, and update the spacing between columns
- make outer buttons where tab, ctrl, shift, back, return, etc. have their own size modifier
- Layers I need to add another layer and have a key I can use to switch on the thumb cluster

## TODO, future
- can we devise a keymap layout config we can save and let ppl edit & the program uses that to map keys?
- add config to splay columns based on your touch
- can this program run in the background and add a taskbar to access the demo/config?
- once we get taskbar set up we should display mouse vs keyboard mode with red light green light?
 