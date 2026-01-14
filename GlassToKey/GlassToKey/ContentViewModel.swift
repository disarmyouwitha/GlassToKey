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

enum TrackpadSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
}

typealias LayeredKeyMappings = [Int: [String: KeyMapping]]

struct GridKeyPosition: Codable, Hashable {
    let side: TrackpadSide
    let row: Int
    let column: Int

    init(side: TrackpadSide, row: Int, column: Int) {
        self.side = side
        self.row = row
        self.column = column
    }

    private static let separator = ":"

    var storageKey: String {
        "\(side.rawValue)\(Self.separator)\(row)\(Self.separator)\(column)"
    }

    static func from(storageKey: String) -> GridKeyPosition? {
        guard let separatorChar = separator.first else { return nil }
        let components = storageKey.split(separator: separatorChar)
        guard components.count == 3,
              let side = TrackpadSide(rawValue: String(components[0])),
              let row = Int(components[1]),
              let column = Int(components[2]) else {
            return nil
        }
        return GridKeyPosition(side: side, row: row, column: column)
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    enum KeyBindingAction: Sendable {
        case key(code: CGKeyCode, flags: CGEventFlags)
        case typingToggle
        case layerMomentary(Int)
        case layerToggle(Int)
        case none
    }

    struct KeyBinding: Sendable {
        let rect: CGRect
        let label: String
        let action: KeyBindingAction
        let position: GridKeyPosition?
        let holdAction: KeyAction?
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
    @Published private(set) var activeLayer: Int = 0
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
    private var customKeyMappingsByLayer: LayeredKeyMappings = [:]
    private var persistentLayer: Int = 0

    private var activeTouches: [TouchKey: ActiveTouch] = [:]
    private var pendingTouches: [TouchKey: PendingTouch] = [:]
    private var disqualifiedTouches: Set<TouchKey> = []
    private var leftShiftTouchCount = 0
    private var controlTouchCount = 0
    private var optionTouchCount = 0
    private var commandTouchCount = 0
    private var repeatTasks: [TouchKey: Task<Void, Never>] = [:]
    private var toggleTouchStarts: [TouchKey: Date] = [:]
    private var layerToggleTouchStarts: [TouchKey: Int] = [:]
    private var momentaryLayerTouches: [TouchKey: Int] = [:]
    private let tapMaxDuration: TimeInterval = 0.2
    private let holdMinDuration: TimeInterval = 0.2
    private let modifierActivationDelay: TimeInterval = 0.05
    private let dragCancelDistance: CGFloat = 5.0
    private let repeatInitialDelay: UInt64 = 350_000_000
    private let repeatInterval: UInt64 = 50_000_000
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

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        customKeyMappingsByLayer = actions
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
        case option
        case command
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

    func setPersistentLayer(_ layer: Int) {
        let clamped = max(0, min(layer, 1))
        persistentLayer = clamped
        updateActiveLayer()
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
            canvasSize: canvasSize,
            side: side
        )

        for touch in touches {
            let point = CGPoint(
                x: CGFloat(touch.position.x) * canvasSize.width,
                y: CGFloat(1.0 - touch.position.y) * canvasSize.height
            )
            let touchKey = TouchKey(deviceID: touch.deviceID, id: touch.id)
            let bindingAtPoint = binding(at: point, bindings: bindings)

            if momentaryLayerTouches[touchKey] != nil {
                handleMomentaryLayerTouch(touchKey: touchKey, state: touch.state, targetLayer: nil)
                continue
            }
            if layerToggleTouchStarts[touchKey] != nil {
                handleLayerToggleTouch(touchKey: touchKey, state: touch.state, targetLayer: nil)
                continue
            }
            if toggleTouchStarts[touchKey] != nil {
                handleTypingToggleTouch(touchKey: touchKey, state: touch.state)
                continue
            }
            if let binding = bindingAtPoint {
                switch binding.action {
                case .typingToggle:
                    handleTypingToggleTouch(touchKey: touchKey, state: touch.state)
                    continue
                case let .layerToggle(targetLayer):
                    handleLayerToggleTouch(touchKey: touchKey, state: touch.state, targetLayer: targetLayer)
                    continue
                case let .layerMomentary(targetLayer):
                    handleMomentaryLayerTouch(touchKey: touchKey, state: touch.state, targetLayer: targetLayer)
                    continue
                case .none:
                    continue
                case .key:
                    break
                }
            }
            if !isTypingEnabled && momentaryLayerTouches.isEmpty {
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
                        triggerBinding(holdBinding, touchKey: touchKey)
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
                                triggerBinding(pending.binding, touchKey: touchKey)
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
                            triggerBinding(binding, touchKey: touchKey)
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
                        triggerBinding(active.binding, touchKey: touchKey)
                    }
                    endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
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
                    endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
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
        canvasSize: CGSize,
        side: TrackpadSide
    ) -> [KeyBinding] {
        var bindings: [KeyBinding] = []
        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < labels.count,
                      col < labels[row].count else { continue }
                let label = labels[row][col]
                let position = GridKeyPosition(side: side, row: row, column: col)
                guard let binding = bindingForLabel(label, rect: keyRects[row][col], position: position) else { continue }
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
            case .layerMomentary:
                action = .layerMomentary(button.action.layer ?? 1)
            case .layerToggle:
                action = .layerToggle(button.action.layer ?? 1)
            }
            bindings.append(KeyBinding(
                rect: rect,
                label: button.action.label,
                action: action,
                position: nil,
                holdAction: button.hold
            ))
        }

        return bindings
    }

