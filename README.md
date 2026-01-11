# GlassToKey

## Intention
An attempt to use the Apple Magic Trackpad as a keyboard (and mouse!) like the TouchStream LP~
Since it is built on the same technology, I thought it would be fun to try and create an open source version!

<img src="Screenshots/touchstreamLP.jpg" alt="Fingerworks Touchstream LP" width="900px" />

It's just Codex and I vibe coding~ you can submit an issue but this is really just a repo for me, you might have to fork and extend!

## Usage

Build the GlassToKey project and you are good to go! A Green circle will appear in the OSX status bar indicating that Typing is allowed.

Clicking the indicator light will allow you to view the Config or Quit the program.

<img src="Screenshots/GTK_config.png" alt="GlassToKey" width="900px" />

If you hold any key for longer than 200ms I have a whole hidden tap-hold layer. <br>
(Sorry it is not more user friendly at this point)

## TODO

This repo is not really in shape for users, but a developer could definitely get in and modify the keymap, etc. 

**I have a todo list in the AGENTS.md file if you want to check it out! Or load up codex and say, "read agents.md" and start submitting PRs, lol!**

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
