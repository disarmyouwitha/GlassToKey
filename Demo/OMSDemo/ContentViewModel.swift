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

    static let leftGridLabels: [[String]] = [
        ["Tab", "Q", "W", "E", "R", "T"],
        ["Option", "A", "S", "D", "F", "G"],
        ["Shift", "Z", "X", "C", "V", "B"]
    ]
    static let rightGridLabels: [[String]] = [
        ["Y", "U", "I", "O", "P", "Back"],
        ["H", "J", "K", "L", ";", "Ret"],
        ["N", "M", ",", ".", "/", "?"]
    ]
    @Published var touchData = [OMSTouchData]()
    @Published var isListening: Bool = false
    @Published var availableDevices = [OMSDeviceInfo]()
    @Published var leftDevice: OMSDeviceInfo?
    @Published var rightDevice: OMSDeviceInfo?

    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?
    private struct TouchKey: Hashable {
        let deviceID: String
        let id: Int32
    }
    private let leftThumbKeys: [(CGKeyCode, CGEventFlags)] = [
        (CGKeyCode(kVK_Delete), []),
        (CGKeyCode(kVK_Delete), []),
        (CGKeyCode(kVK_Delete), [])
    ]
    private let rightThumbKeys: [(CGKeyCode, CGEventFlags)] = [
        (CGKeyCode(kVK_Space), []),
        (CGKeyCode(kVK_Space), []),
        (CGKeyCode(kVK_Space), [])
    ]

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

    private func updateActiveDevices() {
        let devices = [leftDevice, rightDevice].compactMap { $0 }
        guard !devices.isEmpty else { return }
        if manager.setActiveDevices(devices) {
            activeTouches.removeAll()
        }
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
        canvasSize: CGSize,
        labels: [[String]],
        isLeftSide: Bool
    ) {
        guard isListening else { return }
        let bindings = makeBindings(
            keyRects: keyRects,
            thumbRects: thumbRects,
            labels: labels,
            thumbKeys: isLeftSide ? leftThumbKeys : rightThumbKeys
        )

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

    private func makeBindings(
        keyRects: [[CGRect]],
        thumbRects: [CGRect],
        labels: [[String]],
        thumbKeys: [(CGKeyCode, CGEventFlags)]
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

        for (index, rect) in thumbRects.enumerated() {
            guard index < thumbKeys.count else { continue }
            let (code, flags) = thumbKeys[index]
            bindings.append(KeyBinding(rect: rect, keyCode: code, flags: flags))
        }

        return bindings
    }

    private func bindingForLabel(_ label: String, rect: CGRect) -> KeyBinding? {
        let map: [String: (CGKeyCode, CGEventFlags)] = [
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
            "H": (CGKeyCode(kVK_ANSI_H), []),
            "J": (CGKeyCode(kVK_ANSI_J), []),
            "K": (CGKeyCode(kVK_ANSI_K), []),
            "L": (CGKeyCode(kVK_ANSI_L), []),
            ";": (CGKeyCode(kVK_ANSI_Semicolon), []),
            "Ret": (CGKeyCode(kVK_Return), []),
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
