//
//  ContentViewModel.swift
//  OMSDemo
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import Carbon
import OpenMultitouchSupport
import SwiftUI

@MainActor
final class ContentViewModel: ObservableObject {
    struct KeyBinding: Sendable {
        let rect: CGRect
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    static let gridLabels: [[String]] = [
        ["Y", "U", "I", "O", "P", "["],
        ["H", "J", "K", "L", ";", "'"],
        ["N", "M", ",", ".", "/", "?"]
    ]
    static let leftDeviceKey = "LEFT_DEVICE_ID"
    static let rightDeviceKey = "RIGHT_DEVICE_ID"

    @Published var touchData = [OMSTouchData]()
    @Published var isListening: Bool = false
    @Published var availableDevices = [OMSDeviceInfo]()
    @Published var leftDevice: OMSDeviceInfo?
    @Published var rightDevice: OMSDeviceInfo?
    @Published var isHapticEnabled: Bool = false

    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?
    private var hapticStateBeforeHover: Bool = true
    private var isCurrentlyHovering: Bool = false
    private var safetyTimer: Timer?
    private struct TouchKey: Hashable {
        let deviceID: String
        let id: Int32
    }

    private var activeTouches: [TouchKey: ActiveTouch] = [:]
    private let tapMaxDuration: TimeInterval = 0.25

    init() {
        loadDevices()
    }

    var leftTouches: [OMSTouchData] {
        guard let deviceID = leftDevice?.deviceID else { return [] }
        return touchData.filter { $0.deviceID == deviceID }
    }

    var rightTouches: [OMSTouchData] {
        guard let deviceID = rightDevice?.deviceID else { return [] }
        return touchData.filter { $0.deviceID == deviceID }
    }

