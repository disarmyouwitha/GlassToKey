//
//  ContentViewModel.swift
//  GlassToKey
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import Carbon
import CoreGraphics
import OpenMultitouchSupport
import SwiftUI

@MainActor
final class ContentViewModel: ObservableObject {
    enum KeyBindingAction: Sendable {
        case key(code: CGKeyCode, flags: CGEventFlags)
        case typingToggle
    }

    struct KeyBinding: Sendable {
        let rect: CGRect
        let label: String
        let action: KeyBindingAction
    }

    struct Layout {
        let keyRects: [[CGRect]]
    }

    static let leftGridLabels: [[String]] = [
        ["Esc", "Q", "W", "E", "R", "T"],
        ["Shift", "A", "S", "D", "F", "G"],
        ["Shift", "Z", "X", "C", "V", "B"]
    ]
    static let rightGridLabels: [[String]] = [
        ["Y", "U", "I", "O", "P", "Back"],
        ["H", "J", "K", "L", ";", "Ret"],
        ["N", "M", ",", ".", "/", "Ret"]
    ]
    private var latestTouchData = [OMSTouchData]()
    @Published var isListening: Bool = false
    @Published var isTypingEnabled: Bool = true
    private let isDragDetectionEnabled = true
    @Published var availableDevices = [OMSDeviceInfo]()
    @Published var leftDevice: OMSDeviceInfo?
    @Published var rightDevice: OMSDeviceInfo?

    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?
    private struct TouchKey: Hashable {
        let deviceID: String
        let id: Int32
    }
    private var customButtons: [CustomButton] = []

    private var activeTouches: [TouchKey: ActiveTouch] = [:]
    private var pendingTouches: [TouchKey: PendingTouch] = [:]
    private var disqualifiedTouches: Set<TouchKey> = []
    private var leftShiftTouchCount = 0
    private var controlTouchCount = 0
    private var repeatTasks: [TouchKey: Task<Void, Never>] = [:]
    private var toggleTouchStarts: [TouchKey: Date] = [:]
    private let tapMaxDuration: TimeInterval = 0.2
    private let holdMinDuration: TimeInterval = 0.2
    private let modifierActivationDelay: TimeInterval = 0.05
    private let dragCancelDistance: CGFloat = 5.0
    private let repeatInitialDelay: UInt64 = 350_000_000
    private let repeatInterval: UInt64 = 50_000_000
    private let holdBindingsByLabel: [String: (CGKeyCode, CGEventFlags)] = [
        "Esc": (CGKeyCode(kVK_Escape), []),
        "Q": (CGKeyCode(kVK_ANSI_LeftBracket), []),
        "W": (CGKeyCode(kVK_ANSI_RightBracket), []),
        "E": (CGKeyCode(kVK_ANSI_LeftBracket), .maskShift),
        "R": (CGKeyCode(kVK_ANSI_RightBracket), .maskShift),
        "T": (CGKeyCode(kVK_ANSI_Quote), []),
        "Y": (CGKeyCode(kVK_ANSI_Minus), []),
        "U": (CGKeyCode(kVK_ANSI_7), .maskShift),
        "I": (CGKeyCode(kVK_ANSI_8), .maskShift),
        "O": (CGKeyCode(kVK_ANSI_F), .maskCommand),
        "P": (CGKeyCode(kVK_ANSI_R), .maskCommand),
        "A": (CGKeyCode(kVK_ANSI_A), .maskCommand),
        "S": (CGKeyCode(kVK_ANSI_S), .maskCommand),
        "D": (CGKeyCode(kVK_ANSI_9), .maskShift),
        "F": (CGKeyCode(kVK_ANSI_0), .maskShift),
        "G": (CGKeyCode(kVK_ANSI_Quote), .maskShift),
        "H": (CGKeyCode(kVK_ANSI_Minus), .maskShift),
        "J": (CGKeyCode(kVK_ANSI_1), .maskShift),
        "K": (CGKeyCode(kVK_ANSI_3), .maskShift),
        "L": (CGKeyCode(kVK_ANSI_Grave), .maskShift),
        "Z": (CGKeyCode(kVK_ANSI_Z), .maskCommand),
        "X": (CGKeyCode(kVK_ANSI_X), .maskCommand),
        "C": (CGKeyCode(kVK_ANSI_C), .maskCommand),
        "V": (CGKeyCode(kVK_ANSI_V), .maskCommand),
        //"B": (CGKeyCode(kVK_Control), []),
        "N": (CGKeyCode(kVK_ANSI_Equal), []),
        "M": (CGKeyCode(kVK_ANSI_2), .maskShift),
        ",": (CGKeyCode(kVK_ANSI_4), .maskShift),
        ".": (CGKeyCode(kVK_ANSI_6), .maskShift),
        "/": (CGKeyCode(kVK_ANSI_Backslash), [])
    ]
    private var leftLayout: Layout?
    private var rightLayout: Layout?
    private var leftLabels: [[String]] = []
    private var rightLabels: [[String]] = []
    private var trackpadSize: CGSize = .zero

