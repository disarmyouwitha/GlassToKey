import Carbon
import CoreGraphics
import Foundation

final class KeyEventDispatcher: @unchecked Sendable {
    static let shared = KeyEventDispatcher()

    private let configurationQueue = DispatchQueue(
        label: "com.kyome.GlassToKey.KeyDispatch.Configuration"
    )
    private let cgeventDispatcher: CGEventKeyDispatcher
    private lazy var virtualHIDDispatcher: VirtualHIDKeyDispatcher = {
        VirtualHIDKeyDispatcher(
            client: VirtualHIDClient(),
            onFailure: { [weak self] error in
                self?.handleVirtualHIDFailure(error)
            }
        )
    }()
    private var dispatcher: KeyDispatching
    private var backendStatus: KeyboardBackendStatus

    private init() {
        cgeventDispatcher = CGEventKeyDispatcher()
        backendStatus = KeyboardBackendStatus.initial()
        dispatcher = cgeventDispatcher
        DispatchQueue.main.async {
            KeyboardOutputStatusCenter.shared.update(self.backendStatus)
        }
    }

    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken? = nil) {
        dispatcher.postKeyStroke(code: code, flags: flags, token: token)
    }

    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken? = nil) {
        dispatcher.postKey(code: code, flags: flags, keyDown: keyDown, token: token)
    }

    func postLeftClick(clickCount: Int = 1) {
        dispatcher.postLeftClick(clickCount: clickCount)
    }

    func postRightClick() {
        dispatcher.postRightClick()
    }

    func configureBackend(preference: KeyboardOutputBackend) {
        configurationQueue.async { [weak self] in
            self?.applyBackendPreference(preference)
        }
    }

    func refreshBackendStatus() {
        configurationQueue.async { [weak self] in
            guard let self else { return }
            self.applyBackendPreference(self.backendStatus.preference)
        }
    }

    private func applyBackendPreference(_ preference: KeyboardOutputBackend) {
        VirtualHIDClient.refreshAvailability()
        let clientAvailable = VirtualHIDClient.isAvailable
        var virtualStatus = VirtualHIDHealthChecker.check()
        if preference == .virtualhid && !clientAvailable && virtualStatus.lastError == nil {
            virtualStatus.lastError = VirtualHIDClient.lastError ?? "VirtualHID helper unavailable"
        }
        let shouldUseVirtual = preference == .virtualhid
            && virtualStatus.isHealthy
            && clientAvailable
        let newBackend: KeyboardOutputBackend = shouldUseVirtual ? .virtualhid : .cgevent
        let previousBackend = backendStatus.activeBackend
        dispatcher = shouldUseVirtual ? virtualHIDDispatcher : cgeventDispatcher

        let resolvedLastError: String?
        if preference == .cgevent {
            resolvedLastError = nil
        } else if shouldUseVirtual {
            resolvedLastError = nil
        } else {
            resolvedLastError = backendStatus.lastError
        }
        let newStatus = KeyboardBackendStatus(
            preference: preference,
            activeBackend: newBackend,
            virtualHID: virtualStatus,
            lastError: resolvedLastError
        )
        backendStatus = newStatus
        publishStatus(newStatus, previousBackend: previousBackend)
    }

    private func handleVirtualHIDFailure(_ error: VirtualHIDError) {
        configurationQueue.async { [weak self] in
            guard let self else { return }
            guard backendStatus.activeBackend == .virtualhid else { return }
            dispatcher = cgeventDispatcher
            var virtualStatus = backendStatus.virtualHID
            virtualStatus.reachability = .unreachable
            virtualStatus.lastError = error.message
            let updated = KeyboardBackendStatus(
                preference: backendStatus.preference,
                activeBackend: .cgevent,
                virtualHID: virtualStatus,
                lastError: error.message
            )
            let previousBackend = backendStatus.activeBackend
            backendStatus = updated
            publishStatus(updated, previousBackend: previousBackend)
        }
    }

    private func publishStatus(
        _ status: KeyboardBackendStatus,
        previousBackend: KeyboardOutputBackend
    ) {
        if previousBackend != status.activeBackend {
#if DEBUG
            NSLog(
                "Keyboard output backend switched: %@ -> %@",
                previousBackend.rawValue,
                status.activeBackend.rawValue
            )
#endif
        }
        DispatchQueue.main.async {
            KeyboardOutputStatusCenter.shared.update(status)
        }
    }
}

protocol KeyDispatching: Sendable {
    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken?)
    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken?)
    func postLeftClick(clickCount: Int)
    func postRightClick()
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

    func postLeftClick(clickCount: Int) {
        queue.async { [self] in
            autoreleasepool {
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
                let location = CGEvent(source: nil)?.location ?? .zero
                guard let mouseDown = CGEvent(
                    mouseEventSource: source,
                    mouseType: .leftMouseDown,
                    mouseCursorPosition: location,
                    mouseButton: .left
                ),
                let mouseUp = CGEvent(
                    mouseEventSource: source,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: location,
                    mouseButton: .left
                ) else {
                    return
                }
                let clampedCount = max(1, clickCount)
                mouseDown.setIntegerValueField(.mouseEventClickState, value: Int64(clampedCount))
                mouseUp.setIntegerValueField(.mouseEventClickState, value: Int64(clampedCount))
                mouseDown.post(tap: .cghidEventTap)
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    func postRightClick() {
        queue.async { [self] in
            autoreleasepool {
                guard let source = self.eventSource
                    ?? CGEventSource(stateID: .hidSystemState) else {
                    return
                }
                self.eventSource = source
                let location = CGEvent(source: nil)?.location ?? .zero
                guard let mouseDown = CGEvent(
                    mouseEventSource: source,
                    mouseType: .rightMouseDown,
                    mouseCursorPosition: location,
                    mouseButton: .right
                ),
                let mouseUp = CGEvent(
                    mouseEventSource: source,
                    mouseType: .rightMouseUp,
                    mouseCursorPosition: location,
                    mouseButton: .right
                ) else {
                    return
                }
                mouseDown.post(tap: .cghidEventTap)
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }
}