    func onAppear() {
        task = Task { [weak self, manager] in
            for await touchData in manager.touchDataStream {
                await MainActor.run {
                    self?.touchData = touchData
                }
            }
        }
        
        // Start safety timer to periodically check haptic state
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHapticStatus()
            }
        }
    }

    func onDisappear() {
        task?.cancel()
        safetyTimer?.invalidate()
        safetyTimer = nil
        stop()
        
        // Safety: Ensure haptics are restored when view disappears
        ensureHapticsSafe()
    }
    
    deinit {
        // Final safety check: Ensure haptics are enabled during cleanup
        if !manager.isHapticEnabled {
            print("⚠️ Restoring haptics during ViewModel cleanup")
            manager.setHapticEnabled(true)
        }
    }

    func start() {
        if manager.startListening() {
            isListening = true
        }
    }

    func stop() {
        if manager.stopListening() {
            isListening = false
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
        updateHapticStatus()
    }
    
    func selectLeftDevice(_ device: OMSDeviceInfo) {
        leftDevice = device
        updateActiveDevices()
        updateHapticStatus()
    }

    func selectRightDevice(_ device: OMSDeviceInfo) {
        rightDevice = device
        updateActiveDevices()
    }

    private func updateActiveDevices() {
        let devices = [leftDevice, rightDevice].compactMap { $0 }
        guard !devices.isEmpty else { return }
        if manager.setActiveDevices(devices) {
            activeTouches.removeAll()
        }
    }
    
    func startHaptics() {
        if manager.setHapticEnabled(true) {
            isHapticEnabled = true
            // Update the hover state since user explicitly changed haptics
            hapticStateBeforeHover = true
        }
    }
    
    func stopHaptics() {
        if manager.setHapticEnabled(false) {
            isHapticEnabled = false
            // Update the hover state since user explicitly changed haptics
            hapticStateBeforeHover = false
        }
    }
    
    func updateHapticStatus() {
        isHapticEnabled = manager.isHapticEnabled
    }
    
    func onButtonHover() {
        // Only save the state when we first start hovering
        if !isCurrentlyHovering {
            hapticStateBeforeHover = manager.isHapticEnabled
            isCurrentlyHovering = true
            print("🎯 Starting hover - saving haptic state: \(hapticStateBeforeHover)")
        }
        
        if !manager.isHapticEnabled {
            print("🎯 Temporarily enabling haptics for button hover")
            manager.setHapticEnabled(true)
        }
    }
    
    func onButtonExitHover() {
        if isCurrentlyHovering {
            isCurrentlyHovering = false
            if !hapticStateBeforeHover {
                print("🎯 Restoring previous haptic state after hover: \(hapticStateBeforeHover)")
                manager.setHapticEnabled(false)
            } else {
                print("🎯 Keeping haptics enabled after hover")
            }
        }
    }
    
    func ensureHapticsSafe() {
        if !manager.isHapticEnabled {
            print("⚠️ Safety check: Restoring haptics to prevent trackpad issues")
            manager.setHapticEnabled(true)
            updateHapticStatus()
        }
    }
    
    // MARK: - Haptic Testing Functions
    
    private var lastHapticTime: Date = Date.distantPast
    private let hapticDebounceInterval: TimeInterval = 0.010 // 10 seconds debounce
    
    // MARK: - Raw Haptic Testing Properties
    @Published var customActuationID: String = "6"
    @Published var customUnknown1: String = "0"
    @Published var customUnknown2: String = "1.0"
    @Published var customUnknown3: String = "2.0"
    
    private func shouldTriggerHaptic() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastHapticTime) >= hapticDebounceInterval else {
            print("🚫 Haptic debounced - too soon since last trigger")
            return false
        }
        lastHapticTime = now
        return true
    }
    
    func triggerRawHaptic() {
        guard shouldTriggerHaptic() else { return }
        
        guard let actuationID = Int32(customActuationID),
              let unknown1 = UInt32(customUnknown1),
              let unknown2 = Float(customUnknown2),
              let unknown3 = Float(customUnknown3) else {
            print("❌ Invalid haptic parameters")
            return
        }
        
        print("🎯 Raw Haptic - ID: \(actuationID), Unknown1: \(unknown1), Unknown2: \(unknown2), Unknown3: \(unknown3)")
        
        let result = manager.triggerRawHaptic(
            actuationID: actuationID,
            unknown1: unknown1,
            unknown2: unknown2,
            unknown3: unknown3
        )
        
        print("🎯 Raw haptic result: \(result)")
    }

    // MARK: - Key Tap Handling
    private struct ActiveTouch {
        let binding: KeyBinding
        let startTime: Date
    }

    func processTouches(
        _ touches: [OMSTouchData],
        keyRects: [[CGRect]],
        thumbRects: [CGRect],
        canvasSize: CGSize
    ) {
        guard isListening else { return }
        let bindings = makeBindings(keyRects: keyRects, thumbRects: thumbRects)

        for touch in touches {
            let point = CGPoint(
                x: CGFloat(touch.position.x) * canvasSize.width,
                y: CGFloat(1.0 - touch.position.y) * canvasSize.height
            )
            let touchKey = TouchKey(deviceID: touch.deviceID, id: touch.id)
            switch touch.state {
            case .starting, .making, .touching:
                if activeTouches[touchKey] == nil,
                   let binding = binding(at: point, bindings: bindings) {
                    activeTouches[touchKey] = ActiveTouch(binding: binding, startTime: Date())
                }
            case .breaking, .leaving:
                if let active = activeTouches.removeValue(forKey: touchKey),
                   Date().timeIntervalSince(active.startTime) <= tapMaxDuration {
                    sendKey(binding: active.binding)
                }
            case .notTouching:
                activeTouches.removeValue(forKey: touchKey)
            case .hovering, .lingering:
                break
            }
        }
    }

    private func makeBindings(keyRects: [[CGRect]], thumbRects: [CGRect]) -> [KeyBinding] {
        var bindings: [KeyBinding] = []
        for row in 0..<keyRects.count {
            for col in 0..<keyRects[row].count {
                guard row < Self.gridLabels.count,
                      col < Self.gridLabels[row].count else { continue }
                let label = Self.gridLabels[row][col]
                guard let binding = bindingForLabel(label, rect: keyRects[row][col]) else { continue }
                bindings.append(binding)
            }
        }

        let thumbKeys: [(CGKeyCode, CGEventFlags)] = [
            (CGKeyCode(kVK_Space), []),
            (CGKeyCode(kVK_Return), []),
            (CGKeyCode(kVK_Delete), [])
        ]
        for (index, rect) in thumbRects.enumerated() {
            guard index < thumbKeys.count else { continue }
            let (code, flags) = thumbKeys[index]
            bindings.append(KeyBinding(rect: rect, keyCode: code, flags: flags))
        }

        return bindings
    }

    private func bindingForLabel(_ label: String, rect: CGRect) -> KeyBinding? {
        let map: [String: (CGKeyCode, CGEventFlags)] = [
            "Y": (CGKeyCode(kVK_ANSI_Y), []),
            "U": (CGKeyCode(kVK_ANSI_U), []),
            "I": (CGKeyCode(kVK_ANSI_I), []),
            "O": (CGKeyCode(kVK_ANSI_O), []),
            "P": (CGKeyCode(kVK_ANSI_P), []),
            "[": (CGKeyCode(kVK_ANSI_LeftBracket), []),
            "H": (CGKeyCode(kVK_ANSI_H), []),
            "J": (CGKeyCode(kVK_ANSI_J), []),
            "K": (CGKeyCode(kVK_ANSI_K), []),
            "L": (CGKeyCode(kVK_ANSI_L), []),
            ";": (CGKeyCode(kVK_ANSI_Semicolon), []),
            "'": (CGKeyCode(kVK_ANSI_Quote), []),
            "N": (CGKeyCode(kVK_ANSI_N), []),
            "M": (CGKeyCode(kVK_ANSI_M), []),
            ",": (CGKeyCode(kVK_ANSI_Comma), []),
            ".": (CGKeyCode(kVK_ANSI_Period), []),
            "/": (CGKeyCode(kVK_ANSI_Slash), []),
            "?": (CGKeyCode(kVK_ANSI_Slash), .maskShift)
        ]
        guard let (code, flags) = map[label] else { return nil }
        return KeyBinding(rect: rect, keyCode: code, flags: flags)
    }

    private func binding(at point: CGPoint, bindings: [KeyBinding]) -> KeyBinding? {
        bindings.first { $0.rect.contains(point) }
    }

    private func sendKey(binding: KeyBinding) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: binding.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: binding.keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = binding.flags
        keyUp.flags = binding.flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
