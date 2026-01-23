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
    private let rawTouchContinuations = OSAllocatedUnfairLock<[UUID: AsyncStream<OMSRawTouchFrame>.Continuation]>(
        uncheckedState: [:]
    )
    private let rawBufferPool = OSAllocatedUnfairLock<[RawTouchBuffer]>(uncheckedState: [])
#if DEBUG
    private let signposter = OSSignposter(
        subsystem: "com.kyome.GlassToKey",
        category: "OpenMT"
    )
#endif
    public var touchDataStream: AsyncStream<[OMSTouchData]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let task = Task.detached(priority: .userInitiated) { [rawTouchStream] in
                for await frame in rawTouchStream {
                    let data = Self.buildTouchData(from: frame)
                    continuation.yield(data)
                    frame.release()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public var rawTouchStream: AsyncStream<OMSRawTouchFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            let id = UUID()
            rawTouchContinuations.withLockUnchecked { $0[id] = continuation }
            continuation.onTermination = { [rawTouchContinuations] _ in
                rawTouchContinuations.withLockUnchecked { continuations in
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
        let frameTimestamp = event.timestamp
        let deviceID = event.deviceID ?? "Unknown"
        let deviceIndex = resolveDeviceIndex(for: deviceID)
        if touches.isEmpty {
            emitRawTouchFrame(
                OMSRawTouchFrame(
                    deviceID: deviceID,
                    deviceIndex: deviceIndex,
                    timestamp: frameTimestamp,
                    buffer: nil,
                    releaseHandler: nil
                )
            )
            return
        }
        let buffer = takeBuffer(capacity: touches.count)
        buffer.touches.reserveCapacity(touches.count)
        for touch in touches {
            buffer.touches.append(OMSRawTouch(
                id: touch.identifier,
                posX: touch.posX,
                posY: touch.posY,
                total: touch.total,
                pressure: touch.pressure,
                majorAxis: touch.majorAxis,
                minorAxis: touch.minorAxis,
                angle: touch.angle,
                density: touch.density,
                state: touch.state
            ))
        }
        let frame = OMSRawTouchFrame(
            deviceID: deviceID,
            deviceIndex: deviceIndex,
            timestamp: frameTimestamp,
            buffer: buffer,
            releaseHandler: { [rawBufferPool] buffer in
                rawBufferPool.withLockUnchecked { pool in
                    pool.append(buffer)
                    return ()
                }
            }
        )
        emitRawTouchFrame(frame)
    }

    private func emitTouchData(_ data: [OMSTouchData]) {
        let continuations = touchContinuations.withLockUnchecked { Array($0.values) }
        for continuation in continuations {
            _ = continuation.yield(data)
        }
    }

    private func emitRawTouchFrame(_ frame: OMSRawTouchFrame) {
        let continuations = rawTouchContinuations.withLockUnchecked { Array($0.values) }
        for continuation in continuations {
            _ = continuation.yield(frame)
        }
        if continuations.isEmpty {
            frame.release()
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

    private func takeBuffer(capacity: Int) -> RawTouchBuffer {
        rawBufferPool.withLockUnchecked { pool in
            if let buffer = pool.popLast() {
                buffer.touches.removeAll(keepingCapacity: true)
                if buffer.touches.capacity < capacity {
                    buffer.touches.reserveCapacity(capacity)
                }
                return buffer
            }
            return RawTouchBuffer(capacity: max(8, capacity))
        }
    }

    public static func buildTouchData(from frame: OMSRawTouchFrame) -> [OMSTouchData] {
        let formattedTimestamp = shared.protectedTimestampEnabled.withLockUnchecked(\.self)
            ? String(format: "%.5f", frame.timestamp)
            : nil
        let deviceID = frame.deviceID
        let deviceIndex = frame.deviceIndex
        var data: [OMSTouchData] = []
        let touches = frame.touches
        if touches.isEmpty {
            return data
        }
        data.reserveCapacity(touches.count)
        for touch in touches {
            guard let state = OMSState(touch.state) else { continue }
            data.append(OMSTouchData(
                deviceID: deviceID,
                deviceIndex: deviceIndex,
                id: touch.id,
                position: OMSPosition(x: touch.posX, y: touch.posY),
                total: touch.total,
                pressure: touch.pressure,
                axis: OMSAxis(major: touch.majorAxis, minor: touch.minorAxis),
                angle: touch.angle,
                density: touch.density,
                state: state,
                timestamp: frame.timestamp,
                formattedTimestamp: formattedTimestamp
            ))
        }
        return data
    }
}

private struct DeviceIndexStore: Sendable {
    var nextIndex: Int = 0
    var indexByID: [String: Int] = [:]
}

public struct OMSRawTouch: Sendable {
    public let id: Int32
    public let posX: Float
    public let posY: Float
    public let total: Float
    public let pressure: Float
    public let majorAxis: Float
    public let minorAxis: Float
    public let angle: Float
    public let density: Float
    public let state: OpenMTState
}

public final class OMSRawTouchFrame: @unchecked Sendable {
    public let deviceID: String
    public let deviceIndex: Int
    public let timestamp: TimeInterval
    private var buffer: RawTouchBuffer?
    private let releaseHandler: ((RawTouchBuffer) -> Void)?

    public var touches: [OMSRawTouch] {
        buffer?.touches ?? []
    }

    fileprivate init(
        deviceID: String,
        deviceIndex: Int,
        timestamp: TimeInterval,
        buffer: RawTouchBuffer?,
        releaseHandler: ((RawTouchBuffer) -> Void)?
    ) {
        self.deviceID = deviceID
        self.deviceIndex = deviceIndex
        self.timestamp = timestamp
        self.buffer = buffer
        self.releaseHandler = releaseHandler
    }

    public func release() {
        guard let buffer else { return }
        self.buffer = nil
        releaseHandler?(buffer)
    }

    deinit {
        release()
    }
}

private final class RawTouchBuffer {
    var touches: [OMSRawTouch]

    init(capacity: Int) {
        touches = []
        touches.reserveCapacity(capacity)
    }
}
