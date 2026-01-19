//
//  ContentViewModel.swift
//  GlassToKey
//
//  Created by Takuto Nakamura on 2024/03/02.
//

import Carbon
import CoreGraphics
import OpenMultitouchSupport
import QuartzCore
import SwiftUI
import os

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
        let side: TrackpadSide
        let holdAction: KeyAction?
    }

    struct Layout {
        let keyRects: [[CGRect]]
    }

    struct TouchSnapshot: Sendable {
        var data: [OMSTouchData] = []
        var left: [OMSTouchData] = []
        var right: [OMSTouchData] = []
        var revision: UInt64 = 0
    }

    struct TouchFrame: Sendable {
        let data: [OMSTouchData]
        let left: [OMSTouchData]
        let right: [OMSTouchData]
    }

    private struct DeviceSelection: Sendable {
        var leftIndex: Int?
        var rightIndex: Int?
    }

    nonisolated private let touchSnapshotLock = OSAllocatedUnfairLock<TouchSnapshot>(
        uncheckedState: TouchSnapshot()
    )
    private struct PendingTouchState {
        var left: [OMSTouchData] = []
        var right: [OMSTouchData] = []
        var leftDirty = false
        var rightDirty = false
        var lastLeftUpdateTime: TimeInterval = 0
        var lastRightUpdateTime: TimeInterval = 0
    }
    private struct PendingTouchSnapshot {
        let left: [OMSTouchData]
        let right: [OMSTouchData]
    }
    nonisolated private let pendingTouchLock = OSAllocatedUnfairLock<PendingTouchState>(
        uncheckedState: PendingTouchState()
    )
    private let touchCoalesceInterval: TimeInterval = 0.02
    nonisolated private let deviceSelectionLock = OSAllocatedUnfairLock<DeviceSelection>(
        uncheckedState: DeviceSelection()
    )
    nonisolated private let snapshotRecordingLock = OSAllocatedUnfairLock<Bool>(
        uncheckedState: true
    )
    final class ContinuationHolder: @unchecked Sendable {
        var continuation: AsyncStream<UInt64>.Continuation?
    }
    nonisolated let touchRevisionUpdates: AsyncStream<UInt64>
    nonisolated private let touchRevisionContinuationHolder: ContinuationHolder
    @Published var isListening: Bool = false
    @Published var isTypingEnabled: Bool = true
    @Published private(set) var activeLayer: Int = 0
    private let isDragDetectionEnabled = true
    @Published var availableDevices = [OMSDeviceInfo]()
    @Published var leftDevice: OMSDeviceInfo?
    @Published var rightDevice: OMSDeviceInfo?
    @Published private(set) var hasDisconnectedTrackpads = false
    struct DebugHit: Equatable {
        let rect: CGRect
        let label: String
        let side: TrackpadSide
        let timestamp: TimeInterval
    }

    @Published private(set) var debugLastHitLeft: DebugHit?
    @Published private(set) var debugLastHitRight: DebugHit?

    private var requestedLeftDeviceID: String?
    private var requestedRightDeviceID: String?
    private var autoResyncTask: Task<Void, Never>?
    private var autoResyncEnabled = false
    private static let connectedResyncIntervalSeconds: TimeInterval = 10.0
    private static let disconnectedResyncIntervalSeconds: TimeInterval = 1.0
    private static let connectedResyncIntervalNanoseconds = UInt64(connectedResyncIntervalSeconds * 1_000_000_000)
    private static let disconnectedResyncIntervalNanoseconds = UInt64(disconnectedResyncIntervalSeconds * 1_000_000_000)

    private let manager = OMSManager.shared
    private var task: Task<Void, Never>?
    private let processor: TouchProcessor

    init() {
        let holder = ContinuationHolder()
        touchRevisionContinuationHolder = holder
        touchRevisionUpdates = AsyncStream { continuation in
            holder.continuation = continuation
        }
        weak var weakSelf: ContentViewModel?
        let debugBindingHandler: @Sendable (KeyBinding) -> Void = { binding in
            Task { @MainActor in
                weakSelf?.recordDebugHit(binding)
            }
        }
        processor = TouchProcessor(
            keyDispatcher: KeyEventDispatcher.shared,
            onTypingEnabledChanged: { isEnabled in
                Task { @MainActor in
                    weakSelf?.isTypingEnabled = isEnabled
                }
            },
            onActiveLayerChanged: { layer in
                Task { @MainActor in
                    weakSelf?.activeLayer = layer
                }
            },
            onDebugBindingDetected: debugBindingHandler
        )
        weakSelf = self
        loadDevices()
    }

    var leftTouches: [OMSTouchData] {
        touchSnapshotLock.withLockUnchecked { $0.left }
    }

    var rightTouches: [OMSTouchData] {
        touchSnapshotLock.withLockUnchecked { $0.right }
    }

    private func recordDebugHit(_ binding: KeyBinding) {
        let hit = DebugHit(
            rect: binding.rect,
            label: binding.label,
            side: binding.side,
            timestamp: CACurrentMediaTime()
        )
        switch binding.side {
        case .left:
            debugLastHitLeft = hit
        case .right:
            debugLastHitRight = hit
        }
    }

    func onAppear() {
        let snapshotLock = touchSnapshotLock
        let selectionLock = deviceSelectionLock
        let recordingLock = snapshotRecordingLock
        task = Task.detached { [manager, processor, snapshotLock, selectionLock, recordingLock, self] in
            for await touchData in manager.touchDataStream {
                let selection = selectionLock.withLockUnchecked { $0 }
                let split = Self.splitTouches(touchData, selection: selection)
                let frame = TouchFrame(
                    data: touchData,
                    left: split.left,
                    right: split.right
                )
                let now = CACurrentMediaTime()
                let snapshotCandidate = updatePendingTouches(with: frame, at: now)
                var updatedRevision: UInt64?
                if let candidate = snapshotCandidate,
                   recordingLock.withLockUnchecked(\.self) {
                    snapshotLock.withLockUnchecked { snapshot in
                        snapshot.data = candidate.left + candidate.right
                        snapshot.left = candidate.left
                        snapshot.right = candidate.right
                        snapshot.revision &+= 1
                        updatedRevision = snapshot.revision
                    }
                }
                if let revision = updatedRevision {
                    touchRevisionContinuationHolder.continuation?.yield(revision)
                }
                await processor.processTouchFrame(frame)
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
            Task { [processor] in
                await processor.setListening(true)
            }
        }
    }

    func stop() {
        if manager.stopListening() {
            isListening = false
            Task { [processor] in
                await processor.setListening(false)
                await processor.resetState()
            }
        }
    }
    
    func loadDevices(preserveSelection: Bool = false) {
        let previousLeftDeviceID = preserveSelection ? requestedLeftDeviceID : nil
        let previousRightDeviceID = preserveSelection ? requestedRightDeviceID : nil
        availableDevices = manager.availableDevices

        if let matchingLeftID = previousLeftDeviceID,
           let matchingLeft = availableDevices.first(where: { $0.deviceID == matchingLeftID }) {
            leftDevice = matchingLeft
        } else if preserveSelection, previousLeftDeviceID != nil {
            leftDevice = nil
        } else if !preserveSelection {
            leftDevice = availableDevices.first
        } else {
            leftDevice = nil
        }

        let shouldFallbackRight = !preserveSelection || (preserveSelection && previousRightDeviceID != nil)
        if let matchingRightID = previousRightDeviceID,
           let matchingRight = availableDevices.first(where: { $0.deviceID == matchingRightID }) {
            rightDevice = matchingRight
        } else if shouldFallbackRight {
            rightDevice = availableDevices.first(where: { candidate in
                guard let leftID = leftDevice?.deviceID else { return true }
                return candidate.deviceID != leftID
            })
        } else {
            rightDevice = nil
        }

        if !preserveSelection {
            requestedLeftDeviceID = leftDevice?.deviceID
            requestedRightDeviceID = rightDevice?.deviceID
        }

        updateDisconnectedTrackpadState()
        updateActiveDevices()
    }
    
    func selectLeftDevice(_ device: OMSDeviceInfo?) {
        requestedLeftDeviceID = device?.deviceID
        leftDevice = device
        updateDisconnectedTrackpadState()
        updateActiveDevices()
    }

    func selectRightDevice(_ device: OMSDeviceInfo?) {
        requestedRightDeviceID = device?.deviceID
        rightDevice = device
        updateDisconnectedTrackpadState()
        updateActiveDevices()
    }

    private func updateDisconnectedTrackpadState() {
        let availableIDs = Set(availableDevices.map(\.deviceID))
        var hasMissing = false
        if let leftID = requestedLeftDeviceID,
           !leftID.isEmpty,
           !availableIDs.contains(leftID) {
            hasMissing = true
        }
        if let rightID = requestedRightDeviceID,
           !rightID.isEmpty,
           !availableIDs.contains(rightID) {
            hasMissing = true
        }
        if hasDisconnectedTrackpads != hasMissing {
            hasDisconnectedTrackpads = hasMissing
        }
    }

    func setAutoResyncEnabled(_ enabled: Bool) {
        guard autoResyncEnabled != enabled else { return }
        autoResyncEnabled = enabled
        autoResyncTask?.cancel()
        autoResyncTask = nil
        if enabled {
            loadDevices(preserveSelection: true)
            autoResyncTask = Task { [weak self] in
                guard let self = self else { return }
                await self.autoResyncLoop()
            }
        }
    }

    private func autoResyncLoop() async {
        while autoResyncEnabled {
            let interval = hasDisconnectedTrackpads
                ? Self.disconnectedResyncIntervalNanoseconds
                : Self.connectedResyncIntervalNanoseconds
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                break
            }
            guard autoResyncEnabled else { break }
            loadDevices(preserveSelection: true)
        }
    }

    func configureLayouts(
        leftLayout: Layout,
        rightLayout: Layout,
        leftLabels: [[String]],
        rightLabels: [[String]],
        trackpadSize: CGSize
    ) {
        Task { [processor] in
            await processor.updateLayouts(
                leftLayout: leftLayout,
                rightLayout: rightLayout,
                leftLabels: leftLabels,
                rightLabels: rightLabels,
                trackpadSize: trackpadSize
            )
        }
    }

    func updateCustomButtons(_ buttons: [CustomButton]) {
        Task { [processor] in
            await processor.updateCustomButtons(buttons)
        }
    }

    func updateKeyMappings(_ actions: LayeredKeyMappings) {
        Task { [processor] in
            await processor.updateKeyMappings(actions)
        }
    }

    func snapshotTouchData() -> TouchSnapshot {
        touchSnapshotLock.withLockUnchecked { $0 }
    }

    func snapshotTouchDataIfUpdated(
        since revision: UInt64
    ) -> TouchSnapshot? {
        touchSnapshotLock.withLockUnchecked { snapshot in
            guard snapshot.revision != revision else { return nil }
            return snapshot
        }
    }

    nonisolated private static func splitTouches(
        _ touches: [OMSTouchData],
        selection: DeviceSelection
    ) -> (left: [OMSTouchData], right: [OMSTouchData]) {
        var left: [OMSTouchData] = []
        var right: [OMSTouchData] = []
        left.reserveCapacity(touches.count / 2)
        right.reserveCapacity(touches.count / 2)
        for touch in touches {
            if let leftIndex = selection.leftIndex,
               touch.deviceIndex == leftIndex {
                left.append(touch)
            } else if let rightIndex = selection.rightIndex,
                      touch.deviceIndex == rightIndex {
                right.append(touch)
            }
        }
        return (left, right)
    }

    nonisolated private func updatePendingTouches(
        with frame: TouchFrame,
        at now: TimeInterval
    ) -> PendingTouchSnapshot? {
        pendingTouchLock.withLockUnchecked { state in
            if frame.data.isEmpty {
                let hadPendingTouches = !state.left.isEmpty || !state.right.isEmpty
                if hadPendingTouches {
                    state.left.removeAll()
                    state.right.removeAll()
                    state.leftDirty = true
                    state.rightDirty = true
                    state.lastLeftUpdateTime = now
                    state.lastRightUpdateTime = now
                }
                if shouldEmitSnapshot(state: &state, at: now) {
                    return PendingTouchSnapshot(left: state.left, right: state.right)
                }
                return nil
            }

            var hasUpdates = false
            if !frame.left.isEmpty {
                state.left = frame.left
                state.leftDirty = true
                state.lastLeftUpdateTime = now
                hasUpdates = true
            }
            if !frame.right.isEmpty {
                state.right = frame.right
                state.rightDirty = true
                state.lastRightUpdateTime = now
                hasUpdates = true
            }

            if hasUpdates && shouldEmitSnapshot(state: &state, at: now) {
                return PendingTouchSnapshot(left: state.left, right: state.right)
            }
            return nil
        }
    }

    nonisolated private func shouldEmitSnapshot(
        state: inout PendingTouchState,
        at now: TimeInterval
    ) -> Bool {
        let leftStale = now - state.lastLeftUpdateTime >= touchCoalesceInterval
        let rightStale = now - state.lastRightUpdateTime >= touchCoalesceInterval
        if state.leftDirty && state.rightDirty {
            state.leftDirty = false
            state.rightDirty = false
            return true
        }
        if state.leftDirty && rightStale {
            state.leftDirty = false
            state.rightDirty = false
            return true
        }
        if state.rightDirty && leftStale {
            state.rightDirty = false
            state.leftDirty = false
            return true
        }
        return false
    }

    private func updateActiveDevices() {
        let devices = [leftDevice, rightDevice].compactMap { $0 }
        guard !devices.isEmpty else { return }
        if manager.setActiveDevices(devices) {
            Task { [processor] in
                await processor.resetState()
            }
        }
        let leftIndex = leftDevice.flatMap { manager.deviceIndex(for: $0.deviceID) }
        let rightIndex = rightDevice.flatMap { manager.deviceIndex(for: $0.deviceID) }
        deviceSelectionLock.withLockUnchecked { selection in
            selection.leftIndex = leftIndex
            selection.rightIndex = rightIndex
        }
        Task { [processor] in
            await processor.updateActiveDevices(leftIndex: leftIndex, rightIndex: rightIndex)
        }
    }
    func setPersistentLayer(_ layer: Int) {
        Task { [processor] in
            await processor.setPersistentLayer(layer)
        }
    }

    func updateHoldThreshold(_ seconds: TimeInterval) {
        Task { [processor] in
            await processor.updateHoldThreshold(seconds)
        }
    }

    func updateDragCancelDistance(_ distance: CGFloat) {
        Task { [processor] in
            await processor.updateDragCancelDistance(distance)
        }
    }

    func updateTwoFingerTapInterval(_ seconds: TimeInterval) {
        Task { [processor] in
            await processor.updateTwoFingerTapInterval(seconds)
        }
    }

    func updateTwoFingerSuppressionDuration(_ seconds: TimeInterval) {
        Task { [processor] in
            await processor.updateTwoFingerSuppressionDuration(seconds)
        }
    }

    func updateForceClickCap(_ grams: Double) {
        Task { [processor] in
            await processor.updateForceClickCap(grams)
        }
    }

    func clearTouchState() {
        Task { [processor] in
            await processor.resetState()
        }
    }

    func clearVisualCaches() {
        Task { [processor] in
            await processor.clearVisualCaches()
        }
    }

    func setTouchSnapshotRecordingEnabled(_ enabled: Bool) {
        snapshotRecordingLock.withLockUnchecked { $0 = enabled }
        if !enabled {
            touchSnapshotLock.withLockUnchecked { $0 = TouchSnapshot() }
        }
    }

    deinit {
        autoResyncTask?.cancel()
    }

    private actor TouchProcessor {
        private enum ModifierKey {
            case shift
            case control
            case option
            case command
        }

        private enum DisqualifyReason: String {
            case dragCancelled
            case pendingDragCancelled
            case leftContinuousRect
            case pendingLeftRect
            case twoFingerSuppressed
            case typingDisabled
            case forceCapExceeded
        }

        private enum DispatchKind: String {
            case tap
            case hold
            case continuous
        }

        private struct DispatchInfo {
            let kind: DispatchKind
            let durationMs: Int?
            let maxDistance: CGFloat?
        }

        private struct TouchKey: Hashable {
            let deviceIndex: Int
            let id: Int32
        }

        private struct ActiveTouch {
            let binding: KeyBinding
            let startTime: TimeInterval
            let startPoint: CGPoint
            let modifierKey: ModifierKey?
            let isContinuousKey: Bool
            let holdBinding: KeyBinding?
            var didHold: Bool
            var maxDistanceSquared: CGFloat
            let initialPressure: Float
            var forceEntryTime: TimeInterval?
            var forceGuardTriggered: Bool

        }
        private struct PendingTouch {
            let binding: KeyBinding
            let startTime: TimeInterval
            let startPoint: CGPoint
            var maxDistanceSquared: CGFloat
            let initialPressure: Float
            var forceEntryTime: TimeInterval?
            var forceGuardTriggered: Bool

        }

        private enum TouchState {
            case pending(PendingTouch)
            case active(ActiveTouch)
        }

        private struct TwoFingerTapCandidate {
            let touchKey: TouchKey
            let startTime: TimeInterval
        }

        private struct BindingGrid {
            private let rows: Int
            private let cols: Int
            private let canvasSize: CGSize
            private var buckets: [[[KeyBinding]]]

            init(canvasSize: CGSize, rows: Int, cols: Int) {
                self.canvasSize = canvasSize
                self.rows = max(1, rows)
                self.cols = max(1, cols)
                var filledBuckets: [[[KeyBinding]]] = []
                filledBuckets.reserveCapacity(self.rows)
                for _ in 0..<self.rows {
                    var rowBuckets: [[KeyBinding]] = []
                    rowBuckets.reserveCapacity(self.cols)
                    for _ in 0..<self.cols {
                        rowBuckets.append([])
                    }
                    filledBuckets.append(rowBuckets)
                }
                self.buckets = filledBuckets
            }

            mutating func insert(_ binding: KeyBinding) {
                let range = bucketRange(for: binding.rect)
                for row in range.rowRange {
                    for col in range.colRange {
                        buckets[row][col].append(binding)
                    }
                }
            }

            func binding(at point: CGPoint) -> KeyBinding? {
                let row = bucketIndex(
                    for: normalize(point.y, axisSize: canvasSize.height),
                    count: rows
                )
                let col = bucketIndex(
                    for: normalize(point.x, axisSize: canvasSize.width),
                    count: cols
                )
                for binding in buckets[row][col] {
                    if binding.rect.contains(point) {
                        return binding
                    }
                }
                return nil
            }

            private func bucketRange(for rect: CGRect) -> (rowRange: ClosedRange<Int>, colRange: ClosedRange<Int>) {
                let minX = normalize(rect.minX, axisSize: canvasSize.width)
                let maxX = normalize(rect.maxX, axisSize: canvasSize.width)
                let minY = normalize(rect.minY, axisSize: canvasSize.height)
                let maxY = normalize(rect.maxY, axisSize: canvasSize.height)
                let startCol = bucketIndex(for: minX, count: cols)
                let endCol = bucketIndex(for: maxX, count: cols)
                let startRow = bucketIndex(for: minY, count: rows)
                let endRow = bucketIndex(for: maxY, count: rows)
                return (
                    rowRange: min(startRow, endRow)...max(startRow, endRow),
                    colRange: min(startCol, endCol)...max(startCol, endCol)
                )
            }

            private func bucketIndex(for normalizedValue: CGFloat, count: Int) -> Int {
                guard count > 0 else { return 0 }
                let clamped = min(max(normalizedValue, 0), 1)
                let index = Int(clamped * CGFloat(count))
                return index >= count ? count - 1 : index
            }

            private func normalize(_ coordinate: CGFloat, axisSize: CGFloat) -> CGFloat {
                guard axisSize > 0 else { return 0 }
                return min(max(coordinate / axisSize, 0), 1)
            }
        }

        private struct BindingIndex {
            let keyGrid: BindingGrid
            let customGrid: BindingGrid
        }

        private let keyDispatcher: KeyEventDispatcher
        private let onTypingEnabledChanged: @Sendable (Bool) -> Void
        private let onActiveLayerChanged: @Sendable (Int) -> Void
        private let onDebugBindingDetected: @Sendable (KeyBinding) -> Void
        private let isDragDetectionEnabled = true
        private var isListening = false
        private var isTypingEnabled = true
        private var activeLayer: Int = 0
        private var persistentLayer: Int = 0
        private var leftDeviceIndex: Int?
        private var rightDeviceIndex: Int?
        private var customButtons: [CustomButton] = []
        private var customButtonsByLayerAndSide: [Int: [TrackpadSide: [CustomButton]]] = [:]
        private var customKeyMappingsByLayer: LayeredKeyMappings = [:]
        private var touchStates: [TouchKey: TouchState] = [:]
        private var disqualifiedTouches: Set<TouchKey> = []
        private var leftShiftTouchCount = 0
        private var controlTouchCount = 0
        private var optionTouchCount = 0
        private var commandTouchCount = 0
        private var repeatTasks: [TouchKey: Task<Void, Never>] = [:]
        private var repeatTokens: [TouchKey: RepeatToken] = [:]
        private var toggleTouchStarts: [TouchKey: TimeInterval] = [:]
        private var layerToggleTouchStarts: [TouchKey: Int] = [:]
        private var momentaryLayerTouches: [TouchKey: Int] = [:]
        private var touchInitialContactPoint: [TouchKey: CGPoint] = [:]
        private var tapMaxDuration: TimeInterval = 0.2
        private var holdMinDuration: TimeInterval = 0.2
        private let modifierActivationDelay: TimeInterval = 0.05
        private var dragCancelDistance: CGFloat = 2.5
        private var twoFingerTapMaxInterval: TimeInterval = 0.08
        private var twoFingerSuppressionDuration: TimeInterval = 0
        private var twoFingerSuppressionExpiryByDevice: [Int: TimeInterval] = [:]
        private var forceClickCap: Float = 0
        private var twoFingerTapCandidatesByDevice: [Int: TwoFingerTapCandidate] = [:]
        private let repeatInitialDelay: UInt64 = 350_000_000
        private let repeatInterval: UInt64 = 50_000_000
        private let spaceRepeatMultiplier: UInt64 = 2
        private var leftLayout: Layout?
        private var rightLayout: Layout?
        private var leftLabels: [[String]] = []
        private var rightLabels: [[String]] = []
        private var trackpadSize: CGSize = .zero
        private var bindingsCache: [TrackpadSide: BindingIndex] = [:]
        private var bindingsCacheLayer: Int = -1
        private var bindingsGeneration = 0
        private var bindingsGenerationBySide: [TrackpadSide: Int] = [:]

#if DEBUG
        private let signposter = OSSignposter(
            subsystem: "com.kyome.GlassToKey",
            category: "TouchProcessing"
        )
        private let keyLogger = Logger(
            subsystem: "com.kyome.GlassToKey",
            category: "KeyDiagnostics"
        )
#endif

        init(
            keyDispatcher: KeyEventDispatcher,
            onTypingEnabledChanged: @Sendable @escaping (Bool) -> Void,
            onActiveLayerChanged: @Sendable @escaping (Int) -> Void,
            onDebugBindingDetected: @Sendable @escaping (KeyBinding) -> Void
        ) {
            self.keyDispatcher = keyDispatcher
            self.onTypingEnabledChanged = onTypingEnabledChanged
            self.onActiveLayerChanged = onActiveLayerChanged
            self.onDebugBindingDetected = onDebugBindingDetected
        }

        func setListening(_ isListening: Bool) {
            self.isListening = isListening
        }

        func updateActiveDevices(leftIndex: Int?, rightIndex: Int?) {
            leftDeviceIndex = leftIndex
            rightDeviceIndex = rightIndex
        }

        func updateLayouts(
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
            invalidateBindingsCache()
        }

        func updateCustomButtons(_ buttons: [CustomButton]) {
            customButtons = buttons
            rebuildCustomButtonsIndex()
            invalidateBindingsCache()
        }

        func updateKeyMappings(_ actions: LayeredKeyMappings) {
            customKeyMappingsByLayer = actions
            invalidateBindingsCache()
        }

        func setPersistentLayer(_ layer: Int) {
            let clamped = max(0, min(layer, 1))
            persistentLayer = clamped
            updateActiveLayer()
        }

        func updateHoldThreshold(_ seconds: TimeInterval) {
            let clamped = max(0, seconds)
            holdMinDuration = clamped
            tapMaxDuration = clamped
        }

        func updateDragCancelDistance(_ distance: CGFloat) {
            dragCancelDistance = max(0, distance)
        }

        func updateTwoFingerTapInterval(_ seconds: TimeInterval) {
            twoFingerTapMaxInterval = max(0, seconds)
        }

        func updateTwoFingerSuppressionDuration(_ seconds: TimeInterval) {
            let clamped = max(0, seconds)
            twoFingerSuppressionDuration = clamped
            if clamped == 0 {
                twoFingerSuppressionExpiryByDevice.removeAll()
            }
        }

        func updateForceClickCap(_ grams: Double) {
            forceClickCap = Float(max(0, grams))
        }

        func processTouchFrame(_ frame: TouchFrame) {
            guard isListening,
                  let leftLayout,
                  let rightLayout else {
                return
            }
            if leftDeviceIndex == nil && rightDeviceIndex == nil {
                return
            }
            processTouches(
                frame.left,
                keyRects: leftLayout.keyRects,
                canvasSize: trackpadSize,
                labels: leftLabels,
                isLeftSide: true
            )
            processTouches(
                frame.right,
                keyRects: rightLayout.keyRects,
                canvasSize: trackpadSize,
                labels: rightLabels,
                isLeftSide: false
            )
        }

        func resetState() {
            releaseHeldKeys()
        }

        private func rebuildCustomButtonsIndex() {
            var mapping: [Int: [TrackpadSide: [CustomButton]]] = [:]
            for button in customButtons {
                var layerMap = mapping[button.layer] ?? [:]
                var sideButtons = layerMap[button.side] ?? []
                sideButtons.append(button)
                layerMap[button.side] = sideButtons
                mapping[button.layer] = layerMap
            }
            customButtonsByLayerAndSide = mapping
        }

        private func customButtons(for layer: Int, side: TrackpadSide) -> [CustomButton] {
            customButtonsByLayerAndSide[layer]?[side] ?? []
        }

        private func processTouches(
            _ touches: [OMSTouchData],
            keyRects: [[CGRect]],
            canvasSize: CGSize,
            labels: [[String]],
            isLeftSide: Bool
        ) {
            #if DEBUG
            let signpostID = signposter.makeSignpostID()
            let state = signposter.beginInterval(
                "ProcessTouches",
                id: signpostID
            )
            defer { signposter.endInterval("ProcessTouches", state) }
            #endif
            let now = Self.now()
            let dragCancelDistanceSquared = dragCancelDistance * dragCancelDistance
            let side: TrackpadSide = isLeftSide ? .left : .right
            let bindings = bindings(
                for: side,
                keyRects: keyRects,
                labels: labels,
                canvasSize: canvasSize
            )
            if isTypingEnabled, twoFingerTapMaxInterval > 0, !touches.isEmpty {
                var touchKeysInFrame = Set<TouchKey>()
                touchKeysInFrame.reserveCapacity(touches.count)
                for touch in touches {
                    touchKeysInFrame.insert(TouchKey(deviceIndex: touch.deviceIndex, id: touch.id))
                }
                let suppressed = collectTwoFingerTapSuppression(
                    in: touches,
                    now: now,
                    activeTouchKeys: touchKeysInFrame
                )
                if !suppressed.isEmpty {
                    let devices = Set(suppressed.map { $0.deviceIndex })
                    for deviceIndex in devices {
                        extendTwoFingerSuppression(for: deviceIndex, until: now)
                    }
                    for touchKey in suppressed {
                        cancelTwoFingerTapTouch(touchKey)
                    }
                }
            }

            for touch in touches {
                let point = CGPoint(
                    x: CGFloat(touch.position.x) * canvasSize.width,
                    y: CGFloat(1.0 - touch.position.y) * canvasSize.height
                )
                let touchKey = TouchKey(deviceIndex: touch.deviceIndex, id: touch.id)
                if shouldSuppressTouch(
                    touchKey: touchKey,
                    state: touch.state,
                    now: now
                ) {
                    disqualifyTouch(touchKey, reason: .twoFingerSuppressed)
                    continue
                }
                if touchInitialContactPoint[touchKey] == nil,
                   Self.isContactState(touch.state) {
                    touchInitialContactPoint[touchKey] = point
                }
                handleForceGuard(touchKey: touchKey, pressure: touch.pressure, now: now)
                let bindingAtPoint = binding(at: point, index: bindings)

                if disqualifiedTouches.contains(touchKey) {
                    switch touch.state {
                    case .breaking, .leaving, .notTouching:
                        disqualifiedTouches.remove(touchKey)
                    case .starting, .making, .touching, .hovering, .lingering:
                        break
                    }
                    continue
                }

                if momentaryLayerTouches[touchKey] != nil {
                    handleMomentaryLayerTouch(
                        touchKey: touchKey,
                        state: touch.state,
                        targetLayer: nil,
                        bindingRect: nil
                    )
                    continue
                }
                if layerToggleTouchStarts[touchKey] != nil {
                    handleLayerToggleTouch(touchKey: touchKey, state: touch.state, targetLayer: nil)
                    continue
                }
                if toggleTouchStarts[touchKey] != nil {
                    handleTypingToggleTouch(
                        touchKey: touchKey,
                        state: touch.state,
                        point: point
                    )
                    continue
                }
                if let binding = bindingAtPoint {
                    switch binding.action {
                    case .typingToggle:
                        handleTypingToggleTouch(
                            touchKey: touchKey,
                            state: touch.state,
                            point: point
                        )
                        continue
                    case let .layerToggle(targetLayer):
                        handleLayerToggleTouch(touchKey: touchKey, state: touch.state, targetLayer: targetLayer)
                        continue
                    case let .layerMomentary(targetLayer):
                        handleMomentaryLayerTouch(
                            touchKey: touchKey,
                            state: touch.state,
                            targetLayer: targetLayer,
                            bindingRect: binding.rect
                        )
                        continue
                    case .none:
                        continue
                    case .key:
                        break
                    }
                }
                if !isTypingEnabled && momentaryLayerTouches.isEmpty {
                    if let active = removeActiveTouch(for: touchKey) {
                        if let modifierKey = active.modifierKey {
                            handleModifierUp(modifierKey, binding: active.binding)
                        } else if active.isContinuousKey {
                            stopRepeat(for: touchKey)
                       }
                    }
                    _ = removePendingTouch(for: touchKey)
                    disqualifiedTouches.remove(touchKey)
                    touchInitialContactPoint.removeValue(forKey: touchKey)
                    logDisqualify(touchKey, reason: .typingDisabled)
                    continue
                }

                switch touch.state {
                case .starting, .making, .touching:
                    if var active = activeTouch(for: touchKey) {
                        let distanceSquared = distanceSquared(from: active.startPoint, to: point)
                        active.maxDistanceSquared = max(active.maxDistanceSquared, distanceSquared)
                        setActiveTouch(touchKey, active)

                        if isDragDetectionEnabled,
                           active.modifierKey == nil,
                           !active.didHold,
                           active.maxDistanceSquared > dragCancelDistanceSquared {
                            disqualifyTouch(touchKey, reason: .dragCancelled)
                            continue
                        }

                        if active.isContinuousKey,
                           !active.binding.rect.contains(point) {
                            disqualifyTouch(touchKey, reason: .leftContinuousRect)
                            continue
                        }

                        if active.modifierKey == nil,
                        !active.isContinuousKey,
                           !active.didHold,
                           let holdBinding = active.holdBinding,
                           now - active.startTime >= holdMinDuration,
                           (!isDragDetectionEnabled || active.maxDistanceSquared <= dragCancelDistanceSquared) {
                            let dispatchInfo = makeDispatchInfo(
                                kind: .hold,
                                startTime: active.startTime,
                                maxDistanceSquared: active.maxDistanceSquared,
                                now: now
                            )
                            triggerBinding(holdBinding, touchKey: touchKey, dispatchInfo: dispatchInfo)
                            active.didHold = true
                            setActiveTouch(touchKey, active)
                        }
                    } else if var pending = pendingTouch(for: touchKey) {
                        let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
                        pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
                        setPendingTouch(touchKey, pending)

                        if isDragDetectionEnabled,
                           pending.maxDistanceSquared > dragCancelDistanceSquared {
                            disqualifyTouch(touchKey, reason: .pendingDragCancelled)
                            continue
                        }

                        if now - pending.startTime >= modifierActivationDelay {
                            if pending.binding.rect.contains(point) {
                                let modifierKey = modifierKey(for: pending.binding)
                                let isContinuousKey = isContinuousKey(pending.binding)
                                let holdBinding = holdBinding(for: pending.binding)
                                let active = ActiveTouch(
                                    binding: pending.binding,
                                    startTime: pending.startTime,
                                    startPoint: pending.startPoint,
                                    modifierKey: modifierKey,
                                    isContinuousKey: isContinuousKey,
                                    holdBinding: holdBinding,
                                    didHold: false,
                                    maxDistanceSquared: pending.maxDistanceSquared,
                                    initialPressure: pending.initialPressure,
                                    forceEntryTime: pending.forceEntryTime,
                                    forceGuardTriggered: pending.forceGuardTriggered
                                )
                                setActiveTouch(touchKey, active)
                                if let modifierKey {
                                    handleModifierDown(modifierKey, binding: pending.binding)
                                } else if isContinuousKey {
                                    triggerBinding(pending.binding, touchKey: touchKey)
                                    startRepeat(for: touchKey, binding: pending.binding)
                                }
                            } else if isDragDetectionEnabled {
                                disqualifyTouch(touchKey, reason: .pendingLeftRect)
                            } else {
                                _ = removePendingTouch(for: touchKey)
                            }
                        }
                    } else if let binding = bindingAtPoint {
                        let modifierKey = modifierKey(for: binding)
                        let isContinuousKey = isContinuousKey(binding)
                        let holdBinding = holdBinding(for: binding)
                        if isDragDetectionEnabled, (modifierKey != nil || isContinuousKey) {
                            setPendingTouch(
                                touchKey,
                                PendingTouch(
                                    binding: binding,
                                    startTime: now,
                                    startPoint: point,
                                    maxDistanceSquared: 0,
                                    initialPressure: touch.pressure,
                                    forceEntryTime: nil,
                                    forceGuardTriggered: false
                                )
                            )
                        } else {
                            setActiveTouch(
                                touchKey,
                                ActiveTouch(
                                    binding: binding,
                                    startTime: now,
                                    startPoint: point,
                                    modifierKey: modifierKey,
                                    isContinuousKey: isContinuousKey,
                                    holdBinding: holdBinding,
                                    didHold: false,
                                    maxDistanceSquared: 0,
                                    initialPressure: touch.pressure,
                                    forceEntryTime: nil,
                                    forceGuardTriggered: false
                                )
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
                    if let candidate = twoFingerTapCandidatesByDevice[touch.deviceIndex],
                       candidate.touchKey == touchKey {
                        twoFingerTapCandidatesByDevice.removeValue(forKey: touch.deviceIndex)
                    }
                    let releaseStartPoint = touchInitialContactPoint.removeValue(forKey: touchKey)
                    if var pending = removePendingTouch(for: touchKey) {
                        let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
                        pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
                        maybeSendPendingContinuousTap(pending, at: point, now: now)
                    }
                    if disqualifiedTouches.remove(touchKey) != nil {
                        continue
                    }
                    if var active = removeActiveTouch(for: touchKey) {
                        let releaseDistanceSquared = distanceSquared(
                            from: releaseStartPoint ?? active.startPoint,
                            to: point
                        )
                        active.maxDistanceSquared = max(active.maxDistanceSquared, releaseDistanceSquared)
                        let guardTriggered = active.forceGuardTriggered
                        if let modifierKey = active.modifierKey {
                            handleModifierUp(modifierKey, binding: active.binding)
                        } else if active.isContinuousKey {
                            stopRepeat(for: touchKey)
                        } else if !guardTriggered,
                                  !active.didHold,
                                  now - active.startTime <= tapMaxDuration,
                                  (!isDragDetectionEnabled
                                   || releaseDistanceSquared <= dragCancelDistanceSquared) {
                            let dispatchInfo = makeDispatchInfo(
                                kind: .tap,
                                startTime: active.startTime,
                                maxDistanceSquared: active.maxDistanceSquared,
                                now: now
                            )
                            triggerBinding(active.binding, touchKey: touchKey, dispatchInfo: dispatchInfo)
                        }
                        endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
                        if guardTriggered {
                            continue
                        }
                    }
                case .notTouching:
                    if let candidate = twoFingerTapCandidatesByDevice[touch.deviceIndex],
                       candidate.touchKey == touchKey {
                        twoFingerTapCandidatesByDevice.removeValue(forKey: touch.deviceIndex)
                    }
                    touchInitialContactPoint.removeValue(forKey: touchKey)
                    if var pending = removePendingTouch(for: touchKey) {
                        let distanceSquared = distanceSquared(from: pending.startPoint, to: point)
                        pending.maxDistanceSquared = max(pending.maxDistanceSquared, distanceSquared)
                        maybeSendPendingContinuousTap(pending, at: point, now: now)
                    }
                    if disqualifiedTouches.remove(touchKey) != nil {
                        continue
                    }
                    if var active = removeActiveTouch(for: touchKey) {
                        let distanceSquared = distanceSquared(from: active.startPoint, to: point)
                        active.maxDistanceSquared = max(active.maxDistanceSquared, distanceSquared)
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

        private func collectTwoFingerTapSuppression(
            in touches: [OMSTouchData],
            now: TimeInterval,
            activeTouchKeys: Set<TouchKey>
        ) -> [TouchKey] {
            var suppressed: [TouchKey] = []
            suppressed.reserveCapacity(2)
            for touch in touches {
                guard Self.isContactState(touch.state) else { continue }
                let touchKey = TouchKey(deviceIndex: touch.deviceIndex, id: touch.id)
                guard !disqualifiedTouches.contains(touchKey) else { continue }
                guard touchInitialContactPoint[touchKey] == nil else { continue }
                if let candidate = twoFingerTapCandidatesByDevice[touch.deviceIndex] {
                    if !activeTouchKeys.contains(candidate.touchKey) {
                        twoFingerTapCandidatesByDevice.removeValue(forKey: touch.deviceIndex)
                    } else if now - candidate.startTime <= twoFingerTapMaxInterval {
                        suppressed.append(candidate.touchKey)
                        suppressed.append(touchKey)
                        twoFingerTapCandidatesByDevice.removeValue(forKey: touch.deviceIndex)
                        continue
                    }
                }
                twoFingerTapCandidatesByDevice[touch.deviceIndex] = TwoFingerTapCandidate(
                    touchKey: touchKey,
                    startTime: now
                )
            }
            return suppressed
        }

        private func extendTwoFingerSuppression(for deviceIndex: Int, until now: TimeInterval) {
            guard twoFingerSuppressionDuration > 0 else { return }
            let candidateExpiry = now + twoFingerSuppressionDuration
            if candidateExpiry > (twoFingerSuppressionExpiryByDevice[deviceIndex] ?? 0) {
                twoFingerSuppressionExpiryByDevice[deviceIndex] = candidateExpiry
            }
        }

        private func shouldSuppressTouch(
            touchKey: TouchKey,
            state: OMSState,
            now: TimeInterval
        ) -> Bool {
            guard isSuppressionActive(for: touchKey.deviceIndex, at: now),
                  Self.isContactState(state),
                  !disqualifiedTouches.contains(touchKey) else {
                return false
            }
            return true
        }

        private func isSuppressionActive(for deviceIndex: Int, at now: TimeInterval) -> Bool {
            guard twoFingerSuppressionDuration > 0,
                  let expiry = twoFingerSuppressionExpiryByDevice[deviceIndex] else {
                return false
            }
            if now >= expiry {
                twoFingerSuppressionExpiryByDevice.removeValue(forKey: deviceIndex)
                return false
            }
            return true
        }

        private func handleForceGuard(
            touchKey: TouchKey,
            pressure: Float,
            now: TimeInterval
        ) {
            guard forceClickCap > 0 else { return }

            if let active = activeTouch(for: touchKey) {
                let delta = max(0, pressure - active.initialPressure)
                if delta >= forceClickCap {
                    disqualifyTouch(touchKey, reason: .forceCapExceeded)
                }
                return
            }

            if let pending = pendingTouch(for: touchKey) {
                let delta = max(0, pressure - pending.initialPressure)
                if delta >= forceClickCap {
                    disqualifyTouch(touchKey, reason: .forceCapExceeded)
                }
            }
        }

        private func activeTouch(for touchKey: TouchKey) -> ActiveTouch? {
            guard let state = touchStates[touchKey],
                  case let .active(active) = state else {
                return nil
            }
            return active
        }

        private func pendingTouch(for touchKey: TouchKey) -> PendingTouch? {
            guard let state = touchStates[touchKey],
                  case let .pending(pending) = state else {
                return nil
            }
            return pending
        }

        private func setActiveTouch(_ touchKey: TouchKey, _ active: ActiveTouch) {
            touchStates[touchKey] = .active(active)
        }

        private func setPendingTouch(_ touchKey: TouchKey, _ pending: PendingTouch) {
            touchStates[touchKey] = .pending(pending)
        }

        private func removeActiveTouch(for touchKey: TouchKey) -> ActiveTouch? {
            guard let state = touchStates[touchKey],
                  case let .active(active) = state else {
                return nil
            }
            touchStates.removeValue(forKey: touchKey)
            return active
        }

        private func removePendingTouch(for touchKey: TouchKey) -> PendingTouch? {
            guard let state = touchStates[touchKey],
                  case let .pending(pending) = state else {
                return nil
            }
            touchStates.removeValue(forKey: touchKey)
            return pending
        }

        private func popTouchState(for touchKey: TouchKey) -> TouchState? {
            touchStates.removeValue(forKey: touchKey)
        }

        private func cancelTwoFingerTapTouch(_ touchKey: TouchKey) {
            disqualifyTouch(touchKey, reason: .twoFingerSuppressed)
            toggleTouchStarts.removeValue(forKey: touchKey)
            layerToggleTouchStarts.removeValue(forKey: touchKey)
            if momentaryLayerTouches.removeValue(forKey: touchKey) != nil {
                updateActiveLayer()
            }
        }

        private func makeBindings(
            keyRects: [[CGRect]],
            labels: [[String]],
            customButtons: [CustomButton],
            canvasSize: CGSize,
            side: TrackpadSide
        ) -> BindingIndex {
            let keyRows = max(1, keyRects.count)
            let keyCols = max(1, keyRects.first?.count ?? 1)
            var keyGrid = BindingGrid(canvasSize: canvasSize, rows: keyRows, cols: keyCols)
            var customGrid = BindingGrid(
                canvasSize: canvasSize,
                rows: max(4, keyRows),
                cols: max(4, keyCols)
            )

            for row in 0..<keyRects.count {
                let rowRects = keyRects[row]
                for col in 0..<rowRects.count {
                    let rect = rowRects[col]
                    guard row < labels.count,
                          col < labels[row].count else { continue }
                    let label = labels[row][col]
                    let position = GridKeyPosition(side: side, row: row, column: col)
                    guard let binding = bindingForLabel(label, rect: rect, position: position) else {
                        continue
                    }
                    keyGrid.insert(binding)
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
                case .none:
                    action = .none
                }
                let binding = KeyBinding(
                    rect: rect,
                    label: button.action.label,
                    action: action,
                    position: nil,
                    side: button.side,
                    holdAction: button.hold
                )
                customGrid.insert(binding)
            }

            return BindingIndex(
                keyGrid: keyGrid,
                customGrid: customGrid
            )
        }

        private func bindingForLabel(_ label: String, rect: CGRect, position: GridKeyPosition) -> KeyBinding? {
            guard let action = keyAction(for: position, label: label) else { return nil }
            return makeBinding(for: action, rect: rect, position: position, side: position.side)
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
            side: TrackpadSide,
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
                    side: side,
                    holdAction: holdAction
                )
            case .typingToggle:
                return KeyBinding(
                    rect: rect,
                    label: action.label,
                    action: .typingToggle,
                    position: position,
                    side: side,
                    holdAction: holdAction
                )
            case .layerMomentary:
                return KeyBinding(
                    rect: rect,
                    label: action.label,
                    action: .layerMomentary(action.layer ?? 1),
                    position: position,
                    side: side,
                    holdAction: holdAction
                )
            case .layerToggle:
                return KeyBinding(
                    rect: rect,
                    label: action.label,
                    action: .layerToggle(action.layer ?? 1),
                    position: position,
                    side: side,
                    holdAction: holdAction
                )
            case .none:
                return KeyBinding(
                    rect: rect,
                    label: action.label,
                    action: .none,
                    position: position,
                    side: side,
                    holdAction: holdAction
                )
            }
        }

        private func binding(at point: CGPoint, index: BindingIndex) -> KeyBinding? {
            if let binding = index.keyGrid.binding(at: point) {
                return binding
            }
            return index.customGrid.binding(at: point)
        }

        private static func isContactState(_ state: OMSState) -> Bool {
            switch state {
            case .starting, .making, .touching:
                return true
            default:
                return false
            }
        }

        private func handleTypingToggleTouch(
            touchKey: TouchKey,
            state: OMSState,
            point: CGPoint
        ) {
            switch state {
            case .starting, .making, .touching:
                if toggleTouchStarts[touchKey] == nil {
                    toggleTouchStarts[touchKey] = Self.now()
                }
            case .breaking, .leaving:
                let didStart = toggleTouchStarts.removeValue(forKey: touchKey)
                if didStart != nil {
                    let maxDistance = dragCancelDistance * dragCancelDistance
                    let initialPoint = touchInitialContactPoint[touchKey]
                    let distance = initialPoint
                        .map { distanceSquared(from: $0, to: point) } ?? 0
                    if distance <= maxDistance {
                        toggleTypingMode()
                    }
                }
                touchInitialContactPoint.removeValue(forKey: touchKey)
            case .notTouching:
                toggleTouchStarts.removeValue(forKey: touchKey)
                touchInitialContactPoint.removeValue(forKey: touchKey)
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
            targetLayer: Int?,
            bindingRect: CGRect?
        ) {
            switch state {
            case .starting, .making, .touching:
                guard momentaryLayerTouches[touchKey] == nil,
                      let targetLayer,
                      let rect = bindingRect,
                      let initialPoint = touchInitialContactPoint[touchKey],
                      rect.contains(initialPoint) else {
                    break
                }
                momentaryLayerTouches[touchKey] = targetLayer
                updateActiveLayer()
            case .breaking, .leaving, .notTouching:
                if momentaryLayerTouches.removeValue(forKey: touchKey) != nil {
                    updateActiveLayer()
                }
            case .hovering, .lingering:
                break
            }
        }

        private func toggleTypingMode() {
            let updated = !isTypingEnabled
            if updated != isTypingEnabled {
                isTypingEnabled = updated
                onTypingEnabledChanged(updated)
            }
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
            return code == CGKeyCode(kVK_Delete)
                || code == CGKeyCode(kVK_LeftArrow)
                || code == CGKeyCode(kVK_RightArrow)
                || code == CGKeyCode(kVK_UpArrow)
                || code == CGKeyCode(kVK_DownArrow)
        }

        private func holdBinding(for binding: KeyBinding) -> KeyBinding? {
            if let holdAction = binding.holdAction {
                return makeBinding(
                    for: holdAction,
                    rect: binding.rect,
                    position: binding.position,
                    side: binding.side,
                    holdAction: binding.holdAction
                )
            }
            guard let action = holdAction(for: binding.position, label: binding.label) else { return nil }
            return makeBinding(
                for: action,
                rect: binding.rect,
                position: binding.position,
                side: binding.side
            )
        }

        private func maybeSendPendingContinuousTap(
            _ pending: PendingTouch,
            at point: CGPoint,
            now: TimeInterval
        ) {
            let releaseDistanceSquared = distanceSquared(from: pending.startPoint, to: point)
            guard isContinuousKey(pending.binding),
                  now - pending.startTime <= tapMaxDuration,
                  pending.binding.rect.contains(point),
                  (!isDragDetectionEnabled
                   || releaseDistanceSquared <= dragCancelDistance * dragCancelDistance),
                  !pending.forceGuardTriggered else {
                return
            }
            let dispatchInfo = makeDispatchInfo(
                kind: .tap,
                startTime: pending.startTime,
                maxDistanceSquared: pending.maxDistanceSquared,
                now: now
            )
            sendKey(binding: pending.binding, dispatchInfo: dispatchInfo)
        }

        private func triggerBinding(
            _ binding: KeyBinding,
            touchKey: TouchKey?,
            dispatchInfo: DispatchInfo? = nil
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
#if DEBUG
                onDebugBindingDetected(binding)
#endif
                logKeyDispatch(
                    label: binding.label,
                    code: code,
                    flags: flags,
                    kind: dispatchInfo?.kind ?? .continuous,
                    durationMs: dispatchInfo?.durationMs,
                    maxDistance: dispatchInfo?.maxDistance
                )
                sendKey(code: code, flags: flags)
            }
        }

        private func sendKey(code: CGKeyCode, flags: CGEventFlags) {
            let combinedFlags = flags.union(currentModifierFlags())
            keyDispatcher.postKeyStroke(code: code, flags: combinedFlags)
        }

        private func currentModifierFlags() -> CGEventFlags {
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
            return modifierFlags
        }

        private func sendKey(binding: KeyBinding, dispatchInfo: DispatchInfo? = nil) {
            guard case let .key(code, flags) = binding.action else { return }
#if DEBUG
            onDebugBindingDetected(binding)
#endif
            logKeyDispatch(
                label: binding.label,
                code: code,
                flags: flags,
                kind: dispatchInfo?.kind ?? .continuous,
                durationMs: dispatchInfo?.durationMs,
                maxDistance: dispatchInfo?.maxDistance
            )
            sendKey(code: code, flags: flags)
        }

        private func startRepeat(for touchKey: TouchKey, binding: KeyBinding) {
            stopRepeat(for: touchKey)
            guard case let .key(code, flags) = binding.action else { return }
            let repeatFlags = flags.union(currentModifierFlags())
            let initialDelay = repeatInitialDelay
            let interval = repeatInterval(for: binding.action)
            let token = RepeatToken()
            repeatTokens[touchKey] = token
            repeatTasks[touchKey] = Task.detached(priority: .userInitiated) { [dispatcher = keyDispatcher] in
                try? await Task.sleep(nanoseconds: initialDelay)
                while !Task.isCancelled, token.isActive {
                    dispatcher.postKeyStroke(code: code, flags: repeatFlags, token: token)
                    try? await Task.sleep(nanoseconds: interval)
                }
            }
        }

        private func repeatInterval(for action: KeyBindingAction) -> UInt64 {
            if case let .key(code, flags) = action,
               code == CGKeyCode(kVK_Space),
               flags.isEmpty {
                return repeatInterval * spaceRepeatMultiplier
            }
            return repeatInterval
        }

        private func stopRepeat(for touchKey: TouchKey) {
            if let task = repeatTasks.removeValue(forKey: touchKey) {
                task.cancel()
            }
            repeatTokens.removeValue(forKey: touchKey)?.deactivate()
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
#if DEBUG
            onDebugBindingDetected(binding)
#endif
            logKeyDispatch(label: binding.label, code: code, flags: flags, keyDown: keyDown)
            keyDispatcher.postKey(code: code, flags: flags, keyDown: keyDown)
        }

        private func releaseHeldKeys() {
            if leftShiftTouchCount > 0 {
                let shiftBinding = KeyBinding(
                    rect: .zero,
                    label: "Shift",
                    action: .key(code: CGKeyCode(kVK_Shift), flags: []),
                    position: nil,
                    side: .left,
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
                    side: .left,
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
                    side: .left,
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
                    side: .left,
                    holdAction: nil
                )
                postKey(binding: commandBinding, keyDown: false)
                commandTouchCount = 0
            }
            let activeTouchKeys = touchStates.compactMap { key, state in
                if case .active = state { return key }
                return nil
            }
            for touchKey in activeTouchKeys {
                stopRepeat(for: touchKey)
            }
            touchStates.removeAll()
            disqualifiedTouches.removeAll()
            toggleTouchStarts.removeAll()
            layerToggleTouchStarts.removeAll()
            momentaryLayerTouches.removeAll()
            touchInitialContactPoint.removeAll()
            updateActiveLayer()
        }

        private func disqualifyTouch(_ touchKey: TouchKey, reason: DisqualifyReason) {
            touchInitialContactPoint.removeValue(forKey: touchKey)
            disqualifiedTouches.insert(touchKey)
            if let state = popTouchState(for: touchKey),
               case let .active(active) = state {
                if let modifierKey = active.modifierKey {
                    handleModifierUp(modifierKey, binding: active.binding)
                } else if active.isContinuousKey {
                    stopRepeat(for: touchKey)
                }
                endMomentaryHoldIfNeeded(active.holdBinding, touchKey: touchKey)
            }
            logDisqualify(touchKey, reason: reason)
        }

        private func distanceSquared(from start: CGPoint, to end: CGPoint) -> CGFloat {
            let dx = end.x - start.x
            let dy = end.y - start.y
            return dx * dx + dy * dy
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
            let resolvedLayer = momentaryLayerTouches.values.max() ?? persistentLayer
            if activeLayer != resolvedLayer {
                activeLayer = resolvedLayer
                invalidateBindingsCache()
                onActiveLayerChanged(resolvedLayer)
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

        private static func now() -> TimeInterval {
            CACurrentMediaTime()
        }

        private func logDisqualify(_ touchKey: TouchKey, reason: DisqualifyReason) {
            #if DEBUG
            keyLogger.debug("disqualify deviceIndex=\(touchKey.deviceIndex) id=\(touchKey.id) reason=\(reason.rawValue)")
            #endif
        }

        private func logKeyDispatch(
            label: String,
            code: CGKeyCode,
            flags: CGEventFlags,
            keyDown: Bool? = nil,
            kind: DispatchKind = .continuous,
            durationMs: Int? = nil,
            maxDistance: CGFloat? = nil
        ) {
            #if DEBUG
            let shouldLogMetrics = (kind == .tap || kind == .hold)
                && durationMs != nil
                && maxDistance != nil
            if let keyDown {
                if shouldLogMetrics, let durationMs, let maxDistance {
                    keyLogger.debug("dispatch label=\(label, privacy: .public) code=\(code) flags=\(flags.rawValue) keyDown=\(keyDown) kind=\(kind.rawValue) durationMs=\(durationMs) maxDistance=\(maxDistance)")
                } else {
                    keyLogger.debug("dispatch label=\(label, privacy: .public) code=\(code) flags=\(flags.rawValue) keyDown=\(keyDown) kind=\(kind.rawValue)")
                }
            } else {
                if shouldLogMetrics, let durationMs, let maxDistance {
                    keyLogger.debug("dispatch label=\(label, privacy: .public) code=\(code) flags=\(flags.rawValue) kind=\(kind.rawValue) durationMs=\(durationMs) maxDistance=\(maxDistance)")
                } else {
                    keyLogger.debug("dispatch label=\(label, privacy: .public) code=\(code) flags=\(flags.rawValue) kind=\(kind.rawValue)")
                }
            }
            #endif
        }

        private func makeDispatchInfo(
            kind: DispatchKind,
            startTime: TimeInterval,
            maxDistanceSquared: CGFloat,
            now: TimeInterval
        ) -> DispatchInfo {
            let durationMs = Int((now - startTime) * 1000.0)
            let maxDistance = sqrt(maxDistanceSquared)
            return DispatchInfo(kind: kind, durationMs: durationMs, maxDistance: maxDistance)
        }

        private func invalidateBindingsCache() {
            bindingsGeneration &+= 1
        }

        func clearVisualCaches() {
            bindingsCache.removeAll()
            bindingsCacheLayer = -1
            bindingsGeneration &+= 1
            bindingsGenerationBySide.removeAll()
        }

        private func bindings(
            for side: TrackpadSide,
            keyRects: [[CGRect]],
            labels: [[String]],
            canvasSize: CGSize
        ) -> BindingIndex {
            if bindingsCacheLayer != activeLayer {
                bindingsCacheLayer = activeLayer
                invalidateBindingsCache()
            }
            let currentGeneration = bindingsGenerationBySide[side] ?? -1
            if currentGeneration != bindingsGeneration || bindingsCache[side] == nil {
                bindingsCache[side] = makeBindings(
                    keyRects: keyRects,
                    labels: labels,
                    customButtons: customButtons(for: activeLayer, side: side),
                    canvasSize: canvasSize,
                    side: side
                )
                bindingsGenerationBySide[side] = bindingsGeneration
            }
            return bindingsCache[side] ?? BindingIndex(
                keyGrid: BindingGrid(canvasSize: .zero, rows: 1, cols: 1),
                customGrid: BindingGrid(canvasSize: .zero, rows: 1, cols: 1)
            )
        }
    }
}

final class RepeatToken: @unchecked Sendable {
    private let isActiveLock = OSAllocatedUnfairLock<Bool>(uncheckedState: true)

    var isActive: Bool {
        isActiveLock.withLockUnchecked(\.self)
    }

    func deactivate() {
        isActiveLock.withLockUnchecked { $0 = false }
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
        var displayText: String {
            switch kind {
            case .none:
                return ""
            case .typingToggle:
                return KeyActionCatalog.typingToggleDisplayLabel
            default:
                return label
            }
        }

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
    var layer: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case side
        case rect
        case action
        case hold
        case layer
    }

    init(
        id: UUID,
        side: TrackpadSide,
        rect: NormalizedRect,
        action: KeyAction,
        hold: KeyAction?,
        layer: Int = 0
    ) {
        self.id = id
        self.side = side
        self.rect = rect
        self.action = action
        self.hold = hold
        self.layer = layer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        side = try container.decode(TrackpadSide.self, forKey: .side)
        rect = try container.decode(NormalizedRect.self, forKey: .rect)
        action = try container.decode(KeyAction.self, forKey: .action)
        hold = try container.decodeIfPresent(KeyAction.self, forKey: .hold)
        layer = try container.decodeIfPresent(Int.self, forKey: .layer) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(side, forKey: .side)
        try container.encode(rect, forKey: .rect)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(hold, forKey: .hold)
        try container.encode(layer, forKey: .layer)
    }
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
                    hold: nil,
                    layer: 0
                ))
            }
            if index < rightActions.count {
                buttons.append(CustomButton(
                    id: UUID(),
                    side: .right,
                    rect: normalized,
                    action: rightActions[index]
                    ,
                    hold: nil,
                    layer: 0
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
        "Cmd": (CGKeyCode(kVK_Command), []),
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
        "Left": (CGKeyCode(kVK_LeftArrow), []),
        "Right": (CGKeyCode(kVK_RightArrow), []),
        "Up": (CGKeyCode(kVK_UpArrow), []),
        "Down": (CGKeyCode(kVK_DownArrow), []),
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

    static func decodeNormalized(_ data: Data) -> LayeredKeyMappings? {
        guard let layered = decode(data) else { return nil }
        return normalized(layered)
    }

    static func encode(_ mappings: LayeredKeyMappings) -> Data? {
        guard !mappings.isEmpty else { return nil }
        do {
            return try JSONEncoder().encode(mappings)
        } catch {
            return nil
        }
    }

    static func normalized(_ mappings: LayeredKeyMappings) -> LayeredKeyMappings {
        let layer0 = mappings[0] ?? [:]
        let layer1 = mappings[1] ?? layer0
        return [0: layer0, 1: layer1]
    }
}
