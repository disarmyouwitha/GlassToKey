import Carbon
import CoreGraphics
import Foundation

final class KeyEventDispatcher: @unchecked Sendable {
    static let shared = KeyEventDispatcher()

    private let dispatcher: KeyDispatching

    private init() {
        dispatcher = CGEventKeyDispatcher()
    }

    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken? = nil) {
        dispatcher.postKeyStroke(code: code, flags: flags, token: token)
    }

    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken? = nil) {
        dispatcher.postKey(code: code, flags: flags, keyDown: keyDown, token: token)
    }
}

private protocol KeyDispatching: Sendable {
    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken?)
    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken?)
}

private final class CGEventKeyDispatcher: @unchecked Sendable, KeyDispatching {
    private let queue = DispatchQueue(
        label: "com.kyome.GlassToKey.KeyDispatch.CGEvent",
        qos: .userInteractive
    )
    private var eventSource: CGEventSource?

    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken? = nil) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            autoreleasepool {
                if let token, !token.isActive {
                    return
                }
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
                guard let keyDown = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: code,
                    keyDown: true
                ),
                let keyUp = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: code,
                    keyDown: false
                ) else {
                    return
                }
                AutocorrectEngine.shared.recordDispatchedKey(
                    code: code,
                    flags: flags,
                    keyDown: true
                )
                keyDown.flags = flags
                keyUp.flags = flags
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken? = nil) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            autoreleasepool {
                if let token, !token.isActive {
                    return
                }
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
                guard let event = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: code,
                    keyDown: keyDown
                ) else {
                    return
                }
                if keyDown {
                    AutocorrectEngine.shared.recordDispatchedKey(
                        code: code,
                        flags: flags,
                        keyDown: true
                    )
                }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