    init() {
        loadDevices()
    }

    var leftTouches: [OMSTouchData] {
        guard let deviceID = leftDevice?.deviceID else { return [] }
        return latestTouchData.filter { $0.deviceID == deviceID }
    }

    var rightTouches: [OMSTouchData] {
        guard let deviceID = rightDevice?.deviceID else { return [] }
        return latestTouchData.filter { $0.deviceID == deviceID }
    }

    func onAppear() {
        task = Task { [weak self, manager] in
            for await touchData in manager.touchDataStream {
                await MainActor.run {
                    guard let self else { return }
                    self.latestTouchData = touchData
                    guard let leftLayout = self.leftLayout,
                          let rightLayout = self.rightLayout else {
                        return
                    }
                    self.processTouches(
                        self.leftTouches,
                        keyRects: leftLayout.keyRects,
                        canvasSize: self.trackpadSize,
                        labels: self.leftLabels,
                        isLeftSide: true
                    )
                    self.processTouches(
                        self.rightTouches,
                        keyRects: rightLayout.keyRects,
                        canvasSize: self.trackpadSize,
                        labels: self.rightLabels,
                        isLeftSide: false
                    )
                }
            }
        }
    }

    func onDisappear() {
        task?.cancel()
        stop()
    }

    func start() {
        if manager.startListening() {
            isListening = true
        }
    }

    func stop() {
        if manager.stopListening() {
            isListening = false
            releaseHeldKeys()
        }
    }
    
    func loadDevices() {
        availableDevices = manager.availableDevices
        leftDevice = availableDevices.first
        if availableDevices.count > 1 {
            rightDevice = availableDevices[1]
        } else {
            rightDevice = nil
        }
        updateActiveDevices()
    }
    
    func selectLeftDevice(_ device: OMSDeviceInfo?) {
        leftDevice = device
        updateActiveDevices()
    }

    func selectRightDevice(_ device: OMSDeviceInfo?) {
        rightDevice = device
        updateActiveDevices()
    }

    func configureLayouts(
        leftLayout: Layout,
        rightLayout: Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize
    ) {
        self.leftLayout = leftLayout
        self.rightLayout = rightLayout
        self.leftLabels = leftLabels
        self.rightLabels = rightLabels
        self.trackpadSize = trackpadSize
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        customButtons = buttons
    }

    func snapshotTouchData() -> [OMSTouchData] {
        latestTouchData
    }

    private func updateActiveDevices() {
        let devices = [leftDevice, rightDevice].compactMap { $0 }
        guard !devices.isEmpty else { return }
        if manager.setActiveDevices(devices) {
            releaseHeldKeys()
        }
    }

    // MARK: - Key Tap Handling
    private enum ModifierKey {
        case shift
        case control
    }

    private struct ActiveTouch {
        let binding: KeyBinding
        let startTime: Date
        let startPoint: CGPoint
        let modifierKey: ModifierKey?
        let isContinuousKey: Bool
        let holdBinding: KeyBinding?
        var didHold: Bool
        var maxDistance: CGFloat
    }

    private struct PendingTouch {
        let binding: KeyBinding
        let startTime: Date
        let startPoint: CGPoint
        var maxDistance: CGFloat
    }