    private func bindingForLabel(_ label: String, rect: CGRect, position: GridKeyPosition) -> KeyBinding? {
        guard let action = keyAction(for: position, label: label) else { return nil }
        return makeBinding(for: action, rect: rect, position: position)
    }

    private func keyAction(for position: GridKeyPosition, label: String) -> KeyAction? {
        let layerMappings = customKeyMappingsByLayer[activeLayer] ?? [:]
        if let mapping = layerMappings[position.storageKey] {
            return mapping.primary
        }
        if let mapping = layerMappings[label] {
            return mapping.primary
        }
        return KeyActionCatalog.action(for: label)
    }

    private func holdAction(for position: GridKeyPosition?, label: String) -> KeyAction? {
        let layerMappings = customKeyMappingsByLayer[activeLayer] ?? [:]
        if let position, let mapping = layerMappings[position.storageKey] {
            if let hold = mapping.hold { return hold }
        }
        if let mapping = layerMappings[label], let hold = mapping.hold {
            return hold
        }
        return KeyActionCatalog.holdAction(for: label)
    }

    private func makeBinding(
        for action: KeyAction,
        rect: CGRect,
        position: GridKeyPosition?,
        holdAction: KeyAction? = nil
    ) -> KeyBinding? {
        switch action.kind {
        case .key:
            let flags = CGEventFlags(rawValue: action.flags)
            return KeyBinding(
                rect: rect,
                label: action.label,
                action: .key(code: CGKeyCode(action.keyCode), flags: flags),
                position: position,
                holdAction: holdAction
            )
        case .typingToggle:
            return KeyBinding(
                rect: rect,
                label: action.label,
                action: .typingToggle,
                position: position,
                holdAction: holdAction
            )
        case .layerMomentary:
            return KeyBinding(
                rect: rect,
                label: action.label,
                action: .layerMomentary(action.layer ?? 1),
                position: position,
                holdAction: holdAction
            )
        case .layerToggle:
            return KeyBinding(
                rect: rect,
                label: action.label,
                action: .layerToggle(action.layer ?? 1),
                position: position,
                holdAction: holdAction
            )
        case .none:
            return KeyBinding(
                rect: rect,
                label: action.label,
                action: .none,
                position: position,
                holdAction: holdAction
            )
        }
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

    private func handleLayerToggleTouch(
        touchKey: TouchKey,
        state: OMSState,
        targetLayer: Int?
    ) {
        switch state {
        case .starting, .making, .touching:
            guard isTypingEnabled else { break }
            if let targetLayer {
                layerToggleTouchStarts[touchKey] = targetLayer
            }
        case .breaking, .leaving:
            if let targetLayer = layerToggleTouchStarts.removeValue(forKey: touchKey) {
                guard isTypingEnabled else { break }
                toggleLayer(to: targetLayer)
            }
        case .notTouching:
            layerToggleTouchStarts.removeValue(forKey: touchKey)
        case .hovering, .lingering:
            break
        }
    }

    private func handleMomentaryLayerTouch(
        touchKey: TouchKey,
        state: OMSState,
        targetLayer: Int?
    ) {
        switch state {
        case .starting, .making, .touching:
            if momentaryLayerTouches[touchKey] == nil, let targetLayer {
                momentaryLayerTouches[touchKey] = targetLayer
                updateActiveLayer()
            }
        case .breaking, .leaving, .notTouching:
            if momentaryLayerTouches.removeValue(forKey: touchKey) != nil {
                updateActiveLayer()
            }
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
        if code == CGKeyCode(kVK_Option) {
            return .option
        }
        if code == CGKeyCode(kVK_Command) {
            return .command
        }
        return nil
    }

    private func isContinuousKey(_ binding: KeyBinding) -> Bool {
        guard case let .key(code, _) = binding.action else { return false }
        return code == CGKeyCode(kVK_Space) || code == CGKeyCode(kVK_Delete)
    }

    private func holdBinding(for binding: KeyBinding) -> KeyBinding? {
        if let holdAction = binding.holdAction {
            return makeBinding(
                for: holdAction,
                rect: binding.rect,
                position: binding.position,
                holdAction: binding.holdAction
            )
        }
        guard let action = holdAction(for: binding.position, label: binding.label) else { return nil }
        return makeBinding(
            for: action,
            rect: binding.rect,
            position: binding.position
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

    private func triggerBinding(
        _ binding: KeyBinding,
        touchKey: TouchKey?
    ) {
        switch binding.action {
        case let .layerMomentary(layer):
            guard let touchKey else { return }
            momentaryLayerTouches[touchKey] = layer
            updateActiveLayer()
        case let .layerToggle(layer):
            toggleLayer(to: layer)
        case .typingToggle:
            toggleTypingMode()
        case .none:
            break
        case let .key(code, flags):
            sendKey(code: code, flags: flags)
        }
    }

    private func sendKey(code: CGKeyCode, flags: CGEventFlags) {
        var modifierFlags: CGEventFlags = []
        if leftShiftTouchCount > 0 {
            modifierFlags.insert(.maskShift)
        }
        if controlTouchCount > 0 {
            modifierFlags.insert(.maskControl)
        }
        if optionTouchCount > 0 {
            modifierFlags.insert(.maskAlternate)
        }
        if commandTouchCount > 0 {
            modifierFlags.insert(.maskCommand)
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

    private func sendKey(binding: KeyBinding) {
        guard case let .key(code, flags) = binding.action else { return }
        sendKey(code: code, flags: flags)
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
        case .option:
            if optionTouchCount == 0 {
                postKey(binding: binding, keyDown: true)
            }
            optionTouchCount += 1
        case .command:
            if commandTouchCount == 0 {
                postKey(binding: binding, keyDown: true)
            }
            commandTouchCount += 1
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
        case .option:
            optionTouchCount = max(0, optionTouchCount - 1)
            if optionTouchCount == 0 {
                postKey(binding: binding, keyDown: false)
            }
        case .command:
            commandTouchCount = max(0, commandTouchCount - 1)
            if commandTouchCount == 0 {
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
                action: .key(code: CGKeyCode(kVK_Shift), flags: []),
                position: nil,
                holdAction: nil
            )
            postKey(binding: shiftBinding, keyDown: false)
            leftShiftTouchCount = 0
        }
        if controlTouchCount > 0 {
            let controlBinding = KeyBinding(
                rect: .zero,
                label: "Ctrl",
                action: .key(code: CGKeyCode(kVK_Control), flags: []),
                position: nil,
                holdAction: nil
            )
            postKey(binding: controlBinding, keyDown: false)
            controlTouchCount = 0
        }
        if optionTouchCount > 0 {
            let optionBinding = KeyBinding(
                rect: .zero,
                label: "Option",
                action: .key(code: CGKeyCode(kVK_Option), flags: []),
                position: nil,
                holdAction: nil
            )
            postKey(binding: optionBinding, keyDown: false)
            optionTouchCount = 0
        }
        if commandTouchCount > 0 {
            let commandBinding = KeyBinding(
                rect: .zero,
                label: "Cmd",
                action: .key(code: CGKeyCode(kVK_Command), flags: []),
                position: nil,
                holdAction: nil
            )
            postKey(binding: commandBinding, keyDown: false)
            commandTouchCount = 0
        }
        for touchKey in activeTouches.keys {
            stopRepeat(for: touchKey)
        }
        activeTouches.removeAll()
        pendingTouches.removeAll()
        disqualifiedTouches.removeAll()
        toggleTouchStarts.removeAll()
        layerToggleTouchStarts.removeAll()
        momentaryLayerTouches.removeAll()
        updateActiveLayer()
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
            endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
        }
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func toggleLayer(to layer: Int) { 
        let clamped = max(0, min(layer, 1))
        if persistentLayer == clamped {
            persistentLayer = 0
        } else {
            persistentLayer = clamped
        }
        updateActiveLayer()
    }

    private func updateActiveLayer() {
        if let momentaryLayer = momentaryLayerTouches.values.max() {
            activeLayer = momentaryLayer
        } else {
            activeLayer = persistentLayer
        }
    }

    private func endMomentaryHoldIfNeeded(_ binding: KeyBinding?, touchKey: TouchKey) {
        guard let binding else { return }
        switch binding.action {
        case .layerMomentary:
            if momentaryLayerTouches.removeValue(forKey: touchKey) != nil {
                updateActiveLayer()
            }
        default:
            break
        }
    }
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
    case layerMomentary
    case layerToggle
    case none
}

struct KeyAction: Codable, Hashable {
    var label: String
    var keyCode: UInt16
    var flags: UInt64
    var kind: KeyActionKind
    var layer: Int?

    private enum CodingKeys: String, CodingKey {
        case label
        case keyCode
        case flags
        case kind
        case layer
    }

    init(
        label: String,
        keyCode: UInt16,
        flags: UInt64,
        kind: KeyActionKind = .key,
        layer: Int? = nil
    ) {
        self.label = label
        self.keyCode = keyCode
        self.flags = flags
        self.kind = kind
        self.layer = layer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        flags = try container.decode(UInt64.self, forKey: .flags)
        kind = try container.decodeIfPresent(KeyActionKind.self, forKey: .kind) ?? .key
        layer = try container.decodeIfPresent(Int.self, forKey: .layer)
        if kind == .typingToggle, label == KeyActionCatalog.legacyTypingToggleLabel {
            label = KeyActionCatalog.typingToggleLabel
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(flags, forKey: .flags)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(layer, forKey: .layer)
    }
}

struct KeyMapping: Codable, Hashable {
    var primary: KeyAction
    var hold: KeyAction?
}

struct CustomButton: Identifiable, Codable, Hashable {
    var id: UUID
    var side: TrackpadSide
    var rect: NormalizedRect
    var action: KeyAction
    var hold: KeyAction?
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
                    ,
                    hold: nil
                ))
            }
            if index < rightActions.count {
                buttons.append(CustomButton(
                    id: UUID(),
                    side: .right,
                    rect: normalized,
                    action: rightActions[index]
                    ,
                    hold: nil
                ))
            }
        }
        return buttons
    }
}

enum KeyActionCatalog {
    static let typingToggleLabel = "Typing Toggle"
    static let typingToggleDisplayLabel = "Typing\nToggle"
    static let legacyTypingToggleLabel = "Typing Mode Toggle"
    static let momentaryLayer1Label = "MO(1)"
    static let toggleLayer1Label = "TO(1)"
    static let noneLabel = "None"
    static var noneAction: KeyAction {
        KeyAction(
            label: noneLabel,
            keyCode: UInt16.max,
            flags: 0,
            kind: .none
        )
    }
    static let holdBindingsByLabel: [String: (CGKeyCode, CGEventFlags)] = [
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
    static let bindingsByLabel: [String: (CGKeyCode, CGEventFlags)] = [
        "Esc": (CGKeyCode(kVK_Escape), []),
        "Tab": (CGKeyCode(kVK_Tab), []),
        "`": (CGKeyCode(kVK_ANSI_Grave), []),
        "1": (CGKeyCode(kVK_ANSI_1), []),
        "2": (CGKeyCode(kVK_ANSI_2), []),
        "3": (CGKeyCode(kVK_ANSI_3), []),
        "4": (CGKeyCode(kVK_ANSI_4), []),
        "5": (CGKeyCode(kVK_ANSI_5), []),
        "6": (CGKeyCode(kVK_ANSI_6), []),
        "7": (CGKeyCode(kVK_ANSI_7), []),
        "8": (CGKeyCode(kVK_ANSI_8), []),
        "9": (CGKeyCode(kVK_ANSI_9), []),
        "0": (CGKeyCode(kVK_ANSI_0), []),
        "-": (CGKeyCode(kVK_ANSI_Minus), []),
        "=": (CGKeyCode(kVK_ANSI_Equal), []),
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
        "[": (CGKeyCode(kVK_ANSI_LeftBracket), []),
        "]": (CGKeyCode(kVK_ANSI_RightBracket), []),
        "\\": (CGKeyCode(kVK_ANSI_Backslash), []),
        "Back": (CGKeyCode(kVK_Delete), []),
        "H": (CGKeyCode(kVK_ANSI_H), []),
        "J": (CGKeyCode(kVK_ANSI_J), []),
        "K": (CGKeyCode(kVK_ANSI_K), []),
        "L": (CGKeyCode(kVK_ANSI_L), []),
        ";": (CGKeyCode(kVK_ANSI_Semicolon), []),
        "'": (CGKeyCode(kVK_ANSI_Quote), []),
        "Ret": (CGKeyCode(kVK_Return), []),
        "N": (CGKeyCode(kVK_ANSI_N), []),
        "M": (CGKeyCode(kVK_ANSI_M), []),
        ",": (CGKeyCode(kVK_ANSI_Comma), []),
        ".": (CGKeyCode(kVK_ANSI_Period), []),
        "/": (CGKeyCode(kVK_ANSI_Slash), []),
        "!": (CGKeyCode(kVK_ANSI_1), .maskShift),
        "@": (CGKeyCode(kVK_ANSI_2), .maskShift),
        "#": (CGKeyCode(kVK_ANSI_3), .maskShift),
        "$": (CGKeyCode(kVK_ANSI_4), .maskShift),
        "%": (CGKeyCode(kVK_ANSI_5), .maskShift),
        "^": (CGKeyCode(kVK_ANSI_6), .maskShift),
        "&": (CGKeyCode(kVK_ANSI_7), .maskShift),
        "*": (CGKeyCode(kVK_ANSI_8), .maskShift),
        "(": (CGKeyCode(kVK_ANSI_9), .maskShift),
        ")": (CGKeyCode(kVK_ANSI_0), .maskShift),
        "_": (CGKeyCode(kVK_ANSI_Minus), .maskShift),
        "+": (CGKeyCode(kVK_ANSI_Equal), .maskShift),
        "{": (CGKeyCode(kVK_ANSI_LeftBracket), .maskShift),
        "}": (CGKeyCode(kVK_ANSI_RightBracket), .maskShift),
        "|": (CGKeyCode(kVK_ANSI_Backslash), .maskShift),
        ":": (CGKeyCode(kVK_ANSI_Semicolon), .maskShift),
        "\"": (CGKeyCode(kVK_ANSI_Quote), .maskShift),
        "<": (CGKeyCode(kVK_ANSI_Comma), .maskShift),
        ">": (CGKeyCode(kVK_ANSI_Period), .maskShift),
        "?": (CGKeyCode(kVK_ANSI_Slash), .maskShift),
        "~": (CGKeyCode(kVK_ANSI_Grave), .maskShift),
        "Space": (CGKeyCode(kVK_Space), [])
    ]

    private struct ActionIdentifier: Hashable {
        let keyCode: UInt16
        let flags: UInt64
    }

    private static let duplicateLabelOverrides: [String: String] = [
        "Escape": "Esc",
        "Return": "Ret"
    ]

    private static func uniqueActions(from entries: [String: (CGKeyCode, CGEventFlags)]) -> [KeyAction] {
        var actionsById: [ActionIdentifier: KeyAction] = [:]
        for label in entries.keys.sorted() {
            guard let binding = entries[label] else { continue }
            let identifier = ActionIdentifier(
                keyCode: UInt16(binding.0),
                flags: binding.1.rawValue
            )
            guard actionsById[identifier] == nil else { continue }
            let displayLabel = duplicateLabelOverrides[label] ?? label
            actionsById[identifier] = KeyAction(
                label: displayLabel,
                keyCode: identifier.keyCode,
                flags: identifier.flags
            )
        }
        return actionsById.values.sorted { $0.label < $1.label }
    }

    static let holdLabelOverridesByLabel: [String: String] = [
        "Q": "[",
        "W": "]",
        "E": "{",
        "R": "}",
        "T": "'",
        "Y": "-",
        "U": "&",
        "I": "*",
        "O": "Cmd+F",
        "P": "Cmd+R",
        "A": "Cmd+A",
        "S": "Cmd+S",
        "D": "(",
        "F": ")",
        "G": "\"",
        "H": "_",
        "J": "!",
        "K": "#",
        "L": "~",
        "Z": "Cmd+Z",
        "X": "Cmd+X",
        "C": "Cmd+C",
        "V": "Cmd+V",
        "N": "=",
        "M": "@",
        ",": "$",
        ".": "^",
        "/": "\\"
    ]

    static let presets: [KeyAction] = {
        var items = uniqueActions(from: bindingsByLabel)
        items.append(KeyAction(
            label: typingToggleLabel,
            keyCode: 0,
            flags: 0,
            kind: .typingToggle
        ))
        items.append(contentsOf: layerActions)
        return items.sorted { $0.label < $1.label }
    }()

    static let holdPresets: [KeyAction] = {
        var actions = uniqueActions(from: bindingsByLabel)
        var identifiers = Set(actions.map { ActionIdentifier(keyCode: $0.keyCode, flags: $0.flags) })
        for (label, binding) in holdBindingsByLabel {
            let identifier = ActionIdentifier(
                keyCode: UInt16(binding.0),
                flags: binding.1.rawValue
            )
            guard !identifiers.contains(identifier) else { continue }
            let holdLabel = holdLabelOverridesByLabel[label] ?? "Hold \(label)"
            actions.append(KeyAction(
                label: holdLabel,
                keyCode: identifier.keyCode,
                flags: identifier.flags
            ))
            identifiers.insert(identifier)
        }
        actions.append(KeyAction(
            label: typingToggleLabel,
            keyCode: 0,
            flags: 0,
            kind: .typingToggle
        ))
        actions.append(contentsOf: layerActions)
        return actions.sorted { $0.label < $1.label }
    }()

    static func action(for label: String) -> KeyAction? {
        if label == noneLabel {
            return noneAction
        }
        if label == typingToggleLabel || label == legacyTypingToggleLabel {
            return KeyAction(
                label: typingToggleLabel,
                keyCode: 0,
                flags: 0,
                kind: .typingToggle
            )
        }
        if label == momentaryLayer1Label {
            return KeyAction(
                label: momentaryLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerMomentary,
                layer: 1
            )
        }
        if label == toggleLayer1Label {
            return KeyAction(
                label: toggleLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerToggle,
                layer: 1
            )
        }
        guard let binding = bindingsByLabel[label] else { return nil }
        return KeyAction(
            label: label,
            keyCode: UInt16(binding.0),
            flags: binding.1.rawValue
        )
    }
    static func holdAction(for label: String) -> KeyAction? {
        guard let binding = holdBindingsByLabel[label] else { return nil }
        if let preset = action(
            forCode: UInt16(binding.0),
            flags: binding.1
        ) {
            return preset
        }
        let holdLabel = holdLabelOverridesByLabel[label] ?? "Hold \(label)"
        return KeyAction(
            label: holdLabel,
            keyCode: UInt16(binding.0),
            flags: binding.1.rawValue
        )
    }

    static func action(
        forCode keyCode: UInt16,
        flags: CGEventFlags
    ) -> KeyAction? {
        presets.first { $0.keyCode == keyCode && $0.flags == flags.rawValue }
    }

    private static var layerActions: [KeyAction] {
        [
            KeyAction(
                label: momentaryLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerMomentary,
                layer: 1
            ),
            KeyAction(
                label: toggleLayer1Label,
                keyCode: 0,
                flags: 0,
                kind: .layerToggle,
                layer: 1
            )
        ]
    }
}

enum KeyActionMappingStore {
    static func decode(_ data: Data) -> LayeredKeyMappings? {
        guard !data.isEmpty else { return nil }
        if let layered = try? JSONDecoder().decode(LayeredKeyMappings.self, from: data) {
            return layered
        }
        if let legacy = try? JSONDecoder().decode([String: KeyMapping].self, from: data) {
            return [0: legacy, 1: legacy]
        }
        return nil
    }

    static func encode(_ mappings: LayeredKeyMappings) -> Data? {
        guard !mappings.isEmpty else { return nil }
        do {
            return try JSONEncoder().encode(mappings)
        } catch {
            return nil
        }
    }
}
