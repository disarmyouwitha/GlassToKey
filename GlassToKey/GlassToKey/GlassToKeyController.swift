import OpenMultitouchSupport
import SwiftUI

enum GlassToKeySettings {
    static let tapTypeMinHoldMs: Double = 100.0
    static let tapClickEnabled: Bool = true
    static let tapHoldDurationMs: Double = 200.0
    static let dragCancelDistanceMm: Double = 10.0
    static let forceClickCap: Double = 110.0
    static let hapticStrengthPercent: Double = 10.0
    static let typingGraceMs: Double = 600.0
    static let intentMoveThresholdMm: Double = 4.0
    static let intentVelocityThresholdMmPerSec: Double = 50.0
    static let allowMouseTakeoverDuringTyping: Bool = false
    static let autocorrectEnabled: Bool = false
    static let snapRadiusPercent: Double = 35.0

    static func persistedDouble(
        forKey key: String,
        defaults: UserDefaults = .standard,
        fallback: Double
    ) -> Double {
        if let value = defaults.object(forKey: key) as? Double {
            return value
        }
        return fallback
    }
}

@MainActor
final class GlassToKeyController: ObservableObject {
    let viewModel: ContentViewModel
    private var isRunning = false
    private let legacyKeyScaleKey = "GlassToKey.keyScale"
    private let legacyKeyOffsetXKey = "GlassToKey.keyOffsetX"
    private let legacyKeyOffsetYKey = "GlassToKey.keyOffsetY"
    private let legacyRowSpacingPercentKey = "GlassToKey.rowSpacingPercent"

    init(viewModel: ContentViewModel = ContentViewModel()) {
        self.viewModel = viewModel
    }

    func start() {
        guard !isRunning else { return }
        OMSManager.shared.isTimestampEnabled = false
        configureFromDefaults()
        viewModel.start()
        viewModel.onAppear()
        isRunning = true
    }

    private func configureFromDefaults() {
        viewModel.loadDevices()
        let layout = resolvedLayoutPreset()
        let columnSettings = resolvedColumnSettings(for: layout)

        let trackpadSize = CGSize(
            width: ContentView.trackpadWidthMM * ContentView.displayScale,
            height: ContentView.trackpadHeightMM * ContentView.displayScale
        )

        let leftLayout: ContentViewModel.Layout
        let rightLayout: ContentViewModel.Layout
        if layout.columns > 0, layout.rows > 0 {
            leftLayout = ContentView.makeKeyLayout(
                size: trackpadSize,
                keyWidth: ContentView.baseKeyWidthMM,
                keyHeight: ContentView.baseKeyHeightMM,
                columns: layout.columns,
                rows: layout.rows,
                trackpadWidth: ContentView.trackpadWidthMM,
                trackpadHeight: ContentView.trackpadHeightMM,
                columnAnchorsMM: layout.columnAnchors,
                columnSettings: columnSettings,
                mirrored: true
            )
            rightLayout = ContentView.makeKeyLayout(
                size: trackpadSize,
                keyWidth: ContentView.baseKeyWidthMM,
                keyHeight: ContentView.baseKeyHeightMM,
                columns: layout.columns,
                rows: layout.rows,
                trackpadWidth: ContentView.trackpadWidthMM,
                trackpadHeight: ContentView.trackpadHeightMM,
                columnAnchorsMM: layout.columnAnchors,
                columnSettings: columnSettings
            )
        } else {
            leftLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
            rightLayout = ContentViewModel.Layout(keyRects: [], trackpadSize: trackpadSize)
        }

        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: layout.leftLabels,
            rightLabels: layout.rightLabels,
            trackpadSize: trackpadSize,
            trackpadWidthMm: ContentView.trackpadWidthMM
        )

        let customButtons = loadCustomButtons()
        viewModel.updateCustomButtons(customButtons)

        let keyMappings = loadKeyMappings()
        viewModel.updateKeyMappings(keyMappings)

        applySavedInteractionSettings()
        let autocorrectEnabled = UserDefaults.standard.bool(
            forKey: GlassToKeyDefaultsKeys.autocorrectEnabled
        )
        AutocorrectEngine.shared.setEnabled(autocorrectEnabled)

