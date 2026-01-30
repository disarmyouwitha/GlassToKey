# CODEX Checklist - Performance Refactor (Prioritized)

Date: 2026-01-30
Goal: Swift/runtime efficiency, focus on hot paths. Prioritize wins:
1) Remove left/right split allocations.
2) Reduce per-frame object creation in OpenMTManager callback (refcon + pointer-keyed map).
3) Eliminate extra per-frame passes in processTouches/updateIntentGlobal.

Notes:
- Do not add allocations/logging/file I/O to hot paths.
- After large changes, run:
  xcodebuild -project GlassToKey/GlassToKey.xcodeproj -scheme GlassToKey -configuration Debug -destination 'platform=macOS' build

## 1) Remove left/right split allocations (biggest win)
[x] Goal: Avoid per-frame allocation of left/right arrays when splitting touches.
    - Updated pipeline: `ContentViewModel.onAppear` consumes `OMSRawTouchFrame` and avoids `splitTouches`/`TouchFrame`.
    - Hot files: `GlassToKey/GlassToKey/ContentViewModel.swift`, `Sources/OpenMultitouchSupport/OMSManager.swift`.

[x] Option A (preferred): Process raw frames directly, split inside processor without allocating arrays.
    - Add a processing path that takes `OMSRawTouchFrame` (or raw touches) and iterates once.
    - Move left/right device matching logic into processor and update per-side state directly.
    - This avoids building `[OMSTouchData]` and left/right arrays each frame.

[x] Option B: Add reusable buffers for touch data and left/right arrays.
    - Add `buildTouchData(into:inout [OMSTouchData], from:)` in `OMSManager`.
    - (Not wired into UI snapshot path to avoid data races with async snapshot queue.)

[x] Integration note: If switching to raw frame processing, also update UI snapshot path.
    - UI still needs `TouchSnapshot` updates; consider producing a compact per-side snapshot without allocating full arrays when visuals are off.

## 2) Reduce per-frame object creation in OpenMTManager callback
[x] Use refcon callbacks to avoid deviceID dictionary lookups and object churn.
    - In `OpenMTManager.m`, register callbacks with `MTRegisterContactFrameCallbackWithRefcon`.
    - Pass a small context struct per device (deviceRef + numericDeviceID + manager pointer).
    - In callback, use refcon to read numeric deviceID directly.
    - This avoids `NSValue` creation and dictionary lookup in `deviceNumericIDForDeviceRef`.

[x] Replace NSValue-keyed dictionaries with pointer-keyed map.
    - Use `CFDictionary` with pointer personality or `NSMapTable` (pointer keys) for deviceRef -> numericID.
    - Eliminates per-frame `NSValue valueWithPointer:` allocations.

[x] Optional: cache IMP for target/selector listeners.
    - In `OpenMTListener`, store IMP on init to avoid `methodForSelector:` per call.

## 3) Eliminate extra per-frame passes in processTouches/updateIntentGlobal
[x] Fold `contactCount` computation into the main per-touch loop in `processTouches`.
    - Currently uses `reduce` + per-touch loop. Merge for single pass.
    - `GlassToKey/GlassToKey/ContentViewModel.swift`

[x] Avoid re-creating temporary tables/arrays every frame in `updateIntentGlobal`.
    - Reuse `TouchTable` and `[TouchKey]` buffers stored on the actor.
    - Reset with `removeAll(keepingCapacity:)`.

[x] Cache `unitsPerMm` and derived thresholds when trackpad size changes.
    - Today computed per frame; move to cached fields updated on layout/trackpad size changes.

[x] Avoid duplicating point calculations across intent + processing.
    - Cache per-touch CGPoint for the frame (TouchTable<CGPoint>) and reuse in both paths.
    - Only build if both intent + processing need it.

## Secondary Wins (after top 3)
[x] OMSManager: avoid `Array($0.values)` each frame for raw continuations.
    - Keep a stable `[Continuation]` list updated on add/remove.

[x] OMSRawTouchFrame: include numeric deviceID to avoid String parsing in hot paths.

[ ] OMSTouchData: make formattedTimestamp lazily computed or debug-only.
    - Left as-is to avoid breaking public API; current implementation already formats once per frame.

## Build/Verify
[x] After major refactors, run the build command above.
    - If build fails due to added files, add them to the Xcode project.
