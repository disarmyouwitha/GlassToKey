import Carbon
import CoreGraphics
import Foundation

#if canImport(CoreHID)
import CoreHID
#endif

final class KeyEventDispatcher: @unchecked Sendable {
    static let shared = KeyEventDispatcher()

    private let dispatcher: KeyDispatching

    private init() {
        #if canImport(CoreHID)
        if #available(macOS 15, *),
           let virtual = VirtualHIDKeyDispatcher() {
            dispatcher = virtual
            return
        }
        #endif
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
}

#if canImport(CoreHID)
@available(macOS 15, *)
private final class VirtualHIDKeyDispatcher: @unchecked Sendable, KeyDispatching {
    private let queue = DispatchQueue(
        label: "com.kyome.GlassToKey.KeyDispatch.VirtualHID",
        qos: .userInteractive
    )
    private let device: VirtualKeyboardDevice
    private let fallback = CGEventKeyDispatcher()
    private var pendingTask: Task<Void, Never>?

    init?() {
        guard let device = VirtualKeyboardDevice() else { return nil }
        self.device = device
    }

    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken? = nil) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            let modifiers = Self.modifierBits(from: flags)
            if let modifierBit = Self.modifierBit(for: code) {
                self.enqueue {
                    await self.device.sendModifierStroke(bit: modifierBit, modifiers: modifiers)
                }
                return
            }
            guard let usage = Self.usage(for: code) else {
                self.fallback.postKeyStroke(code: code, flags: flags, token: token)
                return
            }
            self.enqueue {
                await self.device.sendKeyStroke(usage: usage, modifiers: modifiers)
            }
        }
    }

    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken? = nil) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            if let modifierBit = Self.modifierBit(for: code) {
                self.enqueue {
                    await self.device.setModifier(bit: modifierBit, isDown: keyDown)
                }
                return
            }
            guard let usage = Self.usage(for: code) else {
                self.fallback.postKey(code: code, flags: flags, keyDown: keyDown, token: token)
                return
            }
            let modifiers = Self.modifierBits(from: flags)
            self.enqueue {
                await self.device.setKey(usage: usage, modifiers: modifiers, isDown: keyDown)
            }
        }
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = pendingTask
        pendingTask = Task(priority: .userInitiated) {
            if let previous {
                _ = await previous.result
            }
            await work()
        }
    }

    private static func modifierBits(from flags: CGEventFlags) -> UInt8 {
        var bits: UInt8 = 0
        if flags.contains(.maskControl) {
            bits |= 0x01
        }
        if flags.contains(.maskShift) {
            bits |= 0x02
        }
        if flags.contains(.maskAlternate) {
            bits |= 0x04
        }
        if flags.contains(.maskCommand) {
            bits |= 0x08
        }
        return bits
    }

    private static func modifierBit(for code: CGKeyCode) -> UInt8? {
        switch code {
        case CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl):
            return 0x01
        case CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift):
            return 0x02
        case CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption):
            return 0x04
        case CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand):
            return 0x08
        default:
            return nil
        }
    }

    private static func usage(for code: CGKeyCode) -> UInt8? {
        usageByKeyCode[code]
    }

    private static let usageByKeyCode: [CGKeyCode: UInt8] = [
        CGKeyCode(kVK_ANSI_A): 0x04,
        CGKeyCode(kVK_ANSI_B): 0x05,
        CGKeyCode(kVK_ANSI_C): 0x06,
        CGKeyCode(kVK_ANSI_D): 0x07,
        CGKeyCode(kVK_ANSI_E): 0x08,
        CGKeyCode(kVK_ANSI_F): 0x09,
        CGKeyCode(kVK_ANSI_G): 0x0A,
        CGKeyCode(kVK_ANSI_H): 0x0B,
        CGKeyCode(kVK_ANSI_I): 0x0C,
        CGKeyCode(kVK_ANSI_J): 0x0D,
        CGKeyCode(kVK_ANSI_K): 0x0E,
        CGKeyCode(kVK_ANSI_L): 0x0F,
        CGKeyCode(kVK_ANSI_M): 0x10,
        CGKeyCode(kVK_ANSI_N): 0x11,
        CGKeyCode(kVK_ANSI_O): 0x12,
        CGKeyCode(kVK_ANSI_P): 0x13,
        CGKeyCode(kVK_ANSI_Q): 0x14,
        CGKeyCode(kVK_ANSI_R): 0x15,
        CGKeyCode(kVK_ANSI_S): 0x16,
        CGKeyCode(kVK_ANSI_T): 0x17,
        CGKeyCode(kVK_ANSI_U): 0x18,
        CGKeyCode(kVK_ANSI_V): 0x19,
        CGKeyCode(kVK_ANSI_W): 0x1A,
        CGKeyCode(kVK_ANSI_X): 0x1B,
        CGKeyCode(kVK_ANSI_Y): 0x1C,
        CGKeyCode(kVK_ANSI_Z): 0x1D,
        CGKeyCode(kVK_ANSI_1): 0x1E,
        CGKeyCode(kVK_ANSI_2): 0x1F,
        CGKeyCode(kVK_ANSI_3): 0x20,
        CGKeyCode(kVK_ANSI_4): 0x21,
        CGKeyCode(kVK_ANSI_5): 0x22,
        CGKeyCode(kVK_ANSI_6): 0x23,
        CGKeyCode(kVK_ANSI_7): 0x24,
        CGKeyCode(kVK_ANSI_8): 0x25,
        CGKeyCode(kVK_ANSI_9): 0x26,
        CGKeyCode(kVK_ANSI_0): 0x27,
        CGKeyCode(kVK_Return): 0x28,
        CGKeyCode(kVK_Escape): 0x29,
        CGKeyCode(kVK_Delete): 0x2A,
        CGKeyCode(kVK_Tab): 0x2B,
        CGKeyCode(kVK_Space): 0x2C,
        CGKeyCode(kVK_ANSI_Minus): 0x2D,
        CGKeyCode(kVK_ANSI_Equal): 0x2E,
        CGKeyCode(kVK_ANSI_LeftBracket): 0x2F,
        CGKeyCode(kVK_ANSI_RightBracket): 0x30,
        CGKeyCode(kVK_ANSI_Backslash): 0x31,
        CGKeyCode(kVK_ANSI_Semicolon): 0x33,
        CGKeyCode(kVK_ANSI_Quote): 0x34,
        CGKeyCode(kVK_ANSI_Grave): 0x35,
        CGKeyCode(kVK_ANSI_Comma): 0x36,
        CGKeyCode(kVK_ANSI_Period): 0x37,
        CGKeyCode(kVK_ANSI_Slash): 0x38,
        CGKeyCode(kVK_CapsLock): 0x39,
        CGKeyCode(kVK_RightArrow): 0x4F,
        CGKeyCode(kVK_LeftArrow): 0x50,
        CGKeyCode(kVK_DownArrow): 0x51,
        CGKeyCode(kVK_UpArrow): 0x52
    ]
}