        let leftDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.leftDeviceID)
        let rightDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.rightDeviceID)
        if let leftDevice = deviceForID(leftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(rightDeviceID) {
            viewModel.selectRightDevice(rightDevice)
        }
        let autoResyncEnabled = UserDefaults.standard.bool(
            forKey: GlassToKeyDefaultsKeys.autoResyncMissingTrackpads
        )
        viewModel.setAutoResyncEnabled(autoResyncEnabled)
    }

    private func deviceForID(_ deviceID: String) -> OMSDeviceInfo? {
        guard !deviceID.isEmpty else { return nil }
        return viewModel.availableDevices.first { $0.deviceID == deviceID }
    }

    private func loadCustomButtons() -> [CustomButton] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.customButtons),
           let decoded = CustomButtonStore.decode(data),
           !decoded.isEmpty {
            return decoded
        }
        return CustomButtonDefaults.defaultButtons(
            trackpadWidth: ContentView.trackpadWidthMM,
            trackpadHeight: ContentView.trackpadHeightMM,
            thumbAnchorsMM: ContentView.ThumbAnchorsMM
        )
    }

    private func loadKeyMappings() -> LayeredKeyMappings {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.keyMappings),
           let mappings = KeyActionMappingStore.decodeNormalized(data) {
            return mappings
        }
        return [0: [:], 1: [:]]
    }

    private func resolvedLayoutPreset() -> TrackpadLayoutPreset {
        let stored = UserDefaults.standard.string(forKey: GlassToKeyDefaultsKeys.layoutPreset)
        return TrackpadLayoutPreset(rawValue: stored ?? "") ?? .sixByThree
    }

    private func resolvedColumnSettings(
        for layout: TrackpadLayoutPreset
    ) -> [ColumnLayoutSettings] {
        let defaults = UserDefaults.standard
        let columns = layout.columns
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.columnSettings),
           let stored = LayoutColumnSettingsStorage.settings(
            for: layout,
            from: data
        ) {
            return ColumnLayoutDefaults.normalizedSettings(stored, columns: columns)
        }
        if let migrated = legacyColumnSettings(for: layout) {
            return migrated
        }
        return ColumnLayoutDefaults.defaultSettings(columns: columns)
    }

    private func applySavedInteractionSettings() {
        let defaults = UserDefaults.standard
        let tapHoldMs = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.tapHoldDuration,
            defaults: defaults,
            fallback: GlassToKeySettings.tapHoldDurationMs
        )
        let tapTypeMinHoldMs = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.tapTypeMinHoldMs,
            defaults: defaults,
            fallback: GlassToKeySettings.tapTypeMinHoldMs
        )
        let tapClickEnabled = defaults.object(
            forKey: GlassToKeyDefaultsKeys.tapClickEnabled
        ) as? Bool ?? GlassToKeySettings.tapClickEnabled
        let dragDistance = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.dragCancelDistance,
            defaults: defaults,
            fallback: GlassToKeySettings.dragCancelDistanceMm
        )
        let forceCap = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.forceClickCap,
            defaults: defaults,
            fallback: GlassToKeySettings.forceClickCap
        )
        let hapticStrengthPercent = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.hapticStrength,
            defaults: defaults,
            fallback: GlassToKeySettings.hapticStrengthPercent
        )
        let typingGraceMs = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.typingGraceMs,
            defaults: defaults,
            fallback: GlassToKeySettings.typingGraceMs
        )
        let intentMoveThresholdMm = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.intentMoveThresholdMm,
            defaults: defaults,
            fallback: GlassToKeySettings.intentMoveThresholdMm
        )
        let intentVelocityThresholdMmPerSec = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.intentVelocityThresholdMmPerSec,
            defaults: defaults,
            fallback: GlassToKeySettings.intentVelocityThresholdMmPerSec
        )
        let allowMouseTakeoverDuringTyping = defaults.object(
            forKey: GlassToKeyDefaultsKeys.allowMouseTakeoverDuringTyping
        ) as? Bool ?? GlassToKeySettings.allowMouseTakeoverDuringTyping
        let snapRadiusPercent = GlassToKeySettings.persistedDouble(
            forKey: GlassToKeyDefaultsKeys.snapRadiusPercent,
            defaults: defaults,
            fallback: GlassToKeySettings.snapRadiusPercent
        )

        viewModel.updateHoldThreshold(tapHoldMs / 1000.0)
        viewModel.updateTapTypeMinHoldMs(tapTypeMinHoldMs)
        viewModel.updateTapClickEnabled(tapClickEnabled)
        viewModel.updateDragCancelDistance(CGFloat(dragDistance))
        viewModel.updateForceClickCap(forceCap)
        viewModel.updateHapticStrength(hapticStrengthPercent / 100.0)
        viewModel.updateTypingGraceMs(typingGraceMs)
        viewModel.updateIntentMoveThresholdMm(intentMoveThresholdMm)
        viewModel.updateIntentVelocityThresholdMmPerSec(intentVelocityThresholdMmPerSec)
        viewModel.updateAllowMouseTakeover(allowMouseTakeoverDuringTyping)
        viewModel.updateSnapRadiusPercent(snapRadiusPercent)
    }

    private func legacyColumnSettings(
        for layout: TrackpadLayoutPreset
    ) -> [ColumnLayoutSettings]? {
        let columns = layout.columns
        guard columns > 0 else { return nil }
        let defaults = UserDefaults.standard
        let hasLegacyScale = defaults.object(forKey: legacyKeyScaleKey) != nil
        let hasLegacyOffsetX = defaults.object(forKey: legacyKeyOffsetXKey) != nil
        let hasLegacyOffsetY = defaults.object(forKey: legacyKeyOffsetYKey) != nil
        let hasLegacyRowSpacing = defaults.object(forKey: legacyRowSpacingPercentKey) != nil
        guard hasLegacyScale || hasLegacyOffsetX || hasLegacyOffsetY || hasLegacyRowSpacing else {
            return nil
        }
        let keyScale = hasLegacyScale ? defaults.double(forKey: legacyKeyScaleKey) : 1.0
        let offsetX = hasLegacyOffsetX ? defaults.double(forKey: legacyKeyOffsetXKey) : 0.0
        let offsetY = hasLegacyOffsetY ? defaults.double(forKey: legacyKeyOffsetYKey) : 0.0
        let rowSpacingPercent = hasLegacyRowSpacing
            ? defaults.double(forKey: legacyRowSpacingPercentKey)
            : 0.0
        let offsetXPercent = offsetX / Double(ContentView.trackpadWidthMM) * 100.0
        let offsetYPercent = offsetY / Double(ContentView.trackpadHeightMM) * 100.0
        let migrated = ColumnLayoutDefaults.defaultSettings(columns: columns).map { _ in
            ColumnLayoutSettings(
                scale: keyScale,
                offsetXPercent: offsetXPercent,
                offsetYPercent: offsetYPercent,
                rowSpacingPercent: rowSpacingPercent
            )
        }
        return ColumnLayoutDefaults.normalizedSettings(migrated, columns: columns)
    }

    private func stringValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
}