    func processTouches(
        _ touches: [OMSTouchData],
        keyRects: [[CGRect]],
        canvasSize: CGSize,
        labels: [[String]],
        isLeftSide: Bool
    ) {
        guard isListening else { return }
        let side: TrackpadSide = isLeftSide ? .left : .right
        let bindings = makeBindings(
            keyRects: keyRects,
            labels: labels,
            customButtons: customButtons.filter { $0.side == side },
            canvasSize: canvasSize
        )

        for touch in touches {
            let point = CGPoint(
                x: CGFloat(touch.position.x) * canvasSize.width,
                y: CGFloat(1.0 - touch.position.y) * canvasSize.height
            )
            let touchKey = TouchKey(deviceID: touch.deviceID, id: touch.id)
            let bindingAtPoint = binding(at: point, bindings: bindings)

            if toggleTouchStarts[touchKey] != nil {
                handleTypingToggleTouch(touchKey: touchKey, state: touch.state)
                continue
            }
            if case .typingToggle = bindingAtPoint?.action {
                handleTypingToggleTouch(touchKey: touchKey, state: touch.state)
                continue
            }
            if !isTypingEnabled {
                if let active = activeTouches.removeValue(forKey: touchKey) {
                    if let modifierKey = active.modifierKey {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.isContinuousKey {
                        stopRepeat(for: touchKey)
                    }
                }
                pendingTouches.removeValue(forKey: touchKey)
                disqualifiedTouches.remove(touchKey)
                continue
            }

            if disqualifiedTouches.contains(touchKey) {
                switch touch.state {
                case .breaking, .leaving, .notTouching:
                    disqualifiedTouches.remove(touchKey)
                case .starting, .making, .touching, .hovering, .lingering:
                    break
                }
                continue
            }

            switch touch.state {
            case .starting, .making, .touching:
                if var active = activeTouches[touchKey] {
                    active.maxDistance = max(active.maxDistance, distance(from: active.startPoint, to: point))
                    activeTouches[touchKey] = active

                    if isDragDetectionEnabled,
                       active.modifierKey == nil,
                       !active.isContinuousKey,
                       !active.didHold,
                       active.maxDistance > dragCancelDistance {
                        disqualifyTouch(touchKey)
                        continue
                    }

                    if active.modifierKey == nil,
                       !active.isContinuousKey,
                       !active.didHold,
                       let holdBinding = active.holdBinding,
                       Date().timeIntervalSince(active.startTime) >= holdMinDuration,
                       (!isDragDetectionEnabled || active.maxDistance <= dragCancelDistance) {
                        sendKey(binding: holdBinding)
                        active.didHold = true
                        activeTouches[touchKey] = active
                    }
                } else if var pending = pendingTouches[touchKey] {
                    pending.maxDistance = max(pending.maxDistance, distance(from: pending.startPoint, to: point))
                    pendingTouches[touchKey] = pending

                    if isDragDetectionEnabled, pending.maxDistance > dragCancelDistance {
                        disqualifyTouch(touchKey)
                        continue
                    }

                    if Date().timeIntervalSince(pending.startTime) >= modifierActivationDelay {
                        if pending.binding.rect.contains(point) {
                            let modifierKey = modifierKey(for: pending.binding)
                            let isContinuousKey = isContinuousKey(pending.binding)
                            let holdBinding = holdBinding(for: pending.binding)
                            activeTouches[touchKey] = ActiveTouch(
                                binding: pending.binding,
                                startTime: pending.startTime,
                                startPoint: pending.startPoint,
                                modifierKey: modifierKey,
                                isContinuousKey: isContinuousKey,
                                holdBinding: holdBinding,
                                didHold: false,
                                maxDistance: pending.maxDistance
                            )
                            pendingTouches.removeValue(forKey: touchKey)
                            if let modifierKey {
                                handleModifierDown(modifierKey, binding: pending.binding)
                            } else if isContinuousKey {
                                sendKey(binding: pending.binding)
                                startRepeat(for: touchKey, binding: pending.binding)
                            }
                        } else if isDragDetectionEnabled {
                            disqualifyTouch(touchKey)
                        } else {
                            pendingTouches.removeValue(forKey: touchKey)
                        }
                    }
                } else if let binding = bindingAtPoint {
                    let modifierKey = modifierKey(for: binding)
                    let isContinuousKey = isContinuousKey(binding)
                    let holdBinding = holdBinding(for: binding)
                    if isDragDetectionEnabled, (modifierKey != nil || isContinuousKey) {
                        pendingTouches[touchKey] = PendingTouch(
                            binding: binding,
                            startTime: Date(),
                            startPoint: point,
                            maxDistance: 0
                        )
                    } else {
                        activeTouches[touchKey] = ActiveTouch(
                            binding: binding,
                            startTime: Date(),
                            startPoint: point,
                            modifierKey: modifierKey,
                            isContinuousKey: isContinuousKey,
                            holdBinding: holdBinding,
                            didHold: false,
                            maxDistance: 0
                        )
                        if let modifierKey {
                            handleModifierDown(modifierKey, binding: binding)
                        } else if isContinuousKey {
                            sendKey(binding: binding)
                            startRepeat(for: touchKey, binding: binding)
                        }
                    }
                }
            case .breaking, .leaving:
                if let pending = pendingTouches.removeValue(forKey: touchKey) {
                    maybeSendPendingContinuousTap(pending, at: point)
                }
                if disqualifiedTouches.remove(touchKey) != nil {
                    continue
                }
                if let active = activeTouches.removeValue(forKey: touchKey) {
                    if let modifierKey = active.modifierKey {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.isContinuousKey {
                        stopRepeat(for: touchKey)
                    } else if !active.didHold,
                              Date().timeIntervalSince(active.startTime) <= tapMaxDuration,
                              (!isDragDetectionEnabled || active.maxDistance <= dragCancelDistance) {
                        sendKey(binding: active.binding)
                    }
                }
            case .notTouching:
                if let pending = pendingTouches.removeValue(forKey: touchKey) {
                    maybeSendPendingContinuousTap(pending, at: point)
                }
                if disqualifiedTouches.remove(touchKey) != nil {
                    continue
                }
                if let active = activeTouches.removeValue(forKey: touchKey) {
                    if let modifierKey = active.modifierKey {
                        handleModifierUp(modifierKey, binding: active.binding)
                    } else if active.isContinuousKey {
                        stopRepeat(for: touchKey)
                    }
                }
            case .hovering, .lingering:
                break
            }
        }
    }

    private func makeBindings(
        keyRects: [[CGRect]],
        labels: [[String]],
        customButtons: [CustomButton],
        canvasSize: CGSize
    ) -> [KeyBinding] {
        var bindings: [KeyBinding] = []
        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < labels.count,
                      col < labels[row].count else { continue }
                let label = labels[row][col]
                guard let binding = bindingForLabel(label, rect: keyRects[row][col]) else { continue }
                bindings.append(binding)
            }
        }

        for button in customButtons {
            let rect = button.rect.rect(in: canvasSize)
            let action: KeyBindingAction
            switch button.action.kind {
            case .key:
                action = .key(
                    code: CGKeyCode(button.action.keyCode),
                    flags: CGEventFlags(rawValue: button.action.flags)
                )
            case .typingToggle:
                action = .typingToggle
            }
            bindings.append(KeyBinding(
                rect: rect,
                label: button.action.label,
                action: action
            ))
        }

        return bindings
    }

