/*
 OMSManager.swift

 Created by Takuto Nakamura on 2024/03/02.
*/

@preconcurrency import OpenMultitouchSupportXCF
import os

public struct OMSDeviceInfo: Sendable, Hashable {
    public let deviceName: String
    public let deviceID: String
    public let isBuiltIn: Bool
    internal nonisolated(unsafe) let deviceInfo: OpenMTDeviceInfo
    
    internal init(_ deviceInfo: OpenMTDeviceInfo) {
        self.deviceInfo = deviceInfo
        self.deviceName = deviceInfo.deviceName
        self.deviceID = deviceInfo.deviceID
        self.isBuiltIn = deviceInfo.isBuiltIn
    }
}

public enum OMSHapticIntensity: Int32, CaseIterable, Sendable {
    case weak = 3
    case medium = 4
    case strong = 6
}

public enum OMSHapticPattern: Int32, CaseIterable, Sendable {
    case generic = 15
    case alignment = 16
    case level = 5  // Changed from 17 to 5 (valid ID)
}

public final class OMSManager: Sendable {
    public static let shared = OMSManager()

    private let protectedManager: OSAllocatedUnfairLock<OpenMTManager?>
    private let protectedListener = OSAllocatedUnfairLock<OpenMTListener?>(uncheckedState: nil)
    private let protectedTimestampEnabled = OSAllocatedUnfairLock<Bool>(uncheckedState: true)
    private let protectedDeviceIndexStore = OSAllocatedUnfairLock<DeviceIndexStore>(
        uncheckedState: DeviceIndexStore()
    )
    private let touchContinuations = OSAllocatedUnfairLock<[UUID: AsyncStream<[OMSTouchData]>.Continuation]>(
        uncheckedState: [:]
    )
#if DEBUG
    private let signposter = OSSignposter(
        subsystem: "com.kyome.GlassToKey",
        category: "OpenMT"
    )
#endif
    public var touchDataStream: AsyncStream<[OMSTouchData]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let id = UUID()
            touchContinuations.withLockUnchecked { $0[id] = continuation }
            continuation.onTermination = { [touchContinuations] _ in
                touchContinuations.withLockUnchecked { continuations in
                    continuations.removeValue(forKey: id)
                    return ()
                }
            }
        }
    }

    public var isListening: Bool {
        protectedListener.withLockUnchecked { $0 != nil }
    }

    public var isTimestampEnabled: Bool {
        get { protectedTimestampEnabled.withLockUnchecked(\.self) }
        set { protectedTimestampEnabled.withLockUnchecked { $0 = newValue } }
    }
    
    public var availableDevices: [OMSDeviceInfo] {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return [] }
        xcfManager.refreshAvailableDevices()
        return xcfManager.availableDevices().map { OMSDeviceInfo($0) }
    }
    
    public var activeDevices: [OMSDeviceInfo] {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return [] }
        return xcfManager.activeDevices().map { OMSDeviceInfo($0) }
    }

    private init() {
        protectedManager = .init(uncheckedState: OpenMTManager.shared())
    }

    @discardableResult
    public func startListening() -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self),
              protectedListener.withLockUnchecked({ $0 == nil }) else {
            return false
        }
        let listener = xcfManager.addListener(
            withTarget: self,
            selector: #selector(listen)
        )
        protectedListener.withLockUnchecked { $0 = listener }
        return true
    }

    @discardableResult
    public func stopListening() -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self),
              let listener = protectedListener.withLockUnchecked(\.self) else {
            return false
        }
        xcfManager.remove(listener)
        protectedListener.withLockUnchecked { $0 = nil }
        return true
    }
    
    @discardableResult
    public func setActiveDevices(_ devices: [OMSDeviceInfo]) -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        let deviceInfos = devices.map { $0.deviceInfo }
        return xcfManager.setActiveDevices(deviceInfos)
    }
    
    public var isHapticEnabled: Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.isHapticEnabled()
    }
    
    @discardableResult
    public func setHapticEnabled(_ enabled: Bool) -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.setHapticEnabled(enabled)
    }
    
    @discardableResult
    public func triggerRawHaptic(actuationID: Int32, unknown1: UInt32, unknown2: Float, unknown3: Float, deviceID: String? = nil) -> Bool {
        guard let xcfManager = protectedManager.withLockUnchecked(\.self) else { return false }
        return xcfManager.triggerRawHaptic(actuationID, unknown1: unknown1, unknown2: unknown2, unknown3: unknown3, deviceID: deviceID)
    }

    @discardableResult
    public func playHapticFeedback(strength: Double, deviceID: String? = nil) -> Bool {
        let clampedStrength = min(max(strength, 0.0), 1.0)
        guard clampedStrength > 0 else {
            return false
        }
        let actuationStep = Int(max(0, min(5, Int(round(clampedStrength * 5.0)))))
        let actuationID = Int32(1 + actuationStep) // falls in 1..6
        let sharpness = Float(10.0 + (clampedStrength * 20.0))
        return triggerRawHaptic(actuationID: actuationID, unknown1: 0, unknown2: sharpness, unknown3: 0, deviceID: deviceID)
    }

    public func deviceIndex(for deviceID: String) -> Int? {
        guard !deviceID.isEmpty else { return nil }
        return resolveDeviceIndex(for: deviceID)
    }

    @objc func listen(_ event: OpenMTEvent) {
#if DEBUG
        let signpostState = signposter.beginInterval("OpenMTEvent")
        defer { signposter.endInterval("OpenMTEvent", signpostState) }
#endif
        guard let touches = (event.touches as NSArray) as? [OpenMTTouch] else { return }
        if touches.isEmpty {
            emitTouchData([])
        } else {
            let frameTimestamp = event.timestamp
            let formattedTimestamp = protectedTimestampEnabled.withLockUnchecked(\.self)
                ? String(format: "%.5f", frameTimestamp)
                : nil
            let deviceID = event.deviceID ?? "Unknown"
            let deviceIndex = resolveDeviceIndex(for: deviceID)
            var data: [OMSTouchData] = []
            data.reserveCapacity(touches.count)
            for touch in touches {
                guard let state = OMSState(touch.state) else { continue }
                data.append(OMSTouchData(
                    deviceID: deviceID,
                    deviceIndex: deviceIndex,
                    id: touch.identifier,
                    position: OMSPosition(x: touch.posX, y: touch.posY),
                    total: touch.total,
                    pressure: touch.pressure,
                    axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                    angle: touch.angle,
                    density: touch.density,
                    state: state,
                    timestamp: frameTimestamp,
                    formattedTimestamp: formattedTimestamp
                ))
            }
            emitTouchData(data)
        }
    }

    private func emitTouchData(_ data: [OMSTouchData]) {
        let continuations = touchContinuations.withLockUnchecked { Array($0.values) }
        for continuation in continuations {
            _ = continuation.yield(data)
        }
    }

    private func resolveDeviceIndex(for deviceID: String) -> Int {
        protectedDeviceIndexStore.withLockUnchecked { store in
            if let existing = store.indexByID[deviceID] {
                return existing
            }
            let assigned = store.nextIndex
            store.nextIndex += 1
            store.indexByID[deviceID] = assigned
            return assigned
        }
    }
}

private struct DeviceIndexStore: Sendable {
    var nextIndex: Int = 0
    var indexByID: [String: Int] = [:]
}
