# GlassToKey

## Intention
An attempt to use the Apple Magic Trackpad as a keyboard (and mouse!) like the TouchStream LP~
Since it is built on the same technology, I thought it would be fun to try and create an open source version!

<img src="Screenshots/touchstreamLP.jpg" alt="Fingerworks Touchstream LP" width="900px" />

It's just Codex and I vibe coding~ You can submit an issue but this is really just a repo for me, you might have to fork and extend!

## Usage

Build the GlassToKey project and you are good to go! A Green circle will appear in the OSX status bar indicating that Typing is allowed.

Clicking the indicator light will allow you to view the Config or Quit the program.

<img src="Screenshots/GTK_config.png" alt="GlassToKey" />

**Clicking Visualize will draw the touches - it is toggleable for performance reasons.**

Clicking Edit will allow you to click any Column/Button and set the Action/Hold Action and set the positioning and size. (It's really laggy idk what to do, so it's in a toggle)

<img src="Screenshots/GTK_keymap.png" alt="GlassToKey" />

## Typing Tuning
- Tap/Hold (ms): Time in miliseconds until a tap becomds a hold
- Drag Cancel (pt): How far you need to move before top becomes a drag
- Force Cap (g): Pressure (in grams) beyond the initial touch that disqualifies the touch before it can type, preventing accidental strong presses.

## Diagnostics (Debug Builds)
- Logs include key dispatches and disqualification reasons (drag cancelled, typing disabled, etc.)
- Performance profiling uses `OSSignposter` intervals around touch processing.

---

## References

**This is a fork of [Kyome22/OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) with some added features.**

This library refers the following frameworks very much. Special Thanks!
- [mhuusko5/M5MultitouchSupport](https://github.com/mhuusko5/M5MultitouchSupport)
- [calftrail/Touch](https://github.com/calftrail/Touch/blob/master/TouchSynthesis/MultitouchSupport.h)
- [KrishKrosh/OpenMultitouchSupport](https://github.com/KrishKrosh/OpenMultitouchSupport)

## Requirements
- Development with Xcode 16.0+
- swift-tools-version: 6.0
- Compatible with macOS 13.0+

## FUTURE
- Add windows support based on https://github.com/vitoplantamura/MagicTrackpad2ForWindows (They should have USB drivers for USB-C support soon!)
