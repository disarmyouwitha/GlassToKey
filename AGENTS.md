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
- Always review the TODO items and show a checklist on startup.
- When a new TODO task is started always offer to create a new branch (auto generate the name for the user silently).
- When user says to create a PR you should fill out the name and the description automatically.
- ALWAYS run `xcodebuild` after finishing changes to check for build errors.
- GlassToKey build command: `xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build`
- Call out testing gaps when relevant.

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

## Important notes for next instance of Codex
- No notes left

## TODO
- add config to splay columns based on config settings
- Layers I need to add a layer key I can add to the thumb cluster like MOmentary layer switching 
- Make status light blue on layer change
- Ask me for arrow keys + Num pad layout for the new layer
- Possible to turn on/off OSX single-finger tap with typing mode??
- can we devise a keymap layout config we can save and let ppl edit & the program uses that to map keys?

## FUTURE
- add config to splay columns based on your touch
- make buttons addable through gui, set position by dragging into place. set action through gui (that saves to the keymap)
- Add functionality to use trackpad as a scale! Lovely repo @ https://github.com/KrishKrosh/TrackWeight
- can we round the corners to give the visuals a softer look?GlassToKey/GlassToKey/GlassToKeyDefaultsKeys.swiftGlassToKey/GlassToKey/GlassToKeyDefaultsKeys.swift