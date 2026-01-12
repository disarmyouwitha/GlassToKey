import OpenMultitouchSupport
import SwiftUI

@MainActor
final class GlassToKeyController: ObservableObject {
    let viewModel: ContentViewModel
    private var isRunning = false
    private let legacyKeyScaleKey = "GlassToKey.keyScale"
    private let legacyKeyOffsetXKey = "GlassToKey.keyOffsetX"
    private let legacyKeyOffsetYKey = "GlassToKey.keyOffsetY"

    init(viewModel: ContentViewModel = ContentViewModel()) {
        self.viewModel = viewModel
    }

    func start() {
        guard !isRunning else { return }
        configureFromDefaults()
        viewModel.start()
        viewModel.onAppear()
        isRunning = true
    }

    private func configureFromDefaults() {
        viewModel.loadDevices()
        let columnSettings = resolvedColumnSettings()

        let trackpadSize = CGSize(
            width: ContentView.trackpadWidthMM * ContentView.displayScale,
            height: ContentView.trackpadHeightMM * ContentView.displayScale
        )

        let leftLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: ContentView.baseKeyWidthMM,
            keyHeight: ContentView.baseKeyHeightMM,
            columns: ContentView.columnCount,
            rows: ContentView.rowCount,
            trackpadWidth: ContentView.trackpadWidthMM,
            trackpadHeight: ContentView.trackpadHeightMM,
            columnAnchorsMM: ContentView.ColumnAnchorsMM,
            columnSettings: columnSettings,
            mirrored: true
        )
        let rightLayout = ContentView.makeKeyLayout(
            size: trackpadSize,
            keyWidth: ContentView.baseKeyWidthMM,
            keyHeight: ContentView.baseKeyHeightMM,
            columns: ContentView.columnCount,
            rows: ContentView.rowCount,
            trackpadWidth: ContentView.trackpadWidthMM,
            trackpadHeight: ContentView.trackpadHeightMM,
            columnAnchorsMM: ContentView.ColumnAnchorsMM,
            columnSettings: columnSettings
        )

        viewModel.configureLayouts(
            leftLayout: leftLayout,
            rightLayout: rightLayout,
            leftLabels: ContentView.mirroredLabels(ContentViewModel.leftGridLabels),
            rightLabels: ContentViewModel.rightGridLabels,
            trackpadSize: trackpadSize
        )

        let customButtons = loadCustomButtons()
        viewModel.updateCustomButtons(customButtons)

        let leftDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.leftDeviceID)
        let rightDeviceID = stringValue(forKey: GlassToKeyDefaultsKeys.rightDeviceID)
        if let leftDevice = deviceForID(leftDeviceID) {
            viewModel.selectLeftDevice(leftDevice)
        }
        if let rightDevice = deviceForID(rightDeviceID) {
            viewModel.selectRightDevice(rightDevice)
        }
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

    private func resolvedColumnSettings() -> [ColumnLayoutSettings] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: GlassToKeyDefaultsKeys.columnSettings),
           let decoded = ColumnLayoutStore.decode(data),
           decoded.count == ContentView.columnCount {
            return ColumnLayoutDefaults.normalizedSettings(
                decoded,
                columns: ContentView.columnCount
            )
        }

        let hasLegacyScale = defaults.object(forKey: legacyKeyScaleKey) != nil
        let hasLegacyOffsetX = defaults.object(forKey: legacyKeyOffsetXKey) != nil
        let hasLegacyOffsetY = defaults.object(forKey: legacyKeyOffsetYKey) != nil
        if hasLegacyScale || hasLegacyOffsetX || hasLegacyOffsetY {
            let keyScale = hasLegacyScale ? defaults.double(forKey: legacyKeyScaleKey) : 1.0
            let offsetX = hasLegacyOffsetX ? defaults.double(forKey: legacyKeyOffsetXKey) : 0.0
            let offsetY = hasLegacyOffsetY ? defaults.double(forKey: legacyKeyOffsetYKey) : 0.0
            let offsetXPercent = offsetX / Double(ContentView.trackpadWidthMM) * 100.0
            let offsetYPercent = offsetY / Double(ContentView.trackpadHeightMM) * 100.0
            let migrated = ColumnLayoutDefaults.defaultSettings(columns: ContentView.columnCount).map { _ in
                ColumnLayoutSettings(
                    scale: keyScale,
                    offsetXPercent: offsetXPercent,
                    offsetYPercent: offsetYPercent
                )
            }
            return ColumnLayoutDefaults.normalizedSettings(
                migrated,
                columns: ContentView.columnCount
            )
        }

        return ColumnLayoutDefaults.defaultSettings(columns: ContentView.columnCount)
    }

    private func stringValue(forKey key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }
}
