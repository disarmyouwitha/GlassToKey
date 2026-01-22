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

    func postUnicodeText(_ text: String, flags: CGEventFlags = []) {
        dispatcher.postUnicodeText(text, flags: flags)
    }
}

private protocol KeyDispatching: Sendable {
    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken?)
    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken?)
    func postUnicodeText(_ text: String, flags: CGEventFlags)
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
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
        }
    }

    func postUnicodeText(_ text: String, flags: CGEventFlags = []) {
        guard !text.isEmpty else { return }
        queue.async { [self] in
            autoreleasepool {
                guard let source = eventSource ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                eventSource = source
                var characters = Array(text.utf16)
                guard !characters.isEmpty else { return }
                guard let keyDown = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: true
                ),
                let keyUp = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: false
                ) else {
                    return
                }
                keyDown.flags = flags
                keyUp.flags = flags
                characters.withUnsafeMutableBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else { return }
                    keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                    keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                }
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }
}