    private func bindingForLabel(_ label: String, rect: CGRect) -> KeyBinding? {
        guard let (code, flags) = KeyActionCatalog.bindingsByLabel[label] else { return nil }
        return KeyBinding(rect: rect, label: label, action: .key(code: code, flags: flags))
    }

    private func binding(at point: CGPoint, bindings: [KeyBinding]) -> KeyBinding? {
        bindings.first { $0.rect.contains(point) }
    }

    private func handleTypingToggleTouch(touchKey: TouchKey, state: OMSState) {
        switch state {
        case .starting, .making, .touching:
            if toggleTouchStarts[touchKey] == nil {
                toggleTouchStarts[touchKey] = Date()
            }
        case .breaking, .leaving:
            if toggleTouchStarts.removeValue(forKey: touchKey) != nil {
                toggleTypingMode()
            }
        case .notTouching:
            toggleTouchStarts.removeValue(forKey: touchKey)
        case .hovering, .lingering:
            break
        }
    }

    private func toggleTypingMode() {
        isTypingEnabled.toggle()
        if !isTypingEnabled {
            releaseHeldKeys()
        }
    }

    private func modifierKey(for binding: KeyBinding) -> ModifierKey? {
        guard case let .key(code, _) = binding.action else { return nil }
        if code == CGKeyCode(kVK_Shift) {
            return .shift
        }
        if code == CGKeyCode(kVK_Control) {
            return .control
        }
        return nil
    }