@available(macOS 15, *)
private final class VirtualKeyboardDevice: @unchecked Sendable {
    private let device: HIDVirtualDevice
    private let delegate: VirtualKeyboardDelegate
    private var heldModifiers: UInt8 = 0
    private var pressedKeys: [UInt8] = []
    private let clock = SuspendingClock()

    init?() {
        let delegate = VirtualKeyboardDelegate()
        let properties = HIDVirtualDevice.Properties(
            descriptor: Self.descriptor,
            vendorID: 0x16C0,
            productID: 0x27DB,
            transport: .virtual,
            product: "GlassToKey Virtual Keyboard",
            manufacturer: "GlassToKey",
            modelNumber: "G2K-VK",
            versionNumber: 1,
            serialNumber: "G2K-01",
            uniqueID: "com.kyome.GlassToKey.VirtualKeyboard",
            locationID: nil,
            localizationCode: nil,
            extraProperties: nil
        )
        guard let device = HIDVirtualDevice(properties: properties) else { return nil }
        self.device = device
        self.delegate = delegate
        Task { [device, delegate] in
            await device.activate(delegate: delegate)
        }
    }

    func sendKeyStroke(usage: UInt8, modifiers: UInt8) async {
        let downModifiers = heldModifiers | modifiers
        let downKeys = keysIncluding(usage)
        await dispatchReport(modifiers: downModifiers, keys: downKeys)
        await dispatchReport(modifiers: heldModifiers, keys: pressedKeys)
    }

    func sendModifierStroke(bit: UInt8, modifiers: UInt8) async {
        let downModifiers = heldModifiers | modifiers | bit
        await dispatchReport(modifiers: downModifiers, keys: pressedKeys)
        await dispatchReport(modifiers: heldModifiers, keys: pressedKeys)
    }

    func setModifier(bit: UInt8, isDown: Bool) async {
        if isDown {
            heldModifiers |= bit
        } else {
            heldModifiers &= ~bit
        }
        await dispatchReport(modifiers: heldModifiers, keys: pressedKeys)
    }

    func setKey(usage: UInt8, modifiers: UInt8, isDown: Bool) async {
        if isDown {
            if !pressedKeys.contains(usage) {
                pressedKeys.append(usage)
            }
        } else {
            pressedKeys.removeAll { $0 == usage }
        }
        let reportModifiers = isDown ? (heldModifiers | modifiers) : heldModifiers
        await dispatchReport(modifiers: reportModifiers, keys: pressedKeys)
    }

    private func keysIncluding(_ usage: UInt8) -> [UInt8] {
        if pressedKeys.contains(usage) {
            return pressedKeys
        }
        if pressedKeys.count < 6 {
            return pressedKeys + [usage]
        }
        return pressedKeys
    }

    private func dispatchReport(modifiers: UInt8, keys: [UInt8]) async {
        var report = [UInt8](repeating: 0, count: 8)
        report[0] = modifiers
        for (index, key) in keys.prefix(6).enumerated() {
            report[2 + index] = key
        }
        let data = Data(report)
        try? await device.dispatchInputReport(data: data, timestamp: clock.now)
    }

    private static let descriptor: Data = Data([
        0x05, 0x01,
        0x09, 0x06,
        0xA1, 0x01,
        0x05, 0x07,
        0x19, 0xE0,
        0x29, 0xE7,
        0x15, 0x00,
        0x25, 0x01,
        0x75, 0x01,
        0x95, 0x08,
        0x81, 0x02,
        0x75, 0x08,
        0x95, 0x01,
        0x81, 0x01,
        0x75, 0x08,
        0x95, 0x06,
        0x15, 0x00,
        0x25, 0x65,
        0x05, 0x07,
        0x19, 0x00,
        0x29, 0x65,
        0x81, 0x00,
        0xC0
    ])
}

@available(macOS 15, *)
private final class VirtualKeyboardDelegate: HIDVirtualDeviceDelegate {
    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedSetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        data: Data
    ) async throws {
    }

    func hidVirtualDevice(
        _ device: HIDVirtualDevice,
        receivedGetReportRequestOfType type: HIDReportType,
        id: HIDReportID?,
        maxSize: Int
    ) async throws -> Data {
        Data()
    }
}
#endif