    private func isContinuousKey(_ binding: KeyBinding) -> Bool {
        guard case let .key(code, _) = binding.action else { return false }
        return code == CGKeyCode(kVK_Space) || code == CGKeyCode(kVK_Delete)
    }

    private func holdBinding(for binding: KeyBinding) -> KeyBinding? {
        guard let (code, flags) = holdBindingsByLabel[binding.label] else { return nil }
        return KeyBinding(
            rect: binding.rect,
            label: binding.label,
            action: .key(code: code, flags: flags)
        )
    }

    private func maybeSendPendingContinuousTap(_ pending: PendingTouch, at point: CGPoint) {
        guard isContinuousKey(pending.binding),
              Date().timeIntervalSince(pending.startTime) <= tapMaxDuration,
              pending.binding.rect.contains(point),
              (!isDragDetectionEnabled || pending.maxDistance <= dragCancelDistance) else {
            return
        }
        sendKey(binding: pending.binding)
    }

    private func sendKey(binding: KeyBinding) {
        guard case let .key(code, flags) = binding.action else { return }
        var modifierFlags: CGEventFlags = []
        if leftShiftTouchCount > 0 {
            modifierFlags.insert(.maskShift)
        }
        if controlTouchCount > 0 {
            modifierFlags.insert(.maskControl)
        }
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            return
        }
        let combinedFlags = flags.union(modifierFlags)
        keyDown.flags = combinedFlags
        keyUp.flags = combinedFlags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func startRepeat(for touchKey: TouchKey, binding: KeyBinding) {
        stopRepeat(for: touchKey)
        repeatTasks[touchKey] = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: self.repeatInitialDelay)
            while !Task.isCancelled {
                guard self.activeTouches[touchKey] != nil else { return }
                self.sendKey(binding: binding)
                try? await Task.sleep(nanoseconds: self.repeatInterval)
            }
        }
    }

    private func stopRepeat(for touchKey: TouchKey) {
        if let task = repeatTasks.removeValue(forKey: touchKey) {
            task.cancel()
        }
    }

    private func handleModifierDown(_ modifierKey: ModifierKey, binding: KeyBinding) {
        switch modifierKey {
        case .shift:
            if leftShiftTouchCount == 0 {
                postKey(binding: binding, keyDown: true)
            }
            leftShiftTouchCount += 1
        case .control:
            if controlTouchCount == 0 {
                postKey(binding: binding, keyDown: true)
            }
            controlTouchCount += 1
        }
    }

    private func handleModifierUp(_ modifierKey: ModifierKey, binding: KeyBinding) {
        switch modifierKey {
        case .shift:
            leftShiftTouchCount = max(0, leftShiftTouchCount - 1)
            if leftShiftTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
        case .control:
            controlTouchCount = max(0, controlTouchCount - 1)
            if controlTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
        }
    }

    private func postKey(binding: KeyBinding, keyDown: Bool) {
        guard case let .key(code, flags) = binding.action else { return }
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: code,
            keyDown: keyDown
        ) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func releaseHeldKeys() {
        if leftShiftTouchCount > 0 {
            let shiftBinding = KeyBinding(
                rect: .zero,
                label: "Shift",
                action: .key(code: CGKeyCode(kVK_Shift), flags: [])
            )
            postKey(binding: shiftBinding, keyDown: false)
            leftShiftTouchCount = 0
        }
        if controlTouchCount > 0 {
            let controlBinding = KeyBinding(
                rect: .zero,
                label: "Ctrl",
                action: .key(code: CGKeyCode(kVK_Control), flags: [])
            )
            postKey(binding: controlBinding, keyDown: false)
            controlTouchCount = 0
        }
        for touchKey in activeTouches.keys {
            stopRepeat(for: touchKey)
        }
        activeTouches.removeAll()
        pendingTouches.removeAll()
        disqualifiedTouches.removeAll()
        toggleTouchStarts.removeAll()
    }

    private func disqualifyTouch(_ touchKey: TouchKey) {
        disqualifiedTouches.insert(touchKey)
        pendingTouches.removeValue(forKey: touchKey)
        if let active = activeTouches.removeValue(forKey: touchKey) {
            if let modifierKey = active.modifierKey {
                handleModifierUp(modifierKey, binding: active.binding)
            } else if active.isContinuousKey {
                stopRepeat(for: touchKey)
            }
        }
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

enum TrackpadSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
}

struct NormalizedRect: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    func clamped(minWidth: CGFloat, minHeight: CGFloat) -> NormalizedRect {
        var updated = self
        updated.width = max(minWidth, min(updated.width, 1.0))
        updated.height = max(minHeight, min(updated.height, 1.0))
        updated.x = min(max(updated.x, 0.0), 1.0 - updated.width)
        updated.y = min(max(updated.y, 0.0), 1.0 - updated.height)
        return updated
    }

    func mirroredHorizontally() -> NormalizedRect {
        NormalizedRect(
            x: 1.0 - x - width,
            y: y,
            width: width,
            height: height
        )
    }
}

enum KeyActionKind: String, Codable {
    case key
    case typingToggle
}

struct KeyAction: Codable, Hashable {
    var label: String
    var keyCode: UInt16
    var flags: UInt64
    var kind: KeyActionKind

    init(label: String, keyCode: UInt16, flags: UInt64, kind: KeyActionKind = .key) {
        self.label = label
        self.keyCode = keyCode
        self.flags = flags
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        flags = try container.decode(UInt64.self, forKey: .flags)
        kind = try container.decodeIfPresent(KeyActionKind.self, forKey: .kind) ?? .key
        if kind == .typingToggle, label == KeyActionCatalog.legacyTypingToggleLabel {
            label = KeyActionCatalog.typingToggleLabel
        }
    }
}

struct CustomButton: Identifiable, Codable, Hashable {
    var id: UUID
    var side: TrackpadSide
    var rect: NormalizedRect
    var action: KeyAction
}

enum CustomButtonStore {
    static func decode(_ data: Data) -> [CustomButton]? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode([CustomButton].self, from: data)
        } catch {
            return nil
        }
    }

    static func encode(_ buttons: [CustomButton]) -> Data? {
        do {
            return try JSONEncoder().encode(buttons)
        } catch {
            return nil
        }
    }
}

enum CustomButtonDefaults {
    static func defaultButtons(
        trackpadWidth: CGFloat,
        trackpadHeight: CGFloat,
        thumbAnchorsMM: [CGRect]
    ) -> [CustomButton] {
        let leftActions = [
            KeyActionCatalog.action(for: "Backspace"),
            KeyActionCatalog.action(for: "Space")
        ].compactMap { $0 }
        let rightActions = [
            KeyActionCatalog.action(for: "Space"),
            KeyActionCatalog.action(for: "Space"),
            KeyActionCatalog.action(for: "Space"),
            KeyActionCatalog.action(for: "Return")
        ].compactMap { $0 }

        func normalize(_ rect: CGRect) -> NormalizedRect {
            NormalizedRect(
                x: rect.minX / trackpadWidth,
                y: rect.minY / trackpadHeight,
                width: rect.width / trackpadWidth,
                height: rect.height / trackpadHeight
            )
        }

        var buttons: [CustomButton] = []
        for (index, rect) in thumbAnchorsMM.enumerated() {
            let normalized = normalize(rect)
            if index < leftActions.count {
                buttons.append(CustomButton(
                    id: UUID(),
                    side: .left,
                    rect: normalized.mirroredHorizontally(),
                    action: leftActions[index]
                ))
            }
            if index < rightActions.count {
                buttons.append(CustomButton(
                    id: UUID(),
                    side: .right,
                    rect: normalized,
                    action: rightActions[index]
                ))
            }
        }
        return buttons
    }
}

enum KeyActionCatalog {
    static let typingToggleLabel = "Typing Toggle"
    static let legacyTypingToggleLabel = "Typing Mode Toggle"
    static let bindingsByLabel: [String: (CGKeyCode, CGEventFlags)] = [
        "Esc": (CGKeyCode(kVK_Tab), []),
        "Escape": (CGKeyCode(kVK_Escape), []),
        "Tab": (CGKeyCode(kVK_Tab), []),
        "Q": (CGKeyCode(kVK_ANSI_Q), []),
        "W": (CGKeyCode(kVK_ANSI_W), []),
        "E": (CGKeyCode(kVK_ANSI_E), []),
        "R": (CGKeyCode(kVK_ANSI_R), []),
        "T": (CGKeyCode(kVK_ANSI_T), []),
        "Option": (CGKeyCode(kVK_Option), []),
        "Shift": (CGKeyCode(kVK_Shift), []),
        "A": (CGKeyCode(kVK_ANSI_A), []),
        "S": (CGKeyCode(kVK_ANSI_S), []),
        "D": (CGKeyCode(kVK_ANSI_D), []),
        "F": (CGKeyCode(kVK_ANSI_F), []),
        "G": (CGKeyCode(kVK_ANSI_G), []),
        "Ctrl": (CGKeyCode(kVK_Control), []),
        "Z": (CGKeyCode(kVK_ANSI_Z), []),
        "X": (CGKeyCode(kVK_ANSI_X), []),
        "C": (CGKeyCode(kVK_ANSI_C), []),
        "V": (CGKeyCode(kVK_ANSI_V), []),
        "B": (CGKeyCode(kVK_ANSI_B), []),
        "Y": (CGKeyCode(kVK_ANSI_Y), []),
        "U": (CGKeyCode(kVK_ANSI_U), []),
        "I": (CGKeyCode(kVK_ANSI_I), []),
        "O": (CGKeyCode(kVK_ANSI_O), []),
        "P": (CGKeyCode(kVK_ANSI_P), []),
        "Back": (CGKeyCode(kVK_Delete), []),
        "Backspace": (CGKeyCode(kVK_Delete), []),
        "H": (CGKeyCode(kVK_ANSI_H), []),
        "J": (CGKeyCode(kVK_ANSI_J), []),
        "K": (CGKeyCode(kVK_ANSI_K), []),
        "L": (CGKeyCode(kVK_ANSI_L), []),
        ";": (CGKeyCode(kVK_ANSI_Semicolon), []),
        "Ret": (CGKeyCode(kVK_Return), []),
        "Return": (CGKeyCode(kVK_Return), []),
        "N": (CGKeyCode(kVK_ANSI_N), []),
        "M": (CGKeyCode(kVK_ANSI_M), []),
        ",": (CGKeyCode(kVK_ANSI_Comma), []),
        ".": (CGKeyCode(kVK_ANSI_Period), []),
        "/": (CGKeyCode(kVK_ANSI_Slash), []),
        "\\": (CGKeyCode(kVK_ANSI_Backslash), []),
        "?": (CGKeyCode(kVK_ANSI_Slash), .maskShift),
        "Space": (CGKeyCode(kVK_Space), [])
    ]

    static let presets: [KeyAction] = {
        var items: [KeyAction] = []
        for (label, binding) in bindingsByLabel {
            items.append(KeyAction(
                label: label,
                keyCode: UInt16(binding.0),
                flags: binding.1.rawValue
            ))
        }
        items.append(KeyAction(
            label: typingToggleLabel,
            keyCode: 0,
            flags: 0,
            kind: .typingToggle
        ))
        return items.sorted { $0.label < $1.label }
    }()

    static func action(for label: String) -> KeyAction? {
        if label == typingToggleLabel || label == legacyTypingToggleLabel {
            return KeyAction(
                label: typingToggleLabel,
                keyCode: 0,
                flags: 0,
                kind: .typingToggle
            )
        }
        guard let binding = bindingsByLabel[label] else { return nil }
        return KeyAction(
            label: label,
            keyCode: UInt16(binding.0),
            flags: binding.1.rawValue
        )
    }
}
